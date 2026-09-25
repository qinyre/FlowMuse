import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, existsSync, mkdirSync} from 'node:fs';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const project = resolve(root, '..');
const data = JSON.parse(readFileSync(resolve(project, 'timeline.json'), 'utf8'));
const duration = data.scenes.reduce((sum, scene) => sum + scene.duration, 0);
assert.equal(duration, 288, '同步修改 Root.tsx 后才能改变总时长');
assert.equal(data.fps, 30);
assert.equal(new Set(data.scenes.map(s => s.id)).size, data.scenes.length);
assert(duration < 300, '规程要求 5 分钟以内');
for (const fps of [15, 30]) {
  const overlap = Math.round(0.4 * fps);
  const frameCounts = data.scenes.map((s, i) => s.duration * fps + (i < data.scenes.length - 1 ? overlap : 0));
  assert.equal(frameCounts.reduce((a, b) => a + b, 0) - overlap * (data.scenes.length - 1), duration * fps);
}
const stamp = s => new Date(Math.round(s * 1000)).toISOString().slice(11, 23).replace('.', ',');
const short = s => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
const probe = file => {
  const result = spawnSync(resolve(root, 'node_modules/@ffprobe-installer/win32-x64/ffprobe.exe'), ['-v', 'error', '-show_entries', 'format=duration:stream=codec_type', '-of', 'json', file], {encoding: 'utf8', windowsHide: true});
  assert.equal(result.status, 0, `无法读取媒体 ${file}: ${result.stderr}`);
  return JSON.parse(result.stdout);
};
mkdirSync(resolve(root, 'src'), {recursive: true});
const missing = [];
const clips = {};
let start = 0;
let guide = '# FlowMuse 复赛视频：逐镜脚本与录制清单\n\n全长 04:48；正式母版 1920 × 1080、30 fps，分镜预演导出为 1280 × 720、15 fps。按当前功能重新盘点，覆盖八组实机镜头，V3 智能排版保留 60 秒重点展示。当前是无配音的分镜预演，不能作为实际功能演示提交。旁白时码是排练参考，录音后按实际语速校准。每段原始录屏前后留 5 秒，不必卡住净时长。完整功能及取舍见《功能盘点与镜头取舍.md》。\n\n';
for (const scene of data.scenes) {
  assert(Number.isInteger(scene.duration) && scene.duration > 0);
  assert(scene.steps.every((step, i) => step.at >= 0 && step.at < scene.duration && (i === 0 || step.at > scene.steps[i - 1].at)));
  if (scene.file) {
    assert(/^[\w-]+\.mp4$/.test(scene.file));
    const relative = `footage/${scene.file}`;
    clips[scene.id] = existsSync(resolve(root, 'public', relative)) ? relative : null;
    if (!clips[scene.id]) missing.push(relative);
    else {
      const info = probe(resolve(root, 'public', relative));
      assert(info.streams.some(s => s.codec_type === 'video'), `${relative} 没有视频轨`);
      assert(Number(info.format.duration) >= scene.duration + 0.4 - 1 / 30, `${relative} 至少需要 ${scene.duration + 0.4} 秒（含转场尾帧）`);
    }
  }
  guide += `## ${short(start)}–${short(start + scene.duration)}｜${scene.title}\n\n`;
  if (scene.file) {
    guide += `**目标镜头：${scene.file}；正文 ${scene.duration} 秒，另留转场余量。**\n\n| 成片时码 | 操作 | 画面验收 |\n|---|---|---|\n`;
    for (const step of scene.steps) guide += `| ${short(start + step.at)} | ${step.label} | ${step.detail} |\n`;
    guide += '\n';
  }
  for (const [at, length, text] of data.cues.filter(c => c[0] >= start && c[0] < start + scene.duration)) guide += `- **${short(at)}–${short(at + length)}** ${text}\n`;
  guide += '\n';
  start += scene.duration;
}
const captions = data.cues.map(([at, length, text], i) => {
  assert(at >= 0 && length > 0 && at + length <= duration && typeof text === 'string' && text.trim());
  if (i) assert(at >= data.cues[i - 1][0] + data.cues[i - 1][1], '字幕不可相互重叠');
  return {text, startMs: at * 1000, endMs: (at + length) * 1000, timestampMs: null, confidence: null};
});
const narration = ['narration.wav', 'narration.mp3'].find(f => existsSync(resolve(root, 'public', f))) || null;
if (!narration) missing.push('narration.wav 或 narration.mp3');
else {
  const info = probe(resolve(root, 'public', narration));
  assert(info.streams.some(s => s.codec_type === 'audio'), '配音文件没有音频轨');
  assert(Math.abs(Number(info.format.duration) - duration) < 1, '配音须先按成片时间轴对齐为约 288 秒');
}
if (!data.team.trim()) missing.push('timeline.json 中的 team（正式队名）');
assert(existsSync(resolve(root, 'public/intro.mp4')), '请先渲染 HyperFrames 片头');
writeFileSync(resolve(root, 'src/media.generated.json'), JSON.stringify({clips, narration, ready: missing.length === 0}, null, 2));
writeFileSync(resolve(root, 'src/captions.generated.json'), JSON.stringify(captions, null, 2));
writeFileSync(resolve(project, '录制脚本.md'), guide.trimEnd() + '\n');
writeFileSync(resolve(project, '旁白草案.srt'), captions.map((c, i) => `${i + 1}\n${stamp(c.startMs / 1000)} --> ${stamp(c.endMs / 1000)}\n${c.text}\n`).join('\n'));
console.log(`时间轴通过：${duration} 秒，${data.scenes.length} 场景，${captions.length} 条旁白字幕。`);
console.log(missing.length ? `尚缺：${missing.join('；')}` : '素材齐全，可以导出无字幕母版交给 Yaps。');
if (process.argv.includes('--final') || process.argv.includes('--render-clean')) assert.equal(missing.length, 0, '还不能导出成片：请补齐以上素材');
if (process.argv.includes('--render-clean')) {
  assert(!/[<>:"/\\|?*\x00-\x1f]/.test(data.team), '队名包含 Windows 文件名不允许的字符');
  const output = resolve(project, 'output', `02-演示视频${data.team}-无字幕审片.mp4`);
  assert(!existsSync(output), '输出已存在，请先更名保留旧版本');
  const result = spawnSync(process.execPath, [resolve(root, 'node_modules/@remotion/cli/remotion-cli.js'), 'render', 'src/index.ts', 'FlowMuseClean', output, '--codec=h264', '--crf=18', '--concurrency=3'], {cwd: root, stdio: 'inherit', windowsHide: true});
  process.exit(result.status ?? 1);
}
