/// V3-602A：智能排版 v3 可复制 CI 矩阵（合并原 V3-602A~B）。
///
/// 目标符号 [SmartLayoutCiMatrix]。约束：
/// - 新 clone 可运行：全部路径仓库相对，报告零本机绝对路径
///   （诊断文本中的仓库根前缀一律脱敏为 repo 相对形态）；
/// - 固定环境：字体=仓库捆绑（Excalifont 等，零网络）、fixture
///   server=测试内自建 loopback（V3-506A 矩阵同源，无外部依赖）、
///   runner 经 workflow 钉死 Flutter 分支；
/// - 归档：机器报告（schema/版本/逐 stage 命令、退出码、时长、
///   失败诊断尾部与失败产物清单）+ 聚合退出码（任一 stage 非零即非零）；
/// - 复现：--replay 对照历史报告 canonical 投影（剥时长/时间戳）；
/// - 缓存：--cache 按 stage 指纹（命令+输入文件内容哈希）复用工作区
///   既有结果，指纹变化自动失效。
library;

import 'dart:convert';
import 'dart:io';

const ciMatrixSchemaVersion = 1;
const ciMatrixToolVersion = '1.0.0';

/// 一条 CI stage：命令（首个元素为可执行文件）+ 仓库相对工作目录 +
/// 输入指纹文件集（缓存键）+ 失败时归档的诊断产物（仓库相对路径）。
class CiStage {
  const CiStage({
    required this.id,
    required this.command,
    required this.workingDir,
    this.inputs = const [],
    this.failureArtifacts = const [],
  });

  final String id;
  final List<String> command;
  final String workingDir;
  final List<String> inputs;
  final List<String> failureArtifacts;

  Map<String, Object?> toJson() => {
    'id': id,
    'command': command,
    'working_dir': workingDir,
    'inputs': inputs,
    'failure_artifacts': failureArtifacts,
  };
}

/// 单次 stage 执行结果（机器报告条目）。
class CiStageResult {
  const CiStageResult({
    required this.id,
    required this.command,
    required this.exitCode,
    required this.durationMs,
    required this.stdoutTail,
    required this.stderrTail,
    required this.capturedArtifacts,
    this.cached = false,
  });

  final String id;
  final List<String> command;
  final int exitCode;
  final int durationMs;
  final String stdoutTail;
  final String stderrTail;
  final List<String> capturedArtifacts;
  final bool cached;

  bool get passed => exitCode == 0;

  Map<String, Object?> toJson() => {
    'id': id,
    'command': command,
    'exit_code': exitCode,
    'duration_ms': durationMs,
    'stdout_tail': stdoutTail,
    'stderr_tail': stderrTail,
    'captured_failure_artifacts': capturedArtifacts,
    if (cached) 'cached': true,
  };

  /// canonical 投影：剥时长与缓存标记（replay 对照口径），其余逐字段。
  Map<String, Object?> toCanonicalJson() => {
    'id': id,
    'command': command,
    'exit_code': exitCode,
    'stdout_tail': stdoutTail,
    'stderr_tail': stderrTail,
    'captured_failure_artifacts': capturedArtifacts,
  };
}

/// 完整矩阵报告。
class CiMatrixReport {
  const CiMatrixReport({
    required this.toolVersion,
    required this.flutterVersion,
    required this.results,
    required this.generatedAtUtc,
  });

  final String toolVersion;
  final String flutterVersion;
  final List<CiStageResult> results;
  final String generatedAtUtc;

  bool get allPassed => results.every((r) => r.passed);

  /// 聚合退出码：全部通过=0；否则首个失败 stage 的退出码（0 时回退 1）。
  int get aggregateExitCode {
    if (allPassed) return 0;
    final failed = results.firstWhere((r) => !r.passed);
    return failed.exitCode == 0 ? 1 : failed.exitCode;
  }

  Map<String, Object?> toJson() => {
    'schema_version': ciMatrixSchemaVersion,
    'tool_version': toolVersion,
    'matrix': 'smart-layout-v3',
    'generated_at_utc': generatedAtUtc,
    'environment': {'flutter': flutterVersion},
    'all_passed': allPassed,
    'aggregate_exit_code': aggregateExitCode,
    'stages': [for (final r in results) r.toJson()],
  };

