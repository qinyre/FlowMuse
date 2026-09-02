import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'determinism_ci_check.dart';

/// V3-602A：确定性双跑门禁单测（机器流解析 + 漂移检测，零子进程）。
void main() {
  String event(Map<String, Object?> e) => jsonEncode(e);

  test('机器流解析：testStart/testDone 逐测试结果映射', () {
    final stream = [
      event({'type': 'testStart', 'test': {'id': 1, 'name': 'loadSuite'}}),
      event({'type': 'testStart', 'test': {'id': 2, 'name': 'group 用例A'}}),
      event({'type': 'testDone', 'testID': 2, 'result': 'success', 'hidden': false}),
      event({'type': 'testStart', 'test': {'id': 3, 'name': 'group 用例B'}}),
      event({'type': 'testDone', 'testID': 3, 'result': 'failure', 'hidden': false}),
      event({'type': 'testDone', 'testID': 1, 'result': 'success', 'hidden': true}),
    ].join('\n');
    final outcome = DeterminismCiCheck.parseMachineStream(
      stdout: stream,
      exitCode: 1,
      repoRoot: '/repo',
    );
    expect(outcome.testResults['group 用例A'], 'success');
    expect(outcome.testResults['group 用例B'], 'failure');
    expect(outcome.testResults['loadSuite'], isNull,
        reason: 'hidden 事件不计入');
    expect(outcome.allPassed, isFalse);
  });

  test('error 事件：脱敏 + 截断归并', () {
    final stream = [
      event({
        'type': 'error',
        'errorType': 'TestFailure',
        'error': 'expected true /repo/FlowMuse-App/test/x.dart:9',
        'stackTrace': '',
      }),
    ].join('\n');
    final outcome = DeterminismCiCheck.parseMachineStream(
      stdout: stream,
      exitCode: 1,
      repoRoot: '/repo',
    );
    expect(outcome.errorSummaries.single, contains('TestFailure'));
    expect(outcome.errorSummaries.single.contains('/repo'), isFalse);
    expect(outcome.errorSummaries.single.contains('x.dart:9'), isTrue);
  });

  test('双跑一致 → deterministic=true；结果漂移 → 漂移清单非空', () async {
    DeterminismRunOutcome outcome(Map<String, String> results) =>
        DeterminismRunOutcome(
          exitCode: results.values.every((r) => r == 'success') ? 0 : 1,
          testResults: results,
          errorSummaries: const [],
        );

    final stable = await DeterminismCiCheck.run(
      runs: 2,
      runOnce: () async => outcome({'a': 'success', 'b': 'success'}),
    );
    expect(stable.deterministic, isTrue);
    expect(stable.driftedTests, isEmpty);

    final drifted = await DeterminismCiCheck.run(
      runs: 2,
      runOnce: () async {
        driftedCallCount++;
        return driftedCallCount == 1
            ? outcome({'a': 'success', 'b': 'success'})
            : outcome({'a': 'success', 'b': 'failure'});
      },
    );
    expect(drifted.deterministic, isFalse);
    expect(drifted.driftedTests, contains('b'));
  });

  test('报告 JSON：口径字段齐备且 targets 仓库相对', () {
    final report = DeterminismReport(
      runs: 2,
      deterministic: true,
      outcomes: const [
        DeterminismRunOutcome(
          exitCode: 0,
          testResults: {'a': 'success'},
          errorSummaries: [],
        ),
        DeterminismRunOutcome(
          exitCode: 0,
          testResults: {'a': 'success'},
          errorSummaries: [],
        ),
      ],
    );
    final json = report.toJson();
    expect(json['deterministic'], isTrue);
    expect(json['targets'], defaultDeterminismTargets);
    for (final target in defaultDeterminismTargets) {
      expect(target.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(target),
          isFalse,
          reason: 'target 须仓库相对: $target');
    }
  });
}

var driftedCallCount = 0;
