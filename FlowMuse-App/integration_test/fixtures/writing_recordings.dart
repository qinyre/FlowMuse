import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_recorder.dart';

const int writingFixtureSchemaVersion = 1;

class WritingRecordingFixture {
  const WritingRecordingFixture({
    required this.name,
    required this.seed,
    required this.expectedRawSampleCount,
    required this.expectedAcceptedSampleCount,
    required this.recording,
  });

  final String name;
  final int seed;
  final int expectedRawSampleCount;
  final int expectedAcceptedSampleCount;
  final StrokeRecording recording;

  int get schemaVersion => writingFixtureSchemaVersion;
}

final List<WritingRecordingFixture> writingRecordingFixtures = [
  _fixture(
    name: 'short_horizontal_no_pressure',
    seed: 101,
    moveCount: 8,
    expectedAccepted: 10,
    pointAt: (index) => (100.0 + index * 8, 160.0),
    pressureAt: (_) => null,
  ),
  _fixture(
    name: 'long_curve_pressure',
    seed: 202,
    moveCount: 120,
    expectedAccepted: 122,
    pointAt: (index) => (80.0 + index * 4, 300.0 + math.sin(index / 10) * 70),
    pressureAt: (index) => 0.25 + (index % 20) / 40,
  ),
  _fixture(
    name: 'quick_zigzag',
    seed: 303,
    moveCount: 40,
    expectedAccepted: 42,
    intervalMicros: 2000,
    pointAt: (index) => (120.0 + index * 9, index.isEven ? 220.0 : 300.0),
    pressureAt: (_) => 0.5,
  ),
  _fixture(
    name: 'pressure_ramp',
    seed: 404,
    moveCount: 30,
    expectedAccepted: 32,
    pointAt: (index) => (160.0 + index * 7, 420.0 + index * 2),
    pressureAt: (index) => (0.1 + index / 40).clamp(0.0, 1.0),
  ),
  _fixture(
    name: 'pointer_cancel',
    seed: 505,
    moveCount: 12,
    expectedAccepted: 13,
    terminalPhase: StrokePhase.cancel,
    pointAt: (index) => (200.0 + index * 6, 520.0 - index * 3),
    pressureAt: (_) => 0.4,
  ),
];

WritingRecordingFixture _fixture({
  required String name,
  required int seed,
  required int moveCount,
  required int expectedAccepted,
  required (double, double) Function(int index) pointAt,
  required double? Function(int index) pressureAt,
  int intervalMicros = 8333,
  StrokePhase terminalPhase = StrokePhase.up,
}) {
  final samples = <StrokeInputSample>[];
  for (var index = 0; index < moveCount + 2; index++) {
    final phase = index == 0
        ? StrokePhase.down
        : index == moveCount + 1
        ? terminalPhase
        : StrokePhase.move;
    final pointIndex = index > moveCount ? moveCount : index;
    final (x, y) = pointAt(pointIndex);
    samples.add(
      StrokeInputSample(
        pointerId: seed,
        x: x,
        y: y,
        time: Duration(microseconds: index * intervalMicros),
        pressure: pressureAt(pointIndex),
        kind: StrokeInputKind.stylus,
        phase: phase,
        source: StrokeSampleSource.actual,
      ),
    );
  }
  return WritingRecordingFixture(
    name: name,
    seed: seed,
    expectedRawSampleCount: samples.length,
    expectedAcceptedSampleCount: expectedAccepted,
    recording: StrokeRecording(
      samples: List.unmodifiable(samples),
      viewportZoom: 1,
      viewportTransform: const [1, 0, 0, 1, 0, 0],
      buildVersion: 'fixture-v$writingFixtureSchemaVersion',
      deviceInfo: 'deterministic',
    ),
  );
}
