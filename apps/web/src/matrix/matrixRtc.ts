import type { BaseKeyProvider } from "livekit-client";
import type { MatrixClient, Room } from "matrix-js-sdk";
import {
  MatrixRTCSessionEvent,
  type LivekitTransport,
  type MatrixRTCSession,
} from "matrix-js-sdk/lib/matrixrtc";
import { MatrixLivekitKeyProvider } from "./livekitE2ee";
import {
  MSC3401_MEMBER_EVENT,
  remoteLivekitFocusFromEvents,
  type CallMemberEventLike,
} from "./rtcMembership";

export type MatrixRtcPhase = "idle" | "connecting" | "connected" | "ended" | "error";

export interface LivekitFocus {
  type: "livekit";
  livekit_service_url: string;
  livekit_alias?: string;
}

export interface SfuConfig {
  url: string;
  jwt: string;
}

export interface MatrixRtcSnapshot {
  roomId: string | null;
  phase: MatrixRtcPhase;
  participantCount: number;
  microphoneMuted: boolean;
  remoteStream: MediaStream | null;
  error: string | null;
  fallbackAvailable: boolean;
}

export interface LivekitConnectOptions {
  keyProvider?: BaseKeyProvider;
}

export interface LivekitMediaSession {
  connect(url: string, token: string, options?: LivekitConnectOptions): Promise<void>;
  disconnect(): Promise<void>;
  setMicrophoneEnabled(enabled: boolean): Promise<void>;
  remoteStream(): MediaStream | null;
  subscribe(listener: () => void): () => void;
}

export interface MatrixRtcClient {
  getUserId(): string | null;
  getDeviceId(): string | null;
  getOpenIdToken(): Promise<{
    access_token: string;
    token_type: string;
    matrix_server_name: string;
    expires_in: number;
  }>;
  getClientWellKnown(): Record<string, unknown> | undefined;
  getRoom(roomId: string): Room | null;
  matrixRTC: {
    getRoomSession(room: Room): MatrixRTCSession;
  };
}

const EMPTY: MatrixRtcSnapshot = {
  roomId: null,
  phase: "idle",
  participantCount: 0,
  microphoneMuted: false,
  remoteStream: null,
  error: null,
  fallbackAvailable: false,
};

export const DEFAULT_LIVEKIT_JWT_URL = "https://rtc.testhighlife.strangled.net/livekit/jwt";

export function discoverLivekitFocus(
  wellKnown: Record<string, unknown> | undefined,
  fallbackUrl = DEFAULT_LIVEKIT_JWT_URL,
): LivekitFocus | null {
  const foci = wellKnown?.["org.matrix.msc4143.rtc_foci"];
  if (Array.isArray(foci)) {
    for (const item of foci) {
      if (!item || typeof item !== "object") continue;
      const focus = item as Record<string, unknown>;
      if (focus.type === "livekit" && typeof focus.livekit_service_url === "string") {
        const url = focus.livekit_service_url.trim();
        if (url) {
          return {
            type: "livekit",
            livekit_service_url: url.replace(/\/$/, ""),
            ...(typeof focus.livekit_alias === "string" ? { livekit_alias: focus.livekit_alias } : {}),
          };
        }
      }
    }
  }
  const fallback = fallbackUrl.trim().replace(/\/$/, "");
  if (!fallback) return null;
  return { type: "livekit", livekit_service_url: fallback };
}

export function jwtRequestUrl(serviceUrl: string, endpoint: "sfu/get" | "get_token"): string {
  return `${serviceUrl.replace(/\/$/, "")}/${endpoint}`;
}

export function legacyJwtRequestBody(
  roomId: string,
  deviceId: string,
  openIdToken: Record<string, unknown>,
): Record<string, unknown> {
  return {
    room: roomId,
    device_id: deviceId,
    openid_token: openIdToken,
  };
}

export function parseSfuConfig(payload: unknown): SfuConfig {
  if (!payload || typeof payload !== "object") throw new Error("Invalid LiveKit JWT response");
  const data = payload as Record<string, unknown>;
  if (typeof data.url !== "string" || typeof data.jwt !== "string") {
    throw new Error("LiveKit JWT response is missing url or jwt");
  }
  return { url: data.url, jwt: data.jwt };
}

export class MatrixRtcController {
  private current: MatrixRtcSnapshot = EMPTY;
  private readonly listeners = new Set<() => void>();
  private session: MatrixRTCSession | null = null;
  private keyProvider: MatrixLivekitKeyProvider | null = null;
  private unsubMedia: (() => void) | null = null;
  private readonly onMemberships = (): void => this.refresh();

  constructor(
    private readonly client: MatrixRtcClient,
    private readonly media: LivekitMediaSession,
    private readonly fetchJson: (url: string, body: unknown) => Promise<unknown>,
    private readonly fallbackUrl = DEFAULT_LIVEKIT_JWT_URL,
  ) {}

