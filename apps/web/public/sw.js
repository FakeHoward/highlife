/* HighLife service worker — Web Push + offline shell. */
const SHELL = "highlife-shell-v1";
const SHELL_URLS = ["/", "/index.html", "/favicon.ico"];

function targetFromPush(payload) {
  const roomId = payload && (payload.room_id || payload.roomId);
  if (typeof roomId === "string" && roomId.charAt(0) === "!") {
    return "/?room=" + encodeURIComponent(roomId);
  }
  return "/";
}

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(SHELL).then((cache) => cache.addAll(SHELL_URLS)).then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("fetch", (event) => {
  if (event.request.mode !== "navigate") return;
  event.respondWith(
    fetch(event.request).catch(() => caches.match("/index.html").then((cached) => cached || caches.match("/"))),
  );
});

self.addEventListener("push", (event) => {
  let title = "HighLife";
  let body = "New message";
  let payload = null;
  try {
    payload = event.data ? event.data.json() : null;
    if (payload && typeof payload === "object") {
      if (typeof payload.title === "string") title = payload.title;
      if (typeof payload.body === "string") body = payload.body;
      else if (typeof payload.content === "string") body = payload.content;
    }
  } catch {
    try {
      const text = event.data ? event.data.text() : "";
      if (text) body = text;
    } catch {
      /* ignore */
    }
  }
  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: "/favicon.ico",
      data: { url: targetFromPush(payload) },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if ("focus" in client) {
          try {
            const url = new URL(target, self.location.origin);
            const roomId = url.searchParams.get("room");
            if (roomId && roomId.startsWith("!")) {
              client.postMessage({ type: "open-room", roomId });
            }
          } catch {
            /* ignore */
          }
          if (typeof client.navigate === "function") client.navigate(target);
          return client.focus();
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
      return undefined;
    }),
  );
});
