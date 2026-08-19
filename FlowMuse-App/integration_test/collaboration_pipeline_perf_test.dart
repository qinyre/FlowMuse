import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/collaboration_scenarios.dart';

const _perfTestEnabled = bool.fromEnvironment('FLOWMUSE_PERF_TEST');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('2/5 人真实协作 CPU 流水线基线', (_) async {
    expect(
      _perfTestEnabled,
      isTrue,
      reason: '性能入口仅允许通过 FLOWMUSE_PERF_TEST=true 启用',
    );

    final results = <Map<String, Object?>>[];
    for (final scenario in collaborationPerformanceScenarios) {
      final result = await runCollaborationPerformanceScenario(scenario);
      expect(result.errors, 0);
      expect(result.converged, isTrue);
      results.add(result.toJson());
    }

    binding.reportData = {
      'schemaVersion': 1,
      'measurementEligible': kProfileMode,
      'mode': 'collaboration_cpu_non_ui',
      'results': results,
    };
  });
}
