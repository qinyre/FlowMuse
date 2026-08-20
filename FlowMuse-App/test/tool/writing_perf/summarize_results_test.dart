import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/writing_performance_manifest.dart';

import '../../../tool/writing_perf/summarize_results.dart';

void main() {
  test('nearest-rank 与 bootstrap 使用确定性算法', () {
    final values = [for (var value = 1; value <= 100; value++) value];
    expect(nearestRank(values, 0.50), 50);
    expect(nearestRank(values, 0.95), 95);
    expect(bootstrapP95(values, iterations: 100, seed: 7), (low: 89, high: 98));
  });

  test('只把同 SHA、设备、fixture、flag 的 1..5 轮汇成稳定场景', () async {
    final directory = await _tempDirectory('valid');
    for (var run = 1; run <= 5; run++) {
      await _writeRun(
        directory,
        'valid-$run.json',
        runIndex: run,
        offset: run - 1,
      );
    }
    await _writeRun(
      directory,
      'debug.json',
      runIndex: 1,
      offset: 0,
      measurementEligible: false,
    );

    final summary = await summarizeDirectory(directory);

    expect(summary.runs, hasLength(6));
    expect(summary.validRuns, hasLength(5));
    expect(summary.completeScenarios, hasLength(1));
    expect(summary.medianRunP95, 97);
    expect(summary.runP95SpreadRatio, closeTo(4 / 97, 0.000001));
    expect(summary.bootstrapP95Interval, isNotNull);
    expect(summary.status, 'stable');
    expect(summary.acceptanceStatus, 'passed');
    expect(summary.toMarkdown(), contains('状态：`stable`'));
    expect(summary.toMarkdown(), contains('有效轮次：5/6'));
    expect(summary.toCsv().split('\n'), hasLength(8));
    expect(
      summary.runs.singleWhere((run) => !run.valid).invalidReasons,
      contains('not_profile_or_not_device_eligible'),
    );
  });

  test('五个异构设备的单轮数据不能拼成稳定基线', () async {
    final directory = await _tempDirectory('heterogeneous');
    for (var run = 1; run <= 5; run++) {
      await _writeRun(
        directory,
        'device-$run.json',
        runIndex: run,
        offset: 0,
        deviceId: 'device-$run',
      );
    }

    final summary = await summarizeDirectory(directory);

    expect(summary.validRuns, hasLength(5));
    expect(summary.scenarios, hasLength(5));
    expect(summary.completeScenarios, isEmpty);
    expect(summary.status, 'insufficient_valid_scenarios');
  });

  test('重复轮次、dirty 与缩短时长不能形成有效五轮', () async {
    final directory = await _tempDirectory('eligibility');
    for (var run = 1; run <= 5; run++) {
      await _writeRun(
        directory,
        'duplicate-$run.json',
        runIndex: 1,
        offset: 0,
        gitDirty: run == 5,
        measureSeconds: run == 4 ? 1 : 60,
      );
    }

    final summary = await summarizeDirectory(directory);

    expect(summary.completeScenarios, isEmpty);
    expect(summary.status, 'insufficient_valid_scenarios');
    expect(
      summary.runs.expand((run) => run.invalidReasons),
      containsAll(['dirty_git_worktree', 'nonstandard_measurement_duration']),
    );
  });

  test('build/raster、deadline miss 与最长连续掉帧进入门禁', () async {
    final directory = await _tempDirectory('frames');
    for (var run = 1; run <= 5; run++) {
      await _writeRun(
        directory,
        'slow-$run.json',
        runIndex: run,
        offset: run - 1,
        frameMicros: 100000,
      );
    }

    final summary = await summarizeDirectory(directory);
    final scenario = summary.completeScenarios.single;

    expect(scenario.frameGatePassed, isFalse);
    expect(summary.acceptanceStatus, 'failed');
    expect(scenario.medianBuildP95, 100000);
    expect(scenario.medianRasterP95, 100000);
    expect(scenario.medianDeadlineMissRatio, 1);
    expect(
      scenario.validRuns.first.frames!.longestConsecutiveDeadlineMiss,
      3000,
    );
    expect(summary.toMarkdown(), contains('100000/100000'));
  });

  test('false/true 五轮生成 P1 成对目标、改善、帧与语义 hash 门禁', () async {
    final directory = await _tempDirectory('paired');
    for (var run = 1; run <= 5; run++) {
      await _writeRun(
        directory,
        'legacy-$run.json',
        runIndex: run,
        offset: 40000 + run - 1,
      );
      await _writeRun(
        directory,
        'layered-$run.json',
        runIndex: run,
        offset: run - 1,
        layeredWetInk: true,
      );
    }

    final summary = await summarizeDirectory(
      directory,
      phase: WritingSummaryPhase.p1,
    );
    final markdown = summary.toMarkdown();

    expect(summary.completeScenarios, hasLength(2));
    expect(summary.acceptanceStatus, 'passed');
    expect(markdown, contains('## P1 成对门禁'));
    expect(markdown, contains('true | true'));
  });

  test('P1 缺任一成对场景时必须失败', () async {
    final directory = await _tempDirectory('missing-p1-pair');
    for (var run = 1; run <= 5; run++) {
      await _writeRun(directory, 'legacy-$run.json', runIndex: run, offset: 0);
    }

    final summary = await summarizeDirectory(
      directory,
      phase: WritingSummaryPhase.p1,
    );

    expect(summary.status, 'stable');
    expect(summary.acceptanceStatus, 'failed');
  });

  test('未知 schema 和缺少正式元数据不能形成有效基线', () async {
    final directory = await _tempDirectory('invalid');
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
    expect(run.invalidReasons, contains('missing_frame_timings'));
  });

  test('协作 CPU 与 live ink 专用报告不混入本地书写基线', () async {
    final directory = await _tempDirectory('collaboration-reports');
    for (final mode in ['collaboration_cpu_non_ui', 'collaboration_live_ink']) {
      await File(
        '${directory.path}/$mode.json',
      ).writeAsString(jsonEncode({'schemaVersion': 1, 'mode': mode}));
    }

    final summary = await summarizeDirectory(directory);

    expect(summary.runs, isEmpty);
  });

  test('桌面平台或未由 host 匹配的设备不能冒充真机', () async {
    final directory = await _tempDirectory('device-evidence');
    await _writeRun(
      directory,
      'mismatch.json',
      runIndex: 1,
      offset: 0,
      detectedDeviceId: 'another-device',
    );

    final run = (await summarizeDirectory(directory)).runs.single;

    expect(run.invalidReasons, contains('device_id_not_host_verified'));
  });

  test('帧数覆盖不足时即使单帧很快也不能验收', () async {
    final directory = await _tempDirectory('frame-coverage');
    await _writeRun(
      directory,
      'short-frames.json',
      runIndex: 1,
      offset: 0,
      frameCount: 1,
    );

    final run = (await summarizeDirectory(directory)).runs.single;

    expect(run.invalidReasons, contains('insufficient_frame_coverage'));
    expect(run.invalidReasons, contains('painted_sample_frame_not_collected'));
  });

  test('自洽的功能 fixture、任意目标和多设备证据仍必须拒绝', () async {
    final directory = await _tempDirectory('manifest-bypass');
    await _writeRun(
      directory,
      'bypass.json',
      runIndex: 1,
      offset: 0,
      writingFixture: 'pointer_cancel',
      measureSeconds: 1,
      eventTargetMicros: 1000000,
      supportedDeviceCount: 2,
    );

    final run = (await summarizeDirectory(directory)).runs.single;

    expect(
      run.invalidReasons,
      containsAll([
        'unsupported_writing_fixture',
        'nonstandard_measurement_duration',
        'unfrozen_event_target',
        'ambiguous_test_device_set',
      ]),
    );
  });

  test('自报计数或 final stroke 数量不一致时必须拒绝', () async {
    final directory = await _tempDirectory('recomputed-counts');
    await _writeRun(
      directory,
      'bad-counts.json',
      runIndex: 1,
      offset: 0,
      reportedAccepted: 101,
      elementsAfterRun: 109,
    );

    final run = (await summarizeDirectory(directory)).runs.single;

    expect(run.invalidReasons, contains('performance_counts_not_reproducible'));
    expect(run.invalidReasons, contains('incomplete_final_scene'));
  });
}

