import 'dart:convert';
import 'dart:io';

import 'src/benchmark_spec.dart';
import 'src/determinism_harness.dart';
import 'src/smart_layout_fixture_runner.dart';

/// 智能排版 v3 fixture manifest 校验与确定性 CLI（V3-001A/B）。
///
/// 用法：
///   dart run tool/smart_layout_v3/main.dart validate --manifest {path} [--repo-root {dir}]
///   dart run tool/smart_layout_v3/main.dart benchmark-hash [--spec {path}]
///   dart run tool/smart_layout_v3/main.dart determinism --manifest {path} --repo-root {dir} [--spec {path}] [--runs N]
///   dart run tool/smart_layout_v3/main.dart determinism-once --manifest {path} --repo-root {dir} [--spec {path}]
///
/// 输出机器可读 JSON。退出码：0=通过；2=拒绝/不一致；64=用法错误。
/// determinism 在隔离子进程中执行 N 次（默认 3），比对各次一致性哈希——
/// V3-001B 验收：同 fixture 三次运行一致；V3-001C 在同一入口上扩展批量执行。
void main(List<String> args) {
  if (args.isEmpty) {
    usage();
  }
  final options = _parseOptions(args.skip(1).toList());
  switch (args[0]) {
    case 'validate':
      _validate(options);
    case 'benchmark-hash':
      _benchmarkHash(options);
    case 'determinism':
      _determinism(options);
    case 'determinism-once':
      _determinismOnce(options);
    default:
      usage();
  }
}

Never usage() {
  stderr.writeln('usage: main.dart {validate|benchmark-hash|determinism|determinism-once} [options]');
  stderr.writeln('  validate --manifest {path} [--repo-root {dir}]');
  stderr.writeln('  benchmark-hash [--spec {path}]');
  stderr.writeln('  determinism --manifest {path} --repo-root {dir} [--spec {path}] [--runs N]');
  stderr.writeln('  determinism-once --manifest {path} --repo-root {dir} [--spec {path}]');
  exit(64);
}

Map<String, String> _parseOptions(List<String> rest) {
  final out = <String, String>{};
  for (var i = 0; i + 1 < rest.length; i += 2) {
    out[rest[i].replaceFirst('--', '')] = rest[i + 1];
  }
  return out;
}

void _validate(Map<String, String> options) {
  final manifestPath = options['manifest'];
  if (manifestPath == null) usage();
  final runner = SmartLayoutFixtureRunner(repoRoot: options['repo-root'] ?? Directory.current.path);
  final admission = runner.loadAndAdmit(manifestPath);
  _emit({
    'admitted': admission.admitted,
    'errors': [for (final e in admission.errors) e.toJson()],
  }, exitCode: admission.admitted ? 0 : 2);
}

void _benchmarkHash(Map<String, String> options) {
  final specPath = options['spec'] ?? _defaultSpecPath();
  final file = File(specPath);
  if (!file.existsSync()) {
    _emit({'ok': false, 'errors': ['benchmark spec 文件不存在：$specPath']}, exitCode: 2);
  }
  final load = BenchmarkSpec.load(jsonDecode(file.readAsStringSync()));
  if (!load.ok) {
    _emit({'ok': false, 'errors': load.errors}, exitCode: 2);
  }
  final spec = load.spec!;
  final hashErrors = BenchmarkSpec.verifyFileHash(specPath);
  _emit({
    'ok': hashErrors.isEmpty,
    'spec_version': spec.specVersion,
    'data_policy': spec.dataPolicy,
    'content_sha256': spec.contentHash,
    'errors': hashErrors,
  }, exitCode: hashErrors.isEmpty ? 0 : 2);
}

/// 默认 spec 路径：优先脚本同级 benchmark/（隔离子进程场景），
/// 回退当前工作目录拼 tool/smart_layout_v3（dart run 场景）。
String _defaultSpecPath() {
  final besideScript =
      '$_scriptDirParent${Platform.pathSeparator}benchmark${Platform.pathSeparator}benchmark-spec.json';
  if (File(besideScript).existsSync()) return besideScript;
  return '${Directory.current.path}${Platform.pathSeparator}tool${Platform.pathSeparator}smart_layout_v3${Platform.pathSeparator}benchmark${Platform.pathSeparator}benchmark-spec.json';
}

/// 单次确定性运行（被隔离子进程调用；也可独立执行）。
void _determinismOnce(Map<String, String> options) {
  final manifestPath = options['manifest'];
  final repoRoot = options['repo-root'];
  if (manifestPath == null || repoRoot == null) usage();
  final result = _singleDeterminismRun(manifestPath, repoRoot, options['spec']);
  _emit(result, exitCode: result['ok'] == true ? 0 : 2);
}

