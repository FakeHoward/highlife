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

export function joinRoomErrorMessage(error: unknown, attempted: string): string {
  const status =
    error && typeof error === "object" && "httpStatus" in error
      ? Number((error as { httpStatus?: number }).httpStatus)
      : NaN;
  const errcode =
    error && typeof error === "object" && "errcode" in error
      ? String((error as { errcode?: string }).errcode)
      : "";
  const message = error instanceof Error ? error.message : String(error);
  if (
    status === 404 ||
    errcode === "M_NOT_FOUND" ||
    message.includes("M_NOT_FOUND") ||
    message.includes("404")
  ) {
    return `Room not found: ${attempted}. Create it, or use a full alias like #room:server.`;
  }
  if (status === 400 || errcode === "M_UNKNOWN" || message.includes("400")) {
    return `Cannot join ${attempted}. Use #alias:server or !roomId:server.`;
  }
  return message || "Room request failed";
}