Future<Directory> _tempDirectory(String name) async {
  final directory = await Directory.systemTemp.createTemp(
    'flowmuse-writing-summary-$name-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

Future<void> _writeRun(
  Directory directory,
  String name, {
  required int runIndex,
  required int offset,
  bool measurementEligible = true,
  bool layeredWetInk = false,
  bool gitDirty = false,
  int measureSeconds = 60,
  int frameMicros = 5000,
  int frameCount = 3000,
  String deviceId = 'physical-device-a',
  String? detectedDeviceId,
  String writingFixture = 'quick_zigzag',
  int eventTargetMicros = 33000,
  int supportedDeviceCount = 1,
  int reportedAccepted = 100,
  int elementsAfterRun = 110,
}) {
  return File('${directory.path}/$name').writeAsString(
    jsonEncode({
      'schemaVersion': supportedReportSchemaVersion,
      'measurementEligible': measurementEligible,
      'buildMode': 'profile',
      'platform': 'android',
      'physicalDevice': true,
      'deviceId': deviceId,
      'deviceClass': 'android-mid',
      'refreshHz': 60,
      'runIndex': runIndex,
      'sceneElementCount': 100,
      'sceneFixtureHash': writingSceneFixtureHashes[100],
      'writingFixture': writingFixture,
      'writingFixtureSchemaVersion': 1,
      'writingFixtureHash':
          writingPerformanceFixtures[writingFixture]?.hash ??
          _repeated('f', 64),
      'measureSeconds': measureSeconds,
      'eventToPaintTargetMicros': eventTargetMicros,
      'flags': {'layeredWetInk': layeredWetInk},
      'sceneHashAfterRun': _repeated('d', 64),
      'semanticSceneHashAfterRun': _repeated('e', 64),
      'codecRoundTripSemanticSceneHashAfterRun': _repeated('e', 64),
      'elementsAfterRun': elementsAfterRun,
      'expectedCompletedStrokes': 10,
      'validCompletedFreedrawCount': 10,
      'hostEvidence': {
        'gitSha': _repeated('a', 40),
        'gitDirty': gitDirty,
        'detectedDeviceId': detectedDeviceId ?? deviceId,
        'detectedTargetPlatform': 'android-arm64',
        'detectedEmulator': false,
        'supportedDeviceCount': supportedDeviceCount,
      },
      'performance': {
        'schemaVersion': supportedReportSchemaVersion,
        'invalidReasons': <String>[],
        'accepted': reportedAccepted,
        'painted': 100,
        'terminalBeforePreview': 0,
        'coverage': 1.0,
        'activePreviewSamples': [
          for (var sample = 1; sample <= 100; sample++)
            {
              'eventToPaintMicros': sample + offset,
              'frameNumber': sample,
              'terminalReason': null,
            },
        ],
        'frames': [
          for (var frame = 1; frame <= frameCount; frame++)
            {
              'frameNumber': frame,
              'buildMicros': frameMicros,
              'rasterMicros': frameMicros,
              'totalSpanMicros': frameMicros,
            },
        ],
      },
    }),
  );
}

String _repeated(String value, int count) => List.filled(count, value).join();
