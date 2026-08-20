import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/writing_performance_manifest.dart';

const int supportedReportSchemaVersion = 1;

enum WritingSummaryPhase { p0, p1 }

class FrameRunSummary {
  const FrameRunSummary({
    required this.count,
    required this.frameBudgetMicros,
    required this.buildP50Micros,
    required this.buildP95Micros,
    required this.buildP99Micros,
    required this.buildWorstMicros,
    required this.rasterP50Micros,
    required this.rasterP95Micros,
    required this.rasterP99Micros,
    required this.rasterWorstMicros,
    required this.deadlineMissCount,
    required this.deadlineMissRatio,
    required this.longestConsecutiveDeadlineMiss,
    required this.frameNumbers,
  });

  final int count;
  final int frameBudgetMicros;
  final int buildP50Micros;
  final int buildP95Micros;
  final int buildP99Micros;
  final int buildWorstMicros;
  final int rasterP50Micros;
  final int rasterP95Micros;
  final int rasterP99Micros;
  final int rasterWorstMicros;
  final int deadlineMissCount;
  final double deadlineMissRatio;
  final int longestConsecutiveDeadlineMiss;
  final Set<int> frameNumbers;

  bool get meetsFrameGate =>
      buildP95Micros <= frameBudgetMicros &&
      rasterP95Micros <= frameBudgetMicros &&
      deadlineMissRatio < 0.01;
}

class WritingRunSummary {
  const WritingRunSummary({
    required this.path,
    required this.valid,
    required this.invalidReasons,
    required this.scenarioKey,
    required this.comparisonKey,
    required this.runIndex,
    required this.layeredWetInk,
    required this.eventToPaintTargetMicros,
    required this.semanticSceneHashAfterRun,
    required this.finalSceneHashAfterRun,
    required this.accepted,
    required this.painted,
    required this.terminalBeforePreview,
    required this.coverage,
    required this.p50Micros,
    required this.p95Micros,
    required this.p99Micros,
    required this.worstMicros,
    required this.eventToPaintMicros,
    required this.frames,
  });

  final String path;
  final bool valid;
  final List<String> invalidReasons;
  final String? scenarioKey;
  final String? comparisonKey;
  final int? runIndex;
  final bool? layeredWetInk;
  final int? eventToPaintTargetMicros;
  final String? semanticSceneHashAfterRun;
  final String? finalSceneHashAfterRun;
  final int accepted;
  final int painted;
  final int terminalBeforePreview;
  final double coverage;
  final int? p50Micros;
  final int? p95Micros;
  final int? p99Micros;
  final int? worstMicros;
  final List<int> eventToPaintMicros;
  final FrameRunSummary? frames;

  double get terminalRatio =>
      accepted == 0 ? 0 : terminalBeforePreview / accepted;
}

class WritingScenarioSummary {
  WritingScenarioSummary(this.key, List<WritingRunSummary> runs)
    : runs = List.unmodifiable(runs);

  final String key;
  final List<WritingRunSummary> runs;

  List<WritingRunSummary> get validRuns =>
      runs.where((run) => run.valid).toList(growable: false);

  bool get complete {
    final indices = validRuns.map((run) => run.runIndex).toSet();
    return validRuns.length == 5 &&
        indices.length == 5 &&
        indices.containsAll(const [1, 2, 3, 4, 5]);
  }

  int? get medianRunP95 => _medianInt([
    for (final run in validRuns)
      if (run.p95Micros != null) run.p95Micros!,
  ]);

  int? get medianBuildP95 => _medianInt([
    for (final run in validRuns)
      if (run.frames != null) run.frames!.buildP95Micros,
  ]);

  int? get medianRasterP95 => _medianInt([
    for (final run in validRuns)
      if (run.frames != null) run.frames!.rasterP95Micros,
  ]);

  double? get medianDeadlineMissRatio => _medianDouble([
    for (final run in validRuns)
      if (run.frames != null) run.frames!.deadlineMissRatio,
  ]);

  double? get medianTerminalRatio =>
      _medianDouble([for (final run in validRuns) run.terminalRatio]);

  double? get aggregateTerminalRatio {
    final totalAccepted = validRuns.fold<int>(
      0,
      (total, run) => total + run.accepted,
    );
    if (totalAccepted == 0) return null;
    final totalTerminal = validRuns.fold<int>(
      0,
      (total, run) => total + run.terminalBeforePreview,
    );
    return totalTerminal / totalAccepted;
  }

