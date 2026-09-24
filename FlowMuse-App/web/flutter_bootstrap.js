{{flutter_js}}
{{flutter_build_config}}

const startup = document.getElementById('startup');
const status = document.getElementById('startup-status');
const hint = document.getElementById('startup-hint');
const retry = document.getElementById('startup-retry');
let finished = false;

function failStartup() {
  if (finished) return;
  startup.dataset.failed = 'true';
  status.textContent = '应用加载失败';
  hint.textContent = '请检查网络连接后重试。';
  retry.hidden = false;
  clearTimeout(slowLoading);
}

const slowLoading = setTimeout(() => {
  hint.textContent = '加载时间有些长，请检查网络；也可以重新加载。';
  retry.hidden = false;
}, 30000);

function onScriptError(event) {
  if (event.target?.tagName === 'SCRIPT' &&
      new URL(event.target.src).pathname.endsWith('/main.dart.js')) {
    failStartup();
  }
}
window.addEventListener('error', onScriptError, true);
window.addEventListener('flutter-first-frame', () => {
  finished = true;
  clearTimeout(slowLoading);
  window.removeEventListener('error', onScriptError, true);
  startup.remove();
}, {once: true});

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    try {
      status.textContent = '正在准备画布…';
      const appRunner = await engineInitializer.initializeEngine();
      status.textContent = '正在打开工作区…';
      await appRunner.runApp();
    } catch (_) {
      failStartup();
    }
  },
}).catch(failStartup);
