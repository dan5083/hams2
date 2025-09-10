const CACHE_NAME = 'hams-static-v1';

// ONLY cache truly static assets
const STATIC_ASSETS = [
  '/assets/', // Rails asset pipeline files only
  '/manifest.json',
  '/icons/'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Only handle GET requests for static assets
  if (event.request.method !== 'GET') return;

  const isStaticAsset = STATIC_ASSETS.some(path =>
    event.request.url.includes(path)
  );

  if (!isStaticAsset) {
    // For all business data: always fetch fresh, never cache
    return;
  }

  // For static assets: cache-first strategy
  event.respondWith(
    caches.match(event.request).then(response => {
      return response || fetch(event.request).then(fetchResponse => {
        if (fetchResponse.status === 200) {
          const responseToCache = fetchResponse.clone();
          caches.open(CACHE_NAME).then(cache => {
            cache.put(event.request, responseToCache);
          });
        }
        return fetchResponse;
      });
    })
  );
});
