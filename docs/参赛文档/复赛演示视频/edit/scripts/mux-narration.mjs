import assert from 'node:assert/strict';
import {readFileSync, renameSync} from 'node:fs';
import {resolve, dirname, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const media = JSON.parse(readFileSync(resolve(root, 'src/media.generated.json'), 'utf8'));
assert(process.argv[2], '请指定已渲染的MP4');
const video = resolve(process.argv[2]);
assert(video.startsWith(resolve(root, '../output') + sep) && video.endsWith('.mp4'), '只处理本工程output目录内的MP4');
if (!media.narration) {
  console.log('未提供旁白，保留无声音轨的视频。');
  process.exit(0);
}
const audio = resolve(root, 'public', media.narration);
const duration = JSON.parse(readFileSync(resolve(root, '../timeline.json'), 'utf8')).scenes.reduce((sum, scene) => sum + scene.duration, 0);
const ffmpeg = resolve(root, 'node_modules/@ffmpeg-installer/win32-x64/ffmpeg.exe');
const verifySync = file => {
  const pcm = input => {
    const decoded = spawnSync(ffmpeg, ['-v', 'error', '-nostdin', '-i', input, '-vn', '-ar', '48000', '-ac', '2', '-f', 's16le', 'pipe:1'], {maxBuffer: (duration + 1) * 192000, windowsHide: true});
    assert.equal(decoded.status, 0, String(decoded.stderr || decoded.error));
    return decoded.stdout;
  };
  const actual = pcm(file), expected = pcm(audio);
  assert(Math.abs(actual.length - expected.length) / 192000 < .1, '导出音轨时长与母带不符');
  let xy = 0, xx = 0, yy = 0;
  for (let i = 0; i < Math.min(actual.length, expected.length); i += 192) {
    const x = actual.readInt16LE(i), y = expected.readInt16LE(i);
    xy += x * y; xx += x * x; yy += y * y;
  }
  const correlation = xy / Math.sqrt(xx * yy);
  assert(correlation > .98, `导出音轨与母带不同步，零偏移相关度 ${correlation}`);
  console.log(`音轨同步校验通过，零偏移相关度 ${correlation.toFixed(6)}`);
};
if (process.argv.includes('--check')) {
  verifySync(video);
  process.exit(0);
}
const temporary = video.replace(/\.mp4$/, '.narration-mux.mp4');
// Direct PCM-to-AAC muxing preserves encoder priming metadata; the Remotion AAC
// export measured 2048 samples late with this installed toolchain.
const result = spawnSync(ffmpeg, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-y', '-i', video, '-i', audio, '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2', '-t', String(duration), '-movflags', '+faststart', temporary], {encoding: 'utf8', windowsHide: true});
assert.equal(result.status, 0, result.stderr || String(result.error));
verifySync(temporary);
renameSync(temporary, video);
console.log(`旁白已同步合入 ${video}`);
