// Service worker: permite instalar la app y abrirla aunque falle la red.
// Sube el número de versión cada vez que quieras forzar la actualización.
const CACHE = 'caja-senati-v1';
const SHELL = ['./', './index.html', './manifest.webmanifest', './icon-192.png', './icon-512.png'];
const CDN = ['cdn.jsdelivr.net', 'cdnjs.cloudflare.com'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const mismoOrigen = url.origin === self.location.origin;

  // Todo lo demás (p. ej. la API de Supabase) pasa directo a la red, sin caché.
  if (!mismoOrigen && !CDN.includes(url.hostname)) return;

  // Páginas: red primero, caché si no hay conexión.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req).then(res => {
        const copia = res.clone();
        caches.open(CACHE).then(c => c.put('./index.html', copia));
        return res;
      }).catch(() => caches.match('./index.html'))
    );
    return;
  }

  // Archivos estáticos y librerías CDN: caché primero, actualiza en segundo plano.
  e.respondWith(
    caches.match(req).then(cached => {
      const red = fetch(req).then(res => {
        if (res.ok || res.type === 'opaque') {
          const copia = res.clone();
          caches.open(CACHE).then(c => c.put(req, copia));
        }
        return res;
      }).catch(() => cached);
      return cached || red;
    })
  );
});
