import type {
  ConnectionState,
  DeliveryStatus,
  HostToast,
  RoomListItem,
  SpaceSummary,
  TimelineItem,
} from "@highlife/ui-contracts";
import {
  AIOMATRIX_CALLBACK_ANSWER_EVENT_TYPE,
  AIOMATRIX_HOST_STATE_EVENT_TYPE,
  AIOMATRIX_PROGRESS_EVENT_TYPE,
  AIOMATRIX_TOAST_EVENT_TYPE,
} from "@highlife/ui-contracts";
import {
  ClientEvent,
  createClient,
  EventStatus,
  EventType,
  MatrixEventEvent,
  MsgType,
  NotificationCountType,
  Preset,
  ReceiptType,
  RelationType,
  RoomEvent,
  RoomMemberEvent,
  RoomStateEvent,
  type MatrixClient,
  type MatrixEvent,
  type Room,
} from "matrix-js-sdk";
import { SlidingSync } from "matrix-js-sdk/lib/sliding-sync";
import {
  CryptoEvent,
  decodeRecoveryKey,
  encodeRecoveryKey,
  type CryptoApi,
  type GeneratedSecretStorageKey,
  type KeyBackupInfo,
} from "matrix-js-sdk/lib/crypto-api";
import { DeviceVerification } from "matrix-js-sdk/lib/models/device";
import {
  VerificationRequestEvent,
  VerifierEvent,
  type ShowSasCallbacks,
  type VerificationRequest,
} from "matrix-js-sdk/lib/crypto-api/verification";
import {
  buildCallbackEvent,
  buildMiniAppDataContent,
  formatMessagePreview,
} from "../protocol/aiomatrix";
import { decryptAttachment, encryptAttachment } from "./encryptedMedia";
import { buildElementCallUrl } from "./callUrl";
import {
  DirectCallController,
  type DirectCallClient,
  type DirectCallSnapshot,
} from "./directCall";
import { BrowserLivekitMedia } from "./livekitMedia";
import {
  DEFAULT_LIVEKIT_JWT_URL,
  MatrixRtcController,
  createBrowserMatrixRtcClient,
  discoverLivekitFocus,
  fetchLivekitJson,
  type MatrixRtcSnapshot,
} from "./matrixRtc";
import {
  buildPollEndContent,
  buildPollResponseContent,
  buildPollStartContent,
  POLL_END_UNSTABLE,
  POLL_RESPONSE_UNSTABLE,
  POLL_START_UNSTABLE,
} from "./polls";
import {
  joinRoomFailure,
  normalizeRoomIdOrAlias,
  serverFromRoomAddress,
} from "./roomAddress";
import { normalizeTimeline, type RawTimelineEvent } from "./timeline";
import {
  attachMentions,
  conversationReplyContent,
  defaultSlidingLists,
  filterCommandSuggestions,
  locationContent,
  MSC2545_PACK_STATE,
  MSC2545_USER_EMOTES,
  MSC3266_SUMMARY,
  MSC3266_SUMMARY_UNSTABLE,
  MSC4139_REPLY,
  MSC4310_DECLINE,
  MSC4310_DECLINE_UNSTABLE,
  MSC4332_COMMANDS,
  parseCommandsState,
  parseImagePack,
  parseRoomSummary,
  rtcDeclineContent,
  slidingSyncSupported,
  STICKER_EVENT,
  stickerContent,
  threadRelation,
  threadRootId,
  threadSubscriptionPath,
  type AdvertisedCommand,
  type ImagePackItem,
  type RoomSummary,
} from "./specFeatures";
import {
  clearCryptoDatabases,
  clearSession,
  loadSession,
  saveSession,
  type StoredSession,
} from "./sessionStore";
import {
  formatForwardedBody,
  isRoomMutedByPushRules,
  togglePinnedIds,
} from "./messengerExtras";
import { DIRECT_CALL_CRYPTO_UNAVAILABLE } from "./directCallErrors";
import {
  qrLoginAvailable,
  startLinkNewDeviceQr,
  startNewDeviceQr,
} from "./qrLogin";
import { assertCryptoForEncryptedRoom } from "./cryptoGuard";
import { matrixRtcCameraOptions, outgoingCallMode } from "./callRouting";
import { registerPushAfterLogin } from "./push";
import {
  MSC3401_MEMBER_EVENT,
  isActiveCallMemberContent,
  pickIncomingRtcCall,
  type CallMemberEventLike,
} from "./rtcMembership";

export { normalizeRoomIdOrAlias } from "./roomAddress";
export { registerPushAfterLogin } from "./push";
export { CryptoUnavailableError } from "./cryptoGuard";

export interface MatrixSnapshot {
  client: MatrixClient | null;
  connection: ConnectionState;
  error: string | null;
  toast: HostToast | null;
  version: number;
}

export interface SearchHit {
  eventId: string;
  roomId: string;
  body: string;
  sender: string;
  timestamp: number;
}

export interface HistoryState {
  loading: boolean;
  exhausted: boolean;
  error: string | null;
}

export interface EncryptionDevice {
  deviceId: string;
  displayName: string;
  fingerprint: string | null;
  current: boolean;
  verified: boolean;
  signedByOwner: boolean;
  dehydrated: boolean;
}

export interface SasChallenge {
  emoji: Array<[string, string]>;
  decimal: [number, number, number] | null;
  confirm: () => Promise<void>;
  mismatch: () => void;
  cancel: () => void;
}

export interface RoomMemberInfo {
  userId: string;
  displayName: string;
  avatarUrl?: string;
  membership: string;
  powerLevel: number;
}

export interface KeyBackupDetails {
  serverInfo: KeyBackupInfo | null;
  activeVersion: string | null;
  secretStorageReady: boolean;
  status: "enabled" | "configured" | "missing" | "unavailable";
}

export interface IncomingVerification {
  transactionId: string | undefined;
  otherUserId: string;
  otherDeviceId: string | undefined;
  isSelfVerification: boolean;
}

let client: MatrixClient | null = null;
let snapshot: MatrixSnapshot = {
  client: null,
  connection: "booting",
  error: null,
  toast: null,
  version: 0,
};
let toastSeq = 0;
let hostCapsBusy = false;
let hostCapsRan = false;
const dismissedRtcInvites = new Set<string>();
const listeners = new Set<() => void>();
const historyStates = new Map<string, HistoryState>();
const secretStorageKeys = new Map<string, Uint8Array<ArrayBuffer>>();
let cachedSecretStorageKey: { keyId: string; privateKey: Uint8Array<ArrayBuffer> } | null = null;
let pendingIncomingVerification: VerificationRequest | null = null;
const verificationListeners = new Set<() => void>();
let directCallController: DirectCallController | null = null;
let detachDirectCall: (() => void) | null = null;
const directCallListeners = new Set<() => void>();
const idleDirectCall: DirectCallSnapshot = {
  call: null,
  roomId: null,
  direction: null,
  phase: "idle",
  peerName: "",
  peerUserId: null,
  microphoneMuted: false,
  remoteStream: null,
  localStream: null,
  error: null,
};
let matrixRtcController: MatrixRtcController | null = null;
let detachMatrixRtc: (() => void) | null = null;
const matrixRtcListeners = new Set<() => void>();
const idleMatrixRtc: MatrixRtcSnapshot = {
  roomId: null,
  phase: "idle",
  participantCount: 0,
  microphoneMuted: false,
  remoteStream: null,
  error: null,
  fallbackAvailable: false,
};

function disposeCallControllers(): void {
  detachDirectCall?.();
  detachDirectCall = null;
  directCallController?.dispose();
  directCallController = null;
  detachMatrixRtc?.();
  detachMatrixRtc = null;
  matrixRtcController?.dispose();
  matrixRtcController = null;
}

function matrixRtcManager(active: MatrixClient | null): { start?: () => void; stop?: () => void } | undefined {
  return active?.matrixRTC as { start?: () => void; stop?: () => void } | undefined;
}

function callMemberEventsFromRoom(room: Room): CallMemberEventLike[] {
  const raw = room.currentState.getStateEvents(MSC3401_MEMBER_EVENT);
  const list = Array.isArray(raw) ? raw : raw ? [raw] : [];
  return list.map((event) => ({
    stateKey: event.getStateKey() ?? "",
    sender: event.getSender() ?? "",
    content: event.getContent() as Record<string, unknown>,
  }));
}

function livekitFallbackUrl(): string {
  return (import.meta.env.VITE_LIVEKIT_JWT_URL as string | undefined)?.trim() || DEFAULT_LIVEKIT_JWT_URL;
}

function attachCallControllers(active: MatrixClient): void {
  directCallController = new DirectCallController(active as unknown as DirectCallClient);
  detachDirectCall = directCallController.subscribe(() => {
    for (const listener of directCallListeners) listener();
  });
  matrixRtcController = new MatrixRtcController(
    createBrowserMatrixRtcClient(active),
    new BrowserLivekitMedia(),
    fetchLivekitJson,
    livekitFallbackUrl(),
  );
  detachMatrixRtc = matrixRtcController.subscribe(() => {
    for (const listener of matrixRtcListeners) listener();
  });
  for (const listener of directCallListeners) listener();
  for (const listener of matrixRtcListeners) listener();
}

/**
 * Zero and drop in-memory secret-storage / recovery key material.
 * Keys are never written to sessionStorage/localStorage; they live only in
 * these module-scoped buffers for the tab lifetime until logout or explicit clear.
 */
export function clearRecoveryKeyCache(): void {
  if (cachedSecretStorageKey) {
    cachedSecretStorageKey.privateKey.fill(0);
    cachedSecretStorageKey = null;
  }
  for (const key of secretStorageKeys.values()) {
    key.fill(0);
  }
  secretStorageKeys.clear();
}

function publishVerification(): void {
  verificationListeners.forEach((listener) => listener());
}

function cacheSecretStorageKey(
  keyId: string,
  _keyInfo: unknown,
  key: Uint8Array<ArrayBuffer>,
): void {
  secretStorageKeys.set(keyId, key);
  cachedSecretStorageKey = { keyId, privateKey: key };
}

async function getSecretStorageKey(opts: {
  keys: Record<string, unknown>;
}): Promise<[string, Uint8Array<ArrayBuffer>] | null> {
  if (cachedSecretStorageKey && opts.keys[cachedSecretStorageKey.keyId]) {
    return [cachedSecretStorageKey.keyId, cachedSecretStorageKey.privateKey];
  }
  for (const keyId of Object.keys(opts.keys)) {
    const cached = secretStorageKeys.get(keyId);
    if (cached) return [keyId, cached];
  }
  if (cachedSecretStorageKey) {
    const first = Object.keys(opts.keys)[0];
    if (first) return [first, cachedSecretStorageKey.privateKey];
  }
  return null;
}

