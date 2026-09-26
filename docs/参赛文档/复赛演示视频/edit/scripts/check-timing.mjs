import assert from 'node:assert/strict';
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const edit = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(edit, '../output');
mkdirSync(output, {recursive: true});
const fixture = mkdtempSync(join(output, 'timing-check-'));
const fixtureEdit = join(fixture, 'edit');
const source = JSON.parse(readFileSync(resolve(edit, '../timeline.json'), 'utf8'));
mkdirSync(join(fixtureEdit, 'scripts'), {recursive: true});
mkdirSync(join(fixtureEdit, 'public/footage'), {recursive: true});
copyFileSync(join(edit, 'scripts/prepare.mjs'), join(fixtureEdit, 'scripts/prepare.mjs'));
copyFileSync(join(edit, 'public/intro-v4.mp4'), join(fixtureEdit, 'public/intro-v4.mp4'));
symlinkSync(join(edit, 'node_modules'), join(fixtureEdit, 'node_modules'), 'junction');
const run = (seconds, final = false) => {
  const data = structuredClone(source);
  data.scenes.find(s => s.id === 'library').duration = seconds;
  writeFileSync(join(fixture, 'timeline.json'), JSON.stringify(data));
  const result = spawnSync(process.execPath, [join(fixtureEdit, 'scripts/prepare.mjs'), ...(final ? ['--final'] : [])], {encoding: 'utf8', windowsHide: true});
  return {...result, log: result.stdout + result.stderr};
};
const captions = () => JSON.parse(readFileSync(join(fixtureEdit, 'src/captions.generated.json'), 'utf8'));
try {
  const original = source.scenes.find(s => s.id === 'library').duration;
  assert.equal(run(original).status, 0);
  const baseline = captions();
  assert.equal(run(original + 7).status, 0);
  const shifted = captions();
  assert.equal(shifted[0].startMs, baseline[0].startMs);
  assert.equal(shifted.at(-1).startMs, baseline.at(-1).startMs + 7000, '后续字幕须随前段变长自动顺延');
  const library = source.scenes.find(s => s.id === 'library');
  const minimum = Math.ceil(Math.max(...library.cues.map(([at, length]) => at + length), ...library.steps.map(s => s.at + 1)));
  assert.equal(run(minimum).status, 0);
  assert.equal(captions().at(-1).startMs, baseline.at(-1).startMs + (minimum - original) * 1000);
  assert.notEqual(run(1).status, 0, '不可静默丢弃超出本段的步骤和字幕');
  assert.equal(run(301).status, 0, '剪辑预演允许超时');
  assert.match(run(301, true).log, /5 分钟以内/, '仅正式导出强制总时长限制');
  copyFileSync(join(edit, 'public/intro-v4.mp4'), join(fixtureEdit, 'public/footage', library.file));
  assert.match(run(original).log, /无需重录成精确时长/, '短素材提示须指向调整剪辑计划');
  console.log('时长回归通过：长短场景、字幕顺延、超短拒绝、超时预演与提交限制、短素材提示。');
} finally {
  assert(resolve(fixture).startsWith(output + '\\') || resolve(fixture).startsWith(output + '/'));
  unlinkSync(join(fixtureEdit, 'node_modules'));
  rmSync(fixture, {recursive: true, force: true});
}
