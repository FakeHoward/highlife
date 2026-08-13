export function isLikelyBotUserId(userId: string): boolean {
  const localpart = userId.startsWith("@")
    ? userId.slice(1).split(":")[0] ?? ""
    : userId;
  const key = localpart.toLowerCase();
  return key === "highlifebot" || key.endsWith("bot") || key.startsWith("bot");
}

/** True when commands state still has payload (ignore empty/redacted leftovers). */
export function hasActiveCommandsState(
  contents: Array<Record<string, unknown> | null | undefined>,
): boolean {
  return contents.some((content) => content != null && Object.keys(content).length > 0);
}

export function roomNeedsHostHandshake(input: {
  isDirect: boolean;
  memberUserIds: string[];
  hasCommandsState?: boolean;
}): boolean {
  if (input.hasCommandsState) return true;
  return input.memberUserIds.some(isLikelyBotUserId);
}
