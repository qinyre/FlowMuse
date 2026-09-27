import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const edit = resolve(dirname(fileURLToPath(import.meta.url)), '..');
assert(process.argv[2], '用法：node scripts/cut-footage.mjs <原素材目录> [--check]');
const source = resolve(process.argv[2]);
const cuts = JSON.parse(readFileSync(resolve(edit, 'cuts-v5.json'), 'utf8'));
const output = resolve(edit, 'public/footage');
const logs = resolve(edit, '../output/cuts-v5');
mkdirSync(output, {recursive: true});
mkdirSync(logs, {recursive: true});
const ffmpeg = resolve(edit, 'node_modules/@ffmpeg-installer/win32-x64/ffmpeg.exe');
const ffprobe = resolve(edit, 'node_modules/@ffprobe-installer/win32-x64/ffprobe.exe');
const run = (exe, args) => {
  const result = spawnSync(exe, args, {encoding: 'utf8', windowsHide: true, maxBuffer: 16 * 1024 * 1024});
  assert.equal(result.status, 0, result.stderr?.slice(-3000));
  return result.stdout;
};
const probe = file => JSON.parse(run(ffprobe, ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', file]));
const frames = seconds => Math.round(seconds * 30);
const manifest = [];
for (const item of cuts) {
  assert(/^[\w-]+\.mp4$/.test(item.source) && /^[\w-]+\.mp4$/.test(item.file));
  const input = resolve(source, item.source);
  const target = resolve(output, item.file);
  assert.notEqual(input.toLowerCase(), target.toLowerCase(), '不可覆盖原素材');
  assert(existsSync(input), `缺少原素材：${item.source}`);
  const metadata = probe(input);
  const video = metadata.streams.find(s => s.codec_type === 'video');
  assert(video, `${item.source} 没有视频轨`);
  let position = 0;
  const ranges = item.cuts.map(([start, end, hold = 0]) => {
    assert(start >= 0 && end > start && end <= Number(video.duration) && hold >= 0, `${item.id} 切点越界`);
    const count = frames(end - start);
    const still = frames(hold);
    const range = {sourceStart: start, sourceEnd: end, sourceFrames: count, holdFrames: still, outputStartFrame: position};
    position += count + still;
    return range;
  });
  assert.equal(position, frames(item.duration), `${item.id} 切点总时长与计划不一致`);
  const result = {id: item.id, source: item.source, sourceSha256: createHash('sha256').update(readFileSync(input)).digest('hex'), file: item.file, duration: item.duration, outputFrames: position + 12, fps: 30, ranges};
  manifest.push(result);
  if (process.argv.includes('--check')) continue;
  // Cuts use source timestamps; fps normalizes VFR without accelerating the action.
  const filters = ranges.map((r, i) => `[0:v]trim=start=${r.sourceStart}:end=${r.sourceEnd},setpts=PTS-STARTPTS,fps=30,tpad=stop_mode=clone:stop_duration=1,trim=end_frame=${r.sourceFrames},setpts=N/(30*TB),tpad=stop_mode=clone:stop_duration=${r.holdFrames / 30},setsar=1[v${i}]`);
  filters.push(`${ranges.map((_, i) => `[v${i}]`).join('')}concat=n=${ranges.length}:v=1:a=0,fps=30,tpad=stop_mode=clone:stop_duration=1,format=yuv420p[out]`);
  const graph = resolve(logs, `${item.id}.ffgraph`);
  writeFileSync(graph, filters.join(';\n'));
  run(ffmpeg, ['-y', '-hide_banner', '-loglevel', 'error', '-i', input, '-filter_complex_script', graph, '-map', '[out]', '-an', '-c:v', 'libx264', '-preset', 'fast', '-crf', '17', '-threads', '4', '-frames:v', String(position + 12), '-movflags', '+faststart', target]);
  const encoded = probe(target).streams.find(s => s.codec_type === 'video');
  assert.equal(Number(encoded.nb_frames), position + 12);
  assert.equal(encoded.avg_frame_rate, '30/1');
  assert.equal(encoded.width, video.width);
  assert.equal(encoded.height, video.height);
  console.log(`${item.file}: ${item.duration}s + 0.4s 尾帧，校验通过`);
}
writeFileSync(resolve(logs, 'manifest.json'), JSON.stringify(manifest, null, 2));
console.log(`8段计划通过，正文 ${cuts.reduce((sum, c) => sum + c.duration, 0)} 秒；${process.argv.includes('--check') ? '未写入媒体' : '已生成剪辑片段'}。`);
