import { appendFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function classifyChanges(paths) {
  const scope = { flutter: false, server: false, layout: false };
  for (const path of paths) {
    // These documents are consumed as contracts/fixtures, including Markdown.
    if (/^docs\/研发记录\/(specs\/smart-layout-v3|evidence|plans\/smart-layout-v3-agent)\//u.test(path)) {
      scope.flutter = scope.server = scope.layout = true;
    } else if (/^FlowMuse-App\/(assets|test\/fixtures|tool\/vendor)\//u.test(path)) {
      scope.flutter = scope.layout = true;
    } else if (/\.(md|mdx|rst|adoc)$/iu.test(path) || /^docs\/.+\.(png|jpe?g|webp|svg|mp4|mp3)$/iu.test(path)) {
      continue;
    } else if (path.startsWith('FlowMuse-App/')) {
      scope.flutter = true;
      if (/^FlowMuse-App\/((lib|test)\/(features\/whiteboard|shared|app)\/|test\/fixtures\/|assets\/|tool\/|pubspec\.)/u.test(path)) {
        scope.layout = true;
      }
    } else if (path.startsWith('FlowMuse-Server/')) {
      scope.server = true;
    } else {
      // Unknown inputs and CI changes must not silently skip a regression.
      scope.flutter = scope.server = scope.layout = true;
    }
  }
  return scope;
}

export function changedPaths(base, cwd = process.cwd()) {
  if (!/^[a-f0-9]{40}$/iu.test(base)) throw new Error('Invalid base commit');
  return execFileSync('git', ['diff', '--no-renames', '--name-only', '-z', base, 'HEAD', '--'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).split('\0').filter(Boolean);
}

export function gatePassed(scopeResult, required, taskResult) {
  return scopeResult === 'success' && (required === 'true' ? taskResult === 'success' : required === 'false' && taskResult === 'skipped');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv[2] === 'gate') {
      if (!gatePassed(process.env.SCOPE_RESULT, process.env.FLUTTER_REQUIRED, process.env.SHARD_RESULT)) throw new Error('Required checks did not complete successfully');
    } else {
      const base = process.env.CI_BASE_SHA;
      let scope;
      if (process.env.GITHUB_EVENT_NAME === 'workflow_dispatch' || !base || /^0+$/u.test(base)) {
        scope = { flutter: true, server: true, layout: true };
      } else {
        if (!/^[a-f0-9]{40}$/iu.test(base)) throw new Error('Invalid base commit');
        try {
          execFileSync('git', ['cat-file', '-e', `${base}^{commit}`], { stdio: 'ignore' });
        } catch {
          execFileSync('git', ['fetch', '--no-tags', '--depth=1', '--filter=blob:none', 'origin', base], { stdio: 'inherit' });
        }
        scope = classifyChanges(changedPaths(base));
      }
      const output = Object.entries(scope).map(([key, value]) => `${key}=${value}\n`).join('');
      if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, output);
      process.stdout.write(output);
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
