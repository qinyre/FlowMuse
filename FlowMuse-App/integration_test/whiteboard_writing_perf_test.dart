import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/active_preview_metrics_probe.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/writing_performance_report.dart';
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
    await _replayFixture(tester, fixture, canvasRect, warmupClock, 0, null);
    final remainingWarmup = const Duration(seconds: 5) - warmupClock.elapsed;
    if (remainingWarmup > Duration.zero) {
      await Future<void>.delayed(remainingWarmup);
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
    binding.reportData = <String, Object?>{
      'schemaVersion': 1,
      'measurementEligible': kProfileMode,
      'buildMode': kProfileMode
          ? 'profile'
          : kReleaseMode
          ? 'release'
          : 'debug',
      'platform': defaultTargetPlatform.name,
      'deviceClass': _deviceClass,
      'refreshHz': _refreshHz,
      'runIndex': _runIndex,
      'sceneElementCount': _sceneElementCount,
      'sceneFixtureHash': sceneFixture.collaborationHash(),
      'writingFixture': fixture.name,
      'writingFixtureSchemaVersion': fixture.schemaVersion,
      'measureSeconds': measureSeconds,
      'injectionJitterP95Micros': jitterP95,
      'injectionJitterMaxMicros': jitterMax,
      'injectionSamples': injectionSamples,
      'elementsAfterRun': controller.currentScene.elements.length,
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
    final event = switch (sample.phase) {
      StrokePhase.down => PointerDownEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: position,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ),
      StrokePhase.move => PointerMoveEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: position,
        delta: position - previousPosition!,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ),
      StrokePhase.up => PointerUpEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: position,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ),
      StrokePhase.cancel => PointerCancelEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: position,
        pressureMin: 0,
        pressureMax: 1,
      ),
    };
    await tester.sendEventToBinding(event);
    previousPosition = position;
  }
}

int _nearestRank(List<int> sorted, double percentile) {
  if (sorted.isEmpty) return 0;
  return sorted[math.max(0, (percentile * sorted.length).ceil() - 1)];
}
