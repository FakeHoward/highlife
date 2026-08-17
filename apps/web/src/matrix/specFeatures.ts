/** Wire helpers for Element-parity MSCs. Keep this file free of the live client. */

export const MSC4139_PROMPTS = "org.matrix.msc4139.prompts";
export const MSC4139_USED_PROMPT = "org.matrix.msc4139.used_prompt";
export const MSC4139_REPLY = "org.matrix.msc4139.conversation.reply";
export const MSC4332_COMMANDS = "org.matrix.msc4332.commands";
export const MSC4310_DECLINE = "m.rtc.decline";
export const MSC4310_DECLINE_UNSTABLE = "org.matrix.msc4310.rtc.decline";
export const MSC2545_PACK_STATE = "im.ponies.room_emotes";
export const MSC2545_USER_EMOTES = "im.ponies.user_emotes";
export const MSC4306_SUBSCRIPTION_PREFIX = "/_matrix/client/unstable/org.matrix.msc4306/rooms";
export const MSC3266_SUMMARY = "/_matrix/client/v1/room_summary";
export const MSC3266_SUMMARY_UNSTABLE = "/_matrix/client/unstable/im.nheko.summary/summary";
export const MSC4039_UPLOAD = "org.matrix.msc4039.upload_file";
export const MSC4039_DOWNLOAD = "org.matrix.msc4039.download_file";
export const STICKER_EVENT = "m.sticker";

export type IntentionalMentions = {
  user_ids: string[];
  room?: boolean;
};

export function intentionalMentions(
  body: string,
  memberIds: readonly string[],
): IntentionalMentions {
  const user_ids = [...new Set(memberIds.filter((id) => id && body.includes(id)))];
  const room = /(^|\s)@room\b/i.test(body);
  return room ? { user_ids, room: true } : { user_ids };
}

export function attachMentions(
  content: Record<string, unknown>,
  body: string,
  memberIds: readonly string[],
): Record<string, unknown> {
  return { ...content, "m.mentions": intentionalMentions(body, memberIds) };
}

export type ThreadRelation = {
  rel_type: "m.thread";
  event_id: string;
  is_falling_back: boolean;
  "m.in_reply_to": { event_id: string };
};

export function threadRelation(
  rootId: string,
  replyToId = rootId,
  fallback?: boolean,
): ThreadRelation {
  return {
    rel_type: "m.thread",
    event_id: rootId,
    is_falling_back: fallback ?? replyToId === rootId,
    "m.in_reply_to": { event_id: replyToId },
  };
}

export function threadRootId(content: Record<string, unknown>): string | undefined {
  const rel = content["m.relates_to"];
  if (!rel || typeof rel !== "object" || Array.isArray(rel)) return undefined;
  const relation = rel as Record<string, unknown>;
  if (relation.rel_type !== "m.thread") return undefined;
  return typeof relation.event_id === "string" ? relation.event_id : undefined;
}

export function isThreadFallback(content: Record<string, unknown>): boolean {
  const rel = content["m.relates_to"];
  if (!rel || typeof rel !== "object" || Array.isArray(rel)) return false;
  return (rel as { is_falling_back?: boolean }).is_falling_back === true;
}

/** Main timeline keeps roots and fallback previews; in-thread replies stay in the panel. */
export function belongsOnMainTimeline(content: Record<string, unknown>): boolean {
  const root = threadRootId(content);
  if (!root) return true;
  return isThreadFallback(content);
}

export type GeoPoint = { lat: number; lon: number; description?: string; geoUri: string };

export function parseGeoUri(value: string): { lat: number; lon: number } | null {
  const match = value.trim().match(/^geo:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?:;|$)/i);
  if (!match) return null;
  const lat = Number(match[1]);
  const lon = Number(match[2]);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
  return { lat, lon };
}

export function locationContent(lat: number, lon: number, description?: string): Record<string, unknown> {
  const geoUri = `geo:${lat},${lon}`;
  const body = description?.trim() || geoUri;
  return {
    msgtype: "m.location",
    body,
    geo_uri: geoUri,
    "org.matrix.msc3488.location": { uri: geoUri, ...(description ? { description } : {}) },
    "org.matrix.msc3488.ts": Date.now(),
    "org.matrix.msc1767.text": body,
  };
}