  get snapshot(): MatrixRtcSnapshot {
    return this.current;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async join(roomId: string): Promise<void> {
    if (this.current.phase === "connecting" || this.current.phase === "connected") {
      if (this.current.roomId === roomId) return;
      await this.leave();
    }
    const room = this.client.getRoom(roomId);
    const userId = this.client.getUserId();
    const deviceId = this.client.getDeviceId();
    const remoteFocus = userId
      ? remoteLivekitFocusFromEvents(callMemberEventsFromRoom(room), userId)
      : null;
    const focus = remoteFocus ?? discoverLivekitFocus(this.client.getClientWellKnown(), this.fallbackUrl);
    if (!room || !userId || !deviceId || !focus) {
      this.publish({
        ...EMPTY,
        phase: "error",
        roomId,
        error: "matrixrtc_unavailable",
        fallbackAvailable: true,
      });
      throw new Error("MatrixRTC LiveKit focus is not available");
    }
    this.publish({
      ...EMPTY,
      roomId,
      phase: "connecting",
      fallbackAvailable: true,
    });
    const rtc = this.client.matrixRTC.getRoomSession(room);
    this.session = rtc;
    rtc.on(MatrixRTCSessionEvent.MembershipsChanged, this.onMemberships);
    const transport: LivekitTransport = {
      type: "livekit",
      livekit_service_url: focus.livekit_service_url,
      livekit_alias: focus.livekit_alias ?? roomId,
    };
    rtc.joinRoomSession([transport], undefined, { manageMediaKeys: true });
    const keyProvider = new MatrixLivekitKeyProvider();
    keyProvider.attach(rtc);
    this.keyProvider = keyProvider;
    try {
      const openId = await this.client.getOpenIdToken();
      let config: SfuConfig;
      try {
        config = parseSfuConfig(
          await this.fetchJson(
            jwtRequestUrl(focus.livekit_service_url, "sfu/get"),
            legacyJwtRequestBody(roomId, deviceId, openId),
          ),
        );
      } catch {
        config = parseSfuConfig(
          await this.fetchJson(jwtRequestUrl(focus.livekit_service_url, "get_token"), {
            room_id: roomId,
            openid_token: openId,
            member: {
              claimed_user_id: userId,
              claimed_device_id: deviceId,
            },
          }),
        );
      }
      this.unsubMedia = this.media.subscribe(() => this.refresh());
      await this.media.connect(config.url, config.jwt, { keyProvider });
      await this.media.setMicrophoneEnabled(true);
      this.refresh({ phase: "connected", error: null });
    } catch (reason) {
      await this.cleanupSession();
      this.publish({
        roomId,
        phase: "error",
        participantCount: 0,
        microphoneMuted: false,
        remoteStream: null,
        error: reason instanceof Error ? reason.message : "matrixrtc_failed",
        fallbackAvailable: true,
      });
      throw reason;
    }
  }

  async leave(): Promise<void> {
    await this.cleanupSession();
    this.publish(EMPTY);
  }

  async toggleMicrophone(): Promise<void> {
    const muted = !this.current.microphoneMuted;
    await this.media.setMicrophoneEnabled(!muted);
    this.refresh({ microphoneMuted: muted });
  }

  dispose(): void {
    void this.leave();
    this.listeners.clear();
  }

  private refresh(overrides: Partial<MatrixRtcSnapshot> = {}): void {
    const memberships = this.session?.memberships ?? [];
    this.publish({
      ...this.current,
      participantCount: memberships.length,
      remoteStream: this.media.remoteStream(),
      ...overrides,
    });
  }

  private async cleanupSession(): Promise<void> {
    this.unsubMedia?.();
    this.unsubMedia = null;
    this.keyProvider?.detach();
    this.keyProvider = null;
    await this.media.disconnect().catch(() => undefined);
    if (this.session) {
      this.session.off(MatrixRTCSessionEvent.MembershipsChanged, this.onMemberships);
      await this.session.leaveRoomSession(4_000).catch(() => undefined);
    }
    this.session = null;
  }

  private publish(next: MatrixRtcSnapshot): void {
    this.current = next;
    for (const listener of this.listeners) listener();
  }
}

function callMemberEventsFromRoom(room: Room | null): CallMemberEventLike[] {
  const getter = room?.currentState?.getStateEvents?.bind(room.currentState);
  if (!getter) return [];
  const raw = getter(MSC3401_MEMBER_EVENT);
  const list = Array.isArray(raw) ? raw : raw ? [raw] : [];
  return list.map((event) => ({
    stateKey: event.getStateKey() ?? "",
    sender: event.getSender() ?? "",
    content: event.getContent() as Record<string, unknown>,
  }));
}

export async function fetchLivekitJson(url: string, body: unknown): Promise<unknown> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    throw new Error(`LiveKit JWT ${response.status}`);
  }
  return response.json();
}

export function createBrowserMatrixRtcClient(client: MatrixClient): MatrixRtcClient {
  return client as unknown as MatrixRtcClient;
}
