import 'dart:math' as dm;
import 'dart:ui';

import '../../core/math/math.dart';
import 'draw_style.dart';

/// Renders freehand drawing paths.
///
/// 当有真实压感([pressures] 非空)时,逐段按压感缩放宽度画出变粗笔迹;
/// 无压感时退化回平滑等粗 Bezier 曲线(向后兼容鼠标/触摸输入)。
class FreedrawRenderer {
  /// 压感有效时的最小宽度倍率(防止 pressure 极小时笔迹断开)。
  static const _minWidthScale = 0.15;

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
  ///
  /// 当 [pressures] 非空且长度匹配 points 时,用压感驱动每段宽度(变粗笔迹);
  /// 否则退化回等粗 Bezier 路径。
  static void draw(
    Canvas canvas,
    List<Point> points,
    DrawStyle style, {
    List<double>? pressures,
  }) {
    if (points.isEmpty) return;

    final basePaint = style.toStrokePaint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 有真压感且数量匹配 → 变粗渲染
    if (pressures != null && pressures.length == points.length && pressures.length >= 2) {
      _drawVariableWidth(canvas, points, pressures, basePaint, style.strokeWidth);
      return;
    }

    // 无压感 → 等粗 Bezier(原行为,兼容鼠标/触摸)
    final path = buildPath(points, style.strokeWidth);
    canvas.drawPath(path, basePaint);
  }

  /// 逐段按相邻点平均压感缩放宽度画线。
  /// 接缝靠 StrokeCap.round 缓解;后续可升级为 perfect-freehand 多边形。
  static void _drawVariableWidth(
    Canvas canvas,
    List<Point> points,
    List<double> pressures,
    Paint basePaint,
    double baseWidth,
  ) {
    // 单点:画一个按压感缩放的圆点
    if (points.length == 1) {
      final p = points[0];
      final w = _widthForPressure(pressures[0], baseWidth);
      canvas.drawCircle(Offset(p.x, p.y), w / 2, basePaint..strokeWidth = w);
      return;
    }

    for (var i = 0; i < points.length - 1; i++) {
      final avgPressure = (pressures[i] + pressures[i + 1]) / 2;
      final width = _widthForPressure(avgPressure, baseWidth);
      basePaint.strokeWidth = width;
      canvas.drawLine(
        Offset(points[i].x, points[i].y),
        Offset(points[i + 1].x, points[i + 1].y),
        basePaint,
      );
    }
  }

  /// 把压感(0.0~1.0)映射到实际像素宽度。
  /// 用 sqrt 做非线性映射,让轻压也有可见宽度,重压不至于过粗。
  static double _widthForPressure(double pressure, double baseWidth) {
    final clamped = pressure.clamp(0.0, 1.0);
    final scale = _minWidthScale + (1.0 - _minWidthScale) * dm.sqrt(clamped);
    return baseWidth * scale;
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
