const CACHE_NAME = 'ironnova-v18-vector-home';
const APP_SHELL = ['./', './index.html', './manifest.webmanifest', './assets/icon-192.png', './assets/icon-512.png', './assets/icon-maskable-512.png', './assets/exercise-photo-catalog.json', './assets/ironnova-reference-refresh.css?v=5', './assets/icons/home-workouts.svg', './assets/icons/ai-doctor-dumbbell.svg', './assets/icons/home-program.svg', './assets/icons/home-smart-coach.svg', './assets/icons/home-nutrition.svg', './assets/icons/home-progress.svg', './assets/icons/home-profile.svg', './assets/icons/home-coaches.svg', './assets/icons/home-coach-panel.svg', './assets/icons/home-store.svg', './assets/icons/home-education.svg', './assets/ironnova-reference-refresh.css?v=4'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  const exerciseMedia = (url.hostname === 'raw.githubusercontent.com' && url.pathname.startsWith('/yuhonas/free-exercise-db/')) ||
    (url.hostname === 'upload.wikimedia.org' && url.pathname.startsWith('/wikipedia/commons/'));
  if (exerciseMedia) {
    event.respondWith(caches.open(CACHE_NAME).then(async cache => {
      const cached = await cache.match(request);
      if (cached) return cached;
      const response = await fetch(request);
      if (response && response.ok) await cache.put(request, response.clone());
      return response;
    }).catch(() => caches.match(request)));
    return;
  }
  if (url.origin !== self.location.origin) return;
  if (url.pathname.endsWith('/index.html') || url.pathname.endsWith('/')) {
    event.respondWith(fetch(request).then(response => {
      if (response && response.ok) caches.open(CACHE_NAME).then(cache => cache.put(request, response.clone()));
      return response;
    }).catch(() => caches.match(request).then(cached => cached || caches.match('./index.html'))));
    return;
  }
  event.respondWith(caches.match(request).then(cached => cached || fetch(request).then(response => {
    if (response && response.ok) { const copy = response.clone(); caches.open(CACHE_NAME).then(cache => cache.put(request, copy)); }
    return response;
  }).catch(() => caches.match('./index.html'))));
});