const cryptoCallbacks = {
  getSecretStorageKey,
  cacheSecretStorageKey,
};

function publish(patch: Partial<MatrixSnapshot> = {}): void {
  snapshot = { ...snapshot, ...patch, client, version: snapshot.version + 1 };
  listeners.forEach((listener) => listener());
}

/** Surface an auth/bootstrap error on the login screen. */
export function publishAuthError(error: string): void {
  publish({ connection: "error", error });
}

function maybeShowHostToast(event: MatrixEvent): void {
  const type = event.getType();
  if (
    type !== AIOMATRIX_CALLBACK_ANSWER_EVENT_TYPE &&
    type !== AIOMATRIX_TOAST_EVENT_TYPE &&
    type !== AIOMATRIX_PROGRESS_EVENT_TYPE
  ) {
    return;
  }
  const content = event.getContent() as Record<string, unknown>;
  const text = typeof content.text === "string" ? content.text.trim() : "";
  if (!text) return;
  const target = typeof content.user_id === "string" ? content.user_id : null;
  const self = client?.getUserId();
  if (target && self && target !== self) return;
  toastSeq += 1;
  publish({
    toast: {
      id: toastSeq,
      text,
      alert: content.alert === true,
    },
  });
}

export function dismissToast(id?: number): void {
  if (id != null && snapshot.toast?.id !== id) return;
  publish({ toast: null });
}

/** Client-originated toast (not from a bot ephemeral event). */
export function showLocalToast(text: string, alert = false): void {
  const trimmed = text.trim();
  if (!trimmed) return;
  toastSeq += 1;
  publish({
    toast: {
      id: toastSeq,
      text: trimmed,
      alert,
    },
  });
}

/** Advertise aiomatrix host caps only in rooms that have a bot. Bulk once, then per new join. */
function leftoverHostStateEvent(room: Room, userId: string): MatrixEvent | null {
  const existing = room.currentState.getStateEvents(AIOMATRIX_HOST_STATE_EVENT_TYPE, userId);
  if (!existing) return null;
  const content = existing.getContent() as Record<string, unknown> | undefined;
  if (!content || Object.keys(content).length === 0) return null;
  return existing;
}

/** Element X renders unknown `dev.aiomatrix.host` state as "Custom host event". */
async function scrubHostCapabilityLeftovers(targetRoom?: Room): Promise<void> {
  if (!client || hostCapsBusy) return;
  if (!targetRoom && hostCapsRan) return;
  hostCapsBusy = true;
  const userId = client.getUserId();
  if (!userId) {
    hostCapsBusy = false;
    return;
  }
  const rooms = targetRoom ? [targetRoom] : client.getRooms();
  try {
    for (const room of rooms) {
      if (room.getMyMembership() !== "join") continue;
      const existing = leftoverHostStateEvent(room, userId);
      const eventId = existing?.getId();
      if (!existing || !eventId) continue;
      try {
        await client.redactEvent(room.roomId, eventId);
      } catch {
        /* power level or 429 — retry when the room is opened */
      }
      if (!targetRoom) {
        await new Promise((resolve) => window.setTimeout(resolve, 2500));
      }
    }
    if (!targetRoom) hostCapsRan = true;
  } finally {
    hostCapsBusy = false;
  }
}

export function scrubHostCapabilitiesForRoom(roomId: string): void {
  const room = client?.getRoom(roomId);
  if (room) void scrubHostCapabilityLeftovers(room);
}

export function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function getSnapshot(): MatrixSnapshot {
  return snapshot;
}

