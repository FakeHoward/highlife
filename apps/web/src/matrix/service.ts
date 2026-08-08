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
  buildHostCapabilitiesContent,
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
  RelationType,
  RoomEvent,
  RoomMemberEvent,
  type MatrixClient,
  type MatrixEvent,
  type Room,
} from "matrix-js-sdk";
import {
  CryptoEvent,
  decodeRecoveryKey,
  encodeRecoveryKey,
  type GeneratedSecretStorageKey,
  type KeyBackupInfo,
} from "matrix-js-sdk/lib/crypto-api";
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
import {
  buildPollEndContent,
  buildPollResponseContent,
  buildPollStartContent,
  POLL_END_UNSTABLE,
  POLL_RESPONSE_UNSTABLE,
  POLL_START_UNSTABLE,
} from "./polls";
import { joinRoomErrorMessage, normalizeRoomIdOrAlias } from "./roomAddress";
import {
  clearCryptoDatabases,
  clearSession,
  loadSession,
  saveSession,
  type StoredSession,
} from "./sessionStore";
import { registerPushAfterLogin } from "./push";
import { normalizeTimeline, type RawTimelineEvent } from "./timeline";

export { normalizeRoomIdOrAlias } from "./roomAddress";
export { registerPushAfterLogin } from "./push";

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
let hostCapsAdvertised = false;
const listeners = new Set<() => void>();
const historyStates = new Map<string, HistoryState>();
const threadTimelines = new Map<string, Awaited<ReturnType<MatrixClient["getThreadTimeline"]>>>();
const secretStorageKeys = new Map<string, Uint8Array<ArrayBuffer>>();
let cachedSecretStorageKey: { keyId: string; privateKey: Uint8Array<ArrayBuffer> } | null = null;
let pendingIncomingVerification: VerificationRequest | null = null;
const verificationListeners = new Set<() => void>();

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

