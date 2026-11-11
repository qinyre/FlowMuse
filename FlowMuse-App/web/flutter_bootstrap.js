{{flutter_js}}
{{flutter_build_config}}

const startup = document.getElementById('startup');
const status = document.getElementById('startup-status');
const hint = document.getElementById('startup-hint');
const retry = document.getElementById('startup-retry');
const progress = document.getElementById('startup-progress');
let finished = false;
let failed = false;
let progressLimit = 37;

// Estimated movement stays within the current stage until Flutter reports a transition.
const advanceProgress = setInterval(() => {
  const remaining = progressLimit - progress.value;
  progress.value += Math.min(remaining, Math.max(0.5, remaining * 0.08));
}, 500);

function enterStage(label, minimum, limit) {
  status.textContent = label;
  progress.value = minimum;
  progressLimit = limit;
}

function failStartup() {
  if (finished || failed) return;
  failed = true;
  startup.dataset.failed = 'true';
  status.textContent = '应用加载失败';
  hint.textContent = '请检查网络连接后重试。';
  retry.hidden = false;
  clearInterval(advanceProgress);
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
  progress.value = 100;
  clearInterval(advanceProgress);
  clearTimeout(slowLoading);
  window.removeEventListener('error', onScriptError, true);
  startup.remove();
}, {once: true});

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    if (failed) return;
    try {
      enterStage('正在准备画布…', 40, 81);
      const appRunner = await engineInitializer.initializeEngine();
      if (failed) return;
      enterStage('正在打开工作区…', 84, 97);
      await appRunner.runApp();
    } catch (_) {
      failStartup();
    }
  },
}).catch(failStartup);