export function parseLocationContent(content: Record<string, unknown>): GeoPoint | null {
  const nested = content["org.matrix.msc3488.location"];
  const uri =
    (nested && typeof nested === "object" && !Array.isArray(nested)
      ? (nested as { uri?: unknown }).uri
      : undefined) ?? content.geo_uri;
  if (typeof uri !== "string") return null;
  const parsed = parseGeoUri(uri);
  if (!parsed) return null;
  const description =
    (nested && typeof nested === "object" && !Array.isArray(nested)
      ? (nested as { description?: unknown }).description
      : undefined) ?? content.body;
  return {
    ...parsed,
    geoUri: uri,
    ...(typeof description === "string" ? { description } : {}),
  };
}

export function openStreetMapUrl(lat: number, lon: number): string {
  return `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=16/${lat}/${lon}`;
}

export type ImagePackItem = {
  shortcode: string;
  url: string;
  body: string;
  usage: string[];
};

export function parseImagePack(content: Record<string, unknown>): ImagePackItem[] {
  const images = content.images;
  if (!images || typeof images !== "object" || Array.isArray(images)) return [];
  const out: ImagePackItem[] = [];
  for (const [shortcode, raw] of Object.entries(images as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    const item = raw as Record<string, unknown>;
    const url = typeof item.url === "string" ? item.url : undefined;
    if (!url?.startsWith("mxc://")) continue;
    const usage = Array.isArray(item.usage)
      ? item.usage.filter((value): value is string => typeof value === "string")
      : ["sticker", "emoticon"];
    out.push({
      shortcode,
      url,
      body: typeof item.body === "string" ? item.body : shortcode,
      usage,
    });
  }
  return out;
}

export function stickerContent(item: ImagePackItem): Record<string, unknown> {
  return {
    body: item.body,
    url: item.url,
    info: { mimetype: "image/png" },
  };
}

export type AdvertisedCommand = {
  name: string;
  aliases: string[];
  description?: string;
  args?: string[];
};

export function parseCommandsState(content: Record<string, unknown>): AdvertisedCommand[] {
  const nested = content[MSC4332_COMMANDS];
  const source =
    nested && typeof nested === "object" && !Array.isArray(nested)
      ? (nested as Record<string, unknown>)
      : content;
  const raw = source.commands;
  if (!Array.isArray(raw)) return [];
  const out: AdvertisedCommand[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const row = item as Record<string, unknown>;
    const name = typeof row.name === "string" ? row.name : "";
    if (!name) continue;
    const aliases = Array.isArray(row.aliases)
      ? row.aliases.filter((value): value is string => typeof value === "string")
      : [];
    const args = Array.isArray(row.args)
      ? row.args.filter((value): value is string => typeof value === "string")
      : undefined;
    out.push({
      name,
      aliases,
      ...(typeof row.description === "string" ? { description: row.description } : {}),
      ...(args ? { args } : {}),
    });
  }
  return out;
}

export function filterCommandSuggestions(
  commands: readonly AdvertisedCommand[],
  typed: string,
): AdvertisedCommand[] {
  const t = typed.trim();
  if (!t.startsWith("/") && !t.startsWith("!")) return [];
  const q = t.slice(1).toLowerCase();
  return commands
    .filter(
      (command) =>
        command.name.toLowerCase().startsWith(q) ||
        command.aliases.some((alias) => alias.toLowerCase().startsWith(q)),
    )
    .slice(0, 8);
}

export function completeCommand(command: AdvertisedCommand, typed: string): string {
  const prefix = typed.trimStart().startsWith("!") ? "!" : "/";
  return `${prefix}${command.name} `;
}

export type Msc4139Prompt = {
  id: string;
  type: "preset" | "input";
  label: string;
  validator?: string;
};

export type Msc4139Prompts = {
  intro?: string;
  scope?: string[];
  prompts: Msc4139Prompt[];
};

function promptLabel(label: unknown): string {
  if (typeof label === "string") return label;
  if (!label || typeof label !== "object" || Array.isArray(label)) return "";
  const text = (label as { "org.matrix.msc1767.text"?: unknown; "m.text"?: unknown })["m.text"]
    ?? (label as { "org.matrix.msc1767.text"?: unknown })["org.matrix.msc1767.text"];
  if (Array.isArray(text) && text[0] && typeof text[0] === "object") {
    const body = (text[0] as { body?: unknown }).body;
    if (typeof body === "string") return body;
  }
  if (typeof text === "string") return text;
  return "";
}

export function parseMsc4139Prompts(content: Record<string, unknown>): Msc4139Prompts | null {
  const raw = content[MSC4139_PROMPTS] ?? content["m.prompts"];
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const block = raw as Record<string, unknown>;
  const promptsRaw = block.prompts;
  if (!Array.isArray(promptsRaw)) return null;
  const prompts: Msc4139Prompt[] = [];
  for (const item of promptsRaw) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const row = item as Record<string, unknown>;
    const id = typeof row.id === "string" ? row.id : "";
    if (!id) continue;
    prompts.push({
      id,
      type: row.type === "input" ? "input" : "preset",
      label: promptLabel(row.label) || id,
      ...(typeof row.validator === "string" ? { validator: row.validator } : {}),
    });
  }
  if (prompts.length === 0) return null;
  const intro = promptLabel((block.intro as { content?: unknown } | undefined)?.content)
    || (typeof block.intro === "string" ? block.intro : undefined);
  const scope = Array.isArray(block.scope)
    ? block.scope.filter((value): value is string => typeof value === "string")
    : undefined;
  return { prompts, ...(intro ? { intro } : {}), ...(scope ? { scope } : {}) };
}

