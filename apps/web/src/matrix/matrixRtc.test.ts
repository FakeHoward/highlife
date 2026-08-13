import { describe, expect, it, vi } from "vitest";
import { MatrixRTCSessionEvent } from "matrix-js-sdk/lib/matrixrtc";
import {
  DEFAULT_LIVEKIT_JWT_URL,
  MatrixRtcController,
  discoverLivekitFocus,
  jwtRequestUrl,
  legacyJwtRequestBody,
  parseSfuConfig,
  type LivekitMediaSession,
  type MatrixRtcClient,
} from "./matrixRtc";

class FakeMedia implements LivekitMediaSession {
  connected = false;
  mic = true;
  stream: MediaStream | null = null;
  private listeners = new Set<() => void>();

  async connect() {
    this.connected = true;
  }
  async disconnect() {
    this.connected = false;
    this.stream = null;
  }
  async setMicrophoneEnabled(enabled: boolean) {
    this.mic = enabled;
  }
  remoteStream() {
    return this.stream;
  }
  subscribe(listener: () => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
}

class FakeSession {
  memberships: unknown[] = [];
  joined = false;
  left = false;
  private listeners = new Map<string, Set<() => void>>();

  on(event: string, listener: () => void) {
    const set = this.listeners.get(event) ?? new Set();
    set.add(listener);
    this.listeners.set(event, set);
    return this;
  }
  off(event: string, listener: () => void) {
    this.listeners.get(event)?.delete(listener);
    return this;
  }
  joinRoomSession() {
    this.joined = true;
    this.memberships = [{}];
    for (const listener of this.listeners.get(MatrixRTCSessionEvent.MembershipsChanged) ?? []) listener();
  }
  async leaveRoomSession() {
    this.left = true;
    this.joined = false;
    this.memberships = [];
  }
}

function fakeClient(session: FakeSession): MatrixRtcClient {
  return {
    getUserId: () => "@me:example.org",
    getDeviceId: () => "DEVICE",
    getOpenIdToken: async () => ({
      access_token: "oid",
      token_type: "Bearer",
      matrix_server_name: "example.org",
      expires_in: 3600,
    }),
    getClientWellKnown: () => ({
      "org.matrix.msc4143.rtc_foci": [
        { type: "livekit", livekit_service_url: "https://rtc.example.org/livekit/jwt" },
      ],
    }),
    getRoom: () => ({ roomId: "!room:example.org" }) as never,
    matrixRTC: {
      getRoomSession: () => session as never,
    },
  };
}

describe("MatrixRTC LiveKit discovery", () => {
  it("prefers well-known livekit foci over the built-in fallback", () => {
    const focus = discoverLivekitFocus({
      "org.matrix.msc4143.rtc_foci": [
        { type: "mesh" },
        { type: "livekit", livekit_service_url: "https://rtc.example.org/livekit/jwt/" },
      ],
    });
    expect(focus).toEqual({
      type: "livekit",
      livekit_service_url: "https://rtc.example.org/livekit/jwt",
    });
  });

  it("falls back to the homeserver JWT service when well-known has no focus", () => {
    expect(discoverLivekitFocus(undefined)?.livekit_service_url).toBe(DEFAULT_LIVEKIT_JWT_URL);
    expect(discoverLivekitFocus({}, "")).toBeNull();
  });

  it("builds the legacy lk-jwt-service body Element Call still uses", () => {
    expect(jwtRequestUrl("https://rtc.example.org/livekit/jwt/", "sfu/get")).toBe(
      "https://rtc.example.org/livekit/jwt/sfu/get",
    );
    expect(legacyJwtRequestBody("!room:example.org", "DEVICE", { access_token: "oid" })).toEqual({
      room: "!room:example.org",
      device_id: "DEVICE",
      openid_token: { access_token: "oid" },
    });
  });

  it("rejects JWT payloads without a LiveKit URL and token", () => {
    expect(parseSfuConfig({ url: "wss://rtc.example.org", jwt: "token" })).toEqual({
      url: "wss://rtc.example.org",
      jwt: "token",
    });
    expect(() => parseSfuConfig({ url: "wss://rtc.example.org" })).toThrow(/jwt/i);
  });
});

describe("MatrixRtcController", () => {
  it("joins MatrixRTC then connects LiveKit media", async () => {
    const session = new FakeSession();
    const media = new FakeMedia();
    const fetchJson = vi.fn(async () => ({ url: "wss://sfu", jwt: "token" }));
    const controller = new MatrixRtcController(fakeClient(session), media, fetchJson);

    await controller.join("!room:example.org");

    expect(session.joined).toBe(true);
    expect(media.connected).toBe(true);
    expect(controller.snapshot.phase).toBe("connected");
    expect(controller.snapshot.participantCount).toBe(1);
    expect(fetchJson).toHaveBeenCalledWith(
      "https://rtc.example.org/livekit/jwt/sfu/get",
      expect.objectContaining({ room: "!room:example.org" }),
    );
  });

  it("marks Element Call as last-resort fallback when LiveKit JWT fails", async () => {
    const session = new FakeSession();
    const media = new FakeMedia();
    const controller = new MatrixRtcController(fakeClient(session), media, async () => {
      throw new Error("jwt down");
    });

    await expect(controller.join("!room:example.org")).rejects.toThrow("jwt down");
    expect(controller.snapshot.phase).toBe("error");
    expect(controller.snapshot.fallbackAvailable).toBe(true);
    expect(session.left).toBe(true);
  });
});
