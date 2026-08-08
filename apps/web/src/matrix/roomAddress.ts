import { type Locale, translate } from "../i18n/messages";

/** Normalize bare names to `#name:homeserver` so join matches Matrix alias form. */
export function normalizeRoomIdOrAlias(input: string, homeserverHost?: string): string {
  const value = input.trim();
  if (!value) throw new Error("Room address is empty");
  if (value.startsWith("!") || value.startsWith("#")) {
    if (value.includes(":")) return value;
    if (!homeserverHost) {
      throw new Error("Room address needs a server, e.g. #room:example.org");
    }
    return `${value}:${homeserverHost}`;
  }
  if (!homeserverHost) {
    throw new Error("Room address needs a server, e.g. #room:example.org");
  }
  return `#${value}:${homeserverHost}`;
}

/** Server part of `#alias:server` / `!id:server` for federation via. */
export function serverFromRoomAddress(roomIdOrAlias: string): string | null {
  const colon = roomIdOrAlias.lastIndexOf(":");
  if (colon < 0) return null;
  const server = roomIdOrAlias.slice(colon + 1).trim();
  return server || null;
}

export type JoinFailKind = "banned" | "forbidden" | "not_found" | "bad_request" | "unknown";

export class JoinRoomFailure extends Error {
  readonly kind: JoinFailKind;
  readonly attempted: string;

  constructor(kind: JoinFailKind, attempted: string, message: string) {
    super(message);
    this.name = "JoinRoomFailure";
    this.kind = kind;
    this.attempted = attempted;
  }
}

export function classifyJoinRoomError(error: unknown): JoinFailKind {
  const status =
    error && typeof error === "object" && "httpStatus" in error
      ? Number((error as { httpStatus?: number }).httpStatus)
      : NaN;
  const errcode =
    error && typeof error === "object" && "errcode" in error
      ? String((error as { errcode?: string }).errcode)
      : "";
  const message =
    error instanceof Error
      ? error.message
      : error && typeof error === "object" && "message" in error
        ? String((error as { message?: string }).message)
        : String(error);
  const banned = /banned from (this )?room/i.test(message);
  if ((status === 403 || errcode === "M_FORBIDDEN" || banned) && banned) return "banned";
  if (status === 403 || errcode === "M_FORBIDDEN") return "forbidden";
  if (
    status === 404 ||
    errcode === "M_NOT_FOUND" ||
    message.includes("M_NOT_FOUND") ||
    message.includes("404")
  ) {
    return "not_found";
  }
  if (status === 400 || errcode === "M_UNKNOWN" || message.includes("400")) {
    return "bad_request";
  }
  return "unknown";
}

export function joinRoomErrorMessage(
  error: unknown,
  attempted: string,
  locale: Locale = "en",
): string {
  const kind = classifyJoinRoomError(error);
  switch (kind) {
    case "banned":
      return translate(locale, "rooms.joinBanned", { room: attempted });
    case "forbidden":
      return translate(locale, "rooms.joinForbidden", { room: attempted });
    case "not_found":
      return translate(locale, "rooms.joinNotFound", { room: attempted });
    case "bad_request":
      return translate(locale, "rooms.joinBadRequest", { room: attempted });
    default: {
      if (error instanceof Error && error.message) return error.message;
      if (error && typeof error === "object" && "message" in error) {
        const message = String((error as { message?: string }).message);
        if (message) return message;
      }
      return translate(locale, "rooms.requestFailed");
    }
  }
}

export function joinRoomFailure(error: unknown, attempted: string): JoinRoomFailure {
  const kind = classifyJoinRoomError(error);
  return new JoinRoomFailure(kind, attempted, joinRoomErrorMessage(error, attempted, "en"));
}