export function resolveHomeserver(input: string): string {
  const value = input.trim().replace(/\/+$/, "");
  if (/^https?:\/\//i.test(value)) return value;
  const server = value.startsWith("@") ? value.split(":").slice(1).join(":") : value;
  return `https://${server}`;
}

function attachIncomingVerification(active: MatrixClient): void {
  active.on(CryptoEvent.VerificationRequestReceived, (request: VerificationRequest) => {
    if (request.initiatedByMe || !request.pending) return;
    pendingIncomingVerification = request;
    request.on(VerificationRequestEvent.Change, () => {
      if (!request.pending) {
        if (pendingIncomingVerification === request) pendingIncomingVerification = null;
      }
      publishVerification();
    });
    publishVerification();
  });
}

async function start(session: StoredSession): Promise<void> {
  disposeCallControllers();
  if (client) {
    try {
      matrixRtcManager(client)?.stop?.();
    } catch {
      /* older SDK */
    }
    client.stopClient();
  }
  pendingIncomingVerification = null;
  client = createClient({
    baseUrl: session.baseUrl,
    userId: session.userId,
    accessToken: session.accessToken,
    deviceId: session.deviceId,
    timelineSupport: true,
    verificationMethods: ["m.sas.v1"],
    cryptoCallbacks,
  });
  attachCallControllers(client);
  publish({ connection: navigator.onLine ? "syncing" : "offline", error: null, toast: null });
  hostCapsBusy = false;
  hostCapsRan = false;
  dismissedRtcInvites.clear();
  client.on(ClientEvent.Sync, (state) => {
    publish({
      connection: state === "SYNCING" || state === "PREPARED" ? "online" : state === "ERROR" ? "error" : "syncing",
    });
    if (state === "PREPARED") {
      void scrubHostCapabilityLeftovers();
    }
  });
  client.on(RoomEvent.MyMembership, (room, membership) => {
    if (membership === "join" && hostCapsRan) {
      void scrubHostCapabilityLeftovers(room);
    }
  });
  client.on(RoomEvent.Timeline, (event, room, toStartOfTimeline) => {
    if (toStartOfTimeline || !room || !client) {
      publish();
      return;
    }
    maybeShowHostToast(event);
    const type = event.getType();
    if (type === MSC4310_DECLINE || type === MSC4310_DECLINE_UNSTABLE) {
      dismissedRtcInvites.add(room.roomId);
    }
    publish();
  });
  client.on(RoomEvent.TimelineReset, () => publish());
  client.on(RoomEvent.Name, () => publish());
  client.on(RoomEvent.Receipt, () => publish());
  client.on(RoomEvent.LocalEchoUpdated, () => publish());
  client.on(RoomMemberEvent.Typing, () => publish());
  client.on(RoomStateEvent.Events, (event) => {
    if (event.getType() === MSC3401_MEMBER_EVENT) publish();
  });
  // Encrypted events land as m.room.encrypted; after async decrypt the clear
  // type becomes m.room.message. Without this, bot replies stay invisible.
  client.on(MatrixEventEvent.Decrypted, (event) => {
    maybeShowHostToast(event);
    publish();
  });
  try {
    // initRustCrypto may GET /_matrix/client/v3/room_keys/version; Synapse 404s when
    // no backup exists yet. Chrome Network shows that 404 — expected until recovery
    // is set up. App code maps the same miss via safeKeyBackupInfo → "missing".
    await client.initRustCrypto({
      useIndexedDB: true,
      cryptoDatabasePrefix: `highlife-${session.userId}-${session.deviceId}`,
    });
    attachIncomingVerification(client);
    // Prefer unlocking an existing identity over creating a new one.
    try {
      await client.getCrypto()?.checkKeyBackupAndEnable();
    } catch {
      /* no backup yet */
    }
    if (cachedSecretStorageKey) {
      void restoreFromKeyBackup().catch(() => undefined);
    }
    void ensureOwnDeviceCrossSigned().catch(() => undefined);
  } catch (error) {
    publish({ error: `Encryption unavailable: ${messageOf(error)}` });
  }
  await startSync(client);
  try {
    matrixRtcManager(client)?.start?.();
  } catch {
    /* older SDK without a session manager */
  }
  void registerPushAfterLogin(client).catch(() => undefined);
}

async function startSync(active: MatrixClient): Promise<void> {
  const opts = { initialSyncLimit: 50, threadSupport: true, lazyLoadMembers: true };
  try {
    const versions = await active.getVersions();
    if (slidingSyncSupported(versions.unstable_features as Record<string, unknown> | undefined)) {
      const slidingSync = new SlidingSync(
        active.baseUrl,
        defaultSlidingLists() as never,
        { timeline_limit: 50, required_state: [["*", "*"]] },
        active,
        30_000,
      );
      await active.startClient({ ...opts, slidingSync });
      return;
    }
  } catch {
    /* homeserver without SSS or SDK mismatch — classic /sync */
  }
  await active.startClient(opts);
}

export async function restoreSession(): Promise<boolean> {
  const session = await loadSession();
  if (!session) {
    publish({ connection: "offline" });
    return false;
  }
  try {
    await start(session);
    return true;
  } catch (error) {
    await clearSession();
    disposeCallControllers();
    client = null;
    publish({ connection: "error", error: messageOf(error) });
    return false;
  }
}

const DEVICE_DISPLAY_NAME = "HighLife";

function uiaSessionFromError(error: unknown): string | null {
  if (!error || typeof error !== "object") return null;
  const data = "data" in error ? (error as { data?: Record<string, unknown> }).data : undefined;
  const session = data && typeof data.session === "string" ? data.session : null;
  return session && session.length > 0 ? session : null;
}

function uiaAllowsDummy(error: unknown): boolean {
  if (!error || typeof error !== "object" || !("data" in error)) return true;
  const data = (error as { data?: { flows?: { stages?: string[] }[] } }).data;
  const flows = data?.flows;
  if (!flows?.length) return true;
  return flows.some(
    (flow) => Array.isArray(flow.stages) && flow.stages.length === 1 && flow.stages[0] === "m.login.dummy",
  );
}

async function establishSession(session: StoredSession): Promise<void> {
  await saveSession(session);
  try {
    await start(session);
  } catch (error) {
    client?.stopClient();
    disposeCallControllers();
    client = null;
    await clearSession();
    publish({ connection: "error", error: messageOf(error) });
    throw error;
  }
}

export async function login(input: {
  homeserver: string;
  userId: string;
  password: string;
}): Promise<void> {
  const baseUrl = resolveHomeserver(input.homeserver);
  const guest = createClient({ baseUrl });
  const response = await guest.login("m.login.password", {
    identifier: { type: "m.id.user", user: input.userId.trim() },
    password: input.password,
    initial_device_display_name: DEVICE_DISPLAY_NAME,
  });
  await establishSession({
    baseUrl,
    userId: response.user_id,
    accessToken: response.access_token,
    deviceId: response.device_id,
  });
}

/** Start a session from an OAuth / MSC3861 access token. */
export async function loginWithAccessToken(input: {
  homeserver: string;
  accessToken: string;
  deviceId?: string;
}): Promise<void> {
  const baseUrl = resolveHomeserver(input.homeserver);
  const probe = createClient({
    baseUrl,
    accessToken: input.accessToken,
    deviceId: input.deviceId,
  });
  const whoami = await probe.whoami();
  if (!whoami.user_id) throw new Error("Access token did not resolve a user");
  await establishSession({
    baseUrl,
    userId: whoami.user_id,
    accessToken: input.accessToken,
    deviceId: whoami.device_id ?? input.deviceId ?? "UNKNOWN",
  });
}

/** Exchange an m.login.token (classic SSO redirect) for a session. */
export async function loginWithSsoToken(input: {
  homeserver: string;
  token: string;
}): Promise<void> {
  const baseUrl = resolveHomeserver(input.homeserver);
  const guest = createClient({ baseUrl });
  const response = await guest.login("m.login.token", {
    token: input.token,
    initial_device_display_name: DEVICE_DISPLAY_NAME,
  });
  await establishSession({
    baseUrl,
    userId: response.user_id,
    accessToken: response.access_token,
    deviceId: response.device_id,
  });
}

/** Register a new account on an open-registration homeserver, then start a session. */
export async function register(input: {
  homeserver: string;
  username: string;
  password: string;
}): Promise<void> {
  const baseUrl = resolveHomeserver(input.homeserver);
  const username = input.username.trim().replace(/^@/, "").split(":")[0] ?? "";
  if (!username) {
    throw Object.assign(new Error("USERNAME_REQUIRED"), { code: "USERNAME_REQUIRED" as const });
  }
  const guest = createClient({ baseUrl });
  async function attempt(sessionId: string | null) {
    return guest.registerRequest({
      username,
      password: input.password,
      auth: {
        type: "m.login.dummy",
        ...(sessionId ? { session: sessionId } : {}),
      },
      initial_device_display_name: DEVICE_DISPLAY_NAME,
    });
  }
  let response;
  try {
    response = await attempt(null);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const errcode =
      error && typeof error === "object" && "errcode" in error
        ? String((error as { errcode?: string }).errcode)
        : "";
    if (errcode === "M_FORBIDDEN" || /registration has been disabled/i.test(message)) {
      throw Object.assign(new Error("REGISTER_DISABLED"), { code: "REGISTER_DISABLED" as const });
    }
    const sessionId = uiaSessionFromError(error);
    if (!sessionId) throw error;
    if (!uiaAllowsDummy(error)) {
      throw Object.assign(new Error("REGISTER_NEEDS_EXTRA"), { code: "REGISTER_NEEDS_EXTRA" as const });
    }
    response = await attempt(sessionId);
  }
  if (!response.access_token || !response.user_id || !response.device_id) {
    throw new Error("Registration did not return a session");
  }
  await establishSession({
    baseUrl,
    userId: response.user_id,
    accessToken: response.access_token,
    deviceId: response.device_id,
  });
}

export async function logout(): Promise<void> {
  const active = client;
  const userId = active?.getUserId();
  const deviceId = active?.getDeviceId();
  if (active) {
    try {
      await active.logout(true);
    } finally {
      try {
        matrixRtcManager(active)?.stop?.();
      } catch {
        /* older SDK */
      }
      active.stopClient();
    }
  }
  disposeCallControllers();
  for (const listener of directCallListeners) listener();
  for (const listener of matrixRtcListeners) listener();
  client = null;
  pendingIncomingVerification = null;
  clearRecoveryKeyCache();
  await clearSession();
  if (userId && deviceId) {
    await clearCryptoDatabases(userId, deviceId);
  }
  publish({ connection: "offline", error: null, toast: null });
  hostCapsBusy = false;
  hostCapsRan = false;
  dismissedRtcInvites.clear();
  publishVerification();
}

function requiredClient(): MatrixClient {
  if (!client) throw new Error("Sign in to continue");
  return client;
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : "Matrix request failed";
}

export function listRooms(query = ""): RoomListItem[] {
  const active = client;
  if (!active) return [];
  const lowered = query.trim().toLocaleLowerCase();
  return active
    .getRooms()
    .filter((room) => ["join", "invite"].includes(room.getMyMembership()))
    .map((room): RoomListItem => {
      const last = [...room.getLiveTimeline().getEvents()]
        .reverse()
        .find((event) =>
          event.getType() === EventType.RoomMessage
          || event.getType() === POLL_START_UNSTABLE
          || event.getType() === "m.poll.start",
        );
      const name = room.name || room.roomId;
      const lastContent = (last?.getContent() ?? {}) as Record<string, unknown>;
      const parents = room.currentState.getStateEvents("m.space.parent");
      const parentId = parents.find((event) => {
        const content = event.getContent() as { via?: string[]; canonical?: boolean };
        return Boolean(content);
      })?.getStateKey();
      return {
        roomId: room.roomId,
        name,
        topic: room.currentState.getStateEvents(EventType.RoomTopic, "")?.getContent().topic as string | undefined,
        avatarUrl: room.getAvatarUrl(active.baseUrl, 72, 72, "crop") ?? undefined,
        canonicalAlias: (
          room.currentState
            .getStateEvents(EventType.RoomCanonicalAlias, "")
            ?.getContent().alias as string | undefined
        ) ?? undefined,
        lastMessage: last ? formatMessagePreview(lastContent) || undefined : undefined,
        unread: room.getUnreadNotificationCount(NotificationCountType.Total),
        highlight: room.getUnreadNotificationCount(NotificationCountType.Highlight),
        isDirect: Boolean(room.getDMInviter() || room.guessDMUserId()),
        isEncrypted: room.hasEncryptionStateEvent(),
        isSpace: room.isSpaceRoom(),
        membership: room.getMyMembership(),
        lastActive: room.getLastActiveTimestamp(),
        muted: isRoomMutedByPushRules(active.pushRules?.global?.room, room.roomId),
        ...(parentId ? { spaceParentId: parentId } : {}),
      };
    })
    .filter((room) => !lowered || `${room.name} ${room.lastMessage ?? ""}`.toLocaleLowerCase().includes(lowered))
    .sort((a, b) => b.lastActive - a.lastActive);
}

export function listSpaces(): SpaceSummary[] {
  const active = client;
  if (!active) return [];
  return active
    .getRooms()
    .filter((room) => room.isSpaceRoom() && room.getMyMembership() === "join")
    .map((room) => {
      const children = room.currentState
        .getStateEvents("m.space.child")
        .map((event) => event.getStateKey())
        .filter((id): id is string => Boolean(id));
      return {
        roomId: room.roomId,
        name: room.name || room.roomId,
        topic: room.currentState.getStateEvents(EventType.RoomTopic, "")?.getContent().topic as string | undefined,
        avatarUrl: room.getAvatarUrl(active.baseUrl, 72, 72, "crop") ?? undefined,
        childRoomIds: children,
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

function mapEventStatus(status: EventStatus | null | undefined): DeliveryStatus | undefined {
  if (!status) return undefined;
  if (status === EventStatus.ENCRYPTING) return "encrypting";
  if (status === EventStatus.SENDING || status === EventStatus.QUEUED) return "sending";
  if (status === EventStatus.SENT) return "sent";
  if (status === EventStatus.NOT_SENT || status === EventStatus.CANCELLED) return "not_sent";
  return "sending";
}

function hasBeenReadByOther(room: Room, event: MatrixEvent, ownUserId: string): boolean {
  const eventId = event.getId();
  if (!eventId) return false;
  const timeline = room.getLiveTimeline().getEvents();
  const index = timeline.findIndex((item) => item.getId() === eventId);
  if (index < 0) return false;
  for (const member of room.getJoinedMembers()) {
    if (member.userId === ownUserId) continue;
    const upTo = room.getEventReadUpTo(member.userId);
    if (!upTo) continue;
    const upIndex = timeline.findIndex((item) => item.getId() === upTo);
    if (upIndex >= index) return true;
  }
  return false;
}

function rawEvent(event: MatrixEvent, room?: Room | null, ownUserId?: string): RawTimelineEvent {
  let status = mapEventStatus(event.status);
  if (
    room
    && ownUserId
    && event.getSender() === ownUserId
    && !status
    && hasBeenReadByOther(room, event, ownUserId)
  ) {
    status = "read";
  } else if (room && ownUserId && event.getSender() === ownUserId && !status) {
    status = "sent";
  }
  return {
    eventId: event.getId() ?? `${event.getTs()}-${event.getSender()}`,
    type: event.getType(),
    sender: event.getSender() ?? "",
    timestamp: event.getTs(),
    content: event.getContent() as Record<string, unknown>,
    redacted: event.isRedacted(),
    ...(status ? { status } : {}),
  };
}

export function roomTimeline(roomId: string): TimelineItem[] {
  const active = client;
  const room = active?.getRoom(roomId);
  if (!active || !room) return [];
  const ownUserId = active.getUserId() ?? "";
  const names = Object.fromEntries(
    room.getJoinedMembers().map((member) => [member.userId, member.name || member.userId]),
  );
  const avatars: Record<string, string> = {};
  for (const member of room.getJoinedMembers()) {
    const avatar = member.getAvatarUrl(active.baseUrl, 64, 64, "crop", false, false);
    if (avatar) avatars[member.userId] = avatar;
  }
  return normalizeTimeline(
    room.getLiveTimeline().getEvents().map((event) => rawEvent(event, room, ownUserId)),
    {
      roomId,
      ownUserId,
      memberNames: names,
      memberAvatars: avatars,
    },
  );
}

export function getHistoryState(roomId: string): HistoryState {
  return historyStates.get(roomId) ?? { loading: false, exhausted: false, error: null };
}

export async function paginateRoomHistory(roomId: string): Promise<void> {
  const active = requiredClient();
  const room = active.getRoom(roomId);
  if (!room) throw new Error("Room is not available");
  const current = getHistoryState(roomId);
  if (current.loading || current.exhausted) return;
  historyStates.set(roomId, { ...current, loading: true, error: null });
  publish();
  try {
    const hasMore = await active.paginateEventTimeline(room.getLiveTimeline(), {
      backwards: true,
      limit: 50,
    });
    historyStates.set(roomId, { loading: false, exhausted: !hasMore, error: null });
  } catch (error) {
    historyStates.set(roomId, {
      loading: false,
      exhausted: false,
      error: messageOf(error),
    });
    throw error;
  } finally {
    publish();
  }
}

export async function sendMessage(
  roomId: string,
  body: string,
  options: { editEventId?: string; replyEventId?: string; threadRootId?: string } = {},
): Promise<void> {
  const active = requiredClient();
  const room = active.getRoom(roomId);
  assertCryptoForEncryptedRoom({
    encrypted: Boolean(room?.hasEncryptionStateEvent()),
    cryptoReady: Boolean(active.getCrypto()),
  });
  const memberIds = room?.getJoinedMembers().map((member) => member.userId) ?? [];
  const content: Record<string, unknown> = attachMentions(
    { msgtype: "m.text", body },
    body,
    memberIds,
  );
  if (options.editEventId) {
    content.body = `* ${body}`;
    content["m.new_content"] = attachMentions({ msgtype: "m.text", body }, body, memberIds);
    content["m.relates_to"] = { rel_type: "m.replace", event_id: options.editEventId };
  } else if (options.threadRootId) {
    content["m.relates_to"] = threadRelation(
      options.threadRootId,
      options.replyEventId ?? options.threadRootId,
      false,
    );
  } else if (options.replyEventId) {
    content["m.relates_to"] = { "m.in_reply_to": { event_id: options.replyEventId } };
  }
  await active.sendEvent(roomId, EventType.RoomMessage, content as never);
  if (options.threadRootId) {
    void subscribeToThread(roomId, options.threadRootId).catch(() => undefined);
  }
}

export async function uploadFile(
  roomId: string,
  file: File,
  options: {
    replyEventId?: string;
    threadRootId?: string;
    onProgress?: (ratio: number) => void;
    voice?: boolean;
    durationMs?: number;
  } = {},
): Promise<void> {
  const active = requiredClient();
  const room = active.getRoom(roomId);
  const encryptedRoom = Boolean(room?.hasEncryptionStateEvent());
  assertCryptoForEncryptedRoom({
    encrypted: encryptedRoom,
    cryptoReady: Boolean(active.getCrypto()),
  });
  const bytes = await file.arrayBuffer();
  options.onProgress?.(0.05);

  let content: Record<string, unknown>;
  const msgtype = file.type.startsWith("image/")
    ? MsgType.Image
    : file.type.startsWith("video/")
      ? MsgType.Video
      : file.type.startsWith("audio/")
        ? MsgType.Audio
        : MsgType.File;

  if (encryptedRoom) {
    const { ciphertext, info } = await encryptAttachment(bytes);
    options.onProgress?.(0.35);
    const upload = await active.uploadContent(new Blob([new Uint8Array(ciphertext)], { type: "application/octet-stream" }), {
      name: file.name,
      type: "application/octet-stream",
      progressHandler: ({ loaded, total }) => {
        if (total > 0) options.onProgress?.(0.35 + (loaded / total) * 0.55);
      },
    });
    content = {
      msgtype,
      body: file.name,
      file: { ...info, url: upload.content_uri },
      info: { mimetype: file.type, size: file.size },
    };
  } else {
    const upload = await active.uploadContent(file, {
      name: file.name,
      type: file.type,
      progressHandler: ({ loaded, total }) => {
        if (total > 0) options.onProgress?.(Math.min(0.95, loaded / total));
      },
    });
    content = {
      msgtype,
      body: file.name,
      url: upload.content_uri,
      info: { mimetype: file.type, size: file.size },
    };
  }

  if (options.threadRootId) {
    content["m.relates_to"] = threadRelation(
      options.threadRootId,
      options.replyEventId ?? options.threadRootId,
      false,
    );
  } else if (options.replyEventId) {
    content["m.relates_to"] = { "m.in_reply_to": { event_id: options.replyEventId } };
  }
  if (options.voice) {
    content["org.matrix.msc3245.voice"] = {};
    const info = (content.info as Record<string, unknown> | undefined) ?? {};
    if (typeof options.durationMs === "number") info.duration = options.durationMs;
    content.info = info;
  }
  options.onProgress?.(0.98);
  await active.sendEvent(roomId, EventType.RoomMessage, content as never);
  options.onProgress?.(1);
}

/** Resolve a media MXC to an object URL, decrypting encrypted attachments when needed. */
export async function resolveMediaObjectUrl(media: {
  mxcUrl: string;
  mimeType?: string;
  encrypted?: {
    mxcUrl: string;
    key: Record<string, unknown>;
    iv: string;
    sha256: string;
    v: string;
  };
}): Promise<string> {
  const active = requiredClient();
  const http = active.mxcUrlToHttp(media.mxcUrl, undefined, undefined, undefined, true);
  if (!http) throw new Error("Media URL unavailable");
  if (!media.encrypted) return http;

  const response = await fetch(http);
  if (!response.ok) throw new Error(`Media download failed (${response.status})`);
  const ciphertext = await response.arrayBuffer();
  const plaintext = await decryptAttachment(ciphertext, {
    v: "v2",
    key: media.encrypted.key as JsonWebKey,
    iv: media.encrypted.iv,
    hashes: { sha256: media.encrypted.sha256 },
  });
  const blob = new Blob([new Uint8Array(plaintext)], { type: media.mimeType || "application/octet-stream" });
  return URL.createObjectURL(blob);
}

export async function react(roomId: string, eventId: string, key: string): Promise<void> {
  await requiredClient().sendEvent(roomId, EventType.Reaction, {
    "m.relates_to": { rel_type: RelationType.Annotation, event_id: eventId, key },
  });
}

export async function redact(roomId: string, eventId: string): Promise<void> {
  await requiredClient().redactEvent(roomId, eventId);
}

/** Toggle an annotation: redact own reaction when present, otherwise send. */
export async function toggleReaction(
  roomId: string,
  targetEventId: string,
  key: string,
  existing?: { reactedByMe: boolean; ownEventId?: string },
): Promise<void> {
  if (existing?.reactedByMe && existing.ownEventId) {
    await redact(roomId, existing.ownEventId);
    return;
  }
  await react(roomId, targetEventId, key);
}

export async function markRead(roomId: string): Promise<void> {
  const active = requiredClient();
  const events = active.getRoom(roomId)?.getLiveTimeline().getEvents() ?? [];
  // Skip local echoes (`~…`) and pending sends — Synapse rejects those event ids.
  for (let i = events.length - 1; i >= 0; i -= 1) {
    const event = events[i]!;
    const eventId = event.getId();
    if (!eventId || eventId.startsWith("~")) continue;
    if (event.status != null) continue;
    if (event.isRedacted()) continue;
    await active.sendReadReceipt(event, ReceiptType.ReadPrivate, true);
    return;
  }
}

export function getOwnReadUpTo(roomId: string): string | null {
  const active = client;
  const self = active?.getUserId();
  const room = active?.getRoom(roomId);
  if (!active || !self || !room) return null;
  return room.getEventReadUpTo(self) ?? null;
}

export function getPinnedEventIds(roomId: string): string[] {
  const content = client?.getRoom(roomId)?.currentState
    .getStateEvents(EventType.RoomPinnedEvents, "")
    ?.getContent() as { pinned?: unknown } | undefined;
  return Array.isArray(content?.pinned)
    ? content.pinned.filter((id): id is string => typeof id === "string")
    : [];
}

export async function togglePinnedEvent(roomId: string, eventId: string): Promise<void> {
  const next = togglePinnedIds(getPinnedEventIds(roomId), eventId);
  await requiredClient().sendStateEvent(roomId, EventType.RoomPinnedEvents, { pinned: next } as never, "");
  publish();
}

export async function setRoomMuted(roomId: string, muted: boolean): Promise<void> {
  await requiredClient().setRoomMutePushRule("global", roomId, muted);
  publish();
}

export function getUserPresence(userId: string): {
  presence: string;
  lastActiveAgo?: number;
  currentlyActive?: boolean;
} {
  const user = client?.getUser(userId);
  return {
    presence: user?.presence ?? "offline",
    ...(typeof user?.lastActiveAgo === "number" ? { lastActiveAgo: user.lastActiveAgo } : {}),
    ...(typeof user?.currentlyActive === "boolean" ? { currentlyActive: user.currentlyActive } : {}),
  };
}

export function getPeerUserId(roomId: string): string | null {
  const room = client?.getRoom(roomId);
  const self = client?.getUserId();
  if (!room || !self) return null;
  const guessed = room.guessDMUserId();
  if (guessed && guessed !== self) return guessed;
  const other = room.getJoinedMembers().find((member) => member.userId !== self);
  return other?.userId ?? null;
}

export function getUserProfileInfo(userId: string): {
  userId: string;
  displayName: string;
  avatarUrl?: string;
} {
  const active = client;
  if (!active) return { userId, displayName: userId };
  for (const room of active.getRooms()) {
    const member = room.getMember(userId);
    if (!member) continue;
    return {
      userId,
      displayName: member.name || userId,
      avatarUrl: member.getAvatarUrl(active.baseUrl, 96, 96, "crop", false, false) ?? undefined,
    };
  }
  const user = active.getUser(userId);
  return { userId, displayName: user?.displayName || userId };
}

export function isUserIgnored(userId: string): boolean {
  return Boolean(client?.isUserIgnored(userId));
}

export async function setUserIgnored(userId: string, ignored: boolean): Promise<void> {
  const active = requiredClient();
  const current = active.getIgnoredUsers();
  const next = ignored
    ? [...new Set([...current, userId])]
    : current.filter((id) => id !== userId);
  await active.setIgnoredUsers(next);
  publish();
}

export async function forwardMessage(fromRoomId: string, eventId: string, toRoomId: string): Promise<void> {
  const active = requiredClient();
  const source = active.getRoom(fromRoomId);
  const event = source?.findEventById(eventId);
  const content = event?.getContent() as Record<string, unknown> | undefined;
  if (event && content && event.getType()) {
    try {
      await active.sendEvent(toRoomId, event.getType() as typeof EventType.RoomMessage, { ...content } as never);
      return;
    } catch {
      // Quote fallback when the original type is rejected (redacted, policy, crypto).
    }
  }
  const item = roomTimeline(fromRoomId).find((entry) => entry.eventId === eventId);
  if (!item || item.redacted) throw new Error("Message is not available");
  await sendMessage(toRoomId, formatForwardedBody(item.senderName, item.body || item.media?.name || ""));
}

export async function retryFailedEvent(roomId: string, eventId: string): Promise<void> {
  const active = requiredClient();
  const room = active.getRoom(roomId);
  if (!room) throw new Error("Room is not available");
  const pending = room.getPendingEvents().find((item) => item.getId() === eventId);
  const event = pending ?? room.findEventById(eventId);
  if (!event) throw new Error("Event is not available");
  const resend = (active as MatrixClient & {
    resendEvent?: (event: MatrixEvent, room: Room) => Promise<unknown>;
  }).resendEvent;
  if (typeof resend !== "function") throw new Error("Retry is not available");
  await resend.call(active, event, room);
  publish();
}

export async function retryDecryptEvent(roomId: string, eventId: string): Promise<void> {
  const active = requiredClient();
  const room = active.getRoom(roomId);
  const event = room?.findEventById(eventId);
  const crypto = active.getCrypto();
  if (!event || !crypto) throw new Error("Event is not available");
  const attempt = event.attemptDecryption?.bind(event);
  if (typeof attempt === "function") {
    await attempt(crypto as never, { isRetry: true });
  }
  publish();
}

export async function enableRoomEncryption(roomId: string): Promise<void> {
  const active = requiredClient();
  assertCryptoForEncryptedRoom({
    encrypted: true,
    cryptoReady: Boolean(active.getCrypto()),
  });
  await active.sendStateEvent(roomId, EventType.RoomEncryption, {
    algorithm: "m.megolm.v1.aes-sha2",
  } as never);
  publish();
}

export function listRoomMedia(roomId: string): TimelineItem[] {
  return roomTimeline(roomId).filter((item) =>
    Boolean(item.media) && (item.kind === "image" || item.kind === "video" || item.kind === "audio" || item.kind === "file"),
  );
}

export async function setTyping(roomId: string, typing: boolean): Promise<void> {
  await requiredClient().sendTyping(roomId, typing, 8000);
}

/** Display names of other members currently typing in the room. */
export function getTypingUsers(roomId: string): string[] {
  const room = client?.getRoom(roomId);
  const self = client?.getUserId();
  if (!room) return [];
  return room
    .getJoinedMembers()
    .filter((member) => member.typing && member.userId !== self)
    .map((member) => member.name || member.userId);
}

export async function createRoom(input: {
  name: string;
  topic?: string;
  alias?: string;
  invite?: string[];
  encrypted?: boolean;
  isSpace?: boolean;
}): Promise<string> {
  const active = requiredClient();
  const encrypted = Boolean(input.encrypted);
  assertCryptoForEncryptedRoom({
    encrypted,
    cryptoReady: Boolean(active.getCrypto()),
  });
  const response = await active.createRoom({
    name: input.name,
    topic: input.topic,
    room_alias_name: input.alias?.trim().replace(/^#/, "").split(":")[0] || undefined,
    invite: input.invite,
    preset: Preset.PrivateChat,
    room_version: input.isSpace ? "11" : undefined,
    creation_content: input.isSpace ? { type: "m.space" } : undefined,
    initial_state: encrypted
      ? [{ type: EventType.RoomEncryption, state_key: "", content: { algorithm: "m.megolm.v1.aes-sha2" } }]
      : undefined,
  });
  return response.room_id;
}

/** Start or reuse a 1:1 DM with another Matrix user. */
export async function startDirectMessage(userId: string, encrypted = true): Promise<string> {
  const active = requiredClient();
  const trimmed = userId.trim();
  if (!trimmed.startsWith("@") || !trimmed.includes(":")) {
    throw new Error("Enter a full Matrix user ID like @name:server");
  }
  assertCryptoForEncryptedRoom({
    encrypted,
    cryptoReady: Boolean(active.getCrypto()),
  });
  for (const room of active.getRooms()) {
    if (!room.getDMInviter() && !room.guessDMUserId()) continue;
    const members = room.getJoinedMembers().map((member) => member.userId);
    if (members.includes(trimmed) && members.length <= 2) {
      return room.roomId;
    }
  }
  const response = await active.createRoom({
    preset: Preset.TrustedPrivateChat,
    invite: [trimmed],
    is_direct: true,
    initial_state: encrypted
      ? [{ type: EventType.RoomEncryption, state_key: "", content: { algorithm: "m.megolm.v1.aes-sha2" } }]
      : undefined,
  });
  const roomId = response.room_id;
  const self = active.getUserId();
  if (self) {
    const direct = (active.getAccountData(EventType.Direct)?.getContent() ?? {}) as Record<string, string[]>;
    const rooms = new Set(direct[trimmed] ?? []);
    rooms.add(roomId);
    await active.setAccountData(EventType.Direct, { ...direct, [trimmed]: [...rooms] });
  }
  return roomId;
}

export async function addRoomToSpace(spaceId: string, roomId: string): Promise<void> {
  const active = requiredClient();
  const via = [new URL(active.baseUrl).hostname];
  await active.sendStateEvent(spaceId, "m.space.child" as typeof EventType.RoomTopic, { via } as never, roomId);
  try {
    await active.sendStateEvent(roomId, "m.space.parent" as typeof EventType.RoomTopic, { via } as never, spaceId);
  } catch {
    /* parent link needs power in the room; child link alone is enough for sidebar */
  }
}

export async function createPoll(
  roomId: string,
  input: { question: string; answers: string[]; maxSelections?: number },
): Promise<void> {
  const content = buildPollStartContent(input);
  await requiredClient().sendEvent(roomId, POLL_START_UNSTABLE as typeof EventType.RoomMessage, content as never);
}

export async function votePoll(roomId: string, pollEventId: string, answerIds: string[]): Promise<void> {
  const content = buildPollResponseContent(pollEventId, answerIds);
  await requiredClient().sendEvent(
    roomId,
    POLL_RESPONSE_UNSTABLE as typeof EventType.RoomMessage,
    content as never,
  );
}

export async function endPoll(roomId: string, pollEventId: string): Promise<void> {
  const content = buildPollEndContent(pollEventId);
  await requiredClient().sendEvent(roomId, POLL_END_UNSTABLE as typeof EventType.RoomMessage, content as never);
}

function homeserverHostFromClient(): string | null {
  const base = client?.baseUrl;
  if (!base) return null;
  try {
    return new URL(base).hostname;
  } catch {
    return null;
  }
}

export async function joinRoom(roomIdOrAlias: string): Promise<string> {
  const attempted = normalizeRoomIdOrAlias(roomIdOrAlias, homeserverHostFromClient() ?? undefined);
  const via = serverFromRoomAddress(attempted);
  try {
    return (
      await requiredClient().joinRoom(attempted, via ? { viaServers: [via] } : undefined)
    ).roomId;
  } catch (error) {
    throw joinRoomFailure(error, attempted);
  }
}

export async function acceptInvite(roomId: string): Promise<void> {
  await requiredClient().joinRoom(roomId);
  publish();
}

export async function rejectInvite(roomId: string): Promise<void> {
  await requiredClient().leave(roomId);
  publish();
}

export async function invite(roomId: string, userId: string): Promise<void> {
  await requiredClient().invite(roomId, userId);
}

export function getJoinedMembers(roomId: string): RoomMemberInfo[] {
  const active = client;
  const room = active?.getRoom(roomId);
  if (!active || !room) return [];
  return room
    .getJoinedMembers()
    .map((member) => ({
      userId: member.userId,
      displayName: member.name || member.userId,
      avatarUrl: member.getAvatarUrl(active.baseUrl, 64, 64, "crop", false, false) ?? undefined,
      membership: member.membership ?? "join",
      powerLevel: member.powerLevel,
    }))
    .sort((a, b) => a.displayName.localeCompare(b.displayName));
}

export async function sendWidgetRoomEvent(
  roomId: string,
  type: string,
  content: Record<string, unknown>,
  stateKey?: string,
): Promise<{ event_id?: string }> {
  const active = requiredClient();
  if (typeof stateKey === "string") {
    const response = await active.sendStateEvent(roomId, type as typeof EventType.RoomTopic, content as never, stateKey);
    return { event_id: response.event_id };
  }
  const response = await active.sendEvent(roomId, type as typeof EventType.RoomMessage, content as never);
  return { event_id: response.event_id };
}

export async function widgetUploadContent(
  file: Blob,
  filename: string,
  mimeType?: string,
): Promise<{ content_uri: string }> {
  const upload = await requiredClient().uploadContent(file, {
    name: filename,
    type: mimeType,
  });
  return { content_uri: upload.content_uri };
}

export async function widgetDownloadContent(mxcUrl: string): Promise<{
  filename?: string;
  contentType?: string;
  data: string;
}> {
  const http = requiredClient().mxcUrlToHttp(mxcUrl, undefined, undefined, undefined, true);
  if (!http) throw new Error("Media URL unavailable");
  const response = await fetch(http);
  if (!response.ok) throw new Error(`Download failed (${response.status})`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  let binary = "";
  bytes.forEach((value) => {
    binary += String.fromCharCode(value);
  });
  return {
    data: btoa(binary),
    contentType: response.headers.get("content-type") ?? undefined,
  };
}

export async function leaveRoom(roomId: string): Promise<void> {
  await requiredClient().leave(roomId);
}

export function getOwnDisplayName(): string {
  const active = requiredClient();
  const userId = active.getUserId();
  if (!userId) return "";
  return active.getUser(userId)?.displayName ?? "";
}

export function getOwnAvatarUrl(): string | undefined {
  const active = requiredClient();
  const userId = active.getUserId();
  if (!userId) return undefined;
  const mxc = active.getUser(userId)?.avatarUrl;
  return mxc ? active.mxcUrlToHttp(mxc, 96, 96, "crop", true) ?? undefined : undefined;
}

export function getOwnPresence(): "online" | "unavailable" | "offline" {
  const active = client;
  const userId = active?.getUserId();
  if (!active || !userId) return "online";
  const value = active.getUser(userId)?.presence;
  if (value === "unavailable" || value === "offline" || value === "online") return value;
  return "online";
}

export async function setOwnPresence(presence: "online" | "unavailable" | "offline"): Promise<void> {
  await requiredClient().setPresence({ presence });
  publish();
}

export function browserNotificationPermission(): NotificationPermission | "unsupported" {
  if (typeof Notification === "undefined") return "unsupported";
  return Notification.permission;
}

export async function requestDesktopNotifications(): Promise<NotificationPermission | "unsupported"> {
  if (typeof Notification === "undefined") return "unsupported";
  const perm = await Notification.requestPermission();
  if (perm === "granted" && client) await registerPushAfterLogin(client);
  return perm;
}

export async function updateProfile(displayName: string, avatar?: File): Promise<void> {
  const active = requiredClient();
  await active.setDisplayName(displayName);
  if (avatar) {
    const result = await active.uploadContent(avatar, { name: avatar.name, type: avatar.type });
    await active.setAvatarUrl(result.content_uri);
  }
  publish();
}

export async function setRoomAvatar(roomId: string, avatar: File): Promise<void> {
  const active = requiredClient();
  const result = await active.uploadContent(avatar, { name: avatar.name, type: avatar.type });
  await active.sendStateEvent(
    roomId,
    EventType.RoomAvatar,
    { url: result.content_uri } as never,
    "",
  );
  publish();
}

export function getRoomAliases(roomId: string): {
  canonicalAlias: string | null;
  aliases: string[];
} {
  const room = client?.getRoom(roomId);
  const content = room?.currentState
    .getStateEvents(EventType.RoomCanonicalAlias, "")
    ?.getContent() as { alias?: unknown; alt_aliases?: unknown } | undefined;
  const canonicalAlias = typeof content?.alias === "string" ? content.alias : null;
  const alternatives = Array.isArray(content?.alt_aliases)
    ? content.alt_aliases.filter((alias): alias is string => typeof alias === "string")
    : [];
  return {
    canonicalAlias,
    aliases: [...new Set([...(canonicalAlias ? [canonicalAlias] : []), ...alternatives])],
  };
}

export async function setCanonicalAlias(roomId: string, alias: string): Promise<void> {
  const active = requiredClient();
  const normalized = alias.trim();
  if (!/^#[^:\s]+:[^:\s]+$/.test(normalized)) {
    throw new Error("Use a full room address like #room:server");
  }
  const current = getRoomAliases(roomId);
  if (!current.aliases.includes(normalized)) await active.createAlias(normalized, roomId);
  await active.sendStateEvent(
    roomId,
    EventType.RoomCanonicalAlias,
    {
      alias: normalized,
      alt_aliases: current.aliases.filter((item) => item !== normalized),
    } as never,
    "",
  );
  publish();
}

export async function removeRoomAlias(roomId: string, alias: string): Promise<void> {
  const active = requiredClient();
  const current = getRoomAliases(roomId);
  await active.deleteAlias(alias);
  await active.sendStateEvent(
    roomId,
    EventType.RoomCanonicalAlias,
    {
      ...(current.canonicalAlias && current.canonicalAlias !== alias
        ? { alias: current.canonicalAlias }
        : {}),
      alt_aliases: current.aliases.filter((item) => item !== alias && item !== current.canonicalAlias),
    } as never,
    "",
  );
  publish();
}

/** Whether classic SSO / CAS appears in login flows for this homeserver. */
export async function probeSsoAvailable(homeserverInput: string): Promise<boolean> {
  const baseUrl = resolveHomeserver(homeserverInput);
  if (!baseUrl) return false;
  try {
    const guest = createClient({ baseUrl });
    const flows = await guest.loginFlows();
    return Boolean(
      flows.flows?.some(
        (flow) =>
          flow.type === "m.login.sso" ||
          flow.type === "m.login.cas" ||
          flow.type === "m.login.token",
      ),
    );
  } catch {
    return false;
  }
}

export async function searchMessages(term: string, roomId?: string): Promise<SearchHit[]> {
  const results = await requiredClient().searchRoomEvents({
    term,
    filter: roomId ? { rooms: [roomId] } : undefined,
  });
  return results.results.map((result) => {
    const event = result.context.getEvent();
    return {
      eventId: event.getId() ?? "",
      roomId: event.getRoomId() ?? "",
      body: (event.getContent().body as string | undefined) ?? "",
      sender: event.getSender() ?? "",
      timestamp: event.getTs(),
    };
  });
}

export async function sendCallback(
  roomId: string,
  data: string,
  eventId: string,
  token?: string | null,
): Promise<void> {
  const event = buildCallbackEvent(data, eventId, token);
  await requiredClient().sendEvent(
    roomId,
    event.eventType as never,
    event.content as never,
  );
}

export async function sendMiniAppData(
  roomId: string,
  data: string,
  ids: { queryId?: string | null; appId?: string | null; messageId?: string | null },
): Promise<void> {
  await requiredClient().sendEvent(roomId, EventType.RoomMessage, buildMiniAppDataContent({ data, ...ids }) as never);
}

export function getCryptoStatus(): {
  enabled: boolean;
  deviceId: string | null;
  userId: string | null;
} {
  return {
    enabled: Boolean(client?.getCrypto()),
    deviceId: client?.getDeviceId() ?? null,
    userId: client?.getUserId() ?? null,
  };
}

export async function getBackupStatus(): Promise<"configured" | "missing" | "unavailable"> {
  const details = await getKeyBackupDetails();
  if (details.status === "enabled" || details.status === "configured") return "configured";
  if (details.status === "missing") return "missing";
  return "unavailable";
}

async function safeKeyBackupInfo(
  crypto: NonNullable<ReturnType<MatrixClient["getCrypto"]>>,
): Promise<KeyBackupInfo | null> {
  try {
    return await crypto.getKeyBackupInfo();
  } catch (error) {
    // Synapse returns 404 when no backup version exists yet — that is "missing", not fatal.
    const status =
      error && typeof error === "object" && "httpStatus" in error
        ? Number((error as { httpStatus?: number }).httpStatus)
        : error && typeof error === "object" && "statusCode" in error
          ? Number((error as { statusCode?: number }).statusCode)
          : NaN;
    const message = error instanceof Error ? error.message : String(error);
    if (status === 404 || message.includes("404") || message.includes("M_NOT_FOUND")) {
      return null;
    }
    throw error;
  }
}

export async function getKeyBackupDetails(): Promise<KeyBackupDetails> {
  const crypto = client?.getCrypto();
  if (!crypto) {
    return { serverInfo: null, activeVersion: null, secretStorageReady: false, status: "unavailable" };
  }
  const [serverInfo, activeVersion, secretStorageReady] = await Promise.all([
    safeKeyBackupInfo(crypto),
    crypto.getActiveSessionBackupVersion().catch(() => null),
    crypto.isSecretStorageReady().catch(() => false),
  ]);
  const status = activeVersion
    ? "enabled"
    : serverInfo
      ? "configured"
      : "missing";
  return { serverInfo, activeVersion, secretStorageReady, status };
}

/**
 * Decode a recovery key into tab-lifetime memory only (Map + cachedSecretStorageKey).
 * Does not persist to sessionStorage/localStorage. The caller's plaintext string is
 * not stored; prefer clearing any UI paste buffer after a successful call.
 */
export function rememberRecoveryKey(recoveryKey: string): string {
  const trimmed = recoveryKey.trim();
  const privateKey = decodeRecoveryKey(trimmed);
  const key = privateKey as Uint8Array<ArrayBuffer>;
  cachedSecretStorageKey = { keyId: "recovery", privateKey: key };
  secretStorageKeys.set("recovery", key);
  // Re-encode so callers can drop the original paste string from React state.
  return encodeRecoveryKey(privateKey) ?? trimmed;
}

/** OpenID token for Element Call Widget API (`get_openid`). */
export async function fetchOpenIdToken(): Promise<{
  access_token: string;
  token_type: string;
  matrix_server_name: string;
  expires_in: number;
} | null> {
  const active = client;
  if (!active?.getUserId()) return null;
  try {
    return await active.getOpenIdToken();
  } catch {
    return null;
  }
}

export async function setupRecoveryAndKeyBackup(): Promise<{ recoveryKey: string }> {
  const crypto = requiredClient().getCrypto();
  if (!crypto) throw new Error("Encryption is unavailable");
  const generated: GeneratedSecretStorageKey = await crypto.createRecoveryKeyFromPassphrase();
  if (!generated.encodedPrivateKey) throw new Error("Recovery key generation failed");
  cacheSecretStorageKey("pending", generated.keyInfo ?? {}, generated.privateKey);
  await crypto.bootstrapCrossSigning({ setupNewCrossSigning: true });
  await crypto.bootstrapSecretStorage({
    createSecretStorageKey: async () => generated,
    setupNewSecretStorage: true,
    setupNewKeyBackup: true,
  });
  await crypto.checkKeyBackupAndEnable();
  return { recoveryKey: generated.encodedPrivateKey };
}

export async function resetKeyBackup(): Promise<void> {
  const crypto = requiredClient().getCrypto();
  if (!crypto) throw new Error("Encryption is unavailable");
  await crypto.resetKeyBackup();
}

export async function enableExistingKeyBackup(): Promise<KeyBackupInfo | null> {
  const crypto = requiredClient().getCrypto();
  if (!crypto) throw new Error("Encryption is unavailable");
  const checked = await crypto.checkKeyBackupAndEnable();
  return checked?.backupInfo ?? (await crypto.getKeyBackupInfo());
}

export async function restoreFromKeyBackup(): Promise<{ imported: number; total: number }> {
  const crypto = requiredClient().getCrypto();
  if (!crypto) throw new Error("Encryption is unavailable");
  const info = await crypto.getKeyBackupInfo();
  if (!info) throw new Error("No key backup on the server");
  if (cachedSecretStorageKey) {
    await crypto.storeSessionBackupPrivateKey(cachedSecretStorageKey.privateKey, info.version);
  } else {
    try {
      await crypto.loadSessionBackupPrivateKeyFromSecretStorage();
    } catch {
      /* restoreKeyBackup may still work if a key was cached by verification gossip */
    }
  }
  const result = await crypto.restoreKeyBackup();
  await ensureOwnDeviceCrossSigned();
  return { imported: result.imported, total: result.total };
}

export async function deleteServerKeyBackup(): Promise<void> {
  const crypto = requiredClient().getCrypto();
  if (!crypto) throw new Error("Encryption is unavailable");
  const info = await crypto.getKeyBackupInfo();
  if (!info) throw new Error("No key backup on the server");
  await crypto.deleteKeyBackupVersion(info.version);
}

export function subscribeIncomingVerification(listener: () => void): () => void {
  verificationListeners.add(listener);
  return () => verificationListeners.delete(listener);
}

export function getIncomingVerification(): IncomingVerification | null {
  const request = pendingIncomingVerification;
  if (!request?.pending) return null;
  return {
    transactionId: request.transactionId,
    otherUserId: request.otherUserId,
    otherDeviceId: request.otherDeviceId,
    isSelfVerification: request.isSelfVerification,
  };
}

export async function respondToIncomingVerification(
  accept: boolean,
  onSas: (challenge: SasChallenge) => void,
  onState: (state: string) => void,
): Promise<void> {
  const request = pendingIncomingVerification;
  if (!request) throw new Error("No incoming verification request");
  if (!accept) {
    await request.cancel();
    pendingIncomingVerification = null;
    publishVerification();
    onState("Verification declined");
    return;
  }
  await request.accept();
  let started = false;
  const advance = () => {
    onState(request.pending ? "Waiting for the other device…" : `Verification phase ${request.phase}`);
    if (started || !request.methods.includes("m.sas.v1")) return;
    started = true;
    void request.startVerification("m.sas.v1").then((verifier) => {
      verifier.on(VerifierEvent.ShowSas, (sas: ShowSasCallbacks) => {
        onSas({
          emoji: sas.sas.emoji ?? [],
          decimal: sas.sas.decimal ?? null,
          confirm: sas.confirm,
          mismatch: sas.mismatch,
          cancel: sas.cancel,
        });
      });
      return verifier.verify();
    }).then(() => {
      pendingIncomingVerification = null;
      publishVerification();
      onState("Device verified");
    }).catch((error) => onState(messageOf(error)));
  };
  request.on(VerificationRequestEvent.Change, advance);
  advance();
}

export async function listOwnDevices(): Promise<EncryptionDevice[]> {
  const active = requiredClient();
  const crypto = active.getCrypto();
  const userId = active.getSafeUserId();
  if (!crypto) return [];
  const devices = (await crypto.getUserDeviceInfo([userId], true)).get(userId);
  if (!devices) return [];
  return Promise.all([...devices.values()].map(async (device) => {
    const status = await crypto.getDeviceVerificationStatus(userId, device.deviceId);
    return {
      deviceId: device.deviceId,
      displayName: device.displayName ?? "",
      fingerprint: device.getFingerprint() ?? null,
      current: device.deviceId === active.getDeviceId(),
      verified: status?.isVerified() ?? false,
      signedByOwner: status?.signedByOwner ?? false,
      dehydrated: device.dehydrated,
    };
  }));
}

function signingKeyUploader(password?: string) {
  return async (makeRequest: (auth: Record<string, unknown> | null) => Promise<unknown>) => {
    try {
      await makeRequest(null);
    } catch (error) {
      const session = uiaSessionFromError(error);
      if (password) {
        await makeRequest({
          type: "m.login.password",
          identifier: { type: "m.id.user", user: requiredClient().getUserId() },
          password,
          session,
        });
        return;
      }
      if (session && uiaAllowsDummy(error)) {
        await makeRequest({ type: "m.login.dummy", session });
        return;
      }
      throw error;
    }
  };
}

/**
 * Sign this device with the account's cross-signing key so Element X stops
 * warning "encrypted by a device not verified by its owner".
 */
export async function ensureOwnDeviceCrossSigned(password?: string): Promise<void> {
  const active = client;
  const crypto = active?.getCrypto();
  const deviceId = active?.getDeviceId();
  if (!active || !crypto || !deviceId) return;
  const userId = active.getSafeUserId();
  const status = await crypto.getDeviceVerificationStatus(userId, deviceId);
  if (status?.signedByOwner) return;
  const crossSigning = await crypto.getCrossSigningStatus();
  const hasLocalMaster = Boolean(crossSigning.privateKeysCachedLocally.masterKey);
  const hasPublicKeys = crossSigning.publicKeysOnDevice;
  try {
    await crypto.bootstrapCrossSigning({
      setupNewCrossSigning: !hasPublicKeys && !hasLocalMaster,
      authUploadDeviceSigningKeys: signingKeyUploader(password),
    });
  } catch {
    /* needs recovery key, password UIA, or another verified device */
  }
}

export async function deleteOtherDevice(deviceId: string, password?: string): Promise<void> {
  const active = requiredClient();
  if (deviceId === active.getDeviceId()) {
    throw new Error("Cannot sign out the current session here");
  }
  const auth = password
    ? {
        type: "m.login.password",
        identifier: { type: "m.id.user", user: active.getUserId() },
        password,
      }
    : undefined;
  try {
    await active.deleteDevice(deviceId, auth);
  } catch (error) {
    const session = uiaSessionFromError(error);
    if (!password) throw error;
    await active.deleteDevice(deviceId, {
      type: "m.login.password",
      identifier: { type: "m.id.user", user: active.getUserId() },
      password,
      session,
    });
  }
}

function bindVerificationRequest(
  request: VerificationRequest,
  onSas: (challenge: SasChallenge) => void,
  onState: (state: string) => void,
): {
  transactionId: string | undefined;
  otherDeviceId: string | undefined;
  cancel: () => Promise<void>;
} {
  let started = false;
  const advance = () => {
    onState(request.pending ? "Waiting for the other device…" : `Verification phase ${request.phase}`);
    if (started || !request.methods.includes("m.sas.v1")) return;
    started = true;
    void request.startVerification("m.sas.v1").then((verifier) => {
      verifier.on(VerifierEvent.ShowSas, (sas: ShowSasCallbacks) => {
        onSas({
          emoji: sas.sas.emoji ?? [],
          decimal: sas.sas.decimal ?? null,
          confirm: sas.confirm,
          mismatch: sas.mismatch,
          cancel: sas.cancel,
        });
      });
      return verifier.verify();
    }).then(() => onState("Device verified")).catch((error) => onState(messageOf(error)));
  };
  request.on(VerificationRequestEvent.Change, advance);
  advance();
  return {
    transactionId: request.transactionId,
    otherDeviceId: request.otherDeviceId,
    cancel: () => request.cancel(),
  };
}

export async function requestDeviceVerification(
  deviceId: string | undefined,
  onSas: (challenge: SasChallenge) => void,
  onState: (state: string) => void,
): Promise<{
  transactionId: string | undefined;
  otherDeviceId: string | undefined;
  cancel: () => Promise<void>;
}> {
  const active = requiredClient();
  const crypto = active.getCrypto();
  if (!crypto) throw new Error("Encryption is unavailable");
  const request = deviceId
    ? await crypto.requestDeviceVerification(active.getSafeUserId(), deviceId)
    : await crypto.requestOwnUserVerification();
  return bindVerificationRequest(request, onSas, onState);
}

export async function requestUserVerification(
  userId: string,
  onSas: (challenge: SasChallenge) => void,
  onState: (state: string) => void,
): Promise<{
  transactionId: string | undefined;
  otherDeviceId: string | undefined;
  cancel: () => Promise<void>;
}> {
  const active = requiredClient();
  const crypto = active.getCrypto();
  if (!crypto) throw new Error("Encryption is unavailable");
  const sharedRoomId = active
    .getRooms()
    .filter((room) => room.getMyMembership() === "join" && room.getMember(userId)?.membership === "join")
    .sort((left, right) => left.getJoinedMemberCount() - right.getJoinedMemberCount())[0]?.roomId;
  const request = sharedRoomId
    ? await crypto.requestVerificationDM(userId, sharedRoomId)
    : await crypto.requestDeviceVerification(userId, await firstUnverifiedDeviceId(crypto, userId));
  return bindVerificationRequest(request, onSas, onState);
}

async function firstUnverifiedDeviceId(crypto: CryptoApi, userId: string): Promise<string> {
  const devices = await crypto.getUserDeviceInfo([userId], true);
  const map = devices.get(userId);
  if (!map || map.size === 0) throw new Error("No devices to verify");
  for (const [id, device] of map) {
    if (device.verified !== DeviceVerification.Verified) return id;
  }
  throw new Error("No unverified device");
}

export function getCallCapability(roomId: string): {
  available: boolean;
  active: boolean;
  groupActive: boolean;
  reason?: string;
} {
  const active = client;
  const room = active?.getRoom(roomId);
  if (!active || !room) {
    return { available: false, active: false, groupActive: false, reason: "Room is not available" };
  }
  const mediaAvailable =
    typeof RTCPeerConnection !== "undefined"
    && typeof navigator.mediaDevices?.getUserMedia === "function";
  // matrix-js-sdk caches an empty MatrixRTC session per room after Room events;
  // Boolean(session) alone is always true. Require live memberships.
  const session = active.matrixRTC.getActiveRoomSession(room);
  const memberships = session?.memberships;
  const direct = directCallController?.snapshot;
  const groupActive = Boolean(
    (memberships && memberships.length > 0)
    || callMemberEventsFromRoom(room).some((event) => isActiveCallMemberContent(event.content)),
  );
  const callActive =
    groupActive
    || Boolean(direct?.call && direct.roomId === roomId);
  return {
    available: window.isSecureContext && mediaAvailable,
    active: callActive,
    groupActive,
    ...(!window.isSecureContext
      ? { reason: "Calls require a secure HTTPS context" }
      : !mediaAvailable
        ? { reason: "This browser does not expose WebRTC media devices" }
        : {}),
  };
}

export function subscribeMatrixRtc(listener: () => void): () => void {
  matrixRtcListeners.add(listener);
  return () => matrixRtcListeners.delete(listener);
}

export function getMatrixRtcSnapshot(): MatrixRtcSnapshot {
  return matrixRtcController?.snapshot ?? idleMatrixRtc;
}

export function startMatrixRtc(roomId: string, options?: { camera?: boolean }): Promise<void> {
  const capability = getCallCapability(roomId);
  if (!capability.available) {
    return Promise.reject(new Error(capability.reason ?? "Calls are unavailable"));
  }
  if (!matrixRtcController) return Promise.reject(new Error("Sign in to call"));
  dismissedRtcInvites.delete(roomId);
  return matrixRtcController.join(roomId, options);
}

export function leaveMatrixRtc(): Promise<void> {
  return matrixRtcController?.leave() ?? Promise.resolve();
}

export function toggleMatrixRtcMicrophone(): Promise<void> {
  if (!matrixRtcController) return Promise.reject(new Error("No active call"));
  return matrixRtcController.toggleMicrophone();
}

export function toggleMatrixRtcCamera(): Promise<void> {
  if (!matrixRtcController) return Promise.reject(new Error("No active call"));
  return matrixRtcController.toggleCamera();
}

export function getGroupCallUrl(roomId: string): string | null {
  return buildElementCallUrl({
    baseUrl: (import.meta.env.VITE_ELEMENT_CALL_URL as string | undefined)?.trim(),
    parentUrl: (import.meta.env.VITE_ELEMENT_CALL_PARENT_URL as string | undefined)?.trim(),
    roomId,
    identity: getSessionIdentity(),
    allowHttpInDev: Boolean(import.meta.env.DEV),
    windowOrigin: typeof window === "undefined" ? undefined : window.location.origin,
  });
}

export function subscribeDirectCall(listener: () => void): () => void {
  directCallListeners.add(listener);
  return () => directCallListeners.delete(listener);
}

export function getDirectCallSnapshot(): DirectCallSnapshot {
  return directCallController?.snapshot ?? idleDirectCall;
}

export function startDirectCall(roomId: string, options?: { video?: boolean }): Promise<void> {
  const capability = getCallCapability(roomId);
  if (!capability.available) {
    return Promise.reject(new Error(capability.reason ?? "Calls are unavailable"));
  }
  if (!directCallController) return Promise.reject(new Error("Sign in to call"));
  const room = client?.getRoom(roomId);
  if (room?.hasEncryptionStateEvent() && !client?.getCrypto()) {
    return Promise.reject(new Error(DIRECT_CALL_CRYPTO_UNAVAILABLE));
  }
  return directCallController.start(roomId, options);
}

export async function startOutgoingCall(roomId: string, options?: { video?: boolean }): Promise<void> {
  const capability = getCallCapability(roomId);
  if (!capability.available) {
    throw new Error(capability.reason ?? "Calls are unavailable");
  }
  const room = client?.getRoom(roomId);
  const mode = outgoingCallMode({
    isDirect: Boolean(room?.getDMInviter() || room?.guessDMUserId()),
    encrypted: Boolean(room?.hasEncryptionStateEvent()),
    cryptoReady: Boolean(client?.getCrypto()),
    matrixRtcAvailable: Boolean(discoverLivekitFocus(client?.getClientWellKnown(), livekitFallbackUrl())),
  });
  if (mode === "matrixrtc") {
    await startMatrixRtc(roomId, matrixRtcCameraOptions(options));
    return;
  }
  if (mode === "direct") {
    await startDirectCall(roomId, options);
    return;
  }
  throw new Error(DIRECT_CALL_CRYPTO_UNAVAILABLE);
}

export function getIncomingRtcCall(): { roomId: string; name: string } | null {
  if (!client) return null;
  const phase = matrixRtcController?.snapshot.phase;
  if (phase === "connecting" || phase === "connected") return null;
  const self = client.getUserId();
  if (!self) return null;
  const incoming = pickIncomingRtcCall({
    selfUserId: self,
    dismissedRoomIds: dismissedRtcInvites,
    rooms: client.getRooms()
      .filter((room) => room.getMyMembership() === "join")
      .map((room) => ({
        roomId: room.roomId,
        name: room.name,
        members: callMemberEventsFromRoom(room),
      })),
  });
  if (!incoming) {
    for (const roomId of [...dismissedRtcInvites]) {
      const room = client.getRoom(roomId);
      if (!room || !callMemberEventsFromRoom(room).some((event) => isActiveCallMemberContent(event.content))) {
        dismissedRtcInvites.delete(roomId);
      }
    }
    return null;
  }
  return { roomId: incoming.roomId, name: incoming.name };
}

export async function dismissIncomingRtcCall(roomId: string): Promise<void> {
  dismissedRtcInvites.add(roomId);
  publish();
  try {
    await requiredClient().sendEvent(roomId, MSC4310_DECLINE as typeof EventType.RoomMessage, rtcDeclineContent() as never);
  } catch {
    try {
      await requiredClient().sendEvent(roomId, MSC4310_DECLINE_UNSTABLE as typeof EventType.RoomMessage, rtcDeclineContent() as never);
    } catch {
      /* older homeserver */
    }
  }
}

export function acceptDirectCall(options?: { video?: boolean }): Promise<void> {
  if (!directCallController) return Promise.reject(new Error("No incoming call"));
  return directCallController.accept(options);
}

export function rejectDirectCall(): void {
  directCallController?.reject();
}

export function hangupDirectCall(): void {
  if (!directCallController) return;
  if (directCallController.snapshot.call) directCallController.hangup();
  else directCallController.clearEnded();
}

export function toggleDirectCallMicrophone(): Promise<void> {
  if (!directCallController) return Promise.reject(new Error("No active call"));
  return directCallController.toggleMicrophone();
}

export function toggleDirectCallCamera(): Promise<void> {
  if (!directCallController) return Promise.reject(new Error("No active call"));
  return directCallController.toggleCamera();
}

export function getSessionIdentity(): {
  userId: string;
  deviceId: string;
  baseUrl: string;
} | null {
  if (!client?.getUserId() || !client.getDeviceId()) return null;
  return {
    userId: client.getSafeUserId(),
    deviceId: client.getDeviceId()!,
    baseUrl: client.baseUrl,
  };
}

export function mediaUrl(mxcUrl: string): string {
  return requiredClient().mxcUrlToHttp(mxcUrl, undefined, undefined, undefined, true) ?? "";
}

export function threadTimeline(roomId: string, rootId: string): TimelineItem[] {
  const all = roomTimeline(roomId);
  const live = client?.getRoom(roomId)?.getLiveTimeline().getEvents() ?? [];
  const extra = normalizeTimeline(
    live
      .filter((event) => threadRootId(event.getContent() as Record<string, unknown>) === rootId || event.getId() === rootId)
      .map((event) => rawEvent(event, client!.getRoom(roomId)!, client!.getUserId() ?? "")),
    {
      roomId,
      ownUserId: client?.getUserId() ?? "",
      memberNames: Object.fromEntries(
        (client?.getRoom(roomId)?.getJoinedMembers() ?? []).map((member) => [member.userId, member.name || member.userId]),
      ),
    },
  );
  const byId = new Map<string, TimelineItem>();
  for (const item of [...all.filter((item) => item.eventId === rootId || item.threadRootId === rootId), ...extra]) {
    byId.set(item.eventId, item);
  }
  return [...byId.values()].sort((a, b) => a.timestamp - b.timestamp);
}

export async function subscribeToThread(roomId: string, rootId: string): Promise<void> {
  const active = requiredClient();
  await active.http.authedRequest(
    "PUT" as never,
    threadSubscriptionPath(roomId, rootId),
    undefined,
    { automatic: false },
  );
}

export async function unsubscribeFromThread(roomId: string, rootId: string): Promise<void> {
  const active = requiredClient();
  await active.http.authedRequest("DELETE" as never, threadSubscriptionPath(roomId, rootId));
}

export async function sendLocation(
  roomId: string,
  lat: number,
  lon: number,
  description?: string,
  threadRootId?: string,
): Promise<void> {
  const active = requiredClient();
  const room = active.getRoom(roomId);
  const memberIds = room?.getJoinedMembers().map((member) => member.userId) ?? [];
  const content = attachMentions(locationContent(lat, lon, description), description ?? "", memberIds);
  if (threadRootId) content["m.relates_to"] = threadRelation(threadRootId, threadRootId, false);
  await active.sendEvent(roomId, EventType.RoomMessage, content as never);
  if (threadRootId) void subscribeToThread(roomId, threadRootId).catch(() => undefined);
}

export async function beginLinkDeviceQr(
  onFailure: (reason: string) => void,
  signal: AbortSignal,
) {
  return startLinkNewDeviceQr(requiredClient(), onFailure, signal);
}

export async function beginLoginQr(
  homeserver: string,
  onFailure: (reason: string) => void,
  signal: AbortSignal,
) {
  return startNewDeviceQr(homeserver, onFailure, signal);
}

export async function isQrLoginAvailable(): Promise<boolean> {
  try {
    return await qrLoginAvailable(requiredClient());
  } catch {
    return false;
  }
}

export function listImagePacks(): ImagePackItem[] {
  const active = client;
  if (!active) return [];
  const fromAccount = parseImagePack(
    (active.getAccountData(MSC2545_USER_EMOTES as typeof EventType.Direct)?.getContent() ?? {}) as Record<string, unknown>,
  );
  const fromRooms = active.getRooms().flatMap((room) => {
    const event = room.currentState.getStateEvents(MSC2545_PACK_STATE, "");
    return event ? parseImagePack(event.getContent() as Record<string, unknown>) : [];
  });
  const seen = new Set<string>();
  const out: ImagePackItem[] = [];
  for (const item of [...fromAccount, ...fromRooms]) {
    if (seen.has(item.url)) continue;
    seen.add(item.url);
    out.push(item);
  }
  return out;
}

export async function sendSticker(roomId: string, item: ImagePackItem, threadRootId?: string): Promise<void> {
  const content: Record<string, unknown> = stickerContent(item);
  if (threadRootId) content["m.relates_to"] = threadRelation(threadRootId, threadRootId, false);
  await requiredClient().sendEvent(roomId, STICKER_EVENT as typeof EventType.RoomMessage, content as never);
}

export function commandsForRoom(roomId: string): AdvertisedCommand[] {
  const room = client?.getRoom(roomId);
  if (!room) return [];
  const out: AdvertisedCommand[] = [];
  for (const type of ["dev.aiomatrix.commands", MSC4332_COMMANDS]) {
    for (const event of room.currentState.getStateEvents(type)) {
      out.push(...parseCommandsState(event.getContent() as Record<string, unknown>));
    }
  }
  return out;
}

export function suggestCommands(roomId: string, typed: string): AdvertisedCommand[] {
  return filterCommandSuggestions(commandsForRoom(roomId), typed);
}

export async function sendConversationReply(
  roomId: string,
  rootEventId: string,
  promptId: string,
  label: string,
): Promise<void> {
  await requiredClient().sendEvent(
    roomId,
    MSC4139_REPLY as typeof EventType.RoomMessage,
    conversationReplyContent(promptId, label, rootEventId) as never,
  );
  void subscribeToThread(roomId, rootEventId).catch(() => undefined);
}

export async function fetchRoomSummary(roomIdOrAlias: string): Promise<RoomSummary> {
  const active = requiredClient();
  const encoded = encodeURIComponent(roomIdOrAlias);
  try {
    const payload = await active.http.authedRequest("GET" as never, `${MSC3266_SUMMARY}/${encoded}`);
    return parseRoomSummary(payload as Record<string, unknown>, roomIdOrAlias);
  } catch {
    const payload = await active.http.authedRequest("GET" as never, `${MSC3266_SUMMARY_UNSTABLE}/${encoded}`);
    return parseRoomSummary(payload as Record<string, unknown>, roomIdOrAlias);
  }
}

export async function knockOnRoom(roomIdOrAlias: string): Promise<void> {
  const active = requiredClient();
  if (typeof active.knockRoom === "function") {
    await active.knockRoom(roomIdOrAlias);
    return;
  }
  await active.http.authedRequest(
    "POST" as never,
    `/_matrix/client/v3/knock/${encodeURIComponent(roomIdOrAlias)}`,
    undefined,
    {},
  );
}

export function listRoomKnocks(roomId: string): Array<{ userId: string; name: string }> {
  const room = client?.getRoom(roomId);
  if (!room) return [];
  return room.getMembers()
    .filter((member) => member.membership === "knock")
    .map((member) => ({ userId: member.userId, name: member.name || member.userId }));
}

export async function approveKnock(roomId: string, userId: string): Promise<void> {
  await requiredClient().invite(roomId, userId);
}

export async function denyKnock(roomId: string, userId: string): Promise<void> {
  await requiredClient().kick(roomId, userId);
}

export async function markThreadRead(roomId: string, eventId: string): Promise<void> {
  const room = requiredClient().getRoom(roomId);
  const event = room?.findEventById(eventId);
  if (!event) return;
  await requiredClient().sendReadReceipt(event, ReceiptType.ReadPrivate, false);
}

window.addEventListener("online", () => publish({ connection: client ? "syncing" : "offline" }));
window.addEventListener("offline", () => publish({ connection: "offline" }));

