import 'dart:math' as dm;
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart' hide Point;

import '../../core/math/math.dart';
import '../../input/outline_render_mode.dart';
import 'draw_style.dart';

/// Renders freehand drawing paths.
///
/// 使用 perfect_freehand 的 outline-stroke 算法:把点序列+压感转成一条
/// 变宽的闭合多边形轮廓,既平滑又自然变粗(Excalidraw/tldraw 同款)。
///
/// - 有真实压感(pressures 非空):simulatePressure=false,用真压感驱动宽度
/// - 无压感(鼠标/触摸):simulatePressure=true,perfect_freehand 用速度模拟
class FreedrawRenderer {
  /// Builds a smooth [Path] through the given freehand [points] (等粗,
  /// 用于无压感退化或外部调用)。
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

  static List<Offset> buildOutline(
    List<Point> points, {
    required double strokeWidth,
    List<double>? pressures,
    double pressureSensitivity = 0.7,
  }) {
    if (points.isEmpty) return const [];

    final hasPressure = pressures != null && pressures.length == points.length;
    final inputPoints = <PointVector>[
      for (var i = 0; i < points.length; i++)
        PointVector(
          points[i].x,
          points[i].y,
          hasPressure ? pressures[i] : null,
        ),
    ];
    final options = StrokeOptions(
      size: dm.max(strokeWidth, 1.0),
      thinning: hasPressure
          ? 0.05 + pressureSensitivity.clamp(0.0, 1.0) * 0.9
          : StrokeOptions.defaultThinning,
      smoothing: StrokeOptions.defaultSmoothing,
      streamline: StrokeOptions.defaultStreamline,
      simulatePressure: !hasPressure,
      isComplete: true,
    );

    return getStroke(inputPoints, options: options);
  }

  /// Constructs a closed [Path] from a perfect_freehand outline.
  ///
  /// - [polygon]: straight-line segments (baseline/control).
  /// - [quadratic]: official quadratic midpoint method -- each outline point
  ///   (including outline[0]) serves as a control point, with the midpoint of
  ///   adjacent vertices as endpoints. The last-to-first seam is handled via
  ///   modulo wrapping so no control segment is missed.
  static Path buildOutlinePath(List<PointVector> outline, OutlineRenderMode mode) {
    if (outline.isEmpty) return Path();
    if (mode == OutlineRenderMode.polygon || outline.length < 3) {
      return Path()
        ..addPolygon(
          [for (final p in outline) Offset(p.x, p.y)],
          true,
        );
    }
    // quadratic: midpoint method. Each vertex (including [0]) is a control
    // point exactly once; the last vertex connects to the first midpoint.
    final path = Path();
    final first = outline.first;
    path.moveTo(first.x, first.y);
    for (var i = 0; i < outline.length; i++) {
      final cur = outline[i];
      final next = outline[(i + 1) % outline.length];
      final midX = (cur.x + next.x) / 2;
      final midY = (cur.y + next.y) / 2;
      path.quadraticBezierTo(cur.x, cur.y, midX, midY);
    }
    path.close();
    return path;
  }

  /// Draws a freehand path on [canvas] with the given [style].
  ///
  /// 优先用 perfect_freehand 的 outline-stroke 算法渲染(平滑+变粗);
  /// pressures 数量与 points 不匹配时退回等粗 Bezier(容错)。
  static void draw(
    Canvas canvas,
    List<Point> points,
    DrawStyle style, {
    List<double>? pressures,
    double pressureSensitivity = 0.7,
  }) {
    if (points.isEmpty) return;

    // perfect_freehand 的 size 是直径,而 DrawStyle.strokeWidth 在 freedraw 语境下
    // 是期望的笔迹宽度。直接用 strokeWidth 作为 size 基准。
    final size = dm.max(style.strokeWidth, 1.0);

    final outline = buildOutline(
      points,
      strokeWidth: size,
      pressures: pressures,
      pressureSensitivity: pressureSensitivity,
    );

    // 单点(点击):outline 为空,画圆点
    if (outline.isEmpty) {
      final p = points[0];
      final paint = style.toStrokePaint()..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), size / 2, paint);
      return;
    }

    // outline 是闭合多边形顶点,用 fill 绘制
    final path = Path()..addPolygon(outline, true);
    final paint = style.toStrokePaint()..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  /// Builds a smooth cubic Bezier path through 3+ points using
  /// Catmull-Rom to cubic Bezier conversion (等粗退化路径用)。
  static Path _buildBezierPath(List<Point> points) {
    final path = Path()..moveTo(points[0].x, points[0].y);

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      final cp1x = p1.x + (p2.x - p0.x) / 6;
      final cp1y = p1.y + (p2.y - p0.y) / 6;
      final cp2x = p2.x - (p3.x - p1.x) / 6;
      final cp2y = p2.y - (p3.y - p1.y) / 6;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y);
    }

    return path;
  }
}
