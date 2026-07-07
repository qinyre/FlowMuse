import 'dart:math' as math;

import 'package:rough_flutter/rough_flutter.dart';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';

/// Converts rough_flutter operations and geometry to SVG path `d` attribute strings.
class SvgPathConverter {
  /// Converts an [OpSet]'s operations to an SVG path `d` attribute.
  ///
  /// Maps OpType.move → M, OpType.lineTo → L, OpType.curveTo → C.
  static String opSetToPathData(OpSet opSet) {
    final buf = StringBuffer();
    for (final op in opSet.ops) {
      switch (op.op) {
        case OpType.move:
          buf.write('M${_n(op.data[0].x)} ${_n(op.data[0].y)}');
        case OpType.lineTo:
          buf.write('L${_n(op.data[0].x)} ${_n(op.data[0].y)}');
        case OpType.curveTo:
          buf.write(
            'C${_n(op.data[0].x)} ${_n(op.data[0].y)} '
            '${_n(op.data[1].x)} ${_n(op.data[1].y)} '
            '${_n(op.data[2].x)} ${_n(op.data[2].y)}',
          );
      }
    }
    return buf.toString();
  }

  /// Converts arrowhead geometry to an SVG path `d` attribute.
  ///
  /// Uses the same math as [ArrowheadRenderer.buildPath].
  static String arrowheadToPathData(
    Arrowhead type,
    Point tip,
    double angle,
    double strokeWidth,
  ) {
    final size = _baseSize(type);
    return switch (type) {
      Arrowhead.arrow => _arrowPath(tip, angle, size),
      Arrowhead.triangle => _trianglePath(tip, angle, size),
      Arrowhead.triangleOutline => _trianglePath(tip, angle, size),
      Arrowhead.bar => _barPath(tip, angle, size),
      Arrowhead.dot => _circlePath(tip, size, strokeWidth),
      Arrowhead.circle => _circlePath(tip, size, strokeWidth),
      Arrowhead.circleOutline => _circlePath(tip, size, strokeWidth),
      Arrowhead.diamond => _diamondPath(tip, angle, size),
      Arrowhead.diamondOutline => _diamondPath(tip, angle, size),
      Arrowhead.crowfootOne => _crowfootOnePath(tip, angle, size),
      Arrowhead.crowfootMany => _crowfootManyPath(tip, angle, size),
      Arrowhead.crowfootOneOrMany => _crowfootOneOrManyPath(tip, angle, size),
    };
  }