  double? get runP95SpreadRatio {
    final values = [for (final run in validRuns) run.p95Micros!]..sort();
    final median = medianRunP95;
    if (values.length < 2 || median == null || median == 0) return null;
    return (values.last - values.first) / median;
  }

  ({int low, int high})? get bootstrapP95Interval {
    final values = validRuns.expand((run) => run.eventToPaintMicros).toList();
    return values.isEmpty ? null : bootstrapP95(values);
  }

  bool get stable =>
      complete && runP95SpreadRatio != null && runP95SpreadRatio! <= 0.10;

  bool get frameGatePassed =>
      complete && validRuns.every((run) => run.frames!.meetsFrameGate);

  Set<String> get semanticSceneHashes => {
    for (final run in validRuns)
      if (run.semanticSceneHashAfterRun != null) run.semanticSceneHashAfterRun!,
  };

  Set<String> get finalSceneHashes => {
    for (final run in validRuns)
      if (run.finalSceneHashAfterRun != null) run.finalSceneHashAfterRun!,
  };

  bool get absoluteTargetPassed {
    final p95 = medianRunP95;
    final target = validRuns.isEmpty
        ? null
        : validRuns.first.eventToPaintTargetMicros;
    return p95 != null && target != null && p95 <= target;
  }

  bool get deterministicScenePassed => semanticSceneHashes.length == 1;

  bool get requiredGatesPassed =>
      stable &&
      frameGatePassed &&
      absoluteTargetPassed &&
      deterministicScenePassed;
}

class WritingResultsSummary {
  WritingResultsSummary({
    required List<WritingRunSummary> runs,
    this.phase = WritingSummaryPhase.p0,
  }) : runs = List.unmodifiable(runs);

  final List<WritingRunSummary> runs;
  final WritingSummaryPhase phase;

  List<WritingRunSummary> get validRuns =>
      runs.where((run) => run.valid).toList(growable: false);

  double get validRate => runs.isEmpty ? 0 : validRuns.length / runs.length;

  List<WritingScenarioSummary> get scenarios {
    final grouped = <String, List<WritingRunSummary>>{};
    for (final run in runs) {
      final key = run.scenarioKey;
      if (key != null) grouped.putIfAbsent(key, () => []).add(run);
    }
    return [
      for (final entry in grouped.entries)
        WritingScenarioSummary(entry.key, entry.value),
    ];
  }

  List<WritingScenarioSummary> get completeScenarios =>
      scenarios.where((scenario) => scenario.complete).toList(growable: false);

  String get status {
    final candidates = scenarios
        .where((scenario) => scenario.validRuns.isNotEmpty)
        .toList();
    if (candidates.isEmpty ||
        candidates.any((scenario) => !scenario.complete)) {
      return 'insufficient_valid_scenarios';
    }
    return candidates.every((scenario) => scenario.stable)
        ? 'stable'
        : 'unstable';
  }

  String get acceptanceStatus =>
      status == 'stable' &&
          (phase == WritingSummaryPhase.p0
              ? scenarios.every((scenario) => scenario.requiredGatesPassed)
              : _p1AcceptancePassed)
      ? 'passed'
      : 'failed';

  bool get _p1AcceptancePassed =>
      completeScenarios.any(
        (scenario) => scenario.validRuns.first.layeredWetInk == true,
      ) &&
      completeScenarios
          .where((scenario) => scenario.validRuns.first.layeredWetInk == true)
          .every((scenario) => scenario.requiredGatesPassed) &&
      _p1ComparisonsPassed;

  int? get medianRunP95 => completeScenarios.length == 1
      ? completeScenarios.single.medianRunP95
      : null;

  double? get runP95SpreadRatio => completeScenarios.length == 1
      ? completeScenarios.single.runP95SpreadRatio
      : null;

  ({int low, int high})? get bootstrapP95Interval =>
      completeScenarios.length == 1
      ? completeScenarios.single.bootstrapP95Interval
      : null;