Map<String, Object?> _singleDeterminismRun(String manifestPath, String repoRoot, String? specPath) {
  final specFile = specPath == null ? File(_defaultSpecPath()) : File(specPath);
  if (!specFile.existsSync()) {
    return {'ok': false, 'errors': ['benchmark spec 不存在：${specFile.path}']};
  }
  final specLoad = BenchmarkSpec.load(jsonDecode(specFile.readAsStringSync()));
  if (!specLoad.ok) {
    return {'ok': false, 'errors': specLoad.errors};
  }
  final admission = SmartLayoutFixtureRunner(repoRoot: repoRoot).loadAndAdmit(manifestPath);
  if (!admission.admitted) {
    return {
      'ok': false,
      'stage': 'admission',
      'errors': [for (final e in admission.errors) e.toJson()],
    };
  }
  final manifest = admission.manifest!;
  final harness = DeterminismHarness(repoRoot: repoRoot);
  final policyViolations = harness.checkDataPolicy(manifest, specLoad.spec!);
  if (policyViolations.isNotEmpty) {
    return {'ok': false, 'stage': 'data_policy', 'errors': policyViolations};
  }
  final reports = [for (final fixture in manifest.fixtures) harness.runOnce(fixture, specLoad.spec!)];
  return {
    'ok': reports.every((r) => r.ok),
    'reports': [for (final r in reports) r.toJson()],
    'consistency': {
      for (final r in reports)
        if (r.ok) r.fixtureId: r.consistencyHash,
    },
  };
}

/// 确定性验收：在 N 个隔离子进程中各跑一次，比对一致性哈希。
void _determinism(Map<String, String> options) {
  final manifestPath = options['manifest'];
  final repoRoot = options['repo-root'];
  if (manifestPath == null || repoRoot == null) usage();
  final specPath = options['spec'];
  final runs = int.tryParse(options['runs'] ?? '') ?? 3;
  final manifestAbs = File(manifestPath).absolute.path;
  final repoAbs = Directory(repoRoot).absolute.path;
  final specAbs = specPath == null ? null : File(specPath).absolute.path;

  final consistencyByRun = <Map<String, Object?>>[];
  for (var i = 0; i < runs; i++) {
    final child = _spawnIsolatedRun(manifestAbs, repoAbs, specAbs);
    if (child == null) {
      _emit({'ok': false, 'errors': ['无法启动隔离子进程（需要 dart VM）']}, exitCode: 2);
    }
    final stdoutText = child.stdout is String ? child.stdout as String : '';
    final Object? json;
    try {
      json = jsonDecode(stdoutText.trim().isEmpty ? child.stderr : stdoutText);
    } on FormatException {
      _emit({
        'ok': false,
        'errors': ['子进程输出不可解析：exitCode=${child.exitCode}', child.stderr],
      }, exitCode: 2);
    }
    if (child.exitCode != 0 || json is! Map<String, Object?> || json['ok'] != true) {
      _emit({
        'ok': false,
        'errors': ['隔离运行 #${i + 1} 失败：exitCode=${child.exitCode}', json],
      }, exitCode: 2);
    }
    consistencyByRun.add((json['consistency'] as Map<String, Object?>?) ?? <String, Object?>{});
  }
  final first = consistencyByRun.first;
  final consistent = consistencyByRun.every((c) => jsonEncode(c) == jsonEncode(first));
  _emit({
    'ok': consistent,
    'runs': runs,
    'isolated_processes': true,
    'consistency_by_run': consistencyByRun,
    'consistent': consistent,
  }, exitCode: consistent ? 0 : 2);
}

String? _dartExecutableCache;

String? get dartExecutable {
  if (_dartExecutableCache != null) return _dartExecutableCache;
  // dart run 下 resolvedExecutable 即 dart VM；flutter_test 下是 flutter_tester，
  // 需回退到 PATH 或 SMART_LAYOUT_V3_DART 环境变量。
  final resolved = Platform.resolvedExecutable;
  final exeSuffix = Platform.isWindows ? '.exe' : '';
  if (resolved.toLowerCase().endsWith('dart$exeSuffix')) {
    return _dartExecutableCache = resolved;
  }
  final env = Platform.environment['SMART_LAYOUT_V3_DART'];
  if (env != null && env.isNotEmpty) return _dartExecutableCache = env;
  final candidates = exeSuffix.isEmpty ? ['dart'] : ['dart.exe', 'dart'];
  for (final candidate in candidates) {
    try {
      if (Process.runSync(candidate, ['--version']).exitCode == 0) {
        return _dartExecutableCache = candidate;
      }
    } on ProcessException {
      // 继续尝试下一个候选。
    }
  }
  return _dartExecutableCache = null;
}

ProcessResult? _spawnIsolatedRun(String manifestAbs, String repoAbs, String? specAbs) {
  final dart = dartExecutable;
  if (dart == null) return null;
  final script = '$_scriptDirParent${Platform.pathSeparator}main.dart';
  final args = [
    script,
    'determinism-once',
    '--manifest', manifestAbs,
    '--repo-root', repoAbs,
    if (specAbs != null) ...['--spec', specAbs],
  ];
  return Process.runSync(dart, args, workingDirectory: repoAbs);
}

/// 当前脚本（main.dart）所在目录：隔离子进程用同一入口脚本。
String get _scriptDirParent {
  final scriptPath = Platform.script.toFilePath();
  return File(scriptPath).parent.path;
}

Never _emit(Map<String, Object?> payload, {required int exitCode}) {
  stdout.writeln(jsonEncode(payload));
  exit(exitCode);
}
