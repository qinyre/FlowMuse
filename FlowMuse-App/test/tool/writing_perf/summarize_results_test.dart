import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/writing_perf/summarize_results.dart';

void main() {
  test('nearest-rank 与 bootstrap 使用确定性算法', () {
    final values = [for (var value = 1; value <= 100; value++) value];
    expect(nearestRank(values, 0.50), 50);
    expect(nearestRank(values, 0.95), 95);
    expect(bootstrapP95(values, iterations: 100, seed: 7), (low: 89, high: 98));
  });

  test('汇总 5 个有效 Profile 轮次并拒绝 Debug 轮次', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flowmuse-writing-summary-',
    );
    addTearDown(() => directory.delete(recursive: true));
    for (var run = 0; run < 5; run++) {
      await _writeRun(directory, 'valid-$run.json', offset: run);
    }
    await _writeRun(
      directory,
      'debug.json',
      offset: 0,
      measurementEligible: false,
    );

    final summary = await summarizeDirectory(directory);

    expect(summary.runs, hasLength(6));
    expect(summary.validRuns, hasLength(5));
    expect(summary.medianRunP95, 97);
    expect(summary.runP95SpreadRatio, closeTo(4 / 97, 0.000001));
    expect(summary.bootstrapP95Interval, isNotNull);
    expect(summary.toMarkdown(), contains('状态：`stable`'));
    expect(summary.toMarkdown(), contains('有效轮次：5/6'));
    expect(summary.toCsv().split('\n'), hasLength(8));
    expect(
      summary.runs.singleWhere((run) => !run.valid).invalidReasons,
      contains('not_profile_or_not_device_eligible'),
    );
  });

  test('未知 schema 和少样本不能形成有效基线', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flowmuse-writing-summary-invalid-',
    );
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/unknown.json').writeAsString(
      jsonEncode({
        'schemaVersion': 99,
        'measurementEligible': true,
        'performance': {
          'schemaVersion': 99,
          'invalidReasons': <String>[],
          'accepted': 1,
          'painted': 1,
          'terminalBeforePreview': 0,
          'coverage': 1.0,
          'activePreviewSamples': [
            {'eventToPaintMicros': 100, 'terminalReason': null},
          ],
        },
      }),
    );

    final run = (await summarizeDirectory(directory)).runs.single;
    expect(run.valid, isFalse);
    expect(run.invalidReasons, contains('unsupported_root_schema'));
    expect(run.invalidReasons, contains('unsupported_performance_schema'));
    expect(run.invalidReasons, contains('fewer_than_100_accepted_samples'));
  });
}

Future<void> _writeRun(
  Directory directory,
  String name, {
  required int offset,
  bool measurementEligible = true,
}) {
  return File('${directory.path}/$name').writeAsString(
    jsonEncode({
      'schemaVersion': supportedReportSchemaVersion,
      'measurementEligible': measurementEligible,
      'performance': {
        'schemaVersion': supportedReportSchemaVersion,
        'invalidReasons': <String>[],
        'accepted': 100,
        'painted': 100,
        'terminalBeforePreview': 0,
        'coverage': 1.0,
        'activePreviewSamples': [
          for (var sample = 1; sample <= 100; sample++)
            {'eventToPaintMicros': sample + offset, 'terminalReason': null},
        ],
      },
    }),
  );
}
