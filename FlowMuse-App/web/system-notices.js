// A notification-only worker; never intercept app requests or cache resources.
(() => {
  const base = new URL('./', document.baseURI);
  const script = new URL('system-notices-worker.js', base);
  const scope = new URL('_system-notices/', base).href;
  let callback, registration, listener;
  const initialURL = new URL(location.href);
  let pending = initialURL.searchParams.get('system-notice');
  if (pending !== null) {
    initialURL.searchParams.delete('system-notice');
    history.replaceState(history.state, '', initialURL);
  }
  const supported = () => isSecureContext && 'Notification' in globalThis && 'serviceWorker' in navigator;
  async function worker() {
    registration ??= await navigator.serviceWorker.register(script, { scope });
    if (!registration.active) {
      await new Promise((resolve, reject) => {
        const installing = registration.installing || registration.waiting;
        if (!installing) { reject(new Error('Worker unavailable')); return; }
        const timer = setTimeout(() => { cleanup(); reject(new Error('Worker activation timed out')); }, 10000);
        const changed = () => {
          if (installing.state === 'activated') { cleanup(); resolve(); }
          else if (installing.state === 'redundant') { cleanup(); reject(new Error('Worker unavailable')); }
        };
        const cleanup = () => { clearTimeout(timer); installing.removeEventListener('statechange', changed); };
        installing.addEventListener('statechange', changed);
        changed();
      });
    }
    return registration;
  }
  async function existing() {
    if (!supported()) return null;
    const result = registration || await navigator.serviceWorker.getRegistration(scope);
    return result?.scope === scope ? result : null;
  }
  globalThis.flowMuseSystemNotice = {
    async permission(request) {
      if (!supported()) return 'unsupported';
      // Preserve the requesting button's user activation.
      const status = request ? await Notification.requestPermission() : Notification.permission;
      if (request && status === 'granted') await worker();
      return status === 'default' ? 'prompt' : status;
    },
    async initialize(onTap) {
      callback = onTap;
      if (!supported()) return;
      if (listener) navigator.serviceWorker.removeEventListener('message', listener);
      listener = (event) => {
        if (event.source?.scriptURL !== script.href || event.data?.type !== 'flowmuse-notice-click') return;
        if (typeof event.data.target === 'string' && event.data.target.length <= 1024) callback?.(event.data.target);
      };
      navigator.serviceWorker.addEventListener('message', listener);
      if (pending !== null) {
        const target = pending; pending = null;
        if (target.length <= 1024) callback(target);
      }
    },
    async show(raw) {
      if (!supported() || Notification.permission !== 'granted') return;
      const payload = JSON.parse(raw);
      const reg = await worker();
      await new Promise((resolve, reject) => {
        const channel = new MessageChannel();
        const cleanup = () => { clearTimeout(timer); channel.port1.close(); };
        const timer = setTimeout(() => { cleanup(); reject(new Error('Notification timed out')); }, 10000);
        channel.port1.onmessage = (event) => {
          cleanup();
          event.data?.ok ? resolve() : reject(new Error('Notification unavailable'));
        };
        reg.active.postMessage({ type: 'flowmuse-notice-show', payload }, [channel.port2]);
      });
    },
    async cancel(tag) {
      const reg = await existing();
      if (!reg) return;
      for (const notice of await reg.getNotifications({ tag: 'flowmuse-social:' + tag })) notice.close();
    },
    async clear() {
      const reg = await existing();
      if (!reg) return;
      for (const notice of await reg.getNotifications()) {
        if (notice.tag.startsWith('flowmuse-social:')) notice.close();
      }
    },
    dispose() {
      if (listener && supported()) navigator.serviceWorker.removeEventListener('message', listener);
      callback = undefined; listener = undefined;
    },
  };
})();
