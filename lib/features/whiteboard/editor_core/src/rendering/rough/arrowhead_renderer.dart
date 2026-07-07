import 'dart:math' as math;
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';

/// Renders arrowhead shapes at line endpoints.
///
/// Sizes and geometry match Excalidraw's implementation:
/// fixed pixel sizes per type, 20° angle for arrow chevron,
/// 25° for triangle/diamond/crowfoot, circle centered on tip.
class ArrowheadRenderer {
  /// Half-angle for arrow chevron (20°).
  static const double _arrowHalfAngle = 0.349;

  /// Half-angle for triangle, diamond, crowfoot (25°).
  static const double _defaultHalfAngle = 0.436;

  /// Fixed pixel sizes per arrowhead type, matching Excalidraw.
  static double _baseSize(Arrowhead type) {
    return switch (type) {
      Arrowhead.arrow => 25.0,
      Arrowhead.diamond || Arrowhead.diamondOutline => 12.0,
      Arrowhead.crowfootOne ||
      Arrowhead.crowfootMany ||
      Arrowhead.crowfootOneOrMany => 20.0,
      _ => 15.0, // bar, triangle, triangleOutline, dot, circle, circleOutline
    };
  }

  /// Computes the direction angle at a line endpoint.
  ///
  /// For [isStart] = true, returns the angle from the second point toward
  /// the first (i.e., the incoming direction at the start).
  /// For [isStart] = false, returns the angle from the second-to-last point
  /// toward the last (i.e., the outgoing direction at the end).
  ///
  /// Returns 0.0 for single-point or coincident-point cases.
  static double directionAngle(List<Point> points, {required bool isStart}) {
    if (points.length < 2) return 0.0;

    final Point from;
    final Point to;
    if (isStart) {
      from = points[1];
      to = points[0];
    } else {
      from = points[points.length - 2];
      to = points[points.length - 1];
    }

    final dx = to.x - from.x;
    final dy = to.y - from.y;
    if (dx == 0 && dy == 0) return 0.0;

    return math.atan2(dy, dx);
  }

  /// Builds a [Path] for the given arrowhead type at the given tip point.
  ///
  /// [angle] is the direction the arrow is pointing (in radians).
  /// [strokeWidth] is used for circle diameter calculation.
  static Path buildPath(
    Arrowhead type,
    Point tip,
    double angle,
    double strokeWidth,
  ) {
    final size = _baseSize(type);
    return switch (type) {
      Arrowhead.arrow => _buildArrowPath(tip, angle, size),
      Arrowhead.triangle => _buildTrianglePath(tip, angle, size),
      Arrowhead.triangleOutline => _buildTrianglePath(tip, angle, size),
      Arrowhead.bar => _buildBarPath(tip, angle, size),
      Arrowhead.dot => _buildCirclePath(tip, size, strokeWidth),
      Arrowhead.circle => _buildCirclePath(tip, size, strokeWidth),
      Arrowhead.circleOutline => _buildCirclePath(tip, size, strokeWidth),
      Arrowhead.diamond => _buildDiamondPath(tip, angle, size),
      Arrowhead.diamondOutline => _buildDiamondPath(tip, angle, size),
      Arrowhead.crowfootOne => _buildCrowfootOnePath(tip, angle, size),
      Arrowhead.crowfootMany => _buildCrowfootManyPath(tip, angle, size),
      Arrowhead.crowfootOneOrMany => _buildCrowfootOneOrManyPath(
        tip,
        angle,
        size,
      ),
    };
  }

  /// Open chevron: two lines from tip at 20° angle.
  static Path _buildArrowPath(Point tip, double angle, double size) {
    final backAngle = angle + math.pi;
    final arm1X = tip.x + size * math.cos(backAngle + _arrowHalfAngle);
    final arm1Y = tip.y + size * math.sin(backAngle + _arrowHalfAngle);
    final arm2X = tip.x + size * math.cos(backAngle - _arrowHalfAngle);
    final arm2Y = tip.y + size * math.sin(backAngle - _arrowHalfAngle);

    return Path()
      ..moveTo(arm1X, arm1Y)
      ..lineTo(tip.x, tip.y)
      ..lineTo(arm2X, arm2Y);
  }

  /// Filled/outline triangle: three-point closed polygon at 25°.
  static Path _buildTrianglePath(Point tip, double angle, double size) {
    final backAngle = angle + math.pi;
    final arm1X = tip.x + size * math.cos(backAngle + _defaultHalfAngle);
    final arm1Y = tip.y + size * math.sin(backAngle + _defaultHalfAngle);
    final arm2X = tip.x + size * math.cos(backAngle - _defaultHalfAngle);
    final arm2Y = tip.y + size * math.sin(backAngle - _defaultHalfAngle);

    return Path()
      ..moveTo(tip.x, tip.y)
      ..lineTo(arm1X, arm1Y)
      ..lineTo(arm2X, arm2Y)
      ..close();
  }

  /// Perpendicular bar across the endpoint.
  static Path _buildBarPath(Point tip, double angle, double size) {
    final perpAngle = angle + math.pi / 2;
    final halfSize = size * 0.5;
    final x1 = tip.x + halfSize * math.cos(perpAngle);
    final y1 = tip.y + halfSize * math.sin(perpAngle);
    final x2 = tip.x - halfSize * math.cos(perpAngle);
    final y2 = tip.y - halfSize * math.sin(perpAngle);

    return Path()
      ..moveTo(x1, y1)
      ..lineTo(x2, y2);
  }