  /// Converts freehand draw points to an SVG path `d` attribute.
  ///
  /// Uses the same Catmull-Rom → cubic Bezier logic as [FreedrawRenderer].
  static String freedrawToPathData(List<Point> points, double strokeWidth) {
    if (points.isEmpty) return '';

    if (points.length == 1) {
      // Small circle (dot) — approximate with arcs
      final p = points[0];
      final r = strokeWidth * 0.5;
      return 'M${_n(p.x - r)} ${_n(p.y)}'
          'A${_n(r)} ${_n(r)} 0 1 0 ${_n(p.x + r)} ${_n(p.y)}'
          'A${_n(r)} ${_n(r)} 0 1 0 ${_n(p.x - r)} ${_n(p.y)}';
    }

    if (points.length == 2) {
      return 'M${_n(points[0].x)} ${_n(points[0].y)}'
          'L${_n(points[1].x)} ${_n(points[1].y)}';
    }

    // 3+ points: Catmull-Rom → cubic Bezier
    final buf = StringBuffer('M${_n(points[0].x)} ${_n(points[0].y)}');
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      final cp1x = p1.x + (p2.x - p0.x) / 6;
      final cp1y = p1.y + (p2.y - p0.y) / 6;
      final cp2x = p2.x - (p3.x - p1.x) / 6;
      final cp2y = p2.y - (p3.y - p1.y) / 6;

      buf.write(
        'C${_n(cp1x)} ${_n(cp1y)} '
        '${_n(cp2x)} ${_n(cp2y)} '
        '${_n(p2.x)} ${_n(p2.y)}',
      );
    }
    return buf.toString();
  }

  // -- Size and angle constants matching Excalidraw --

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
      _ => 15.0,
    };
  }

  // -- Arrowhead path builders (same math as ArrowheadRenderer) --

  static String _arrowPath(Point tip, double angle, double size) {
    final backAngle = angle + math.pi;
    final arm1X = tip.x + size * math.cos(backAngle + _arrowHalfAngle);
    final arm1Y = tip.y + size * math.sin(backAngle + _arrowHalfAngle);
    final arm2X = tip.x + size * math.cos(backAngle - _arrowHalfAngle);
    final arm2Y = tip.y + size * math.sin(backAngle - _arrowHalfAngle);

    return 'M${_n(arm1X)} ${_n(arm1Y)}'
        'L${_n(tip.x)} ${_n(tip.y)}'
        'L${_n(arm2X)} ${_n(arm2Y)}';
  }

  static String _trianglePath(Point tip, double angle, double size) {
    final backAngle = angle + math.pi;
    final arm1X = tip.x + size * math.cos(backAngle + _defaultHalfAngle);
    final arm1Y = tip.y + size * math.sin(backAngle + _defaultHalfAngle);
    final arm2X = tip.x + size * math.cos(backAngle - _defaultHalfAngle);
    final arm2Y = tip.y + size * math.sin(backAngle - _defaultHalfAngle);

    return 'M${_n(tip.x)} ${_n(tip.y)}'
        'L${_n(arm1X)} ${_n(arm1Y)}'
        'L${_n(arm2X)} ${_n(arm2Y)}Z';
  }

  static String _barPath(Point tip, double angle, double size) {
    final perpAngle = angle + math.pi / 2;
    final halfSize = size * 0.5;
    final x1 = tip.x + halfSize * math.cos(perpAngle);
    final y1 = tip.y + halfSize * math.sin(perpAngle);
    final x2 = tip.x - halfSize * math.cos(perpAngle);
    final y2 = tip.y - halfSize * math.sin(perpAngle);

    return 'M${_n(x1)} ${_n(y1)}L${_n(x2)} ${_n(y2)}';
  }

  static String _circlePath(Point tip, double size, double strokeWidth) {
    final radius = (size + strokeWidth - 2) / 2;
    // Circle via two half-arcs, centered on tip
    return 'M${_n(tip.x - radius)} ${_n(tip.y)}'
        'A${_n(radius)} ${_n(radius)} 0 1 0 ${_n(tip.x + radius)} ${_n(tip.y)}'
        'A${_n(radius)} ${_n(radius)} 0 1 0 ${_n(tip.x - radius)} ${_n(tip.y)}';
  }

  static String _diamondPath(Point tip, double angle, double size) {
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

    return 'M${_n(tip.x)} ${_n(tip.y)}'
        'L${_n(rightX)} ${_n(rightY)}'
        'L${_n(backX)} ${_n(backY)}'
        'L${_n(leftX)} ${_n(leftY)}Z';
  }

  static String _crowfootOnePath(Point tip, double angle, double size) {
    final backAngle = angle + math.pi;
    final baseX = tip.x + size * math.cos(backAngle);
    final baseY = tip.y + size * math.sin(backAngle);
    final x1 = _rotateX(tip.x, tip.y, baseX, baseY, -_defaultHalfAngle);
    final y1 = _rotateY(tip.x, tip.y, baseX, baseY, -_defaultHalfAngle);
    final x2 = _rotateX(tip.x, tip.y, baseX, baseY, _defaultHalfAngle);
    final y2 = _rotateY(tip.x, tip.y, baseX, baseY, _defaultHalfAngle);

    return 'M${_n(x1)} ${_n(y1)}L${_n(x2)} ${_n(y2)}';
  }

  static String _crowfootManyPath(Point tip, double angle, double size) {
    final backAngle = angle + math.pi;
    final baseX = tip.x + size * math.cos(backAngle);
    final baseY = tip.y + size * math.sin(backAngle);
    final armX1 = _rotateX(tip.x, tip.y, baseX, baseY, -_defaultHalfAngle);
    final armY1 = _rotateY(tip.x, tip.y, baseX, baseY, -_defaultHalfAngle);
    final armX2 = _rotateX(tip.x, tip.y, baseX, baseY, _defaultHalfAngle);
    final armY2 = _rotateY(tip.x, tip.y, baseX, baseY, _defaultHalfAngle);

    return 'M${_n(armX1)} ${_n(armY1)}'
        'L${_n(baseX)} ${_n(baseY)}'
        'L${_n(armX2)} ${_n(armY2)}';
  }

  static String _crowfootOneOrManyPath(Point tip, double angle, double size) {
    final many = _crowfootManyPath(tip, angle, size);
    final one = _crowfootOnePath(tip, angle, size);
    return '$many$one';
  }

  /// Rotates point (px, py) around center (cx, cy) by [radians].
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

  /// Formats a number with up to 2 decimal places, stripping trailing zeros.
  static String _n(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    final s = v.toStringAsFixed(2);
    // Strip trailing zeros after decimal
    if (s.contains('.')) {
      var end = s.length;
      while (end > 0 && s[end - 1] == '0') {
        end--;
      }
      if (end > 0 && s[end - 1] == '.') end--;
      return s.substring(0, end);
    }
    return s;
  }
}
