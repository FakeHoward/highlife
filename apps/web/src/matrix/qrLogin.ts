import { createClient, type MatrixClient } from "matrix-js-sdk";
import {
  isSignInWithQRAvailable,
  linkNewDeviceByGeneratingQR,
  signInByGeneratingQR,
  type MSC4108SignInWithQR,
} from "matrix-js-sdk/lib/rendezvous";

export async function qrLoginAvailable(client: MatrixClient): Promise<boolean> {
  try {
    return await isSignInWithQRAvailable(client);
  } catch {
    return false;
  }
}

export async function startLinkNewDeviceQr(
  client: MatrixClient,
  onFailure: (reason: string) => void,
  signal: AbortSignal,
): Promise<MSC4108SignInWithQR> {
  return linkNewDeviceByGeneratingQR(client, (reason) => onFailure(String(reason)), signal);
}

export async function startNewDeviceQr(
  homeserver: string,
  onFailure: (reason: string) => void,
  signal: AbortSignal,
): Promise<MSC4108SignInWithQR> {
  const temp = createClient({ baseUrl: homeserver, timelineSupport: true });
  return signInByGeneratingQR(temp, (reason) => onFailure(String(reason)), signal);
}

export function qrBytesToDataUrl(bytes: Uint8Array): string {
  const chars = Array.from(bytes, (value) => String.fromCharCode(value)).join("");
  return `data:application/octet-stream;base64,${btoa(chars)}`;
}
