/* HighLife service worker — Web Push + offline shell placeholder. */
self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("push", (event) => {
  let title = "HighLife";
  let body = "New Matrix activity";
  try {
    const payload = event.data ? event.data.json() : null;
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
      data: { url: "/" },
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
          client.navigate(target);
          return client.focus();
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
      return undefined;
    }),
  );
});
