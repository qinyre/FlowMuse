const appBase = new URL('./', self.location.href);
const noticePrefix = 'flowmuse-social:';

self.addEventListener('install', (event) => event.waitUntil(self.skipWaiting()));

self.addEventListener('message', (event) => {
  if (event.data?.type !== 'flowmuse-notice-show' || !event.source?.url) return;
  const source = new URL(event.source.url);
  if (source.origin !== appBase.origin || !source.pathname.startsWith(appBase.pathname)) return;
  const payload = event.data.payload;
  if (!payload || typeof payload.tag !== 'string' || payload.tag.length > 300 ||
      typeof payload.target !== 'string' || payload.target.length > 1024 ||
      typeof payload.title !== 'string' || payload.title.length > 300 ||
      typeof payload.body !== 'string' || payload.body.length > 1000 ||
      !Number.isSafeInteger(payload.expiresAt) || payload.expiresAt <= Date.now()) {
    event.ports[0]?.postMessage({ ok: false });
    return;
  }
  event.waitUntil(self.registration.showNotification(payload.title, {
    body: payload.body,
    tag: noticePrefix + payload.tag,
    icon: new URL('icons/Icon-192.png', appBase).href,
    data: { target: payload.target, clientId: event.source.id, expiresAt: payload.expiresAt },
  }).then(() => event.ports[0]?.postMessage({ ok: true }),
    () => event.ports[0]?.postMessage({ ok: false })));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data;
  if (!event.notification.tag.startsWith(noticePrefix) || typeof data?.target !== 'string' ||
      data.target.length > 1024 || !Number.isSafeInteger(data.expiresAt) || data.expiresAt <= Date.now()) return;
  event.waitUntil((async () => {
    const owner = typeof data.clientId === 'string' ? await self.clients.get(data.clientId) : null;
    if (owner?.type === 'window' && new URL(owner.url).origin === appBase.origin) {
      await owner.focus();
      owner.postMessage({ type: 'flowmuse-notice-click', target: data.target });
      return;
    }
    const url = new URL('social', appBase);
    url.searchParams.set('system-notice', data.target);
    await self.clients.openWindow(url.href);
  })());
});