export function conversationReplyContent(promptId: string, label: string, rootEventId: string): Record<string, unknown> {
  return {
    [MSC4139_USED_PROMPT]: { id: promptId },
    "org.matrix.msc1767.text": label,
    body: label,
    msgtype: "m.text",
    "m.relates_to": threadRelation(rootEventId),
    "m.in_reply_to": { event_id: rootEventId, rel_type: "m.thread" },
  };
}

export function rtcDeclineContent(notificationEventId?: string): Record<string, unknown> {
  return {
    ...(notificationEventId ? { "m.relates_to": { rel_type: "m.reference", event_id: notificationEventId } } : {}),
  };
}

export function threadSubscriptionPath(roomId: string, threadRootId: string): string {
  return `${MSC4306_SUBSCRIPTION_PREFIX}/${encodeURIComponent(roomId)}/thread/${encodeURIComponent(threadRootId)}/subscription`;
}

export const PROFILE_ABOUT_KEY = "com.highlife.about";

export function parseProfileAbout(profile: Record<string, unknown>): string | undefined {
  const value = profile[PROFILE_ABOUT_KEY];
  return typeof value === "string" && value.trim() ? value : undefined;
}

const HTTP_URL = /\bhttps?:\/\/[^\s<>"']+/i;

export function firstHttpUrl(body: string): string | undefined {
  const match = body.match(HTTP_URL);
  if (!match) return undefined;
  return match[0].replace(/[),.;]+$/, "");
}

export type UrlPreview = {
  url: string;
  title?: string;
  description?: string;
  image?: string;
};

export function parseUrlPreview(payload: Record<string, unknown>, fallbackUrl: string): UrlPreview | null {
  const title = typeof payload["og:title"] === "string" ? payload["og:title"] : undefined;
  const description = typeof payload["og:description"] === "string" ? payload["og:description"] : undefined;
  const image = typeof payload["og:image"] === "string" ? payload["og:image"] : undefined;
  const rawUrl = typeof payload["og:url"] === "string" ? payload["og:url"] : fallbackUrl;
  const url = safeHttpUrl(rawUrl) ?? safeHttpUrl(fallbackUrl);
  if (!url) return null;
  if (!title && !description && !image) return null;
  return { url, ...(title ? { title } : {}), ...(description ? { description } : {}), ...(image ? { image } : {}) };
}

function safeHttpUrl(value: string): string | null {
  try {
    const parsed = new URL(value);
    if (parsed.protocol === "https:" || parsed.protocol === "http:") return parsed.toString();
  } catch {
    /* ignore */
  }
  return null;
}

