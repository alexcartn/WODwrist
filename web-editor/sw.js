// WODwrist editor service worker: works offline, receives shared screenshots.
//  - app files: network first (updates show up at once), cache when offline
//  - CDN files (text reader, versioned URLs): cache first
//  - Android share sheet: POST ./?share-target with images -> kept in a
//    cache, then the page opens with ?shared and imports them

const CACHE = "wodwrist-v1";
const SHARE = "wodwrist-share";
const SHELL = ["./", "index.html", "style.css", "manifest.webmanifest", "icons/icon-192.png"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE && k !== SHARE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

async function receiveShare(request) {
  const form = await request.formData();
  const files = form.getAll("shots").filter((f) => f && typeof f !== "string");
  await caches.delete(SHARE);
  const c = await caches.open(SHARE);
  for (let i = 0; i < files.length; i++) {
    await c.put(`./shared/${i}`, new Response(files[i], {
      headers: { "content-type": files[i].type || "image/png", "x-name": encodeURIComponent(files[i].name || `shot-${i}.png`) },
    }));
  }
  return Response.redirect(`./?shared=${files.length}`, 303);
}

async function networkFirst(request) {
  const c = await caches.open(CACHE);
  try {
    const res = await fetch(request);
    if (res.ok) c.put(request, res.clone());
    return res;
  } catch (err) {
    const hit = await c.match(request, { ignoreSearch: true });
    if (hit) return hit;
    throw err;
  }
}

async function cacheFirst(request) {
  const c = await caches.open(CACHE);
  const hit = await c.match(request);
  if (hit) return hit;
  const res = await fetch(request);
  if (res.ok) c.put(request, res.clone());
  return res;
}

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method === "POST" && url.origin === location.origin && url.searchParams.has("share-target")) {
    e.respondWith(receiveShare(e.request));
    return;
  }
  if (e.request.method !== "GET") return;
  if (url.origin === location.origin) {
    // the published WOD and GitHub API calls always go to the network
    if (url.pathname.endsWith("/wod/today.json")) return;
    e.respondWith(networkFirst(e.request));
  } else if (url.hostname === "cdn.jsdelivr.net") {
    e.respondWith(cacheFirst(e.request));
  }
});
