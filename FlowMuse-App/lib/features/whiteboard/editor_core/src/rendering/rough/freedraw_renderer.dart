import 'dart:math' as math;
import 'dart:ui';

import '../../core/math/math.dart';
import '../../core/elements/brush_type.dart';
import '../../input/outline_render_mode.dart';
import '../../input/stroke_render_metrics.dart';
import 'draw_style.dart';
import 'pencil_shader.dart';
import 'saber_stroke_geometry.dart';

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
    bool isComplete = true,
    BrushType brushType = BrushType.fountainPen,
  }) {
    return SaberStrokeGeometry.outline(
      points,
      strokeWidth: strokeWidth,
      pressures: pressures,
      brushType: brushType,
      pressureSensitivity: pressureSensitivity,
      isComplete: isComplete,
    );
  }

  /// Constructs a closed [Path] from a perfect_freehand outline.
  ///
  /// - [polygon]: straight-line segments (baseline/control).
  /// - [quadratic]: official quadratic midpoint method -- each outline point
  ///   (including outline[0]) serves as a control point, with the midpoint of
  ///   adjacent vertices as endpoints. The last-to-first seam is handled via
  ///   modulo wrapping so no control segment is missed.
  static Path buildOutlinePath(
    List<Offset> outline,
    OutlineRenderMode mode,
  ) {
    return SaberStrokeGeometry.pathFromOutline(
      outline,
      mode,
      isComplete: true,
    );
  }

  /// Measures the same outline and Path construction used by [draw], without
  /// submitting paint commands. Intended for debug/test replay parameter sweeps.
  static StrokeRenderMetrics measureStroke(
    List<Point> points, {
    required double strokeWidth,
    List<double>? pressures,
    double pressureSensitivity = 0.7,
    bool isComplete = true,
    required OutlineRenderMode outlineRenderMode,
  }) {
    final outlineWatch = Stopwatch()..start();
    final outline = buildOutline(
      points,
      strokeWidth: strokeWidth,
      pressures: pressures,
      pressureSensitivity: pressureSensitivity,
      isComplete: isComplete,
    );
    final getStrokeDuration = (outlineWatch..stop()).elapsed;
    final pathWatch = Stopwatch()..start();
    buildOutlinePath(outline, outlineRenderMode);
    final pathBuildDuration = (pathWatch..stop()).elapsed;
    return StrokeRenderMetrics(
      outlinePointCount: outline.length,
      getStrokeDuration: getStrokeDuration,
      pathBuildDuration: pathBuildDuration,
    );
  }

  /// Draws a freehand path on [canvas] with the given [style].
  ///
  /// 优先用 perfect_freehand 的 outline-stroke 算法渲染(平滑+变粗);
  /// pressures 数量与 points 不匹配时退回等粗 Bezier(容错)。
  /// [outlineRenderMode] 控制轮廓路径构建方式: polygon(直线段)或 quadratic(二次贝塞尔平滑)。
  static void draw(
    Canvas canvas,
    List<Point> points,
    DrawStyle style, {
    List<double>? pressures,
    double pressureSensitivity = 0.7,
    bool isComplete = true,
    required OutlineRenderMode outlineRenderMode,
    StrokeRenderMetricsSink? metricsSink,
    BrushType brushType = BrushType.fountainPen,
  }) {
    if (points.isEmpty) return;

    final brush = SaberBrushConfig.forType(brushType);
    // perfect_freehand 的 size 是直径,而 DrawStyle.strokeWidth 在 freedraw 语境下
    // 是期望的笔迹宽度。直接用 strokeWidth 作为 size 基准。
    final size = math.max(style.strokeWidth * brush.sizeScale, 1.0);

    Stopwatch? outlineWatch;
    if (metricsSink != null) {
      outlineWatch = Stopwatch()..start();
    }
    final outline = buildOutline(
      points,
      strokeWidth: style.strokeWidth,
      pressures: pressures,
      pressureSensitivity: pressureSensitivity,
      isComplete: isComplete,
      brushType: brushType,
    );
    final getStrokeDuration = outlineWatch != null
        ? (outlineWatch..stop()).elapsed
        : Duration.zero;

    // 单点(点击):outline 为空,画圆点
    if (outline.isEmpty) {
      final p = points[0];
      final paint = style.toStrokePaint()
        ..style = PaintingStyle.fill
        ..color = style.toStrokePaint().color.withValues(
          alpha: style.toStrokePaint().color.a * brush.opacityScale,
        );
      canvas.drawCircle(Offset(p.x, p.y), size / 2, paint);
      return;
    }

    // outline 是闭合多边形顶点,用 fill 绘制
    Stopwatch? sw;
    if (metricsSink != null) {
      sw = Stopwatch()..start();
    }
    final path = SaberStrokeGeometry.pathFromOutline(
      outline,
      outlineRenderMode,
      isComplete: isComplete,
    );
    final pathBuildDuration = sw != null ? (sw..stop()).elapsed : Duration.zero;
    final basePaint = style.toStrokePaint();
    final paint = basePaint
      ..style = PaintingStyle.fill
      ..color = basePaint.color.withValues(
        alpha: basePaint.color.a * brush.opacityScale,
      );

    // 铅笔纹理：如果平台支持 shader，用 FragmentShader 叠加纸张纹理（参考 Saber）
    if (brushType == BrushType.pencil && PencilShader.isAvailable) {
      final shader = PencilShader.create()!;
      final c = paint.color;
      shader
        ..setFloat(0, c.r)
        ..setFloat(1, c.g)
        ..setFloat(2, c.b);
      paint.shader = shader;
      paint.color = const Color(0xFFFFFFFF); // shader 负责着色
    }

    canvas.drawPath(path, paint);
    metricsSink?.onMetrics(
      StrokeRenderMetrics(
        outlinePointCount: outline.length,
        getStrokeDuration: getStrokeDuration,
        pathBuildDuration: pathBuildDuration,
      ),
    );
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
