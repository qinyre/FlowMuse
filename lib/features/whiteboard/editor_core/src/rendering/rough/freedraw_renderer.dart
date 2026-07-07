import 'dart:ui';

import '../../core/math/math.dart';
import 'draw_style.dart';

/// Renders freehand drawing paths with smooth Bezier interpolation.
///
/// This does not use rough_flutter — freehand strokes are inherently
/// hand-drawn and don't need additional wobble.
class FreedrawRenderer {
  /// Builds a smooth [Path] through the given freehand [points].
  ///
  /// - Empty list: returns empty Path
  /// - Single point: returns a small circle (dot)
  /// - Two points: returns a straight line
  /// - Three+ points: returns a smooth cubic Bezier curve
  static Path buildPath(List<Point> points, double strokeWidth) {
    if (points.isEmpty) return Path();

    if (points.length == 1) {
      final p = points[0];
      final r = strokeWidth * 0.5;
      return Path()
        ..addOval(Rect.fromCircle(center: Offset(p.x, p.y), radius: r));
    }

    if (points.length == 2) {
      return Path()
        ..moveTo(points[0].x, points[0].y)
        ..lineTo(points[1].x, points[1].y);
    }

    return _buildBezierPath(points);
  }

  /// Draws a freehand path on [canvas] with the given [style].
  static void draw(Canvas canvas, List<Point> points, DrawStyle style) {
    if (points.isEmpty) return;

    final path = buildPath(points, style.strokeWidth);
    final paint = style.toStrokePaint();
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  /// Builds a smooth cubic Bezier path through 3+ points using
  /// Catmull-Rom to cubic Bezier conversion.
  static Path _buildBezierPath(List<Point> points) {
    final path = Path()..moveTo(points[0].x, points[0].y);

    // For each segment between consecutive points, compute cubic Bezier
    // control points using Catmull-Rom interpolation.
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      // Catmull-Rom to cubic Bezier control points
      final cp1x = p1.x + (p2.x - p0.x) / 6;
      final cp1y = p1.y + (p2.y - p0.y) / 6;
      final cp2x = p2.x - (p3.x - p1.x) / 6;
      final cp2y = p2.y - (p3.y - p1.y) / 6;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y);
    }

    return path;
  }
}