  bool get _p1ComparisonsPassed {
    final grouped = <String, List<WritingScenarioSummary>>{};
    for (final scenario in completeScenarios) {
      final key = scenario.validRuns.first.comparisonKey;
      if (key != null) grouped.putIfAbsent(key, () => []).add(scenario);
    }
    if (grouped.isEmpty) return false;
    for (final scenarios in grouped.values) {
      WritingScenarioSummary? legacy;
      WritingScenarioSummary? layered;
      for (final scenario in scenarios) {
        if (scenario.validRuns.first.layeredWetInk == true) {
          layered = scenario;
        } else {
          legacy = scenario;
        }
      }
      if (legacy == null || layered == null || scenarios.length != 2) {
        return false;
      }
      final legacyP95 = legacy.medianRunP95!;
      final layeredP95 = layered.medianRunP95!;
      final improvement = legacyP95 == 0
          ? 0.0
          : (legacyP95 - layeredP95) / legacyP95;
      final hashesMatch =
          legacy.semanticSceneHashes.length == 1 &&
          layered.semanticSceneHashes.length == 1 &&
          legacy.semanticSceneHashes.single ==
              layered.semanticSceneHashes.single;
      if (improvement < 0.30 ||
          !layered.frameGatePassed ||
          layered.medianDeadlineMissRatio! > legacy.medianDeadlineMissRatio! ||
          layered.aggregateTerminalRatio! >
              legacy.aggregateTerminalRatio! + 0.005 ||
          !hashesMatch) {
        return false;
      }
    }
    return true;
  }

  String toCsv() {
    final buffer = StringBuffer(
      'path,scenarioKey,runIndex,layeredWetInk,valid,invalidReasons,'
      'accepted,painted,terminalBeforePreview,coverage,'
      'eventP50Micros,eventP95Micros,eventP99Micros,eventWorstMicros,'
      'buildP95Micros,rasterP95Micros,deadlineMissRatio,'
      'longestConsecutiveDeadlineMiss\n',
    );
    for (final run in runs) {
      buffer.writeln(
        [
          _csv(run.path),
          _csv(run.scenarioKey ?? ''),
          run.runIndex ?? '',
          run.layeredWetInk ?? '',
          run.valid,
          _csv(run.invalidReasons.join('|')),
          run.accepted,
          run.painted,
          run.terminalBeforePreview,
          run.coverage.toStringAsFixed(6),
          run.p50Micros ?? '',
          run.p95Micros ?? '',
          run.p99Micros ?? '',
          run.worstMicros ?? '',
          run.frames?.buildP95Micros ?? '',
          run.frames?.rasterP95Micros ?? '',
          run.frames?.deadlineMissRatio.toStringAsFixed(6) ?? '',
          run.frames?.longestConsecutiveDeadlineMiss ?? '',
        ].join(','),
      );
    }
    return buffer.toString();
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# 书写性能结果汇总')
      ..writeln()
      ..writeln('- 状态：`$status`')
      ..writeln('- 验收：`$acceptanceStatus`')
      ..writeln('- 有效轮次：${validRuns.length}/${runs.length}')
      ..writeln('- 有效率：${(validRate * 100).toStringAsFixed(2)}%')
      ..writeln()
      ..writeln(
        '| scenario | valid runs | stability | event P95 median/CI (µs) | build/raster P95 (µs) | miss | frame gate |',
      )
      ..writeln('| --- | ---: | --- | --- | --- | ---: | --- |');
    for (final scenario in scenarios) {
      final interval = scenario.bootstrapP95Interval;
      final spread = scenario.runP95SpreadRatio;
      buffer.writeln(
        '| `${_shortKey(scenario.key)}` | ${scenario.validRuns.length}/5 | '
        '${spread == null ? '-' : '${(spread * 100).toStringAsFixed(2)}%'} | '
        '${scenario.medianRunP95 ?? '-'} / '
        '${interval == null ? '-' : '${interval.low}～${interval.high}'} | '
        '${scenario.medianBuildP95 ?? '-'}/${scenario.medianRasterP95 ?? '-'} | '
        '${scenario.medianDeadlineMissRatio == null ? '-' : '${(scenario.medianDeadlineMissRatio! * 100).toStringAsFixed(2)}%'} | '
        '${scenario.complete ? scenario.frameGatePassed : 'not_evaluated'} |',
      );
    }
    _writeP1Comparisons(buffer);
    buffer
      ..writeln()
      ..writeln(
        '| raw path | valid | invalid reasons | accepted | coverage | event P50/P95/P99/worst (µs) | frame build/raster P95, miss, streak |',
      )
      ..writeln('| --- | --- | --- | ---: | ---: | --- | --- |');
    for (final run in runs) {
      buffer.writeln(
        '| `${run.path}` | ${run.valid} | ${run.invalidReasons.join(', ')} | '
        '${run.accepted} | ${(run.coverage * 100).toStringAsFixed(2)}% | '
        '${run.p50Micros ?? '-'}/${run.p95Micros ?? '-'}/'
        '${run.p99Micros ?? '-'}/${run.worstMicros ?? '-'} | '
        '${run.frames?.buildP95Micros ?? '-'}/${run.frames?.rasterP95Micros ?? '-'}, '
        '${run.frames == null ? '-' : '${(run.frames!.deadlineMissRatio * 100).toStringAsFixed(2)}%'}, '
        '${run.frames?.longestConsecutiveDeadlineMiss ?? '-'} |',
      );
    }
    return buffer.toString();
  }

