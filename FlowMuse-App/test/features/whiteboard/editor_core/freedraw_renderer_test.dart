import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
