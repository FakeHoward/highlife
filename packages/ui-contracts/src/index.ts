export type MessageKind =
  | "text"
  | "notice"
  | "image"
  | "video"
  | "audio"
  | "file"
  | "poll"
  | "system"
  | "sticker"
  | "location";

export type DeliveryStatus =
  | "encrypting"
  | "sending"
  | "queued"
  | "sent"
  | "not_sent"
  | "cancelled"
  | "delivered"
  | "read";

export const AIOMATRIX_CALLBACK_EVENT_TYPE = "dev.aiomatrix.callback";
export const AIOMATRIX_CALLBACK_ANSWER_EVENT_TYPE = "dev.aiomatrix.callback_answer";
export const AIOMATRIX_TOAST_EVENT_TYPE = "dev.aiomatrix.toast";
export const AIOMATRIX_PROGRESS_EVENT_TYPE = "dev.aiomatrix.progress";
export const AIOMATRIX_HOST_STATE_EVENT_TYPE = "dev.aiomatrix.host";
export const AIOMATRIX_HOST_CAPABILITIES_SCHEMA_VERSION = 1;

/** Aware-host handshake for `dev.aiomatrix.host` room state. */
export function buildHostCapabilitiesContent(): Record<string, unknown> {
  return {
    version: AIOMATRIX_HOST_CAPABILITIES_SCHEMA_VERSION,
    client_profile: "aware",
    features: [
      "keyboard",
      "callback_answer",
      "toast",
      "progress",
      "poll_ui",
      "mini_app",
    ],
    keyboard: true,
    callback_answer: true,
    toast: true,
    progress: true,
    poll_ui: true,
    mini_app: true,
  };
}

export interface HostToast {
  id: number;
  text: string;
  alert?: boolean;
}

export interface EncryptedFileDescriptor {
  mxcUrl: string;
  key: Record<string, unknown>;
  iv: string;
  sha256: string;
  v: string;
}

export interface MediaDescriptor {
  mxcUrl: string;
  name: string;
  mimeType?: string;
  size?: number;
  width?: number;
  height?: number;
  /** Present when attachment bytes are encrypted at rest (Matrix file encryption). */
  encrypted?: EncryptedFileDescriptor;
  voice?: boolean;
  durationMs?: number;
}

export interface ReactionSummary {
  key: string;
  count: number;
  reactedByMe: boolean;
  /** Event id of the current user's annotation, when `reactedByMe` is true. */
  ownEventId?: string;
}

export interface PollAnswerOption {
  id: string;
  text: string;
}

export interface PollDescriptor {
  question: string;
  answers: PollAnswerOption[];
  maxSelections: number;
  disclosed: boolean;
  ended: boolean;
  counts: Record<string, number>;
  mySelections: string[];
  totalVoters: number;
}

export interface TimelineItem {
  eventId: string;
  roomId: string;
  senderId: string;
  senderName: string;
  senderAvatarUrl?: string;
  timestamp: number;
  body: string;
  formattedBody?: string;
  kind: MessageKind;
  isOwn: boolean;
  edited: boolean;
  redacted: boolean;
  replyToEventId?: string;
  replyPreview?: {
    senderId: string;
    senderName: string;
    body: string;
  };
  threadRootId?: string;
  threadReplyCount?: number;
  geoUri?: string;
  latitude?: number;
  longitude?: number;
  media?: MediaDescriptor;
  poll?: PollDescriptor;
  deliveryStatus?: DeliveryStatus;
  reactions: ReactionSummary[];
  rawContent: Record<string, unknown>;
}

export interface RoomListItem {
  roomId: string;
  name: string;
  topic?: string;
  avatarUrl?: string;
  canonicalAlias?: string;
  lastMessage?: string;
  unread: number;
  highlight: number;
  isDirect: boolean;
  isEncrypted: boolean;
  isSpace: boolean;
  membership: string;
  lastActive: number;
  /** Parent space room id when this room is nested under a space. */
  spaceParentId?: string;
  muted?: boolean;
}

export type ConnectionState = "booting" | "syncing" | "online" | "offline" | "error";

export interface SpaceSummary {
  roomId: string;
  name: string;
  topic?: string;
  avatarUrl?: string;
  childRoomIds: string[];
}