  /// Circle centered on the tip. Diameter = size + strokeWidth - 2
  /// (matches Excalidraw).
  static Path _buildCirclePath(Point tip, double size, double strokeWidth) {
    final radius = (size + strokeWidth - 2) / 2;
    return Path()
      ..addOval(Rect.fromCircle(center: Offset(tip.x, tip.y), radius: radius));
  }

  /// Diamond (4-point polygon): tip → right → back → left.
  ///
  /// Back vertex at size × 2 from tip; side vertices at ±25° from tip.
  static Path _buildDiamondPath(Point tip, double angle, double size) {
    final backAngle = angle + math.pi;

    // Back vertex: offset backward by size × 2
    final backX = tip.x + size * 2 * math.cos(backAngle);
    final backY = tip.y + size * 2 * math.sin(backAngle);

    // Side vertices: tip rotated ±25° around mid-point (at size back)
    final midX = tip.x + size * math.cos(backAngle);
    final midY = tip.y + size * math.sin(backAngle);
    final leftX = _rotateX(tip.x, tip.y, midX, midY, _defaultHalfAngle);
    final leftY = _rotateY(tip.x, tip.y, midX, midY, _defaultHalfAngle);
    final rightX = _rotateX(tip.x, tip.y, midX, midY, -_defaultHalfAngle);
    final rightY = _rotateY(tip.x, tip.y, midX, midY, -_defaultHalfAngle);

    return Path()
      ..moveTo(tip.x, tip.y)
      ..lineTo(rightX, rightY)
      ..lineTo(backX, backY)
      ..lineTo(leftX, leftY)
      ..close();
  }

  /// Crow's foot "one": bar connecting tip rotated ±25° around base.
  static Path _buildCrowfootOnePath(Point tip, double angle, double size) {
    final backAngle = angle + math.pi;
    // Base point offset backward from tip by size
    final baseX = tip.x + size * math.cos(backAngle);
    final baseY = tip.y + size * math.sin(backAngle);
    // Rotate tip around base by ±25°
    final x1 = _rotateX(tip.x, tip.y, baseX, baseY, -_defaultHalfAngle);
    final y1 = _rotateY(tip.x, tip.y, baseX, baseY, -_defaultHalfAngle);
    final x2 = _rotateX(tip.x, tip.y, baseX, baseY, _defaultHalfAngle);
    final y2 = _rotateY(tip.x, tip.y, baseX, baseY, _defaultHalfAngle);

    return Path()
      ..moveTo(x1, y1)
      ..lineTo(x2, y2);
  }

  /// Crow's foot "many": V-fork — two lines from base to tip rotated ±25°.
  static Path _buildCrowfootManyPath(Point tip, double angle, double size) {
    final backAngle = angle + math.pi;
    // Base point offset backward from tip by size
    final baseX = tip.x + size * math.cos(backAngle);
    final baseY = tip.y + size * math.sin(backAngle);
    // Rotate tip around base by ±25°
    final armX1 = _rotateX(tip.x, tip.y, baseX, baseY, -_defaultHalfAngle);
    final armY1 = _rotateY(tip.x, tip.y, baseX, baseY, -_defaultHalfAngle);
    final armX2 = _rotateX(tip.x, tip.y, baseX, baseY, _defaultHalfAngle);
    final armY2 = _rotateY(tip.x, tip.y, baseX, baseY, _defaultHalfAngle);

    return Path()
      ..moveTo(armX1, armY1)
      ..lineTo(baseX, baseY)
      ..lineTo(armX2, armY2);
  }

  /// Crow's foot "one or many": V-fork + bar.
  static Path _buildCrowfootOneOrManyPath(
    Point tip,
    double angle,
    double size,
  ) {
    final manyPath = _buildCrowfootManyPath(tip, angle, size);
    final onePath = _buildCrowfootOnePath(tip, angle, size);
    return manyPath..addPath(onePath, Offset.zero);
  }

  /// Rotates point (px, py) around center (cx, cy) by [radians].
  /// Returns the new x coordinate.
  static double _rotateX(
    double px,
    double py,
    double cx,
    double cy,
    double radians,
  ) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return cx + (px - cx) * cos - (py - cy) * sin;
  }

  /// Rotates point (px, py) around center (cx, cy) by [radians].
  /// Returns the new y coordinate.
  static double _rotateY(
    double px,
    double py,
    double cx,
    double cy,
    double radians,
  ) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return cy + (px - cx) * sin + (py - cy) * cos;
  }

  /// The set of arrowhead types that are drawn with fill style.
  static const _filledTypes = {
    Arrowhead.triangle,
    Arrowhead.dot,
    Arrowhead.circle,
    Arrowhead.diamond,
  };

  /// Draws an arrowhead on the canvas.
  static void draw(
    Canvas canvas,
    Arrowhead type,
    Point tip,
    double angle,
    double strokeWidth,
    Paint paint,
  ) {
    final path = buildPath(type, tip, angle, strokeWidth);
    if (_filledTypes.contains(type)) {
      canvas.drawPath(path, paint..style = PaintingStyle.fill);
    } else {
      canvas.drawPath(path, paint..style = PaintingStyle.stroke);
    }
  }
}