  void _writeP1Comparisons(StringBuffer buffer) {
    final grouped = <String, List<WritingScenarioSummary>>{};
    for (final scenario in completeScenarios) {
      final key = scenario.validRuns.first.comparisonKey;
      if (key != null) grouped.putIfAbsent(key, () => []).add(scenario);
    }
    final pairs = <(WritingScenarioSummary, WritingScenarioSummary)>[];
    for (final scenarios in grouped.values) {
      WritingScenarioSummary? legacy;
      WritingScenarioSummary? layered;
      for (final scenario in scenarios) {
        if (scenario.validRuns.first.layeredWetInk == true) {
          layered = scenario;
        } else {
          legacy = scenario;
        }
      }
      if (legacy != null && layered != null) pairs.add((legacy, layered));
    }
    if (pairs.isEmpty) return;
    buffer
      ..writeln()
      ..writeln('## P1 成对门禁')
      ..writeln()
      ..writeln(
        '| comparison | event target | ≥30% improvement | frame gate | no miss regression | semantic hash |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final pair in pairs) {
      final legacy = pair.$1;
      final layered = pair.$2;
      final legacyP95 = legacy.medianRunP95!;
      final layeredP95 = layered.medianRunP95!;
      final target = layered.validRuns.first.eventToPaintTargetMicros!;
      final improvement = legacyP95 == 0
          ? 0.0
          : (legacyP95 - layeredP95) / legacyP95;
      final hashPassed =
          legacy.semanticSceneHashes.length == 1 &&
          layered.semanticSceneHashes.length == 1 &&
          legacy.semanticSceneHashes.single ==
              layered.semanticSceneHashes.single;
      final missPassed =
          layered.medianDeadlineMissRatio! <= legacy.medianDeadlineMissRatio!;
      buffer.writeln(
        '| `${_shortKey(layered.validRuns.first.comparisonKey!)}` | '
        '${layeredP95 <= target} | ${improvement >= 0.30} '
        '(${(improvement * 100).toStringAsFixed(2)}%) | '
        '${layered.frameGatePassed} | $missPassed | $hashPassed |',
      );
    }
  }
}

Future<WritingResultsSummary> summarizeDirectory(
  Directory input, {
  WritingSummaryPhase phase = WritingSummaryPhase.p0,
}) async {
  if (!await input.exists()) {
    throw ArgumentError.value(input.path, 'input', 'directory does not exist');
  }
  final files = await input
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));
  final runs = <WritingRunSummary>[];
  for (final file in files) {
    final json = jsonDecode(await file.readAsString());
    if (json is! Map) continue;
    final root = Map<String, Object?>.from(json);
    if (root['mode'] == 'collaboration_cpu_non_ui' ||
        root['mode'] == 'collaboration_live_ink') {
      continue;
    }
    runs.add(_summarizeRun(file.absolute.path, root));
  }
  return WritingResultsSummary(runs: runs, phase: phase);
}

