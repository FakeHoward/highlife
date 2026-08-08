import { isSafeWebUrl } from "../protocol/aiomatrix";

export interface CallIdentity {
  userId: string;
  deviceId: string;
  baseUrl: string;
}

export function buildElementCallUrl(input: {
  baseUrl: string | undefined;
  parentUrl: string | undefined;
  roomId: string;
  identity: CallIdentity | null;
  allowHttpInDev?: boolean;
  windowOrigin?: string;
}): string | null {
  const { baseUrl, parentUrl, roomId, identity, allowHttpInDev = false, windowOrigin } = input;
  if (!baseUrl || !identity || !isSafeWebUrl(baseUrl, allowHttpInDev)) return null;
  const resolvedParent = parentUrl && isSafeWebUrl(parentUrl, allowHttpInDev)
    ? parentUrl
    : (windowOrigin ?? "");
  if (!resolvedParent) return null;
  try {
    const target = new URL(baseUrl);
    target.search = new URLSearchParams({
      widgetId: `highlife_call_${roomId}`,
      parentUrl: resolvedParent,
      roomId,
      userId: identity.userId,
      deviceId: identity.deviceId,
      baseUrl: identity.baseUrl,
    }).toString();
    return target.toString();
  } catch {
    return null;
  }
}

export function callWidgetId(roomId: string): string {
  return `highlife_call_${roomId}`;
}
