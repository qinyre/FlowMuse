import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/active_preview_metrics_probe.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/writing_performance_report.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/scene_fixtures.dart';
import 'fixtures/writing_recordings.dart';

const _perfTestEnabled = bool.fromEnvironment('FLOWMUSE_PERF_TEST');
const _sceneElementCount = int.fromEnvironment(
  'FLOWMUSE_SCENE_ELEMENTS',
  defaultValue: 100,
);
const _writingFixtureName = String.fromEnvironment(
  'FLOWMUSE_WRITING_FIXTURE',
  defaultValue: 'quick_zigzag',
);
const _measureSecondsOverride = int.fromEnvironment('FLOWMUSE_MEASURE_SECONDS');
const _deviceClass = String.fromEnvironment(
  'FLOWMUSE_DEVICE_CLASS',
  defaultValue: 'unspecified',
);
const _refreshHz = int.fromEnvironment('FLOWMUSE_REFRESH_HZ');
const _runIndex = int.fromEnvironment('FLOWMUSE_RUN_INDEX');
const _physicalDevice = bool.fromEnvironment('FLOWMUSE_PHYSICAL_DEVICE');
const _deviceId = String.fromEnvironment('FLOWMUSE_DEVICE_ID');
const _eventToPaintTargetOverride = int.fromEnvironment(
  'FLOWMUSE_EVENT_TO_PAINT_TARGET_MICROS',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('固定 fixture 的真实 EditorCanvas 书写性能', (tester) async {
    expect(
      _perfTestEnabled,
      isTrue,
      reason: '性能入口仅允许通过 FLOWMUSE_PERF_TEST=true 启用',
    );
    final fixture = writingRecordingFixtures.singleWhere(
      (item) => item.name == _writingFixtureName,
    );
    final sceneFixture = buildSceneFixture(_sceneElementCount);
    final probe = ActivePreviewMetricsProbe();
    final controller = MarkdrawController(activePreviewMetricsProbe: probe);
    addTearDown(controller.dispose);
    controller.loadFromContent(
      sceneFixture.toContent(),
      'writing-performance.excalidraw',
    );
    controller.switchTool(ToolType.freedraw);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdrawEditor(
            controller: controller,
            config: const MarkdrawEditorConfig(
              showToolbar: false,
              showPropertyPanel: false,
              showZoomControls: false,
              showHelpButton: false,
              showLibraryPanel: false,
              showMarkdownButton: false,
              showMenu: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canvas = find.byType(EditorCanvas);
    expect(canvas, findsOneWidget);
    final canvasRect = tester.getRect(canvas);
    final warmupClock = Stopwatch()..start();
    var warmupStrokeIndex = 0;
    while (warmupClock.elapsed < const Duration(seconds: 5)) {
      await _replayFixture(
        tester,
        fixture,
        canvasRect,
        warmupClock,
        warmupStrokeIndex++,
        null,
      );
    }
    controller.loadFromContent(
      sceneFixture.toContent(),
      'writing-performance.excalidraw',
    );
    controller.switchTool(ToolType.freedraw);
    probe.clear();
    await tester.pump();

    final frameTimings = FrameTimingMetricsCollector()..start();
    addTearDown(frameTimings.stop);
    final injectionSamples = <Map<String, int>>[];
    final runClock = Stopwatch()..start();
    final measureSeconds = _measureSecondsOverride > 0
        ? _measureSecondsOverride
        : fixture.name.contains('long_curve')
        ? 30
        : 60;
    final expectedMeasureSeconds = fixture.name.contains('long_curve')
        ? 30
        : 60;
    final eventToPaintTargetMicros = _eventToPaintTargetOverride > 0
        ? _eventToPaintTargetOverride
        : _refreshHz >= 55 && _refreshHz <= 65
        ? 33400
        : _refreshHz >= 100
        ? (1000000 / _refreshHz).ceil()
        : 0;
    var strokeIndex = 0;
    while (runClock.elapsed < Duration(seconds: measureSeconds)) {
      await _replayFixture(
        tester,
        fixture,
        canvasRect,
        runClock,
        strokeIndex++,
        injectionSamples,
      );
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    frameTimings.stop();

    final jitters =
        injectionSamples.map((sample) => sample['jitterMicros']!.abs()).toList()
          ..sort();
    final jitterP95 = _nearestRank(jitters, 0.95);
    final jitterMax = jitters.isEmpty ? 0 : jitters.last;
    final invalidReasons = <String>[
      if (jitterP95 > 4000) 'injection_jitter_p95_above_4ms',
      if (jitterMax > 16000) 'injection_jitter_max_above_16ms',
    ];
    final performance = WritingPerformanceReport.capture(
      activePreview: probe,
      frames: frameTimings.frames,
      invalidReasons: invalidReasons,
    );
    final sceneAfterRun = controller.serializeExcalidrawSceneJson();
    binding.reportData = <String, Object?>{
      'schemaVersion': 1,
      'measurementEligible':
          kProfileMode &&
          _physicalDevice &&
          _deviceId.isNotEmpty &&
          _deviceClass != 'unspecified' &&
          _refreshHz > 0 &&
          _runIndex >= 1 &&
          _runIndex <= 5 &&
          measureSeconds == expectedMeasureSeconds &&
          eventToPaintTargetMicros > 0,
      'buildMode': kProfileMode
          ? 'profile'
          : kReleaseMode
          ? 'release'
          : 'debug',
      'platform': defaultTargetPlatform.name,
      'deviceClass': _deviceClass,
      'deviceId': _deviceId,
      'physicalDevice': _physicalDevice,
      'refreshHz': _refreshHz,
      'runIndex': _runIndex,
      'sceneElementCount': _sceneElementCount,
      'sceneFixtureHash': sceneFixture.collaborationHash(),
      'writingFixture': fixture.name,
      'writingFixtureSchemaVersion': fixture.schemaVersion,
      'writingFixtureHash': fixture.contentHash,
      'measureSeconds': measureSeconds,
      'expectedMeasureSeconds': expectedMeasureSeconds,
      'eventToPaintTargetMicros': eventToPaintTargetMicros,
      'flags': {'layeredWetInk': writingFeatureFlags.layeredWetInk},
      'injectionJitterP95Micros': jitterP95,
      'injectionJitterMaxMicros': jitterMax,
      'injectionSamples': injectionSamples,
      'elementsAfterRun': controller.currentScene.elements.length,
      'sceneHashAfterRun': _jsonHash(sceneAfterRun),
      'semanticSceneHashAfterRun': _semanticSceneHash(sceneAfterRun),
      'performance': performance.toJson(),
    };
  });
}

Future<void> _replayFixture(
  WidgetTester tester,
  WritingRecordingFixture fixture,
  Rect canvasRect,
  Stopwatch clock,
  int strokeIndex,
  List<Map<String, int>>? injectionSamples,
) async {
  final samples = fixture.recording.samples;
  final minX = samples.map((sample) => sample.x).reduce(math.min);
  final maxX = samples.map((sample) => sample.x).reduce(math.max);
  final minY = samples.map((sample) => sample.y).reduce(math.min);
  final maxY = samples.map((sample) => sample.y).reduce(math.max);
  final scale = math.min(
    1.0,
    math.min(
      (canvasRect.width - 40) / math.max(1, maxX - minX),
      (canvasRect.height - 40) / math.max(1, maxY - minY),
    ),
  );
  final strokeStartMicros = clock.elapsedMicroseconds;
  final pointer = fixture.seed + strokeIndex;
  Offset? previousPosition;
  for (final sample in samples) {
    final targetMicros = strokeStartMicros + sample.time.inMicroseconds;
    final waitMicros = targetMicros - clock.elapsedMicroseconds;
    if (waitMicros > 0) {
      await Future<void>.delayed(Duration(microseconds: waitMicros));
    }
    final actualMicros = clock.elapsedMicroseconds;
    injectionSamples?.add({
      'targetMicros': targetMicros,
      'actualMicros': actualMicros,
      'jitterMicros': actualMicros - targetMicros,
    });
    final position =
        canvasRect.topLeft +
        Offset(20 + (sample.x - minX) * scale, 20 + (sample.y - minY) * scale);
    final timeStamp = Duration(microseconds: targetMicros);
    final pressure = sample.pressure ?? 0;
    final kind = _pointerDeviceKind(sample.kind);
    final event = switch (sample.phase) {
      StrokePhase.down => PointerDownEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        kind: kind,
        position: position,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ),
      StrokePhase.move => PointerMoveEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        kind: kind,
        position: position,
        delta: position - previousPosition!,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ),
      StrokePhase.up => PointerUpEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        kind: kind,
        position: position,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ),
      StrokePhase.cancel => PointerCancelEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        kind: kind,
        position: position,
        pressureMin: 0,
        pressureMax: 1,
      ),
    };
    await tester.sendEventToBinding(event);
    previousPosition = position;
  }
}

PointerDeviceKind _pointerDeviceKind(StrokeInputKind kind) => switch (kind) {
  StrokeInputKind.stylus => PointerDeviceKind.stylus,
  StrokeInputKind.invertedStylus => PointerDeviceKind.invertedStylus,
  StrokeInputKind.touch => PointerDeviceKind.touch,
  StrokeInputKind.mouse => PointerDeviceKind.mouse,
  StrokeInputKind.unknown => PointerDeviceKind.unknown,
};

String _jsonHash(Map<String, Object?> value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

String _semanticSceneHash(Map<String, Object?> scene) {
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

int _nearestRank(List<int> sorted, double percentile) {
  if (sorted.isEmpty) return 0;
  return sorted[math.max(0, (percentile * sorted.length).ceil() - 1)];
}