/** Best-effort aware-host handshake (`dev.aiomatrix.host`). */
async function advertiseHostCapabilities(): Promise<void> {
  if (!client || hostCapsAdvertised) return;
  hostCapsAdvertised = true;
  const userId = client.getUserId();
  if (!userId) return;
  const content = buildHostCapabilitiesContent();
  for (const room of client.getRooms()) {
    if (room.getMyMembership() !== "join") continue;
    try {
      await client.sendStateEvent(
        room.roomId,
        AIOMATRIX_HOST_STATE_EVENT_TYPE as typeof EventType.RoomTopic,
        content as never,
        userId,
      );
    } catch {
      // Needs power level; aware bots already use toast profile.
    }
  }
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
  if (client) client.stopClient();
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
  publish({ connection: navigator.onLine ? "syncing" : "offline", error: null, toast: null });
  hostCapsAdvertised = false;
  client.on(ClientEvent.Sync, (state) => {
    publish({
      connection: state === "SYNCING" || state === "PREPARED" ? "online" : state === "ERROR" ? "error" : "syncing",
    });
    if (state === "PREPARED" || state === "SYNCING") {
      void advertiseHostCapabilities();
    }
  });
  client.on(RoomEvent.Timeline, (event, room, toStartOfTimeline) => {
    if (toStartOfTimeline || !room || !client) {
      publish();
      return;
    }
    maybeShowHostToast(event);
    publish();
  });
  client.on(RoomEvent.TimelineReset, () => publish());
  client.on(RoomEvent.Name, () => publish());
  client.on(RoomEvent.Receipt, () => publish());
  client.on(RoomEvent.LocalEchoUpdated, () => publish());
  client.on(RoomMemberEvent.Typing, () => publish());
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
  } catch (error) {
    publish({ error: `Encryption unavailable: ${messageOf(error)}` });
  }
  await client.startClient({ initialSyncLimit: 50 });
  void registerPushAfterLogin(client).catch(() => undefined);
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
    throw new Error("Username is required");
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
    const sessionId = uiaSessionFromError(error);
    if (!sessionId) throw error;
    if (!uiaAllowsDummy(error)) {
      throw new Error(
        "This homeserver needs extra verification (email, captcha, or SSO). HighLife supports open registration with dummy auth only.",
      );
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
      active.stopClient();
    }
  }
  client = null;
  pendingIncomingVerification = null;
  cachedSecretStorageKey = null;
  secretStorageKeys.clear();
  await clearSession();
  if (userId && deviceId) {
    await clearCryptoDatabases(userId, deviceId);
  }
  publish({ connection: "offline", error: null, toast: null });
  hostCapsAdvertised = false;
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
        lastMessage: last ? formatMessagePreview(lastContent) || undefined : undefined,
        unread: room.getUnreadNotificationCount(NotificationCountType.Total),
        highlight: room.getUnreadNotificationCount(NotificationCountType.Highlight),
        isDirect: Boolean(room.getDMInviter() || room.guessDMUserId()),
        isEncrypted: room.hasEncryptionStateEvent(),
        isSpace: room.isSpaceRoom(),
        membership: room.getMyMembership(),
        lastActive: room.getLastActiveTimestamp(),
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
  return normalizeTimeline(
    room.getLiveTimeline().getEvents().map((event) => rawEvent(event, room, ownUserId)),
    {
      roomId,
      ownUserId,
      memberNames: names,
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

export async function loadThread(roomId: string, rootEventId: string): Promise<TimelineItem[]> {
  const active = requiredClient();
  const room = active.getRoom(roomId);
  if (!room) throw new Error("Room is not available");
  const key = `${roomId}|${rootEventId}`;
  let timeline = threadTimelines.get(key);
  if (!timeline) {
    timeline = await active.getThreadTimeline(room.getUnfilteredTimelineSet(), rootEventId);
    threadTimelines.set(key, timeline);
  }
  const thread = room.getThread(rootEventId);
  const events = thread?.events ?? timeline?.getEvents() ?? [];
  const root = room.findEventById(rootEventId);
  const complete = root && !events.some((event) => event.getId() === rootEventId)
    ? [root, ...events]
    : events;
  const names = Object.fromEntries(
    room.getJoinedMembers().map((member) => [member.userId, member.name || member.userId]),
  );
  const ownUserId = active.getUserId() ?? "";
  return normalizeTimeline(complete.map((event) => rawEvent(event, room, ownUserId)), {
    roomId,
    ownUserId,
    memberNames: names,
  });
}

export async function paginateThread(roomId: string, rootEventId: string): Promise<boolean> {
  const active = requiredClient();
  const key = `${roomId}|${rootEventId}`;
  const timeline = threadTimelines.get(key);
  if (!timeline) {
    await loadThread(roomId, rootEventId);
  }
  const current = threadTimelines.get(key);
  if (!current) return false;
  return active.paginateEventTimeline(current, { backwards: true, limit: 30 });
}

export async function sendMessage(
  roomId: string,
  body: string,
  options: { editEventId?: string; replyEventId?: string; threadRootId?: string } = {},
): Promise<void> {
  const content: Record<string, unknown> = { msgtype: "m.text", body };
  if (options.editEventId) {
    content.body = `* ${body}`;
    content["m.new_content"] = { msgtype: "m.text", body };
    content["m.relates_to"] = { rel_type: "m.replace", event_id: options.editEventId };
  } else if (options.threadRootId) {
    content["m.relates_to"] = { rel_type: "m.thread", event_id: options.threadRootId };
  } else if (options.replyEventId) {
    content["m.relates_to"] = { "m.in_reply_to": { event_id: options.replyEventId } };
  }
  await requiredClient().sendEvent(roomId, EventType.RoomMessage, content as never);
}

export async function uploadFile(
  roomId: string,
  file: File,
  options: { replyEventId?: string; threadRootId?: string; onProgress?: (ratio: number) => void } = {},
): Promise<void> {
  const active = requiredClient();
  const room = active.getRoom(roomId);
  const encryptedRoom = Boolean(room?.hasEncryptionStateEvent());
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
    content["m.relates_to"] = { rel_type: "m.thread", event_id: options.threadRootId };
  } else if (options.replyEventId) {
    content["m.relates_to"] = { "m.in_reply_to": { event_id: options.replyEventId } };
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
    await active.sendReadReceipt(event);
    return;
  }
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
  invite?: string[];
  encrypted?: boolean;
  isSpace?: boolean;
}): Promise<string> {
  const response = await requiredClient().createRoom({
    name: input.name,
    topic: input.topic,
    invite: input.invite,
    preset: Preset.PrivateChat,
    room_version: input.isSpace ? "11" : undefined,
    creation_content: input.isSpace ? { type: "m.space" } : undefined,
    initial_state: input.encrypted
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
  try {
    return (await requiredClient().joinRoom(attempted)).roomId;
  } catch (error) {
    throw new Error(joinRoomErrorMessage(error, attempted));
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
  const room = client?.getRoom(roomId);
  if (!room) return [];
  return room
    .getJoinedMembers()
    .map((member) => ({
      userId: member.userId,
      displayName: member.name || member.userId,
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

export async function leaveRoom(roomId: string): Promise<void> {
  await requiredClient().leave(roomId);
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

export function rememberRecoveryKey(recoveryKey: string): string {
  const privateKey = decodeRecoveryKey(recoveryKey.trim());
  const key = privateKey as Uint8Array<ArrayBuffer>;
  cachedSecretStorageKey = { keyId: "recovery", privateKey: key };
  secretStorageKeys.set("recovery", key);
  return encodeRecoveryKey(privateKey) ?? recoveryKey.trim();
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
      displayName: device.displayName ?? "Unnamed device",
      fingerprint: device.getFingerprint() ?? null,
      current: device.deviceId === active.getDeviceId(),
      verified: status?.isVerified() ?? false,
      dehydrated: device.dehydrated,
    };
  }));
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

export function getCallCapability(roomId: string): {
  available: boolean;
  active: boolean;
  reason?: string;
} {
  const active = client;
  const room = active?.getRoom(roomId);
  if (!active || !room) return { available: false, active: false, reason: "Room is not available" };
  const callUrl = import.meta.env.VITE_ELEMENT_CALL_URL as string | undefined;
  let configured = false;
  try {
    const protocol = new URL(callUrl ?? "").protocol;
    configured = protocol === "https:" || (import.meta.env.DEV && protocol === "http:");
  } catch {
    configured = false;
  }
  return {
    available: window.isSecureContext && configured,
    active: Boolean(active.matrixRTC.getActiveRoomSession(room)),
    ...(!window.isSecureContext
      ? { reason: "Calls require a secure HTTPS context" }
      : !configured
        ? { reason: "No trusted Element Call deployment is configured" }
        : {}),
  };
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

window.addEventListener("online", () => publish({ connection: client ? "syncing" : "offline" }));
window.addEventListener("offline", () => publish({ connection: "offline" }));