  /// canonical 投影（时间戳/时长/环境版本之外的执行事实）——replay 与
  /// 双跑对照的唯一口径。
  Map<String, Object?> toCanonicalJson() => {
    'schema_version': ciMatrixSchemaVersion,
    'tool_version': toolVersion,
    'matrix': 'smart-layout-v3',
    'all_passed': allPassed,
    'aggregate_exit_code': aggregateExitCode,
    'stages': [for (final r in results) r.toCanonicalJson()],
  };
}

/// 命令执行器抽象（测试注入 fake；生产 [ProcessCiCommandExecutor]）。
typedef CiCommandExecutor = Future<CiCommandOutcome> Function(
  List<String> command,
  String workingDir,
);

class CiCommandOutcome {
  const CiCommandOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// 诊断尾部上限：失败诊断保留必要信息但不吞报告。
const ciDiagnosticTailLimit = 4000;

/// CI 矩阵本体。
class SmartLayoutCiMatrix {
  SmartLayoutCiMatrix({
    required this.stages,
    required this.repoRoot,
    CiCommandExecutor? executor,
    DateTime Function()? now,
  }) : _executor = executor ?? ProcessCiCommandExecutor.execute,
       _now = now ?? DateTime.now;

  final List<CiStage> stages;
  final String repoRoot;
  final CiCommandExecutor _executor;
  final DateTime Function() _now;

  /// 顺序执行全部 stage；[workDir]（仓库相对）存 stage 缓存与失败产物
  /// 副本；[useCache] 为真时按指纹复用缓存结果。
  Future<CiMatrixReport> run({
    required String workDir,
    bool useCache = false,
  }) async {
    CiPathPolicy.ensureRelative(workDir);
    final flutterVersion = await _flutterVersion();
    final results = <CiStageResult>[];
    for (final stage in stages) {
      results.add(await _runStage(stage, workDir, useCache));
    }
    return CiMatrixReport(
      toolVersion: ciMatrixToolVersion,
      flutterVersion: flutterVersion,
      results: results,
      generatedAtUtc: _now().toUtc().toIso8601String(),
    );
  }

  Future<CiStageResult> _runStage(
    CiStage stage,
    String workDir,
    bool useCache,
  ) async {
    final cacheFile = _cacheFilePath(repoRoot, workDir, stage.id);
    final fingerprint = stageFingerprint(stage, repoRoot);

    if (useCache && File(cacheFile).existsSync()) {
      try {
        final cached = jsonDecode(File(cacheFile).readAsStringSync())
            as Map<String, Object?>;
        if (cached['fingerprint'] == fingerprint &&
            cached['result'] is Map) {
          final r = Map<String, Object?>.from(cached['result']! as Map);
          return CiStageResult(
            id: r['id'] as String,
            command: [for (final c in r['command'] as List) c as String],
            exitCode: r['exit_code'] as int,
            durationMs: r['duration_ms'] as int,
            stdoutTail: r['stdout_tail'] as String,
            stderrTail: r['stderr_tail'] as String,
            capturedArtifacts: [
              for (final a in r['captured_failure_artifacts'] as List)
                a as String,
            ],
            cached: true,
          );
        }
      } catch (_) {
        // 缓存损坏即视为未命中。
      }
    }

    final started = _now();
    final outcome = await _executor(
      stage.command,
      _absoluteWorkingDir(stage.workingDir),
    );
    final durationMs = _now().difference(started).inMilliseconds;

    final failed = outcome.exitCode != 0;
    final captured = <String>[];
    if (failed) {
      for (final artifact in stage.failureArtifacts) {
        captured.addAll(_copyGlobInto(artifact, '$workDir/failures/${stage.id}'));
      }
    }
    final result = CiStageResult(
      id: stage.id,
      command: stage.command,
      exitCode: outcome.exitCode,
      durationMs: durationMs,
      stdoutTail: CiPathPolicy.redactRepoRoot(
        _tail(outcome.stdout),
        repoRoot,
      ),
      stderrTail: CiPathPolicy.redactRepoRoot(
        _tail(outcome.stderr),
        repoRoot,
      ),
      capturedArtifacts: captured,
    );
    try {
      _writeCache(cacheFile, fingerprint, result);
    } on FileSystemException {
      // 未启用缓存时，缓存预热失败不应让实际检查结果变红。
      if (useCache) rethrow;
    }
    return result;
  }

