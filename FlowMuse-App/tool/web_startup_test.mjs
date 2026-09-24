import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../web/flutter_bootstrap.js', import.meta.url), 'utf8')
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');

function boot() {
  const elements = Object.fromEntries(
    ['startup', 'startup-status', 'startup-hint', 'startup-retry'].map(id =>
      [id, {dataset: {}, hidden: true, remove() { this.removed = true; }}]),
  );
  const listeners = new Map();
  const timers = new Map();
  let options;
  vm.runInNewContext(source, {
    URL,
    document: {getElementById: id => elements[id]},
    window: {
      addEventListener: (name, callback) => listeners.set(name, callback),
      removeEventListener: name => listeners.delete(name),
    },
    setTimeout: callback => { timers.set(1, callback); return 1; },
    clearTimeout: id => timers.delete(id),
    _flutter: {loader: {load: config => { options = config; return Promise.resolve(); }}},
  });
  return {elements, listeners, timers, options};
}

test('加载阶段随真实初始化推进，只在第一帧移除，不影响应用启动', async () => {
  const {elements, listeners, timers, options} = boot();
  let finishEngine;
  const engine = new Promise(resolve => { finishEngine = resolve; });
  let runs = 0;
  const loading = options.onEntrypointLoaded({initializeEngine: () => engine});
  assert.equal(elements['startup-status'].textContent, '正在准备画布…');
  timers.get(1)();
  assert.equal(elements['startup-retry'].hidden, false);
  finishEngine({runApp: async () => { runs++; }});
  await loading;
  assert.equal(runs, 1);
  assert.equal(elements['startup-status'].textContent, '正在打开工作区…');
  assert.equal(elements.startup.removed, undefined);
  listeners.get('flutter-first-frame')();
  assert.equal(elements.startup.removed, true);
  assert.equal(timers.size, 0);
  assert.equal(listeners.has('error'), false);
});

test('主程序或引擎加载失败可手动重试，非关键脚本失败不遮挡正常启动', async () => {
  const {elements, listeners, timers, options} = boot();
  listeners.get('error')({target: {tagName: 'SCRIPT', src: 'https://cdn.example/pdf.js'}});
  assert.equal(elements.startup.dataset.failed, undefined);
  listeners.get('error')({target: {tagName: 'SCRIPT', src: 'https://example.test/main.dart.js'}});
  assert.equal(elements.startup.dataset.failed, 'true');
  assert.equal(elements['startup-retry'].hidden, false);
  assert.equal(timers.size, 0);
  await options.onEntrypointLoaded({initializeEngine: async () => { throw Error('fixture'); }});
  assert.equal(elements['startup-status'].textContent, '应用加载失败');
  assert.equal(elements.startup.removed, undefined);
});
