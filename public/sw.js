const CACHE_NAME = 'northstar-shell-v1'
const APP_SHELL = ['/', '/northstar-icon.svg', '/manifest.webmanifest']

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)))
  self.skipWaiting()
})

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys()
    await Promise.all(keys.filter(key => key.startsWith('northstar-shell-') && key !== CACHE_NAME).map(key => caches.delete(key)))
    await self.clients.claim()
  })())
})

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(async () => (await caches.match('/')) || Response.error()))
  }
})

self.addEventListener('push', event => {
  event.waitUntil((async () => {
    let payload = {}
    try {
      payload = event.data?.json() ?? {}
    } catch {
      payload = { body: event.data?.text() ?? '' }
    }

    const target = new URL(typeof payload.url === 'string' ? payload.url : '/notifications', self.location.origin)
    if (target.origin !== self.location.origin) return

    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    const pageAlreadyVisible = windows.some(client => {
      if (client.visibilityState !== 'visible') return false
      try {
        return new URL(client.url).pathname === target.pathname
      } catch {
        return false
      }
    })
    if (pageAlreadyVisible) return

    await self.registration.showNotification(payload.title || 'Northstar', {
      body: payload.body || 'You have a new Northstar update.',
      icon: '/northstar-icon.svg',
      badge: '/northstar-icon.svg',
      tag: payload.tag || undefined,
      renotify: false,
      data: { url: target.href },
    })
  })())
})

self.addEventListener('notificationclick', event => {
  event.notification.close()
  event.waitUntil((async () => {
    const target = new URL(event.notification.data?.url || '/notifications', self.location.origin)
    if (target.origin !== self.location.origin) return
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    for (const client of windows) {
      if (new URL(client.url).origin !== self.location.origin) continue
      await client.focus()
      if ('navigate' in client) await client.navigate(target.href)
      return
    }
    await self.clients.openWindow(target.href)
  })())
})