  /// 仓库相对工作目录 → 绝对路径（repoRoot 基准；策略校验后解析）。
  String _absoluteWorkingDir(String workingDir) {
    final relative = workingDir == '.'
        ? ''
        : CiPathPolicy.ensureRelative(workingDir);
    return relative.isEmpty ? repoRoot : '$repoRoot/$relative';
  }

  Future<String> _flutterVersion() async {
    try {
      final outcome = await _executor(
        [CiCommandResolver.flutter, '--version'],
        _absoluteWorkingDir('.'),
      );
      final first = CiPathPolicy.redactRepoRoot(
        outcome.stdout.split('\n').first.trim(),
        repoRoot,
      );
      return first.isEmpty ? 'unknown' : first;
    } catch (_) {
      return 'unknown';
    }
  }

  static String _tail(String text) {
    if (text.length <= ciDiagnosticTailLimit) return text;
    return '...(截断)...${text.substring(text.length - ciDiagnosticTailLimit)}';
  }

  static String _cacheFilePath(
    String repoRoot,
    String workDir,
    String stageId,
  ) => '$repoRoot/$workDir/cache/$stageId.json';

  static void _writeCache(
    String cacheFile,
    String fingerprint,
    CiStageResult result,
  ) {
    final file = File(cacheFile);
    file.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'fingerprint': fingerprint,
        'result': result.toJson(),
      }),
    );
  }

  /// stage 指纹：命令 + 输入内容哈希（文件或目录；仓库相对路径策略校验）。
  static String stageFingerprint(CiStage stage, String repoRoot) {
    final inputHashes = [
      for (final input in stage.inputs)
        '$input:${_hashPath('$repoRoot/${CiPathPolicy.ensureRelative(input)}')}',
    ];
    return _sha256String(
      jsonEncode({'command': stage.command, 'inputs': inputHashes}),
    );
  }

  /// 路径指纹：文件=内容哈希；目录=内部全部文件（排序后名+内容）联合哈希。
  static String _hashPath(String path) {
    final file = File(path);
    if (file.existsSync()) return _sha256Bytes(file.readAsBytesSync());
    final dir = Directory(path);
    if (!dir.existsSync()) return 'missing';
    final entries = dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/'))
        .toList()
      ..sort();
    return _sha256String(
      jsonEncode({
        for (final entry in entries)
          entry.substring(entry.lastIndexOf('/') + 1):
              _sha256Bytes(File(entry).readAsBytesSync()),
      }),
    );
  }

  static String _sha256String(String value) =>
      _sha256Bytes(utf8.encode(value));

  static String _sha256Bytes(List<int> bytes) {
    var digest = bytes;
    // 轻量 FNV-1a 64：报告指纹只用于缓存失效判定，非密码学用途。
    var hash = 0xcbf29ce484222325;
    for (final byte in digest) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  /// 将 glob（仓库相对，支持目录前缀展开为该目录下全部文件）复制进
  /// 失败归档目录，返回归档相对路径清单。
  List<String> _copyGlobInto(String pattern, String destDir) {
    CiPathPolicy.ensureRelative(pattern);
    final source = Directory('$repoRoot/$pattern');
    final files = <File>[];
    if (source.existsSync()) {
      files.addAll(
        source.listSync(recursive: true).whereType<File>().where(
          (f) => f.path.endsWith('.json'),
        ),
      );
    } else if (File('$repoRoot/$pattern').existsSync()) {
      files.add(File('$repoRoot/$pattern'));
    }
    final copied = <String>[];
    for (final file in files) {
      final normalized = file.path.replaceAll('\\', '/');
      final name = normalized.substring(normalized.lastIndexOf('/') + 1);
      final dest = File('$repoRoot/$destDir/$name');
      dest.createSync(recursive: true);
      dest.writeAsBytesSync(file.readAsBytesSync());
      copied.add('$destDir/$name');
    }
    return copied;
  }
}

