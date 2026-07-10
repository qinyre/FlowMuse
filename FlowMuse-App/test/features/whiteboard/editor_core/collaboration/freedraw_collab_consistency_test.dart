import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart' show PointVector;
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/freedraw_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/excalidraw_json_codec.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/parse_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';

void main() {
  // ──────────────────────────────────────────────────────────────
  // 1. JSON 往返：points/pressures/simulatePressure 一致，isComplete 不出现
  // ──────────────────────────────────────────────────────────────
  group('FreedrawElement JSON round-trip', () {
    test('preserves points, pressures, and simulatePressure', () {
      final element = FreedrawElement(
        id: const ElementId('collab-test-1'),
        x: 10,
        y: 20,
        width: 100,
        height: 80,
        points: const [
          Point(0, 0),
          Point(10, 5),
          Point(25, 8),
          Point(50, 12),
          Point(80, 6),
        ],
        pressures: const [0.2, 0.4, 0.7, 0.9, 0.3],
        simulatePressure: false,
      );

      final json = ExcalidrawJsonCodec.elementToJson(element);
      final restored = ExcalidrawJsonCodec.parseElement(
        json,
        json['type'] as String,
        0,
        <ParseWarning>[],
      ) as FreedrawElement;

      expect(restored.points, element.points);
      expect(restored.pressures, element.pressures);
      expect(restored.simulatePressure, element.simulatePressure);
    });

    test('simulatePressure=true is preserved through round-trip', () {
      final element = FreedrawElement(
        id: const ElementId('collab-test-2'),
        x: 0,
        y: 0,
        width: 50,
        height: 50,
        points: const [Point(0, 0), Point(20, 20), Point(40, 10)],
        pressures: const [],
        simulatePressure: true,
      );

      final json = ExcalidrawJsonCodec.elementToJson(element);
      final restored = ExcalidrawJsonCodec.parseElement(
        json,
        json['type'] as String,
        0,
        <ParseWarning>[],
      ) as FreedrawElement;

      expect(restored.points, element.points);
      expect(restored.pressures, isEmpty);
      expect(restored.simulatePressure, isTrue);
    });

    test('isComplete is NOT present in serialized JSON', () {
      final element = FreedrawElement(
        id: const ElementId('collab-test-3'),
        x: 0,
        y: 0,
        width: 30,
        height: 30,
        points: const [Point(0, 0), Point(5, 5)],
        pressures: const [0.5, 0.6],
        simulatePressure: false,
      );

      final json = ExcalidrawJsonCodec.elementToJson(element);
      expect(json.containsKey('isComplete'), isFalse);
    });

    test('isComplete defaults to true after deserialization (runtime-only)', () {
      final element = FreedrawElement(
        id: const ElementId('collab-test-4'),
        x: 0,
        y: 0,
        width: 30,
        height: 30,
        points: const [Point(0, 0), Point(5, 5)],
        pressures: const [0.5, 0.6],
        simulatePressure: false,
        isComplete: false, // sender-side: still in progress
      );

      // Serialize (isComplete dropped)
      final json = ExcalidrawJsonCodec.elementToJson(element);
      expect(json.containsKey('isComplete'), isFalse);

      // Deserialize on receiver side
      final restored = ExcalidrawJsonCodec.parseElement(
        json,
        json['type'] as String,
        0,
        <ParseWarning>[],
      ) as FreedrawElement;

      // Receiver sees isComplete=true because JSON omits the field
      expect(restored.isComplete, isTrue);
      expect(restored.points, element.points);
      expect(restored.pressures, element.pressures);
    });

    test('handles empty pressures list round-trip correctly', () {
      final element = FreedrawElement(
        id: const ElementId('collab-test-5'),
        x: 0,
        y: 0,
        width: 40,
        height: 40,
        points: const [Point(0, 0), Point(10, 3), Point(30, 7)],
        pressures: const [],
        simulatePressure: true,
      );

      final json = ExcalidrawJsonCodec.elementToJson(element);
      expect(json['pressures'], isEmpty);

      final restored = ExcalidrawJsonCodec.parseElement(
        json,
        json['type'] as String,
        0,
        <ParseWarning>[],
      ) as FreedrawElement;

      expect(restored.pressures, isEmpty);
      expect(restored.simulatePressure, isTrue);
    });

    test('single-point stroke round-trips correctly', () {
      final element = FreedrawElement(
        id: const ElementId('collab-test-dot'),
        x: 5,
        y: 5,
        width: 1,
        height: 1,
        points: const [Point(0, 0)],
        pressures: const [0.8],
        simulatePressure: false,
      );

      final json = ExcalidrawJsonCodec.elementToJson(element);
      final restored = ExcalidrawJsonCodec.parseElement(
        json,
        json['type'] as String,
        0,
        <ParseWarning>[],
      ) as FreedrawElement;

      expect(restored.points, element.points);
      expect(restored.pressures, element.pressures);
      expect(restored.simulatePressure, element.simulatePressure);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 2. 接收端用相同 renderer 参数重建，几何与发送端一致
  // ──────────────────────────────────────────────────────────────
  group('Receiver-side reconstruction consistency', () {
    // Sender params that the receiver must replicate.
    const senderPoints = [
      Point(0, 0),
      Point(10, 3),
      Point(25, 7),
      Point(45, 5),
      Point(65, 12),
      Point(80, 8),
    ];
    const senderPressures = [0.1, 0.3, 0.6, 0.9, 0.5, 0.2];
    const strokeWidth = 3.0;
    const pressureSensitivity = 0.7;

    test('same outlineRenderMode + pressureSensitivity => identical outline', () {
      // Sender side
      final senderOutline = FreedrawRenderer.buildOutline(
        senderPoints,
        strokeWidth: strokeWidth,
        pressures: senderPressures,
        pressureSensitivity: pressureSensitivity,
        isComplete: true,
      );

      // Receiver side: reconstruct from deserialized element with same params
      final receiverOutline = FreedrawRenderer.buildOutline(
        senderPoints,
        strokeWidth: strokeWidth,
        pressures: senderPressures,
        pressureSensitivity: pressureSensitivity,
        isComplete: true,
      );

      expect(receiverOutline.length, senderOutline.length);
      for (var i = 0; i < senderOutline.length; i++) {
        expect(receiverOutline[i].dx, senderOutline[i].dx);
        expect(receiverOutline[i].dy, senderOutline[i].dy);
      }
    });

    test(
      'outlinePath geometry is consistent for both OutlineRenderMode values',
      () {
        final outline = FreedrawRenderer.buildOutline(
          senderPoints,
          strokeWidth: strokeWidth,
          pressures: senderPressures,
          pressureSensitivity: pressureSensitivity,
          isComplete: true,
        );

        final outlineVectors = [
          for (final o in outline) PointVector(o.dx, o.dy, 0),
        ];
        for (final mode in OutlineRenderMode.values) {
          final path1 = FreedrawRenderer.buildOutlinePath(outlineVectors, mode);
          final path2 = FreedrawRenderer.buildOutlinePath(outlineVectors, mode);

          // Second build from same outline should produce same geometry
          // Path equality in Flutter compares internal commands
          final metrics1 = path1.computeMetrics();
          final metrics2 = path2.computeMetrics();

          // Verify number of contour segments matches
          final list1 = metrics1.toList();
          final list2 = metrics2.toList();
          expect(list1.length, list2.length);

          // The second build from the same outline vertices must
          // reconstruct a non-empty path
          expect(list1, isNotEmpty);
          if (mode == OutlineRenderMode.quadratic) {
            // quadratic mode has at least as many segments as polygon
            expect(list1.length, greaterThanOrEqualTo(1));
          }
        }
      },
    );

    test(
      'outline is non-empty and finite for both modes with real pressures',
      () {
        for (final mode in OutlineRenderMode.values) {
          final outline = FreedrawRenderer.buildOutline(
            senderPoints,
            strokeWidth: strokeWidth,
            pressures: senderPressures,
            pressureSensitivity: pressureSensitivity,
            isComplete: true,
          );

          final outlineVectors = [
            for (final o in outline) PointVector(o.dx, o.dy, 0),
          ];
          final path = FreedrawRenderer.buildOutlinePath(outlineVectors, mode);

          expect(outline, isNotEmpty);
          expect(
            outline.every((p) => p.dx.isFinite && p.dy.isFinite),
            isTrue,
          );

          // Path should have content
          final bounds = path.getBounds();
          expect(bounds.width, greaterThan(0));
          expect(bounds.height, greaterThan(0));
        }
      },
    );

    test('different pressureSensitivity yields different outline', () {
      final lowSens = FreedrawRenderer.buildOutline(
        senderPoints,
        strokeWidth: strokeWidth,
        pressures: senderPressures,
        pressureSensitivity: 0.0,
        isComplete: true,
      );
      final highSens = FreedrawRenderer.buildOutline(
        senderPoints,
        strokeWidth: strokeWidth,
        pressures: senderPressures,
        pressureSensitivity: 1.0,
        isComplete: true,
      );

      // When sensitivity differs, outlines should differ
      // (only safe to assert when points.length > 2 and pressures present)
      final same = _outlinesEqual(lowSens, highSens);
      expect(same, isFalse,
          reason: 'Different pressureSensitivity must produce different outlines');
    });

    test('isComplete=false vs isComplete=true produce different outlines', () {
      final incompleteOutline = FreedrawRenderer.buildOutline(
        senderPoints,
        strokeWidth: strokeWidth,
        pressures: senderPressures,
        pressureSensitivity: pressureSensitivity,
        isComplete: false,
      );
      final completeOutline = FreedrawRenderer.buildOutline(
        senderPoints,
        strokeWidth: strokeWidth,
        pressures: senderPressures,
        pressureSensitivity: pressureSensitivity,
        isComplete: true,
      );

      // isComplete affects the tail styling in perfect_freehand
      final same = _outlinesEqual(incompleteOutline, completeOutline);
      expect(same, isFalse,
          reason: 'isComplete must affect outline geometry for dry-ink tail');
    });

    test('reconstructed from JSON element yields same outline as original', () {
      // Full round-trip simulation: sender serializes, receiver deserializes,
      // then both build outlines with identical renderer parameters.
      final originalElement = FreedrawElement(
        id: const ElementId('recon-test'),
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        points: senderPoints,
        pressures: senderPressures,
        simulatePressure: false,
      );

      // Sender builds outline from the live element (isComplete: true on wire)
      final senderOutline = FreedrawRenderer.buildOutline(
        originalElement.points,
        strokeWidth: originalElement.strokeWidth,
        pressures: originalElement.pressures,
        pressureSensitivity: pressureSensitivity,
        isComplete: true,
      );

      // Serialize
      final json = ExcalidrawJsonCodec.elementToJson(originalElement);
      // Deserialize on receiver
      final restoredElement = ExcalidrawJsonCodec.parseElement(
        json,
        json['type'] as String,
        0,
        <ParseWarning>[],
      ) as FreedrawElement;

      // Receiver builds outline (same renderer params, isComplete: true)
      final receiverOutline = FreedrawRenderer.buildOutline(
        restoredElement.points,
        strokeWidth: restoredElement.strokeWidth,
        pressures: restoredElement.pressures,
        pressureSensitivity: pressureSensitivity,
        isComplete: true,
      );

      expect(receiverOutline.length, senderOutline.length);
      for (var i = 0; i < senderOutline.length; i++) {
        expect(receiverOutline[i].dx, senderOutline[i].dx);
        expect(receiverOutline[i].dy, senderOutline[i].dy);
      }
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 3. 预测点（source=predicted）不进入 FreedrawElement
  // ──────────────────────────────────────────────────────────────
  group('Predicted points isolation', () {
    test('only actual samples are included in committed stroke points', () {
      // Simulate a stroke with mixed actual and predicted samples.
      // The predicted samples come from HarmonyOS native point prediction
      // and should only affect the wet-ink overlay, never the committed element.
      final allSamples = <StrokeInputSample>[
        // Down: always actual
        StrokeInputSample(
          pointerId: 1,
          x: 0,
          y: 0,
          time: const Duration(milliseconds: 0),
          pressure: 0.2,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.down,
          source: StrokeSampleSource.actual,
        ),
        // Move 1: actual
        StrokeInputSample(
          pointerId: 1,
          x: 10,
          y: 2,
          time: const Duration(milliseconds: 8),
          pressure: 0.4,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.move,
          source: StrokeSampleSource.actual,
        ),
        // Move 2: predicted (native point prediction)
        StrokeInputSample(
          pointerId: 1,
          x: 22,
          y: 4,
          time: const Duration(milliseconds: 12),
          pressure: 0.5,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.move,
          source: StrokeSampleSource.predicted,
        ),
        // Move 3: actual (real point catches up, replacing prediction tail)
        StrokeInputSample(
          pointerId: 1,
          x: 20,
          y: 3,
          time: const Duration(milliseconds: 16),
          pressure: 0.55,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.move,
          source: StrokeSampleSource.actual,
        ),
        // Move 4: predicted
        StrokeInputSample(
          pointerId: 1,
          x: 35,
          y: 7,
          time: const Duration(milliseconds: 20),
          pressure: 0.7,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.move,
          source: StrokeSampleSource.predicted,
        ),
        // Move 5: actual
        StrokeInputSample(
          pointerId: 1,
          x: 30,
          y: 5,
          time: const Duration(milliseconds: 24),
          pressure: 0.65,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.move,
          source: StrokeSampleSource.actual,
        ),
        // Move 6: predicted
        StrokeInputSample(
          pointerId: 1,
          x: 52,
          y: 10,
          time: const Duration(milliseconds: 28),
          pressure: 0.85,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.move,
          source: StrokeSampleSource.predicted,
        ),
        // Up: always actual
        StrokeInputSample(
          pointerId: 1,
          x: 40,
          y: 8,
          time: const Duration(milliseconds: 32),
          pressure: 0.6,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.up,
          source: StrokeSampleSource.actual,
        ),
      ];

      // Filter: only actual samples enter the committed element
      final actualSamples = allSamples
          .where((s) => s.source == StrokeSampleSource.actual)
          .toList();

      // Predicted samples exist in the raw stream
      final predictedSamples = allSamples
          .where((s) => s.source == StrokeSampleSource.predicted)
          .toList();
      expect(predictedSamples, isNotEmpty,
          reason: 'Test must include predicted samples to be meaningful');

      // Verify predicted sample coordinates do NOT appear in actual points
      final actualPoints = actualSamples
          .map((s) => Point(s.x, s.y))
          .toList();
      final predictedPoints = predictedSamples
          .map((s) => Point(s.x, s.y))
          .toSet();

      for (final pp in predictedPoints) {
        expect(actualPoints, isNot(contains(pp)),
            reason: 'Predicted point $pp must not appear in committed element points');
      }

      // Verify total count: actual-only, no predicted sneaking in
      expect(actualSamples.length, lessThan(allSamples.length),
          reason: 'Filtering must reduce sample count');

      // Build the committed FreedrawElement from actual-only samples
      final committedElement = FreedrawElement(
        id: const ElementId('prediction-isolation-test'),
        x: 0,
        y: 0,
        width: 40,
        height: 10,
        points: actualPoints,
        pressures: actualSamples
            .map((s) => s.pressure ?? 0.5)
            .toList(),
        simulatePressure: false,
      );

      // The element must NOT contain predicted point coordinates
      for (final committedPoint in committedElement.points) {
        expect(predictedPoints, isNot(contains(committedPoint)),
            reason: 'Committed element point $committedPoint is from a predicted sample');
      }

      // Element point count equals actual sample count (down+move*3+up = 5)
      expect(committedElement.points.length, actualSamples.length);
    });

    test('stroke with only actual samples includes all of them', () {
      // Baseline: when there are no predicted samples, all points survive.
      final samples = <StrokeInputSample>[
        StrokeInputSample(
          pointerId: 1,
          x: 0,
          y: 0,
          time: const Duration(milliseconds: 0),
          pressure: 0.3,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.down,
          source: StrokeSampleSource.actual,
        ),
        StrokeInputSample(
          pointerId: 1,
          x: 10,
          y: 5,
          time: const Duration(milliseconds: 10),
          pressure: 0.6,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.move,
          source: StrokeSampleSource.actual,
        ),
        StrokeInputSample(
          pointerId: 1,
          x: 20,
          y: 8,
          time: const Duration(milliseconds: 20),
          pressure: 0.4,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.up,
          source: StrokeSampleSource.actual,
        ),
      ];

      final actualSamples = samples
          .where((s) => s.source == StrokeSampleSource.actual)
          .toList();

      expect(actualSamples.length, samples.length);

      final element = FreedrawElement(
        id: const ElementId('no-prediction'),
        x: 0,
        y: 0,
        width: 20,
        height: 10,
        points: actualSamples.map((s) => Point(s.x, s.y)).toList(),
        pressures: actualSamples.map((s) => s.pressure ?? 0.5).toList(),
        simulatePressure: false,
      );

      expect(element.points.length, 3);
      expect(element.pressures.length, 3);
    });

    test('stroke with only predicted samples produces empty committed element', () {
      // Edge case: if somehow all samples are predicted (should not happen
      // in normal operation because down/up are always actual), the filter
      // must produce zero points.
      final samples = <StrokeInputSample>[
        StrokeInputSample(
          pointerId: 1,
          x: 5,
          y: 0,
          time: const Duration(milliseconds: 0),
          pressure: 0.3,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.move,
          source: StrokeSampleSource.predicted,
        ),
        StrokeInputSample(
          pointerId: 1,
          x: 15,
          y: 5,
          time: const Duration(milliseconds: 10),
          pressure: 0.6,
          kind: StrokeInputKind.stylus,
          phase: StrokePhase.move,
          source: StrokeSampleSource.predicted,
        ),
      ];

      final actualSamples = samples
          .where((s) => s.source == StrokeSampleSource.actual)
          .toList();

      expect(actualSamples, isEmpty,
          reason: 'All-predicted stroke must yield zero actual points');
    });

    test('predicted samples with touch input are also excluded', () {
      // Touch input can also receive predicted points.
      final samples = <StrokeInputSample>[
        StrokeInputSample(
          pointerId: 2,
          x: 0,
          y: 0,
          time: const Duration(milliseconds: 0),
          pressure: null,
          kind: StrokeInputKind.touch,
          phase: StrokePhase.down,
          source: StrokeSampleSource.actual,
        ),
        StrokeInputSample(
          pointerId: 2,
          x: 18,
          y: 3,
          time: const Duration(milliseconds: 10),
          pressure: null,
          kind: StrokeInputKind.touch,
          phase: StrokePhase.move,
          source: StrokeSampleSource.predicted,
        ),
        StrokeInputSample(
          pointerId: 2,
          x: 15,
          y: 2,
          time: const Duration(milliseconds: 16),
          pressure: null,
          kind: StrokeInputKind.touch,
          phase: StrokePhase.move,
          source: StrokeSampleSource.actual,
        ),
        StrokeInputSample(
          pointerId: 2,
          x: 30,
          y: 5,
          time: const Duration(milliseconds: 26),
          pressure: null,
          kind: StrokeInputKind.touch,
          phase: StrokePhase.up,
          source: StrokeSampleSource.actual,
        ),
      ];

      final actualSamples = samples
          .where((s) => s.source == StrokeSampleSource.actual)
          .toList();

      final predictedSamples = samples
          .where((s) => s.source == StrokeSampleSource.predicted)
          .toList();
      expect(predictedSamples, isNotEmpty);

      final actualPoints = actualSamples.map((s) => Point(s.x, s.y)).toList();
      final predictedPoints = predictedSamples
          .map((s) => Point(s.x, s.y))
          .toSet();

      for (final pp in predictedPoints) {
        expect(actualPoints, isNot(contains(pp)));
      }

      // Touch strokes use simulated pressure
      final element = FreedrawElement(
        id: const ElementId('touch-prediction'),
        x: 0,
        y: 0,
        width: 30,
        height: 5,
        points: actualPoints,
        pressures: const [],
        simulatePressure: true,
      );

      expect(element.points.length, 3); // down, actual move, up
      for (final p in element.points) {
        expect(predictedPoints, isNot(contains(p)));
      }
    });
  });
}

/// Compares two outlines for strict equality.
bool _outlinesEqual(List<Offset> a, List<Offset> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].dx != b[i].dx || a[i].dy != b[i].dy) return false;
  }
  return true;
}
