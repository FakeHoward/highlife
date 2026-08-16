/** Localpart for MAS-compat password login (`@user:server` → `user`). */
export function localpartOf(userIdOrName: string): string {
  const trimmed = userIdOrName.trim().replace(/^@/, "");
  if (!trimmed) return "";
  return trimmed.split(":")[0] ?? "";
}

/** MAS/Synapse password login answers 403 M_FORBIDDEN for a bad identifier or password. */
export function isInvalidCredentialsError(reason: unknown): boolean {
  if (!reason || typeof reason !== "object") return false;
  const err = reason as {
    httpStatus?: number;
    statusCode?: number;
    errcode?: string;
    message?: string;
  };
  const status = err.httpStatus ?? err.statusCode;
  const message = err.message ?? "";
  if (status === 403 || err.errcode === "M_FORBIDDEN") return true;
  return /invalid username\/password/i.test(message) || /\[403\]/.test(message);
}