/// 路径策略：报告与配置零本机绝对路径（新 clone 可运行的前提）。
abstract final class CiPathPolicy {
  /// 校验仓库相对路径：拒绝绝对路径（POSIX / 与 Windows 盘符）与 ..。
  static String ensureRelative(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized.split('/').contains('..')) {
      throw FormatException('CI 路径必须仓库相对且不含 ..: $path');
    }
    return normalized;
  }

  /// 诊断脱敏：把文本中的仓库根绝对前缀替换为空（报告零本机路径）。
  static String redactRepoRoot(String text, String repoRoot) {
    if (repoRoot.isEmpty) return text;
    return text
        .replaceAll(repoRoot, '')
        .replaceAll(repoRoot.replaceAll('/', '\\'), '');
  }
}

/// 跨平台命令解析（Windows flutter.bat / 其他 flutter）。
abstract final class CiCommandResolver {
  static String get flutter =>
      Platform.isWindows ? 'flutter.bat' : 'flutter';

  static String get dart => Platform.isWindows ? 'dart.bat' : 'dart';
}

class ProcessCiCommandExecutor {
  static Future<CiCommandOutcome> execute(
    List<String> command,
    String workingDir,
  ) async {
    final resolved = command.first == 'flutter'
        ? [CiCommandResolver.flutter, ...command.skip(1)]
        : command.first == 'dart'
        ? [CiCommandResolver.dart, ...command.skip(1)]
        : command;
    final effectiveDir = workingDir == '.'
        ? Directory.current.path
        : workingDir;
    final result = await Process.run(
      resolved.first,
      resolved.skip(1).toList(),
      workingDirectory: effectiveDir,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return CiCommandOutcome(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}

/// 矩阵默认 stage 集（智能排版 v3 CI 固定口径；字体=仓库捆绑零网络，
/// fixture server=测试内自建 loopback）。
List<CiStage> smartLayoutV3DefaultStages() => const [
  CiStage(
    id: 'analyze-smart-layout',
    command: [
      'flutter', 'analyze',
      'lib/features/whiteboard/smart_layout',
      'test/features/whiteboard/smart_layout',
      'tool/smart_layout_v3/ci',
    ],
    workingDir: 'FlowMuse-App',
    inputs: [
      'FlowMuse-App/lib/features/whiteboard/smart_layout',
      'FlowMuse-App/tool/smart_layout_v3/ci',
    ],
  ),
  CiStage(
    id: 'test-smart-layout-core',
    command: [
      'flutter', 'test',
      'test/features/whiteboard/smart_layout/patch',
      'test/features/whiteboard/smart_layout/snapshot',
      'test/features/whiteboard/smart_layout/document',
      'test/features/whiteboard/smart_layout/compatibility',
    ],
    workingDir: 'FlowMuse-App',
    inputs: ['FlowMuse-App/lib/features/whiteboard/smart_layout'],
    failureArtifacts: ['docs/研发记录/evidence/smart-layout-v3/tasks'],
  ),
  CiStage(
    id: 'test-smart-layout-transaction',
    command: [
      'flutter', 'test',
      'test/features/whiteboard/smart_layout/transaction',
    ],
    workingDir: 'FlowMuse-App',
    inputs: ['FlowMuse-App/lib/features/whiteboard/smart_layout/session'],
  ),
  CiStage(
    id: 'determinism-double-run',
    command: [
      'dart', 'run', 'tool/smart_layout_v3/ci/determinism_ci_check.dart',
      '--runs', '2',
    ],
    workingDir: 'FlowMuse-App',
    inputs: ['FlowMuse-App/tool/smart_layout_v3/ci'],
  ),
  CiStage(
    id: 'ci-tool-self-test',
    command: ['flutter', 'test', 'tool/smart_layout_v3/ci'],
    workingDir: 'FlowMuse-App',
    inputs: ['FlowMuse-App/tool/smart_layout_v3/ci'],
  ),
];

/// 故意破坏探针 stage（--sabotage 注入）：证明失败能阻断聚合退出码并
/// 保留诊断与失败产物。
const CiStage sabotageProbeStage = CiStage(
  id: 'sabotage-probe',
  command: ['dart', 'run', 'tool/smart_layout_v3/ci/sabotage_probe.dart'],
  workingDir: 'FlowMuse-App',
  inputs: ['FlowMuse-App/tool/smart_layout_v3/ci/sabotage_probe.dart'],
  failureArtifacts: ['docs/研发记录/evidence/smart-layout-v3/ci/sabotage'],
);

Future<void> main(List<String> args) async {
  final workDir = _argValue(args, '--workdir') ?? '.dart_tool/smart_layout_v3_ci';
  final reportPath = _argValue(args, '--report');
  final replayPath = _argValue(args, '--replay');
  final useCache = args.contains('--cache');
  final sabotage = args.contains('--sabotage');
  final repoRoot = _repoRootFromScript();

  // --only <id>（可重复）：只跑指定 stage（破坏验证/调试用）。
  final only = <String>{
    for (var i = 0; i < args.length - 1; i++)
      if (args[i] == '--only') args[i + 1],
  };
  final stages = [
    ...smartLayoutV3DefaultStages(),
    if (sabotage) sabotageProbeStage,
  ].where((s) => only.isEmpty || only.contains(s.id)).toList();
  final matrix = SmartLayoutCiMatrix(stages: stages, repoRoot: repoRoot);
  final report = await matrix.run(workDir: workDir, useCache: useCache);

  final reportJson = const JsonEncoder.withIndent('  ').convert(
    report.toJson(),
  );
  if (reportPath != null) {
    CiPathPolicy.ensureRelative(reportPath);
    final file = File('$repoRoot/$reportPath');
    file.createSync(recursive: true);
    file.writeAsStringSync(reportJson);
    stdout.writeln('[ci-matrix] report: $reportPath');
  } else {
    stdout.writeln(reportJson);
  }

  if (replayPath != null) {
    CiPathPolicy.ensureRelative(replayPath);
    final replayFile = File('$repoRoot/$replayPath');
    if (!replayFile.existsSync()) {
      stderr.writeln('[ci-matrix] replay 基准不存在: $replayPath');
      exit(2);
    }
    final baseline = CiReplay.loadCanonical(replayFile.readAsStringSync());
    final current = CiReplay.canonicalOf(report);
    if (baseline == null) {
      stderr.writeln('[ci-matrix] replay 基准不是合法矩阵报告');
      exit(2);
    }
    if (jsonEncode(baseline) != jsonEncode(current)) {
      stderr.writeln('[ci-matrix] replay 不一致（执行事实偏离基线）');
      exit(3);
    }
    stdout.writeln('[ci-matrix] replay 一致');
  }

  stdout.writeln(
    '[ci-matrix] all_passed=${report.allPassed} '
    'aggregate_exit_code=${report.aggregateExitCode}',
  );
  exit(report.aggregateExitCode);
}

/// replay 对照：从历史报告 JSON 提取 canonical 投影。
abstract final class CiReplay {
  static Map<String, Object?>? loadCanonical(String reportJson) {
    try {
      final decoded = jsonDecode(reportJson);
      if (decoded is! Map<String, Object?>) return null;
      if (decoded['matrix'] != 'smart-layout-v3') return null;
      return _extractCanonical(decoded);
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?> canonicalOf(CiMatrixReport report) =>
      report.toCanonicalJson();

  static Map<String, Object?> _extractCanonical(
    Map<String, Object?> report,
  ) => {
    'schema_version': report['schema_version'],
    'tool_version': report['tool_version'],
    'matrix': report['matrix'],
    'all_passed': report['all_passed'],
    'aggregate_exit_code': report['aggregate_exit_code'],
    'stages': [
      for (final stage in (report['stages'] as List).cast<Map<String, Object?>>())
        {
          'id': stage['id'],
          'command': stage['command'],
          'exit_code': stage['exit_code'],
          'stdout_tail': stage['stdout_tail'],
          'stderr_tail': stage['stderr_tail'],
          'captured_failure_artifacts': stage['captured_failure_artifacts'],
        },
    ],
  };
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

/// 从脚本位置推导仓库根（脚本位于 repo 内 FlowMuse-App/tool/smart_layout_v3/ci/）。
String _repoRootFromScript() {
  final script = Platform.script.toFilePath().replaceAll('\\', '/');
  final marker = '/FlowMuse-App/tool/';
  final idx = script.lastIndexOf(marker);
  if (idx <= 0) {
    throw StateError('无法从脚本位置推导仓库根: $script');
  }
  return script.substring(0, idx);
}
