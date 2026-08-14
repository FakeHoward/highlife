export function isRoomMutedByPushRules(
  roomRules: Array<{ rule_id?: string; enabled?: boolean; actions?: unknown[] }> | undefined,
  roomId: string,
): boolean {
  const rule = roomRules?.find((item) => item.rule_id === roomId);
  if (!rule || rule.enabled === false) return false;
  return (rule.actions ?? []).some((action) => action === "dont_notify");
}

export function togglePinnedIds(current: string[], eventId: string): string[] {
  if (current.includes(eventId)) return current.filter((id) => id !== eventId);
  return [...current, eventId];
}

export function firstUnreadEventId(
  eventIds: string[],
  readUpTo: string | null | undefined,
): string | null {
  if (eventIds.length === 0) return null;
  if (!readUpTo) return eventIds[0] ?? null;
  const index = eventIds.indexOf(readUpTo);
  if (index < 0) return eventIds[0] ?? null;
  return eventIds[index + 1] ?? null;
}

export function formatPresenceLabel(
  presence: string | undefined,
  lastActiveAgoMs: number | undefined,
  currentlyActive: boolean | undefined,
  labels: { online: string; away: string; offline: string; lastSeen: (when: string) => string },
): string {
  if (currentlyActive || presence === "online") return labels.online;
  if (presence === "unavailable") return labels.away;
  if (typeof lastActiveAgoMs === "number" && lastActiveAgoMs >= 0) {
    const at = new Date(Date.now() - lastActiveAgoMs);
    return labels.lastSeen(at.toLocaleString());
  }
  return labels.offline;
}

export function isVoiceMessageContent(content: Record<string, unknown> | undefined): boolean {
  if (!content) return false;
  return Boolean(content["org.matrix.msc3245.voice"]);
}

export function formatForwardedBody(senderName: string, body: string): string {
  const trimmed = body.trim();
  if (!trimmed) return senderName;
  return `${senderName}:\n${trimmed}`;
}

export function formatForwardedMedia(senderName: string, kind: string): string {
  const label = kind.trim() || "attachment";
  return `${senderName}:\n[${label}]`;
}

export function partitionInvitesAndJoined<T>(
  items: T[],
  membershipOf: (item: T) => string,
): { invites: T[]; joined: T[] } {
  const invites: T[] = [];
  const joined: T[] = [];
  for (const item of items) {
    const membership = membershipOf(item);
    if (membership === "invite") invites.push(item);
    else if (membership === "join") joined.push(item);
  }
  return { invites, joined };
}

export function notificationTargetFromPush(payload: Record<string, unknown> | null | undefined): string {
  const roomId = payload?.room_id ?? payload?.roomId;
  if (typeof roomId === "string" && roomId.startsWith("!")) {
    return `/?room=${encodeURIComponent(roomId)}`;
  }
  return "/";
}

function startOfLocalDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

function pad2(value: number): string {
  return String(value).padStart(2, "0");
}

/** Compact Telegram-style room list timestamp. */
export function formatRoomListTime(
  timestampMs: number,
  yesterdayLabel: string,
  nowMs = Date.now(),
): string {
  const dt = new Date(timestampMs);
  const now = new Date(nowMs);
  const today = startOfLocalDay(now);
  const yesterday = startOfLocalDay(
    new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1),
  );
  const day = startOfLocalDay(dt);
  const clock = `${pad2(dt.getHours())}:${pad2(dt.getMinutes())}`;
  if (day === today) return clock;
  if (day === yesterday) return yesterdayLabel;
  return `${pad2(dt.getDate())}.${pad2(dt.getMonth() + 1)}`;
}
