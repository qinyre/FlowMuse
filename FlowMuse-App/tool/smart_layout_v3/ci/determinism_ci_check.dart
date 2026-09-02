/// V3-602A：确定性双跑门禁——目标符号 [DeterminismCiCheck]。
///
/// 对固定确定性测试集连续跑 N 次（默认 2），逐测试比对结果集：
/// - 任何一轮非全绿 → 非零退出 + 失败清单；
/// - 轮间同测试结果漂移（success↔failure 或失败详情变化）→ 非零退出；
/// - 全部一致 → 报告 deterministic=true，退出 0。
///
/// 解析 `flutter test --machine` 事件流（testDone/error 事件），输出为
/// 仓库相对、零本机路径（诊断经 [CiPathPolicy.redactRepoRoot] 脱敏）。
library;

import 'dart:convert';
import 'dart:io';

import 'smart_layout_ci_matrix.dart';

const determinismCheckToolVersion = '1.0.0';

/// 确定性关键测试集（双跑对照组）：patch 构建/不变量、快照指纹与账本
/// 哈希、文档映射 canonical 判别——全部为显式确定性设计（无时钟、无
/// 随机、双跑深度等价是其既有契约）。
const List<String> defaultDeterminismTargets = [
  'test/features/whiteboard/smart_layout/patch',
  'test/features/whiteboard/smart_layout/snapshot',
  'test/features/whiteboard/smart_layout/document',
];

class DeterminismRunOutcome {
  const DeterminismRunOutcome({
    required this.exitCode,
    required this.testResults,
    required this.errorSummaries,
  });

  final int exitCode;

  /// 测试名 → 结果（success/failure/error）。
  final Map<String, String> testResults;

  /// error 事件摘要（脱敏后，按出现序）。
  final List<String> errorSummaries;

  bool get allPassed =>
      exitCode == 0 && testResults.values.every((r) => r == 'success');
}

class DeterminismReport {
  const DeterminismReport({
    required this.runs,
    required this.deterministic,
    required this.outcomes,
    this.driftedTests = const [],
  });

  final int runs;
  final bool deterministic;
  final List<DeterminismRunOutcome> outcomes;

  /// 轮间漂移的测试名（结果或失败详情变化）。
  final List<String> driftedTests;

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'tool_version': determinismCheckToolVersion,
    'check': 'smart-layout-v3-determinism',
    'targets': defaultDeterminismTargets,
    'runs': runs,
    'deterministic': deterministic,
    'run_exit_codes': [for (final o in outcomes) o.exitCode],
    'per_run_test_counts': [
      for (final o in outcomes)
        {'passed': o.testResults.values.where((r) => r == 'success').length,
         'failed': o.testResults.values.where((r) => r != 'success').length},
    ],
    'drifted_tests': driftedTests,
    'error_summaries': [
      for (final o in outcomes) o.errorSummaries,
    ],
  };
}

abstract final class DeterminismCiCheck {
  /// 执行 N 轮并比对。测试注入用 [runMachineOnce] 的包装。
  static Future<DeterminismReport> run({
    int runs = 2,
    Future<DeterminismRunOutcome> Function()? runOnce,
  }) async {
    final outcomes = <DeterminismRunOutcome>[];
    for (var i = 0; i < runs; i++) {
      outcomes.add(
        await (runOnce ?? _runMachineOnce)(),
      );
    }
    final drifted = <String>[];
    final first = outcomes.first;
    for (final outcome in outcomes.skip(1)) {
      final names = {...first.testResults.keys, ...outcome.testResults.keys};
      for (final name in names) {
        if (first.testResults[name] != outcome.testResults[name]) {
          drifted.add(name);
        }
      }
    }
    // 失败详情漂移：同结果为 failure 时错误摘要必须一致。
    for (var i = 1; i < outcomes.length; i++) {
      if (!listEquals(outcomes[i].errorSummaries, first.errorSummaries)) {
        drifted.add('(failure-detail-drift-run-$i)');
      }
    }
    return DeterminismReport(
      runs: runs,
      deterministic: drifted.isEmpty && outcomes.every((o) => o.allPassed),
      outcomes: outcomes,
      driftedTests: drifted,
    );
  }

  static Future<DeterminismRunOutcome> _runMachineOnce() async {
    final cwd = Directory.current.path;
    final repoRoot = _repoRootFromCwd(cwd);
    final result = await Process.run(
      CiCommandResolver.flutter,
      [
        'test', '--machine',
        ...defaultDeterminismTargets,
      ],
      workingDirectory: cwd,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return parseMachineStream(
      stdout: result.stdout.toString(),
      exitCode: result.exitCode,
      repoRoot: repoRoot,
    );
  }

  /// 解析 `flutter test --machine` 事件流为逐测试结果（可测纯函数）。
  static DeterminismRunOutcome parseMachineStream({
    required String stdout,
    required int exitCode,
    required String repoRoot,
  }) {
    final results = <String, String>{};
    final errors = <String>[];
    var nameById = <String, String>{};
    for (final line in stdout.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('{')) continue;
      final Object? event;
      try {
        event = jsonDecode(trimmed);
      } catch (_) {
        continue;
      }
      if (event is! Map<String, Object?>) continue;
      final type = event['type'];
      if (type == 'testStart') {
        final test = event['test'];
        if (test is Map<String, Object?>) {
          nameById['${test['id']}'] = '${test['name']}';
        }
      } else if (type == 'testDone') {
        final id = '${event['testID']}';
        final name = nameById[id] ?? 'unknown-$id';
        final result = event['result'];
        // 跳过虚拟 loadSuite/done 事件（hidden 或无名字）。
        if (event['hidden'] == true) continue;
        if (name.isEmpty) continue;
        results[name] = result is String ? result : 'unknown';
      } else if (type == 'error') {
        final detail = CiPathPolicy.redactRepoRoot(
          '${event['errorType'] ?? ''}: ${event['error'] ?? ''} '
          '${event['stackTrace'] ?? ''}'
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
          repoRoot,
        );
        if (detail.length > 300) {
          errors.add('${detail.substring(0, 300)}...');
        } else {
          errors.add(detail);
        }
      }
    }
    return DeterminismRunOutcome(
      exitCode: exitCode,
      testResults: results,
      errorSummaries: errors,
    );
  }

  static String _repoRootFromCwd(String cwd) {
    final normalized = cwd.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/FlowMuse-App');
    return idx <= 0 ? normalized : normalized.substring(0, idx);
  }
}

bool listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> main(List<String> args) async {
  final runs = int.tryParse(_argValue(args, '--runs') ?? '2') ?? 2;
  final reportPath = _argValue(args, '--report');
  final report = await DeterminismCiCheck.run(runs: runs);
  final json = const JsonEncoder.withIndent('  ').convert(report.toJson());
  if (reportPath != null) {
    CiPathPolicy.ensureRelative(reportPath);
    final file = File(reportPath);
    file.createSync(recursive: true);
    file.writeAsStringSync(json);
    stdout.writeln('[determinism] report: $reportPath');
  } else {
    stdout.writeln(json);
  }
  stdout.writeln(
    '[determinism] deterministic=${report.deterministic} '
    'drifted=${report.driftedTests.length}',
  );
  exit(report.deterministic ? 0 : 1);
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
