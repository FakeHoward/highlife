export const DIRECT_CALL_MIC_BLOCKED = "mic_blocked";
export const DIRECT_CALL_CRYPTO_UNAVAILABLE = "crypto_unavailable";

export function classifyDirectCallFailure(reason: unknown): string {
  const name =
    reason && typeof reason === "object" && "name" in reason
      ? String((reason as { name?: unknown }).name)
      : "";
  const message =
    reason && typeof reason === "object" && "message" in reason
      ? String((reason as { message?: unknown }).message)
      : typeof reason === "string"
        ? reason
        : "";
  const code =
    reason && typeof reason === "object" && "code" in reason
      ? String((reason as { code?: unknown }).code)
      : "";
  if (
    name === "NotAllowedError" ||
    name === "NotFoundError" ||
    code === "no_user_media" ||
    /permission denied/i.test(message) ||
    /notallowederror/i.test(message)
  ) {
    return DIRECT_CALL_MIC_BLOCKED;
  }
  if (/does not support encryption/i.test(message) || /crypto_unavailable/.test(message)) {
    return DIRECT_CALL_CRYPTO_UNAVAILABLE;
  }
  return message || "Call failed";
}
