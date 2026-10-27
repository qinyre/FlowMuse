import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { classifyChanges, changedPaths, gatePassed } from './ci-scope.mjs';

test('scope covers human docs, machine contracts, source, dependencies and unknown inputs', () => {
  const none = { flutter: false, server: false, layout: false };
  const app = { ...none, flutter: true };
  const layout = { ...app, layout: true };
  const all = { flutter: true, server: true, layout: true };
  for (const [paths, expected] of [
    [['README.md', 'AGENTS.md', 'FlowMuse-App/README.md', 'docs/研发记录/images/ui.png'], none],
    [['FlowMuse-App/lib/features/settings/views/settings_page.dart'], app],
    [['FlowMuse-App/test/features/settings/views/settings_layout_test.dart'], app],
    [['FlowMuse-App/lib/features/whiteboard/editor_core/editor.dart'], layout],
    [['FlowMuse-App/lib/shared/storage/local_database.dart'], layout],
    [['FlowMuse-App/pubspec.lock'], layout],
    [['FlowMuse-App/assets/help.md'], layout],
    [['FlowMuse-App/test/fixtures/contract.md'], layout],
    [['FlowMuse-App/test/features/whiteboard/smart_layout/patch/apply_test.dart'], layout],
    [['FlowMuse-App/tool/vendor/code_assets/lib/code_assets.dart'], layout],
    [['docs/研发记录/specs/smart-layout-v3/protocol/protocol.md'], all],
    [['docs/研发记录/evidence/smart-layout-v3/gates/G0/report.json'], all],
    [['docs/研发记录/plans/smart-layout-v3-agent/schema.json'], all],
    [['FlowMuse-Server/internal/collab/hub.go'], { ...none, server: true }],
    [['.github/workflows/quality.yml'], all],
    [['future-runtime/config.json'], all],
    [[], none],
  ]) assert.deepEqual(classifyChanges(paths), expected, paths.join(','));
});

test('a removed source or a rename into documentation still requires its original regression', () => {
  const dir = mkdtempSync(join(tmpdir(), 'flowmuse-ci-'));
  const git = (...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  try {
    git('init', '-q'); git('config', 'user.name', 'CI Test'); git('config', 'user.email', 'ci@example.invalid');
    mkdirSync(join(dir, 'FlowMuse-App'), { recursive: true });
    writeFileSync(join(dir, 'FlowMuse-App/source.dart'), 'old source');
    git('add', '.'); git('commit', '-qm', 'base');
    const base = git('rev-parse', 'HEAD');
    git('mv', 'FlowMuse-App/source.dart', 'README.md'); git('commit', '-qm', 'rename');
    const paths = changedPaths(base, dir);
    assert(paths.includes('FlowMuse-App/source.dart') && paths.includes('README.md'));
    assert.equal(classifyChanges(paths).flutter, true);
    const checkout = join(dir, 'checkout');
    git('clone', '--quiet', '--depth=1', '--no-checkout', pathToFileURL(dir).href, checkout);
    execFileSync('git', ['sparse-checkout', 'set', '.github/scripts'], { cwd: checkout });
    execFileSync('git', ['checkout', '--quiet'], { cwd: checkout });
    const output = execFileSync(process.execPath, [fileURLToPath(new URL('./ci-scope.mjs', import.meta.url))], {
      cwd: checkout,
      encoding: 'utf8',
      env: { ...process.env, CI_BASE_SHA: base, GITHUB_EVENT_NAME: 'pull_request', GITHUB_OUTPUT: join(checkout, 'outputs') },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    assert.match(output, /flutter=true\nserver=false\nlayout=false\n/u);
    assert.throws(() => changedPaths('--bad-base', dir), /Invalid base/);
    assert.throws(() => changedPaths('f'.repeat(40), dir));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('summary gate rejects failed detection, failed/cancelled/missing shards and invalid flags', () => {
  assert(gatePassed('success', 'true', 'success'));
  assert(gatePassed('success', 'false', 'skipped'));
  for (const state of ['failure', 'cancelled', 'skipped', undefined]) {
    assert.equal(gatePassed(state, 'false', 'skipped'), false);
    assert.equal(gatePassed('success', 'true', state), false);
  }
  assert.equal(gatePassed('success', undefined, 'skipped'), false);
  assert.equal(gatePassed('success', 'false', 'failure'), false);
});
