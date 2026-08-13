export const MSC3401_MEMBER_EVENT = "org.matrix.msc3401.call.member";

export interface LivekitFocusHint {
  type: "livekit";
  livekit_service_url: string;
  livekit_alias?: string;
}

export function userIdFromCallMember(stateKey: string, sender: string): string {
  const match = stateKey.match(/(@[^:]+:[^_]+)/);
  return match?.[1] ?? sender;
}

function expiresInPast(membership: Record<string, unknown>, nowMs: number): boolean {
  const expires = membership.expires_ts ?? membership.expires;
  return typeof expires === "number" && expires > 0 && expires <= nowMs;
}

/** True for MSC3401 nested memberships and MSC4143 slot events used by Element X. */
export function isActiveCallMemberContent(
  content: Record<string, unknown> | undefined,
  nowMs = Date.now(),
): boolean {
  if (!content || Object.keys(content).length === 0) return false;
  if (slotMembershipActive(content, nowMs)) return true;
  const memberships = content.memberships;
  if (!Array.isArray(memberships) || memberships.length === 0) return false;
  return memberships.some((raw) => {
    if (!raw || typeof raw !== "object") return false;
    return slotMembershipActive(raw as Record<string, unknown>, nowMs);
  });
}

function slotMembershipActive(membership: Record<string, unknown>, nowMs: number): boolean {
  if (expiresInPast(membership, nowMs)) return false;
  const kind = String(membership.membership ?? "").toLowerCase();
  if (kind === "leave" || kind === "hangup") return false;
  const application = membership.application;
  if (typeof application === "string" && application.length > 0) return true;
  const deviceId = membership.device_id;
  if (typeof deviceId === "string" && deviceId.length > 0) {
    return kind === "" || kind === "join" || kind === "call" || kind === "connected";
  }
  return false;
}

function livekitUrlFromFocus(value: unknown): LivekitFocusHint | null {
  if (!value || typeof value !== "object") return null;
  const rec = value as Record<string, unknown>;
  if (rec.type !== "livekit") return null;
  const url = typeof rec.livekit_service_url === "string"
    ? rec.livekit_service_url.trim().replace(/\/$/, "")
    : "";
  if (!url) return null;
  return {
    type: "livekit",
    livekit_service_url: url,
    ...(typeof rec.livekit_alias === "string" && rec.livekit_alias
      ? { livekit_alias: rec.livekit_alias }
      : {}),
  };
}

export function livekitFocusFromCallMemberContent(
  content: Record<string, unknown> | undefined,
): LivekitFocusHint | null {
  if (!content) return null;
  const lists = [content.foci_preferred, content.foci_active, content.foci];
  for (const list of lists) {
    if (!Array.isArray(list)) continue;
    for (const item of list) {
      const found = livekitUrlFromFocus(item);
      if (found) return found;
    }
  }
  const active = livekitUrlFromFocus(content.focus_active);
  if (active) return active;
  const memberships = content.memberships;
  if (Array.isArray(memberships)) {
    for (const raw of memberships) {
      if (!raw || typeof raw !== "object") continue;
      const nested = livekitFocusFromCallMemberContent(raw as Record<string, unknown>);
      if (nested) return nested;
    }
  }
  return null;
}

export interface CallMemberEventLike {
  stateKey?: string;
  sender?: string;
  content?: Record<string, unknown>;
}

export function rtcPeersFromMemberEvents(
  events: CallMemberEventLike[],
  selfUserId: string,
  nowMs = Date.now(),
): { others: string[]; selfPresent: boolean } {
  const others: string[] = [];
  let selfPresent = false;
  for (const event of events) {
    if (!isActiveCallMemberContent(event.content, nowMs)) continue;
    const userId = userIdFromCallMember(event.stateKey ?? "", event.sender ?? "");
    if (!userId) continue;
    if (userId === selfUserId) selfPresent = true;
    else if (!others.includes(userId)) others.push(userId);
  }
  return { others, selfPresent };
}

export function remoteLivekitFocusFromEvents(
  events: CallMemberEventLike[],
  selfUserId: string,
): LivekitFocusHint | null {
  for (const event of events) {
    const userId = userIdFromCallMember(event.stateKey ?? "", event.sender ?? "");
    if (userId === selfUserId) continue;
    const focus = livekitFocusFromCallMemberContent(event.content);
    if (focus) return focus;
  }
  return null;
}

export function pickIncomingRtcCall(input: {
  selfUserId: string;
  dismissedRoomIds: Iterable<string>;
  rooms: Array<{
    roomId: string;
    name: string;
    members: CallMemberEventLike[];
  }>;
  nowMs?: number;
}): { roomId: string; name: string; peerUserId: string } | null {
  const dismissed = new Set(input.dismissedRoomIds);
  for (const room of input.rooms) {
    if (dismissed.has(room.roomId)) continue;
    const { others, selfPresent } = rtcPeersFromMemberEvents(
      room.members,
      input.selfUserId,
      input.nowMs,
    );
    if (others.length > 0 && !selfPresent) {
      return { roomId: room.roomId, name: room.name, peerUserId: others[0]! };
    }
  }
  return null;
}