WritingRunSummary _summarizeRun(String path, Map<String, Object?> root) {
  final invalidReasons = <String>[];
  if (root['schemaVersion'] != supportedReportSchemaVersion) {
    invalidReasons.add('unsupported_root_schema');
  }
  if (root['measurementEligible'] != true || root['buildMode'] != 'profile') {
    invalidReasons.add('not_profile_or_not_device_eligible');
  }
  if (root['physicalDevice'] != true) invalidReasons.add('not_physical_device');
  final platform = root['platform'];
  if (platform is! String ||
      !const {'android', 'iOS', 'ohos'}.contains(platform)) {
    invalidReasons.add('unsupported_physical_platform');
  }
  final deviceId = root['deviceId'];
  if (deviceId is! String || deviceId.isEmpty) {
    invalidReasons.add('missing_device_id');
  }
  final deviceClass = root['deviceClass'];
  if (deviceClass is! String ||
      deviceClass.isEmpty ||
      deviceClass == 'unspecified') {
    invalidReasons.add('missing_device_class');
  }
  final refreshHz = (root['refreshHz'] as num?)?.toInt() ?? 0;
  final frozenTarget = frozenEventToPaintTargetMicros(refreshHz);
  if (frozenTarget <= 0) invalidReasons.add('unsupported_refresh_hz');
  final sceneElementCount = (root['sceneElementCount'] as num?)?.toInt();
  if (!const [100, 1000, 5000].contains(sceneElementCount)) {
    invalidReasons.add('unsupported_scene_element_count');
  }
  final writingFixture = root['writingFixture'];
  final fixtureSpec = writingFixture is String
      ? writingPerformanceFixtures[writingFixture]
      : null;
  if (fixtureSpec == null) invalidReasons.add('unsupported_writing_fixture');
  if (root['writingFixtureSchemaVersion'] != 1) {
    invalidReasons.add('unsupported_writing_fixture_schema');
  }
  final runIndex = (root['runIndex'] as num?)?.toInt();
  if (runIndex == null || runIndex < 1 || runIndex > 5) {
    invalidReasons.add('invalid_run_index');
  }
  final measureSeconds = (root['measureSeconds'] as num?)?.toInt();
  if (measureSeconds == null ||
      measureSeconds != fixtureSpec?.durationSeconds) {
    invalidReasons.add('nonstandard_measurement_duration');
  }
  final eventTarget = (root['eventToPaintTargetMicros'] as num?)?.toInt();
  if (eventTarget == null || eventTarget != frozenTarget) {
    invalidReasons.add('unfrozen_event_target');
  }
  final hostEvidence = root['hostEvidence'];
  String? gitSha;
  if (hostEvidence is Map) {
    gitSha = hostEvidence['gitSha'] as String?;
    if (hostEvidence['gitDirty'] != false) {
      invalidReasons.add('dirty_git_worktree');
    }
    if (hostEvidence['detectedDeviceId'] != deviceId) {
      invalidReasons.add('device_id_not_host_verified');
    }
    if (hostEvidence['detectedEmulator'] != false) {
      invalidReasons.add('device_is_emulator_or_unknown');
    }
    if (hostEvidence['supportedDeviceCount'] != 1) {
      invalidReasons.add('ambiguous_test_device_set');
    }
    final detectedTarget = hostEvidence['detectedTargetPlatform'];
    if (platform is String &&
        (detectedTarget is! String ||
            !detectedTarget.toLowerCase().startsWith(platform.toLowerCase()))) {
      invalidReasons.add('device_platform_not_host_verified');
    }
  } else {
    invalidReasons.add('missing_host_evidence');
  }
  if (gitSha == null || !RegExp(r'^[0-9a-f]{40}$').hasMatch(gitSha)) {
    invalidReasons.add('invalid_git_sha');
  }
  final fixtureHash = root['writingFixtureHash'];
  if (fixtureHash != fixtureSpec?.hash) {
    invalidReasons.add('unfrozen_writing_fixture_hash');
  }
  final sceneFixtureHash = root['sceneFixtureHash'];
  final sceneHashAfterRun = root['sceneHashAfterRun'];
  final reportedSemanticSceneHash = root['semanticSceneHashAfterRun'];
  for (final entry in {
    'invalid_scene_fixture_hash': sceneFixtureHash,
    'invalid_final_scene_hash': sceneHashAfterRun,
    'invalid_semantic_scene_hash': reportedSemanticSceneHash,
  }.entries) {
    if (entry.value is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(entry.value! as String)) {
      invalidReasons.add(entry.key);
    }
  }
  if (sceneFixtureHash != writingSceneFixtureHashes[sceneElementCount]) {
    invalidReasons.add('unfrozen_scene_fixture_hash');
  }
  final expectedCompletedStrokes =
      (root['expectedCompletedStrokes'] as num?)?.toInt() ?? 0;
  final rawFinalScene = root['finalScene'];
  Map<String, Object?>? finalScene;
  try {
    if (rawFinalScene is Map) {
      finalScene = ExcalidrawScene.fromJson(
        Map<String, Object?>.from(rawFinalScene),
      ).toJson();
    }
  } on Object {
    finalScene = null;
  }
  final completedElements = finalScene?['elements'] is List
      ? (finalScene!['elements']! as List).skip(sceneElementCount ?? 0).toList()
      : const <Object?>[];
  final structurallyValidFreedraw = completedElements.where((element) {
    if (element is! Map || element['type'] != 'freedraw') return false;
    final points = element['points'];
    return points is List &&
        points.isNotEmpty &&
        points.every(
          (point) =>
              point is List &&
              point.length >= 2 &&
              point[0] is num &&
              (point[0] as num).toDouble().isFinite &&
              point[1] is num &&
              (point[1] as num).toDouble().isFinite,
        );
  }).length;
  final recomputedSceneHash = finalScene == null
      ? null
      : canonicalSceneHash(finalScene);
  final recomputedSemanticHash = finalScene == null
      ? null
      : semanticSceneHash(finalScene);
  if (finalScene == null ||
      recomputedSceneHash != sceneHashAfterRun ||
      recomputedSemanticHash != reportedSemanticSceneHash) {
    invalidReasons.add('scene_artifact_hash_mismatch');
  }
  if (expectedCompletedStrokes <= 0 ||
      finalScene?['elements'] is! List ||
      (finalScene!['elements']! as List).length !=
          (sceneElementCount ?? 0) + expectedCompletedStrokes ||
      structurallyValidFreedraw != expectedCompletedStrokes) {
    invalidReasons.add('incomplete_final_scene');
  }
  final flags = root['flags'];
  final layeredWetInk = flags is Map ? flags['layeredWetInk'] as bool? : null;
  if (layeredWetInk == null) invalidReasons.add('missing_layered_wet_ink_flag');

  final scenarioFields = <String, Object?>{
    'gitSha': gitSha,
    'platform': root['platform'],
    'deviceId': deviceId,
    'deviceClass': deviceClass,
    'refreshHz': refreshHz,
    'sceneElementCount': sceneElementCount,
    'sceneFixtureHash': sceneFixtureHash,
    'writingFixture': writingFixture,
    'writingFixtureSchemaVersion': root['writingFixtureSchemaVersion'],
    'writingFixtureHash': fixtureHash,
    'measureSeconds': measureSeconds,
    'eventToPaintTargetMicros': eventTarget,
  };
  final hasScenarioIdentity = scenarioFields.values.every(
    (value) => value != null && value != '' && value != 0,
  );
  final comparisonKey = hasScenarioIdentity ? jsonEncode(scenarioFields) : null;
  final scenarioKey = comparisonKey == null || layeredWetInk == null
      ? null
      : jsonEncode({...scenarioFields, 'layeredWetInk': layeredWetInk});

  final rawPerformance = root['performance'];
  Map<String, Object?>? performance;
  if (rawPerformance is Map) {
    performance = Map<String, Object?>.from(rawPerformance);
  } else {
    invalidReasons.add('missing_performance_report');
  }
  if (performance != null &&
      performance['schemaVersion'] != supportedReportSchemaVersion) {
    invalidReasons.add('unsupported_performance_schema');
  }
  final reportInvalidReasons = performance?['invalidReasons'];
  if (reportInvalidReasons is List) {
    invalidReasons.addAll(reportInvalidReasons.whereType<String>());
  }
  final durations = <int>[];
  final paintedFrameNumbers = <int>{};
  var accepted = 0;
  var painted = 0;
  var terminal = 0;
  final sampleKeys = <String>{};
  final strokeEpochs = <int>{};
  final acceptedByStrokeEpoch = <int, int>{};
  final samples = performance?['activePreviewSamples'];
  if (samples is List) {
    for (final rawSample in samples) {
      if (rawSample is! Map) continue;
      final strokeEpoch = (rawSample['strokeEpoch'] as num?)?.toInt();
      final inputSeq = (rawSample['inputSeq'] as num?)?.toInt();
      if (strokeEpoch == null ||
          strokeEpoch <= 0 ||
          inputSeq == null ||
          inputSeq < 0 ||
          !sampleKeys.add('$strokeEpoch:$inputSeq')) {
        invalidReasons.add('invalid_or_duplicate_sample_identity');
        continue;
      }
      strokeEpochs.add(strokeEpoch);
      acceptedByStrokeEpoch.update(
        strokeEpoch,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      accepted++;
      final duration = rawSample['eventToPaintMicros'];
      final terminalReason = rawSample['terminalReason'];
      if (duration is num && duration.toInt() >= 0 && terminalReason == null) {
        painted++;
        durations.add(duration.toInt());
        final frameNumber = (rawSample['frameNumber'] as num?)?.toInt();
        if (frameNumber == null) {
          invalidReasons.add('painted_sample_missing_frame_number');
        } else {
          paintedFrameNumbers.add(frameNumber);
        }
      } else if (duration == null && terminalReason is String) {
        terminal++;
      } else {
        invalidReasons.add('invalid_sample_state');
      }
    }
  }
  if (strokeEpochs.length != expectedCompletedStrokes) {
    invalidReasons.add('sample_stroke_count_mismatch');
  }
  if (acceptedByStrokeEpoch.length != expectedCompletedStrokes ||
      acceptedByStrokeEpoch.values.any(
        (count) => count != fixtureSpec?.acceptedSamplesPerStroke,
      )) {
    invalidReasons.add('fixture_accepted_sample_count_mismatch');
  }
  final denominator = accepted - terminal;
  final missingPaint = denominator - painted;
  final coverage = denominator <= 0 ? 0.0 : painted / denominator;
  if ((performance?['accepted'] as num?)?.toInt() != accepted ||
      (performance?['painted'] as num?)?.toInt() != painted ||
      (performance?['missingPaint'] as num?)?.toInt() != missingPaint ||
      (performance?['terminalBeforePreview'] as num?)?.toInt() != terminal ||
      ((performance?['coverage'] as num?)?.toDouble() ?? -1) != coverage) {
    invalidReasons.add('performance_counts_not_reproducible');
  }
  if (accepted < 100) invalidReasons.add('fewer_than_100_accepted_samples');
  if (coverage < 0.995) invalidReasons.add('coverage_below_99_5_percent');
  durations.sort();
  if (durations.isEmpty) invalidReasons.add('no_painted_samples');
  FrameRunSummary? frames;
  if (refreshHz > 0) {
    frames = _summarizeFrames(
      performance?['frames'],
      refreshHz,
      measureSeconds,
      invalidReasons,
    );
  } else if (performance?['frames'] is! List) {
    invalidReasons.add('missing_frame_timings');
  }
  if (frames != null && !frames.frameNumbers.containsAll(paintedFrameNumbers)) {
    invalidReasons.add('painted_sample_frame_not_collected');
  }
  return WritingRunSummary(
    path: path,
    valid: invalidReasons.isEmpty,
    invalidReasons: List.unmodifiable(invalidReasons),
    scenarioKey: scenarioKey,
    comparisonKey: comparisonKey,
    runIndex: runIndex,
    layeredWetInk: layeredWetInk,
    eventToPaintTargetMicros: eventTarget,
    semanticSceneHashAfterRun: reportedSemanticSceneHash is String
        ? reportedSemanticSceneHash
        : null,
    finalSceneHashAfterRun: sceneHashAfterRun is String
        ? sceneHashAfterRun
        : null,
    accepted: accepted,
    painted: painted,
    terminalBeforePreview: terminal,
    coverage: coverage,
    p50Micros: durations.isEmpty ? null : nearestRank(durations, 0.50),
    p95Micros: durations.isEmpty ? null : nearestRank(durations, 0.95),
    p99Micros: durations.isEmpty ? null : nearestRank(durations, 0.99),
    worstMicros: durations.isEmpty ? null : durations.last,
    eventToPaintMicros: List.unmodifiable(durations),
    frames: frames,
  );
}

String canonicalSceneHash(Map<String, Object?> scene) =>
    sha256.convert(utf8.encode(jsonEncode(scene))).toString();

String semanticSceneHash(Map<String, Object?> scene) {
  const ignoredKeys = {
    'id',
    'seed',
    'versionNonce',
    'updated',
    'selectedElementIds',
    'selectedGroupIds',
    'editingElement',
  };
  Object? normalize(Object? value) {
    if (value is List) return [for (final item in value) normalize(item)];
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (!ignoredKeys.contains(entry.key))
            entry.key.toString(): normalize(entry.value),
      };
    }
    return value;
  }

  return sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'elements': normalize(scene['elements']),
            'appState': normalize(scene['appState']),
            'files': normalize(scene['files']),
          }),
        ),
      )
      .toString();
}

