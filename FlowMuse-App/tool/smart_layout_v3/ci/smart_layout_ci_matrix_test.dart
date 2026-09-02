import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'smart_layout_ci_matrix.dart';

/// V3-602A：CI 矩阵核心逻辑单测（fake executor 注入，零真实子进程）。
void main() {
  CiCommandOutcome ok([String stdout = 'ok']) =>
      CiCommandOutcome(exitCode: 0, stdout: stdout, stderr: '');

  CiStage stage(String id, {List<String> inputs = const []}) => CiStage(
    id: id,
    command: const ['flutter', 'test', 'x'],
    workingDir: 'FlowMuse-App',
    inputs: inputs,
    failureArtifacts: inputs,
  );

  test('全绿矩阵：allPassed/aggregateExitCode=0/报告 canonical 双跑一致', () async {
    Future<CiMatrixReport> run() => SmartLayoutCiMatrix(
      stages: [stage('a'), stage('b')],
      repoRoot: '/repo',
      executor: (command, cwd) async => ok(),
      now: _fixedClock,
    ).run(workDir: '.dart_tool/ci-test');

    final first = await run();
    final second = await run();
    expect(first.allPassed, isTrue);
    expect(first.aggregateExitCode, 0);
    expect(
      jsonEncode(first.toCanonicalJson()),
      jsonEncode(second.toCanonicalJson()),
      reason: 'canonical 投影须剥离时间戳/时长（报告确定性）',
    );
    // 时间戳在完整报告中存在（归档口径），但被 canonical 剥离。
    expect(first.generatedAtUtc, isNotEmpty);
    expect(
      first.toCanonicalJson().containsKey('generated_at_utc'),
      isFalse,
    );
  });

  test('失败阻断：聚合退出码=失败 stage 退出码，诊断与失败产物归档', () async {
    var testCalls = 0;
    final report = await SmartLayoutCiMatrix(
      stages: [stage('a'), stage('b')],
      repoRoot: Directory.current.path.replaceAll('\\', '/'),
      executor: (command, cwd) async {
        // 版本探针（flutter --version）不计入 stage 序号。
        if (command.contains('--version')) return ok('Flutter 3.x');
        testCalls++;
        return testCalls == 2
            ? CiCommandOutcome(
                exitCode: 7,
                stdout: 'boom',
                stderr: 'failure detail',
              )
            : ok();
      },
      now: _fixedClock,
    ).run(workDir: '.dart_tool/ci-test-fail');

    expect(report.allPassed, isFalse);
    expect(report.aggregateExitCode, 7);
    final failed = report.results[1];
    expect(failed.stdoutTail, 'boom');
    expect(failed.stderrTail, 'failure detail');
  });

  test('诊断脱敏：报告零本机绝对路径（仓库根前缀剥除）', () async {
    final repoRoot = '/machine/somewhere/repo';
    final report = await SmartLayoutCiMatrix(
      stages: [stage('a')],
      repoRoot: repoRoot,
      executor: (command, cwd) async => CiCommandOutcome(
        exitCode: 1,
        stdout: 'file $repoRoot/FlowMuse-App/lib/x.dart:3:1 broken',
        stderr: '$repoRoot\\FlowMuse-App\\other',
      ),
      now: _fixedClock,
    ).run(workDir: '.dart_tool/ci-test-redact');

    final json = jsonEncode(report.toJson());
    expect(json.contains(repoRoot), isFalse);
    expect(json.contains('/machine/somewhere'), isFalse);
    expect(json.contains('lib/x.dart:3:1'), isTrue, reason: '诊断保留');
  });

  test('路径策略：绝对路径与 .. 拒绝', () {
    expect(CiPathPolicy.ensureRelative('a/b'), 'a/b');
    expect(() => CiPathPolicy.ensureRelative('/abs'), throwsFormatException);
    expect(
      () => CiPathPolicy.ensureRelative(r'D:\abs'),
      throwsFormatException,
    );
    expect(
      () => CiPathPolicy.ensureRelative('a/../../b'),
      throwsFormatException,
    );
  });

  test('缓存：指纹命中复用零执行，输入变化失效重跑', () async {
    final temp = await Directory.systemTemp.createTemp('ci-matrix-test');
    try {
      final repoRoot = temp.path.replaceAll('\\', '/');
      Directory('$repoRoot/inputs').createSync();
      File('$repoRoot/inputs/a.txt').writeAsStringSync('v1');
      await Directory('$repoRoot/.dart_tool/w').create(recursive: true);

      var executions = 0;
      Future<CiMatrixReport> run(bool cache) => SmartLayoutCiMatrix(
        stages: [stage('s', inputs: ['inputs'])],
        repoRoot: repoRoot,
        executor: (command, cwd) async {
          // 版本探针不计入 stage 执行数。
          if (command.contains('--version')) return ok('Flutter 3.x');
          executions++;
          return ok('run-$executions');
        },
        now: _fixedClock,
      ).run(workDir: '.dart_tool/w', useCache: cache);

      final first = await run(false);
      expect(executions, 1);
      expect(first.results.single.cached, isFalse);

      // 缓存命中：不执行，结果来自缓存且内容一致。
      final cached = await run(true);
      expect(executions, 1, reason: '指纹未变不得重跑');
      expect(cached.results.single.cached, isTrue);
      expect(cached.results.single.stdoutTail, 'run-1');

      // 输入变化 → 指纹失效 → 重跑。
      File('$repoRoot/inputs/a.txt').writeAsStringSync('v2');
      final rerun = await run(true);
      expect(executions, 2);
      expect(rerun.results.single.cached, isFalse);
      expect(rerun.results.single.stdoutTail, 'run-2');
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('replay：canonical 提取与偏离检测', () async {
    final report = await SmartLayoutCiMatrix(
      stages: [stage('a'), stage('b')],
      repoRoot: '/repo',
      executor: (command, cwd) async => ok(),
      now: _fixedClock,
    ).run(workDir: '.dart_tool/ci-test-replay');

    final baseline = CiReplay.loadCanonical(
      jsonEncode(report.toJson()),
    );
    expect(baseline, isNotNull);

    // 同一报告再跑一次 → canonical 一致。
    final again = await SmartLayoutCiMatrix(
      stages: [stage('a'), stage('b')],
      repoRoot: '/repo',
      executor: (command, cwd) async => ok(),
      now: _fixedClock,
    ).run(workDir: '.dart_tool/ci-test-replay2');
    expect(
      jsonEncode(CiReplay.canonicalOf(again)),
      jsonEncode(baseline),
    );

    // 偏离：一个 stage 失败 → replay 对照必须能发现。
    final drifted = await SmartLayoutCiMatrix(
      stages: [stage('a'), stage('b')],
      repoRoot: '/repo',
      executor: (command, cwd) async => CiCommandOutcome(
        exitCode: 5,
        stdout: '',
        stderr: 'changed',
      ),
      now: _fixedClock,
    ).run(workDir: '.dart_tool/ci-test-replay3');
    expect(
      jsonEncode(CiReplay.canonicalOf(drifted)) == jsonEncode(baseline),
      isFalse,
    );

    // 非矩阵报告拒收。
    expect(CiReplay.loadCanonical('{"foo": 1}'), isNull);
  });

  test('默认 stage 集：全部仓库相对路径，命令口径固定', () {
    final stages = smartLayoutV3DefaultStages();
    expect(stages.map((s) => s.id), [
      'analyze-smart-layout',
      'test-smart-layout-core',
      'test-smart-layout-transaction',
      'determinism-double-run',
      'ci-tool-self-test',
    ]);
    for (final s in stages) {
      expect(() => CiPathPolicy.ensureRelative(s.workingDir), returnsNormally,
          reason: '${s.id} workingDir');
      for (final input in s.inputs) {
        expect(() => CiPathPolicy.ensureRelative(input), returnsNormally,
            reason: '${s.id} input $input');
      }
    }
  });
}

DateTime _fixedClock() => DateTime.fromMillisecondsSinceEpoch(
      1725000000000,
      isUtc: true,
    );
