export function isLikelyBotUserId(userId: string): boolean {
  const localpart = userId.startsWith("@")
    ? userId.slice(1).split(":")[0] ?? ""
    : userId;
  const key = localpart.toLowerCase();
  return key === "highlifebot" || key.endsWith("bot") || key.startsWith("bot");
}

export function roomNeedsHostHandshake(input: {
  isDirect: boolean;
  memberUserIds: string[];
  hasCommandsState?: boolean;
}): boolean {
  if (input.hasCommandsState) return true;
  return input.memberUserIds.some(isLikelyBotUserId);
}
