import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart' hide Point;
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';

List<PointVector> poly(int n) => [for (var i = 0; i < n; i++) PointVector(i.toDouble(), (i % 2).toDouble(), 0.5)];

void main() {
  group('FreedrawRenderer.buildOutlinePath', () {
    test('polygon mode closes the path', () {
      final path = FreedrawRenderer.buildOutlinePath(poly(20), OutlineRenderMode.polygon);
      final bounds = path.getBounds();
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(-1)); // non-empty
    });

    test('quadratic mode closes the path and is finite', () {
      final path = FreedrawRenderer.buildOutlinePath(poly(20), OutlineRenderMode.quadratic);
      final bounds = path.getBounds();
      expect(bounds.width.isFinite, isTrue);
      expect(bounds.height.isFinite, isTrue);
      expect(bounds.width, greaterThan(0));
    });

    test('quadratic with < 3 points falls back gracefully (no throw)', () {
      expect(() => FreedrawRenderer.buildOutlinePath(poly(2), OutlineRenderMode.quadratic), returnsNormally);
      expect(() => FreedrawRenderer.buildOutlinePath(poly(1), OutlineRenderMode.quadratic), returnsNormally);
      expect(() => FreedrawRenderer.buildOutlinePath(poly(0), OutlineRenderMode.quadratic), returnsNormally);
    });

    test('no NaN/Infinity in quadratic path bounds', () {
      final path = FreedrawRenderer.buildOutlinePath(poly(50), OutlineRenderMode.quadratic);
      final b = path.getBounds();
      expect(b.left.isNaN, isFalse);
      expect(b.top.isNaN, isFalse);
      expect(b.right.isFinite, isTrue);
      expect(b.bottom.isFinite, isTrue);
    });
  });
}
