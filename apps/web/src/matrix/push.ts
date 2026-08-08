import type { MatrixClient } from "matrix-js-sdk";

const APP_ID = "im.highlife.web";

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  const output = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i += 1) output[i] = raw.charCodeAt(i);
  return output;
}

/** Register an HTTP Web Push pusher when VAPID + gateway env vars are set. No-op otherwise. */
export async function registerPushAfterLogin(client: MatrixClient): Promise<void> {
  const vapid = (import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined)?.trim();
  const gateway = (import.meta.env.VITE_PUSH_GATEWAY_URL as string | undefined)?.trim();
  if (!vapid || !gateway) return;
  if (!("serviceWorker" in navigator) || !("PushManager" in window) || !window.isSecureContext) {
    return;
  }

  try {
    const registration = await navigator.serviceWorker.ready.catch(async () => {
      // No SW registered yet — try a minimal registration of the app root.
      return navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`).catch(() => null);
    });
    if (!registration) return;

    let subscription = await registration.pushManager.getSubscription();
    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapid) as BufferSource,
      });
    }

    await client.setPusher({
      kind: "http",
      app_id: APP_ID,
      app_display_name: "HighLife",
      device_display_name: (navigator.userAgent || "HighLife Web").slice(0, 64),
      pushkey: JSON.stringify(subscription.toJSON()),
      lang: navigator.language || "en",
      data: {
        url: gateway.replace(/\/+$/, ""),
        format: "event_id_only",
      },
      append: false,
    });
  } catch {
    // Push is optional — ignore permission denials and missing SW.
  }
}
