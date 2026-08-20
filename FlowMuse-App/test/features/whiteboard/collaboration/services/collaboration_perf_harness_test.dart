import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_performance_probe.dart';

import '../../../../../integration_test/fixtures/collaboration_scenarios.dart';

void main() {
  test('probe 使用单调时钟记录旁路样本', () {
    var now = 10;
    final probe = CollaborationPerformanceProbe(nowMicros: () => now);
    final started = probe.nowMicros();
    now = 35;
    probe.recordSince(
      CollaborationPerformanceStage.encrypt,
      started,
      itemCount: 2,
      byteCount: 128,
    );

    final sample = probe.samples.single;
    expect(sample.stage, CollaborationPerformanceStage.encrypt);
    expect(sample.durationMicros, 25);
    expect(sample.itemCount, 2);
    expect(sample.byteCount, 128);
  });

  test('正式场景冻结为 2/5 人、100 次预热、1000 次测量', () {
    expect(
      collaborationPerformanceScenarios.map((scenario) => scenario.memberCount),
      [2, 5],
    );
    for (final scenario in collaborationPerformanceScenarios) {
      expect(scenario.warmupIterations, 100);
      expect(scenario.measuredIterations, 1000);
    }
  });

  for (final memberCount in [2, 5]) {
    test('$memberCount 人真实 repository 流水线收敛并覆盖全部阶段', () async {
      final result = await runCollaborationPerformanceScenario(
        CollaborationPerformanceScenario(
          memberCount: memberCount,
          warmupIterations: 2,
          measuredIterations: 5,
        ),
      );

      expect(result.errors, 0);
      expect(result.converged, isTrue);
      expect(result.finalSceneHashes, hasLength(memberCount));
      expect(
        result.stages[CollaborationPerformanceStage.jsonEncode]!.sampleCount,
        5,
      );
      expect(
        result.stages[CollaborationPerformanceStage.encrypt]!.sampleCount,
        5,
      );
      expect(
        result.stages[CollaborationPerformanceStage.transportSend]!.sampleCount,
        5,
      );
      for (final stage in [
        CollaborationPerformanceStage.decrypt,
        CollaborationPerformanceStage.jsonDecode,
        CollaborationPerformanceStage.reconcile,
      ]) {
        expect(result.stages[stage]!.sampleCount, 5 * (memberCount - 1));
      }
      expect(result.allocationBytesApprox, greaterThan(0));
      expect(result.toJson()['mode'], 'collaboration_cpu_non_ui');
    });
  }
}
