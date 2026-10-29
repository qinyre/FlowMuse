const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = (name) => fs.readFileSync(path.join(__dirname, '../../web', name), 'utf8');

function worker(base) {
  const events = {}, shown = [], opened = [], posted = [];
  let focused = false;
  const owner = { type: 'window', url: base + 'library', async focus() { focused = true; }, postMessage(value) { posted.push(value); } };
  const self = {
    location: { href: base + 'system-notices-worker.js' },
    addEventListener(name, callback) { events[name] = callback; },
    skipWaiting() { return Promise.resolve(); },
    registration: { async showNotification(title, options) { shown.push({ title, ...options }); } },
    clients: { async get(id) { return id === 'owner' ? owner : null; }, async openWindow(url) { opened.push(url); } },
  };
  vm.runInNewContext(source('system-notices-worker.js'), { self, URL, Date });
  async function dispatch(name, event) {
    let completion;
    events[name]({ ...event, waitUntil(value) { completion = value; } });
    await completion;
  }
  return { events, shown, opened, posted, dispatch, focused: () => focused };
}

test('通知 worker 保持子路径，点击只聚焦来源页面，页面关闭才打开收件箱', async () => {
  for (const base of ['https://app.example.test/', 'https://app.example.test/wet-ink-v2/']) {
    const w = worker(base);
    const payload = { tag: 'A:conversation:chat', title: '协作伙伴', body: '有新消息', target: '{"userId":"A"}', expiresAt: Date.now() + 60000 };
    await w.dispatch('message', { data: { type: 'flowmuse-notice-show', payload }, source: { url: base + 'library', id: 'owner' }, ports: [] });
    assert.equal(w.shown.length, 1);
    assert.equal(w.shown[0].tag, 'flowmuse-social:A:conversation:chat');
    assert.equal(w.events.fetch, undefined);
    assert.equal(w.events.push, undefined);
    const notice = { ...w.shown[0], close() {} };
    await w.dispatch('notificationclick', { notification: notice });
    assert.equal(w.focused(), true);
    assert.equal(w.posted[0].target, payload.target);
    assert.equal(w.opened.length, 0);
    notice.data.clientId = 'closed';
    await w.dispatch('notificationclick', { notification: notice });
    const opened = new URL(w.opened[0]);
    assert.equal(opened.origin, new URL(base).origin);
    assert.equal(opened.pathname, new URL('social', base).pathname);
    assert.equal(opened.searchParams.get('system-notice'), payload.target);
  }
});

test('拒绝跨来源、畸形、过期通知；过期点击无跳转', async () => {
  const w = worker('https://app.example.test/');
  const payload = { tag: 'A:request:friend', title: 'FlowMuse', body: '好友申请', target: '{}', expiresAt: Date.now() + 60000 };
  for (const event of [
    { source: { url: 'https://outside.test/', id: 'x' }, payload },
    { payload: { ...payload, target: 'x'.repeat(1025) } },
    { payload: { ...payload, expiresAt: 1 } },
    { payload: { ...payload, expiresAt: 'invalid' } },
  ]) {
    await w.dispatch('message', { source: { url: 'https://app.example.test/library', id: 'owner' }, ports: [], ...event, data: { type: 'flowmuse-notice-show', payload: event.payload } });
  }
  assert.equal(w.shown.length, 0);
  await w.dispatch('notificationclick', { notification: { tag: 'flowmuse-social:x', data: { target: '{}', expiresAt: 1 }, close() {} } });
  assert.equal(w.opened.length, 0);
});

test('桥接不会自动申请权限；拒绝/不支持环境不注册 worker，点击参数立即移出地址栏', async () => {
  let requests = 0, registrations = 0, replaced;
  const browser = {
    URL, isSecureContext: true,
    document: { baseURI: 'https://app.example.test/wet-ink-v2/' },
    location: { href: 'https://app.example.test/wet-ink-v2/social?system-notice=%7B%7D' },
    history: { state: null, replaceState(_, __, url) { replaced = String(url); } },
    Notification: { permission: 'default', async requestPermission() { requests++; return 'denied'; } },
    navigator: { serviceWorker: { addEventListener() {}, removeEventListener() {}, async register() { registrations++; } } },
  };
  vm.runInNewContext(source('system-notices.js'), browser);
  assert.equal(replaced, 'https://app.example.test/wet-ink-v2/social');
  assert.equal(await browser.flowMuseSystemNotice.permission(false), 'prompt');
  assert.equal(requests, 0);
  let clicked;
  await browser.flowMuseSystemNotice.initialize((raw) => { clicked = raw; });
  assert.equal(clicked, '{}');
  assert.equal(await browser.flowMuseSystemNotice.permission(true), 'denied');
  assert.equal(requests, 1);
  assert.equal(registrations, 0);
  browser.isSecureContext = false;
  assert.equal(await browser.flowMuseSystemNotice.permission(true), 'unsupported');
  assert.equal(requests, 1);
});