export function urlPreviewCapabilityEnabled(capabilities: Record<string, unknown> | undefined): boolean {
  if (!capabilities) return false;
  const keys = ["org.matrix.msc4452", "m.url_preview"] as const;
  for (const key of keys) {
    const value = capabilities[key];
    if (value && typeof value === "object" && !Array.isArray(value) && (value as { enabled?: unknown }).enabled === true) {
      return true;
    }
  }
  return false;
}

export function slidingSyncSupported(unstable: Record<string, unknown> | undefined): boolean {
  if (!unstable) return false;
  return unstable["org.matrix.simplified_msc3575"] === true
    || unstable["org.matrix.msc4186"] === true
    || unstable["org.matrix.msc3575"] === true;
}

/**
 * Room state Sliding Sync should keep. `["*", "*"]` dumps every membership
 * change and makes Megolm rotate on historical leaves.
 */
export const SLIDING_SYNC_REQUIRED_STATE: string[][] = [
  ["m.room.create", ""],
  ["m.room.name", ""],
  ["m.room.avatar", ""],
  ["m.room.topic", ""],
  ["m.room.canonical_alias", ""],
  ["m.room.encryption", ""],
  ["m.room.power_levels", ""],
  ["m.room.join_rules", ""],
  ["m.room.guest_access", ""],
  ["m.room.history_visibility", ""],
  ["m.room.tombstone", ""],
  ["m.room.member", "$LAZY"],
  ["m.room.member", "$ME"],
  ["m.space.child", "*"],
  ["m.space.parent", "*"],
  ["org.matrix.msc3401.call", "*"],
  ["org.matrix.msc3401.call.member", "*"],
  ["dev.aiomatrix.host", "*"],
  ["im.vector.modular.widgets", "*"],
  [MSC2545_PACK_STATE, "*"],
];

export function slidingSyncRoomSubscription(): {
  timeline_limit: number;
  required_state: string[][];
} {
  return { timeline_limit: 50, required_state: SLIDING_SYNC_REQUIRED_STATE };
}

export function defaultSlidingLists(): Map<string, {
  ranges: number[][];
  sort: string[];
  timeline_limit: number;
  required_state: string[][];
}> {
  return new Map([
    ["all", {
      ranges: [[0, 99]],
      sort: ["by_notification_level", "by_recency"],
      ...slidingSyncRoomSubscription(),
    }],
  ]);
}

export type RoomSummary = {
  roomId: string;
  name?: string;
  topic?: string;
  avatarUrl?: string;
  joinRule?: string;
  guestCanJoin?: boolean;
  numJoinedMembers?: number;
  worldReadable?: boolean;
};

export function parseRoomSummary(payload: Record<string, unknown>, fallbackId: string): RoomSummary {
  return {
    roomId: typeof payload.room_id === "string" ? payload.room_id : fallbackId,
    ...(typeof payload.name === "string" ? { name: payload.name } : {}),
    ...(typeof payload.topic === "string" ? { topic: payload.topic } : {}),
    ...(typeof payload.avatar_url === "string" ? { avatarUrl: payload.avatar_url } : {}),
    ...(typeof payload.join_rule === "string" ? { joinRule: payload.join_rule } : {}),
    ...(typeof payload.guest_can_join === "boolean" ? { guestCanJoin: payload.guest_can_join } : {}),
    ...(typeof payload.num_joined_members === "number" ? { numJoinedMembers: payload.num_joined_members } : {}),
    ...(typeof payload.world_readable === "boolean" ? { worldReadable: payload.world_readable } : {}),
  };
}

export function knockMembers(events: Array<{ sender: string; content: Record<string, unknown> }>): string[] {
  return events
    .filter((event) => event.content.membership === "knock")
    .map((event) => event.sender);
}

export const WIDGET_MSC4039_CAPABILITIES = [
  MSC4039_UPLOAD,
  MSC4039_DOWNLOAD,
  "org.matrix.msc2762.send.event:m.sticker",
  "org.matrix.msc2762.receive.event:m.sticker",
] as const;