FrameRunSummary? _summarizeFrames(
  Object? rawFrames,
  int refreshHz,
  int? measureSeconds,
  List<String> invalidReasons,
) {
  if (rawFrames is! List || rawFrames.isEmpty) {
    invalidReasons.add('missing_frame_timings');
    return null;
  }
  final frames = <({int number, int build, int raster, int total})>[];
  for (final raw in rawFrames) {
    if (raw is! Map) continue;
    final number = (raw['frameNumber'] as num?)?.toInt();
    final build = (raw['buildMicros'] as num?)?.toInt();
    final raster = (raw['rasterMicros'] as num?)?.toInt();
    final total = (raw['totalSpanMicros'] as num?)?.toInt();
    if (number != null && build != null && raster != null && total != null) {
      frames.add((number: number, build: build, raster: raster, total: total));
    }
  }
  if (frames.isEmpty) {
    invalidReasons.add('missing_frame_timings');
    return null;
  }
  frames.sort((left, right) => left.number.compareTo(right.number));
  if (frames.map((frame) => frame.number).toSet().length != frames.length) {
    invalidReasons.add('duplicate_frame_numbers');
  }
  if (measureSeconds != null) {
    final minimumFrameCount = (measureSeconds * refreshHz * 0.8).ceil();
    if (frames.length < minimumFrameCount) {
      invalidReasons.add('insufficient_frame_coverage');
    }
  }
  final buildValues = [for (final frame in frames) frame.build]..sort();
  final rasterValues = [for (final frame in frames) frame.raster]..sort();
  final budget = (1000000 / refreshHz).round();
  var missCount = 0;
  var streak = 0;
  var longestStreak = 0;
  for (final frame in frames) {
    if (frame.total > budget) {
      missCount++;
      streak++;
      longestStreak = math.max(longestStreak, streak);
    } else {
      streak = 0;
    }
  }
  return FrameRunSummary(
    count: frames.length,
    frameBudgetMicros: budget,
    buildP50Micros: nearestRank(buildValues, 0.50),
    buildP95Micros: nearestRank(buildValues, 0.95),
    buildP99Micros: nearestRank(buildValues, 0.99),
    buildWorstMicros: buildValues.last,
    rasterP50Micros: nearestRank(rasterValues, 0.50),
    rasterP95Micros: nearestRank(rasterValues, 0.95),
    rasterP99Micros: nearestRank(rasterValues, 0.99),
    rasterWorstMicros: rasterValues.last,
    deadlineMissCount: missCount,
    deadlineMissRatio: missCount / frames.length,
    longestConsecutiveDeadlineMiss: longestStreak,
    frameNumbers: Set.unmodifiable(frames.map((frame) => frame.number)),
  );
}

