import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/brush_type.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart' hide Point;

void main() {
  test('measures outline and Path construction for replay metrics', () {
    final metrics = FreedrawRenderer.measureStroke(
      const [Point(0, 0), Point(10, 2), Point(20, 0)],
      strokeWidth: 4,
      outlineRenderMode: OutlineRenderMode.quadratic,
    );

    expect(metrics.outlinePointCount, greaterThan(0));
    expect(metrics.getStrokeDuration, isA<Duration>());
    expect(metrics.pathBuildDuration, isA<Duration>());
  });
  const points = [Point(0, 0), Point(4, 3), Point(8, 2), Point(12, 6)];

  test('builds a finite outline from real pressure samples', () {
    final outline = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 4,
      pressures: const [0.2, 0.4, 0.7, 1.0],
    );

    expect(outline, isNotEmpty);
    expect(
      outline.every((point) => point.dx.isFinite && point.dy.isFinite),
      isTrue,
    );
  });

  test('falls back to simulated pressure when samples are misaligned', () {
    final outline = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 4,
      pressures: const [0.5],
    );

    expect(outline, isNotEmpty);
  });

  test('pressure sensitivity changes the generated outline', () {
    final low = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 4,
      pressures: const [0.2, 0.4, 0.7, 1.0],
      pressureSensitivity: 0,
    );
    final high = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 4,
      pressures: const [0.2, 0.4, 0.7, 1.0],
      pressureSensitivity: 1,
    );

    expect(high, isNot(equals(low)));
  });

  test('fountain pen uses the pre-merge real-pressure curve', () {
    const pressures = [0.2, 0.4, 0.7, 1.0];
    final actual = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 4,
      pressures: pressures,
      pressureSensitivity: 0.7,
      brushType: BrushType.fountainPen,
    );
    final expected = getStroke(
      [
        for (var i = 0; i < points.length; i++)
          PointVector(points[i].x, points[i].y, pressures[i]),
      ],
      options: StrokeOptions(
        size: 4,
        thinning: 0.05 + 0.7 * 0.9,
        smoothing: StrokeOptions.defaultSmoothing,
        streamline: StrokeOptions.defaultStreamline,
        simulatePressure: false,
        isComplete: true,
      ),
    );

    expect(actual, equals(expected));
  });
}
