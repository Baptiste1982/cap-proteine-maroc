/* Service worker du CRM CAP : uniquement les notifications (aucun cache, le site reste toujours à jour). */
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));
self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: "CRM Protéine", body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || "CRM Protéine", {
    body: d.body || "", tag: d.tag, icon: "/icone-192.png", badge: "/icone-192.png", data: { url: d.url || "/" },
  }));
});
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || "/", self.location.origin).href;
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const w of wins) { if ("focus" in w) { await w.navigate(url).catch(() => {}); return w.focus(); } }
    return self.clients.openWindow(url);
  })());
});
