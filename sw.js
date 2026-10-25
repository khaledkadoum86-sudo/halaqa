// Fast start: the app opens instantly from the copy saved on the device,
// then quietly downloads the newest version for the next launch.
const CACHE = "halaqa-v14";
const SHELL = ["./", "index.html", "manifest.webmanifest", "icon-180.png", "icon-167.png", "icon-152.png", "icon-192.png", "icon-512.png", "banner.jpg", "logo.webp"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
function refresh() {
  return fetch("index.html", { cache: "no-store" }).then(r => { if (r.ok) { const c = r.clone(); caches.open(CACHE).then(x => x.put("index.html", c)); } return r; });
}
self.addEventListener("fetch", e => {
  const req = e.request; if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (req.mode === "navigate" || (url.origin === location.origin && url.pathname.endsWith(".html"))) {
    e.respondWith(caches.match("index.html").then(hit => {
      const net = refresh();
      if (hit) { e.waitUntil(net.catch(() => {})); return hit; }
      return net.catch(() => caches.match("./"));
    }));
    return;
  }
  e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => {
    if (r && (r.ok || r.type === "opaque")) { const c = r.clone(); caches.open(CACHE).then(x => x.put(req, c)); }
    return r;
  })));
});
