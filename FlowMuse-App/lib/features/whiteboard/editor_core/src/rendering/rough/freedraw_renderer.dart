import 'dart:math' as dm;
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart' hide Point;

import '../../core/math/math.dart';
import '../../core/elements/brush_type.dart';
import '../../input/outline_render_mode.dart';
import '../../input/stroke_render_metrics.dart';
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
    bool isComplete = true,
    BrushType brushType = BrushType.fountainPen,
  }) {
    if (points.isEmpty) return const [];

    final brush = _configFor(brushType);
    final hasRawPressure =
        pressures != null && pressures.length == points.length;
    // 当笔形关闭压感时，丢弃真实压感数据，始终走模拟（参考 Saber pressureEnabled）。
    final hasPressure = hasRawPressure && brush.pressureEnabled;
    final inputPoints = <PointVector>[
      for (var i = 0; i < points.length; i++)
        PointVector(
          points[i].x,
          points[i].y,
          hasPressure ? pressures[i] : null,
        ),
    ];
    final sensitivity = pressureSensitivity.clamp(0.0, 1.0);
    final simulatePressure =
        !hasPressure || brush.forceSimulatePressure;
    final options = StrokeOptions(
      size: dm.max(strokeWidth * brush.sizeScale, 1.0),
      thinning: hasPressure
          ? switch (brushType) {
              // Keep the established fountain-pen response: a small base
              // pressure term remains even at the lowest sensitivity.
              BrushType.fountainPen => 0.05 + sensitivity * 0.9,
              _ => brush.thinning * sensitivity,
            }
          : brush.simulatedThinning,
      smoothing: brush.smoothing,
      streamline: brush.streamline,
      simulatePressure: simulatePressure,
      isComplete: isComplete,
      // 笔锋效果（参考 Saber pencil taper）
      start: brush.taperEnabled
          ? StrokeEndOptions.start(
              taperEnabled: true,
              customTaper: brush.customTaper,
            )
          : null,
      end: brush.taperEnabled
          ? StrokeEndOptions.end(
              taperEnabled: true,
              customTaper: brush.customTaper,
            )
          : null,
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
  static Path buildOutlinePath(
    List<PointVector> outline,
    OutlineRenderMode mode,
  ) {
    if (outline.isEmpty) return Path();
    if (mode == OutlineRenderMode.polygon || outline.length < 3) {
      return Path()
        ..addPolygon([for (final p in outline) Offset(p.x, p.y)], true);
    }
    // quadratic: classic midpoint method for a fully-smooth closed path.
    // Start at (P0+P1)/2 so every segment has a distinct control point ≠ its
    // start — no flat edges. Each vertex serves as control exactly once,
    // including outline[0] as the final control before close.
    final path = Path();
    final first = outline.first;
    final startX = (first.x + outline[1].x) / 2;
    final startY = (first.y + outline[1].y) / 2;
    path.moveTo(startX, startY);
    for (var i = 1; i <= outline.length; i++) {
      final cur = outline[i % outline.length];
      final next = outline[(i + 1) % outline.length];
      final midX = (cur.x + next.x) / 2;
      final midY = (cur.y + next.y) / 2;
      path.quadraticBezierTo(cur.x, cur.y, midX, midY);
    }
    path.close();
    return path;
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
    buildOutlinePath(_asPointVectors(outline), outlineRenderMode);
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

    final brush = _configFor(brushType);
    // perfect_freehand 的 size 是直径,而 DrawStyle.strokeWidth 在 freedraw 语境下
    // 是期望的笔迹宽度。直接用 strokeWidth 作为 size 基准。
    final size = dm.max(style.strokeWidth * brush.sizeScale, 1.0);

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
    final outlineVectors = _asPointVectors(outline);
    Stopwatch? sw;
    if (metricsSink != null) {
      sw = Stopwatch()..start();
    }
    final path = buildOutlinePath(outlineVectors, outlineRenderMode);
    final pathBuildDuration = sw != null ? (sw..stop()).elapsed : Duration.zero;
    final basePaint = style.toStrokePaint();
    final paint = basePaint
      ..style = PaintingStyle.fill
      ..color = basePaint.color.withValues(
        alpha: basePaint.color.a * brush.opacityScale,
      );
    canvas.drawPath(path, paint);
    metricsSink?.onMetrics(
      StrokeRenderMetrics(
        outlinePointCount: outlineVectors.length,
        getStrokeDuration: getStrokeDuration,
        pathBuildDuration: pathBuildDuration,
      ),
    );
  }

  static List<PointVector> _asPointVectors(List<Offset> outline) => [
    for (final o in outline) PointVector(o.dx, o.dy, 0),
  ];

  static _BrushConfig _configFor(BrushType brushType) {
    return switch (brushType) {
      // 铅笔：半透明 + 笔锋 + 低延迟跟手(参考 Saber pencil:
      // streamline=0.1, smoothing=0)
      BrushType.pencil => const _BrushConfig(
        sizeScale: 0.82,
        opacityScale: 0.68,
        thinning: 0.45,
        simulatedThinning: 0.32,
        smoothing: 0.2,
        streamline: 0.15,
        taperEnabled: true,
        customTaper: 1.0,
      ),
      // 圆珠笔：极细均匀，关闭压感(参考 Saber ballpointPen)
      BrushType.ballpoint => const _BrushConfig(
        sizeScale: 0.72,
        thinning: 0.08,
        simulatedThinning: 0.02,
        smoothing: 0.62,
        streamline: 0.52,
        pressureEnabled: false,
      ),
      // 钢笔：标准压感，无笔锋(默认笔形)
      BrushType.fountainPen => _BrushConfig(
        thinning: 0.9,
        simulatedThinning: StrokeOptions.defaultThinning,
        smoothing: StrokeOptions.defaultSmoothing,
        streamline: StrokeOptions.defaultStreamline,
      ),
      // 毛笔：粗笔 + 强压感 + 微笔锋(参考 Saber taper 设计)
      BrushType.brushPen => const _BrushConfig(
        sizeScale: 1.15,
        thinning: 1.0,
        simulatedThinning: 0.82,
        smoothing: 0.58,
        streamline: 0.42,
        taperEnabled: true,
        customTaper: 0.5,
      ),
      // 荧光笔：特粗半透明，关闭压感(参考 Saber highlighter)
      BrushType.highlighter => const _BrushConfig(
        sizeScale: 4.2,
        opacityScale: 0.32,
        thinning: 0.05,
        simulatedThinning: 0.02,
        smoothing: 0.72,
        streamline: 0.58,
        forceSimulatePressure: true,
        pressureEnabled: false,
      ),
    };
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

class _BrushConfig {
  const _BrushConfig({
    this.sizeScale = 1.0,
    this.opacityScale = 1.0,
    required this.thinning,
    required this.simulatedThinning,
    required this.smoothing,
    required this.streamline,
    this.forceSimulatePressure = false,
    this.pressureEnabled = true,
    this.taperEnabled = false,
    this.customTaper = 0.0,
  });

  final double sizeScale;
  final double opacityScale;
  final double thinning;
  final double simulatedThinning;
  final double smoothing;
  final double streamline;
  final bool forceSimulatePressure;

  /// 是否启用真实压感。关闭后始终使用模拟压感（参考 Saber 设计）。
  final bool pressureEnabled;

  /// 是否启用笔锋（起笔/收笔变细效果）。
  final bool taperEnabled;

  /// 笔锋缩放比例，仅 [taperEnabled] 为 true 时生效。
  /// 值越大笔锋越短，1.0 为 Saber 铅笔同款效果。
  final double customTaper;
}
