import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync, renameSync} from 'node:fs';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = process.argv[2];
assert(source, '用法：node scripts/assemble-narration.mjs <35段WAV所在目录> [--check]');
const spec = JSON.parse(readFileSync(resolve(root, 'narration-v6.json'), 'utf8'));
const timeline = JSON.parse(readFileSync(resolve(root, '../timeline.json'), 'utf8'));
const supplied = JSON.parse(readFileSync(resolve(source, 'segments.json'), 'utf8').replace(/^\uFEFF/, ''));
assert.equal(spec.lines.length, 35);
assert.equal(supplied.length, spec.lines.length);
assert.equal(spec.duration, timeline.scenes.reduce((n, scene) => n + scene.duration, 0));
const rate = 48000, bytesPerFrame = 4;
const ffmpeg = resolve(root, 'node_modules/@ffmpeg-installer/win32-x64/ffmpeg.exe');
const ffprobe = resolve(root, 'node_modules/@ffprobe-installer/win32-x64/ffprobe.exe');
const run = (exe, args, binary = false) => {
  const result = spawnSync(exe, args, {encoding: binary ? null : 'utf8', maxBuffer: 16 * 1024 * 1024, windowsHide: true});
  assert.equal(result.status, 0, String(result.stderr || result.error));
  return result;
};
const scenes = new Map();
let sceneStart = 0;
for (const scene of timeline.scenes) {
  scenes.set(scene.id, {...scene, start: sceneStart});
  sceneStart += scene.duration;
}
let previousEnd = 0;
const takes = spec.lines.map((line, i) => {
  assert.equal(line.id, String(i + 1).padStart(2, '0'));
  assert.equal(supplied[i].num, i + 1, `${line.id} 的来源段号不符`);
  assert.equal(supplied[i].text, line.text, `${line.id} 的来源文案与v6不符`);
  const file = resolve(source, `${line.id}.wav`);
  const info = JSON.parse(run(ffprobe, ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', file]).stdout);
  assert.equal(info.streams.length, 1);
  const stream = info.streams[0];
  assert.equal(stream.codec_name, 'pcm_s16le');
  assert.equal(Number(stream.sample_rate), rate);
  assert.equal(stream.channels, 2);
  const {start, trim} = line.audio;
  assert([start, ...trim].every(Number.isFinite));
  assert(trim[0] >= 0 && trim[1] > trim[0] && trim[1] <= Number(info.format.duration) + 0.0001, `${line.id} 裁切越界`);
  const duration = Number((trim[1] - trim[0]).toFixed(6));
  const scene = scenes.get(line.scene);
  assert(scene && start >= scene.start && start + duration <= scene.start + scene.duration + 0.0001, `${line.id} 超出章节`);
  assert(start >= previousEnd - 0.0001, `${line.id} 与前段重叠`);
  previousEnd = start + duration;
  const cue = scene.cues.find(([at, length, text]) => text === line.text && Math.abs(scene.start + at - start) < .001 && Math.abs(length - duration) < .001);
  assert(cue, `${line.id} 字幕未与音频落点一致`);
  return {...line, file, duration, sourceDuration: Number(info.format.duration), sourceSha256: createHash('sha256').update(readFileSync(file)).digest('hex')};
});
if (process.argv.includes('--check')) {
  console.log('35段来源、格式、裁切、章节、字幕与无重叠校验通过。');
  process.exit(0);
}
const output = resolve(root, '../output/narration-v6');
mkdirSync(output, {recursive: true});
const pcm = Buffer.alloc(spec.duration * rate * bytesPerFrame);
for (const take of takes) {
  const trim = `atrim=start=${take.audio.trim[0]}:end=${take.audio.trim[1]},asetpts=PTS-STARTPTS`;
  const target = 'loudnorm=I=-18:TP=-2:LRA=11';
  const measured = run(ffmpeg, ['-hide_banner', '-nostdin', '-i', take.file, '-af', `${trim},${target}:print_format=json`, '-f', 'null', '-']).stderr;
  const match = measured.match(/\{\s*"input_i"[\s\S]*?\}/);
  assert(match, `${take.id} 无法测量响度`);
  const stats = JSON.parse(match[0]);
  for (const key of ['input_i', 'input_tp', 'input_lra', 'input_thresh', 'target_offset']) assert(Number.isFinite(Number(stats[key])), `${take.id} 响度无效`);
  const normalize = `${target}:measured_I=${stats.input_i}:measured_TP=${stats.input_tp}:measured_LRA=${stats.input_lra}:measured_thresh=${stats.input_thresh}:offset=${stats.target_offset}:linear=true`;
  const filters = `${trim},${normalize},afade=t=in:d=0.005,afade=t=out:st=${take.duration - .005}:d=0.005`;
  const rendered = run(ffmpeg, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-i', take.file, '-af', filters, '-ar', String(rate), '-ac', '2', '-f', 's16le', 'pipe:1'], true).stdout;
  const frames = Math.round(take.duration * rate);
  assert(Math.abs(rendered.length / bytesPerFrame - frames) <= 2, `${take.id} 归一化改变了时长`);
  const offset = Math.round(take.audio.start * rate) * bytesPerFrame;
  assert(offset + rendered.length <= pcm.length, `${take.id} 超出总片长`);
  rendered.copy(pcm, offset);
  take.loudness = stats;
  console.log(`${take.id}: ${take.audio.start.toFixed(3)}–${(take.audio.start + take.duration).toFixed(3)}s，输入 ${stats.input_i} LUFS`);
}
const raw = resolve(output, 'narration.s16le');
writeFileSync(raw, pcm);
const wav = resolve(output, 'narration.wav');
run(ffmpeg, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-y', '-f', 's16le', '-ar', String(rate), '-ac', '2', '-i', raw, '-c:a', 'pcm_s16le', wav]);
// Only replace the public master after every take and the full encode have passed.
const target = resolve(root, 'public/narration.wav');
renameSync(wav, target);
writeFileSync(resolve(output, 'manifest.json'), JSON.stringify({duration: spec.duration, sampleRate: rate, channels: 2, targetLufs: -18, bgm: 'none', takes}, null, 2) + '\n');
console.log(`已生成 ${target}`);
