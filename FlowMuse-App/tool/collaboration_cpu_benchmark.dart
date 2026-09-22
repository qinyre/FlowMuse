// Run with: flutter test tool/collaboration_cpu_benchmark.dart --reporter expanded
// Synthetic data only. This measures CPU pipeline work, not device frame time.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/fixtures/collaboration_scenarios.dart';

void main() {
  test('协作长笔 CPU 基准：2/5 人与历史笔迹', () async {
    final previousDebugPrint = debugPrint;
    debugPrint = (_, {wrapWidth}) {};
    try {
      for (var round = 0; round < 3; round++) {
        for (final members in [2, 5]) {
          for (final background in [0, 1000]) {
            for (final points in [32, 2048]) {
              final result = await runCollaborationPerformanceScenario(
                CollaborationPerformanceScenario(
                  memberCount: members,
                  warmupIterations: 5,
                  measuredIterations: 25,
                  backgroundElementCount: background,
                  strokePointCount: points,
                ),
              );
              expect(result.errors, 0);
              expect(result.converged, isTrue);
              final report = result.toJson()..remove('finalSceneHashes');
              previousDebugPrint(
                jsonEncode({
                  'round': round,
                  'backgroundElements': background,
                  'backgroundPointsPerElement': 128,
                  'strokePoints': points,
                  ...report,
                }),
              );
            }
          }
        }
      }
    } finally {
      debugPrint = previousDebugPrint;
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