int nearestRank(List<int> sortedValues, double percentile) {
  if (sortedValues.isEmpty) throw ArgumentError('values must not be empty');
  if (percentile <= 0 || percentile > 1) {
    throw RangeError.range(percentile, 0, 1, 'percentile');
  }
  final index = math.max(0, (percentile * sortedValues.length).ceil() - 1);
  return sortedValues[index];
}

({int low, int high}) bootstrapP95(
  List<int> values, {
  int iterations = 1000,
  int seed = 1701,
}) {
  if (values.isEmpty) throw ArgumentError('values must not be empty');
  final random = math.Random(seed);
  final estimates = <int>[];
  for (var iteration = 0; iteration < iterations; iteration++) {
    final sample = [
      for (var index = 0; index < values.length; index++)
        values[random.nextInt(values.length)],
    ]..sort();
    estimates.add(nearestRank(sample, 0.95));
  }
  estimates.sort();
  return (
    low: nearestRank(estimates, 0.025),
    high: nearestRank(estimates, 0.975),
  );
}

int? _medianInt(List<int> values) {
  if (values.isEmpty) return null;
  values.sort();
  return nearestRank(values, 0.50);
}

double? _medianDouble(List<double> values) {
  if (values.isEmpty) return null;
  values.sort();
  return values[math.max(0, (values.length * 0.5).ceil() - 1)];
}

String _shortKey(String key) {
  var hash = 0xcbf29ce484222325;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String _csv(String value) => '"${value.replaceAll('"', '""')}"';

Future<void> main(List<String> arguments) async {
  String? inputPath;
  String? outputPath;
  WritingSummaryPhase? phase;
  var reportOnly = false;
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--input':
        inputPath = arguments[++index];
        break;
      case '--output':
        outputPath = arguments[++index];
        break;
      case '--phase':
        phase = switch (arguments[++index]) {
          'p0' => WritingSummaryPhase.p0,
          'p1' => WritingSummaryPhase.p1,
          _ => null,
        };
        break;
      case '--report-only':
        reportOnly = true;
        break;
    }
  }
  if (inputPath == null || outputPath == null || phase == null) {
    stderr.writeln(
      'Usage: dart run tool/writing_perf/summarize_results.dart --phase p0|p1 --input <raw-directory> --output <report.md> [--report-only]',
    );
    exitCode = 64;
    return;
  }
  final summary = await summarizeDirectory(Directory(inputPath), phase: phase);
  final markdownFile = File(outputPath);
  await markdownFile.parent.create(recursive: true);
  await markdownFile.writeAsString(summary.toMarkdown());
  final csvPath = outputPath.toLowerCase().endsWith('.md')
      ? '${outputPath.substring(0, outputPath.length - 3)}.csv'
      : '$outputPath.csv';
  await File(csvPath).writeAsString(summary.toCsv());
  stdout.writeln('markdown=${markdownFile.absolute.path}');
  stdout.writeln('csv=${File(csvPath).absolute.path}');
  if (!reportOnly && summary.acceptanceStatus != 'passed') {
    stderr.writeln('acceptance=${summary.acceptanceStatus}');
    exitCode = 1;
  }
}
