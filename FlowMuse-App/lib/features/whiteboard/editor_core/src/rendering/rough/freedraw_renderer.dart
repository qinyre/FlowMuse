import 'dart:math' as math;
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart' hide Point;

import '../../core/math/math.dart';
import '../../core/elements/brush_render_profile.dart';
import '../../core/elements/brush_type.dart';
import '../../input/outline_render_mode.dart';
import '../../input/stroke_render_metrics.dart';
import 'draw_style.dart';
import 'pencil_shader.dart';

/// Renders freehand drawing paths.
///
/// 使用 perfect_freehand 的 outline-stroke 算法:把点序列+压感转成一条
/// 变宽的闭合多边形轮廓,既平滑又自然变粗(Excalidraw/tldraw 同款)。
///
/// 笔刷参数的唯一真源是 [BrushRenderProfile.forType]；本文件不保留第二
/// 份配置。压力语义（issue #5 计划 §6.3）：
/// - pressureEncoded=true：pressures 已在创建时按灵敏度烘焙，渲染用
///   profile 最大 thinning（本地湿墨、远端湿墨、新元素）；
/// - pressureEncoded=false（旧元素）：pressures 为原始值，渲染用对应
///   笔刷出厂默认灵敏度的 effectiveThinning（确定性，不读当前状态）。
///
/// 禁止给 StrokeOptions 传非默认 easing：压力烘焙等价性仅在 identity
/// 下成立（见 BrushRenderProfile 文档）。
class FreedrawRenderer {
  /// 铅笔纹理频率种子（T5 起按笔宽派生；此处先固定为 shader 原默认值）。
  static const double _kPencilTextureFreq = 0.7;

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
    bool pressureEncoded = false,
    bool isComplete = true,
    BrushType brushType = BrushType.fountainPen,
    FreedrawTaperPhase taperPhase = FreedrawTaperPhase.full,
    double? wholeStrokeRawLength,
  }) {
    if (points.isEmpty) return const [];

    final profile = BrushRenderProfile.forType(brushType);
    final hasRawPressure =
        pressures != null && pressures.length == points.length;
    // 当笔形关闭压感时，丢弃真实压感数据，始终走模拟（参考 Saber pressureEnabled）。
    final hasPressure = hasRawPressure && profile.pressureEnabled;
    final inputPoints = <PointVector>[
      for (var i = 0; i < points.length; i++)
        PointVector(
          points[i].x,
          points[i].y,
          hasPressure ? pressures[i] : null,
        ),
    ];
    // taper 门控按整条可见笔迹的原始折线长度判断（远端分段渲染时由
    // 调用方传入 wholeStrokeRawLength；本地/静态渲染即本列表长度）。
    final rawLength = wholeStrokeRawLength ?? _polylineLength(points);
    final startTaper =
        taperPhase == FreedrawTaperPhase.full ||
            taperPhase == FreedrawTaperPhase.headOnly
        ? profile.startTaperDistance(strokeWidth, rawLength)
        : 0.0;
    final endTaper =
        taperPhase == FreedrawTaperPhase.full ||
            taperPhase == FreedrawTaperPhase.tailOnly
        ? profile.endTaperDistance(strokeWidth, rawLength)
        : 0.0;
    final options = StrokeOptions(
      size: profile.renderSize(strokeWidth),
      thinning: hasPressure
          ? (pressureEncoded
                ? profile.maxThinning
                : profile.effectiveThinning(
                    profile.legacySensitivity(brushType),
                  ))
          : profile.simulatedThinning,
      smoothing: profile.smoothing,
      streamline: profile.streamline,
      simulatePressure: !hasPressure || profile.forceSimulatePressure,
      isComplete: isComplete,
      // 笔锋：绝对距离（customTaper 单位即距离）；未启用时传 null 走
      // 默认圆端帽。taper 期间包会忽略 cap。
      start: startTaper > 0
          ? StrokeEndOptions.start(taperEnabled: true, customTaper: startTaper)
          : null,
      end: endTaper > 0
          ? StrokeEndOptions.end(taperEnabled: true, customTaper: endTaper)
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
    bool pressureEncoded = false,
    bool isComplete = true,
    required OutlineRenderMode outlineRenderMode,
    BrushType brushType = BrushType.fountainPen,
    FreedrawTaperPhase taperPhase = FreedrawTaperPhase.full,
    double? wholeStrokeRawLength,
  }) {
    final outlineWatch = Stopwatch()..start();
    final outline = buildOutline(
      points,
      strokeWidth: strokeWidth,
      pressures: pressures,
      pressureEncoded: pressureEncoded,
      isComplete: isComplete,
      brushType: brushType,
      taperPhase: taperPhase,
      wholeStrokeRawLength: wholeStrokeRawLength,
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
    bool pressureEncoded = false,
    bool isComplete = true,
    required OutlineRenderMode outlineRenderMode,
    StrokeRenderMetricsSink? metricsSink,
    BrushType brushType = BrushType.fountainPen,
    FreedrawTaperPhase taperPhase = FreedrawTaperPhase.full,
    double? wholeStrokeRawLength,
  }) {
    if (points.isEmpty) return;

    final profile = BrushRenderProfile.forType(brushType);
    // perfect_freehand 的 size 是直径,而 DrawStyle.strokeWidth 在 freedraw 语境下
    // 是期望的笔迹宽度。直接用 strokeWidth 作为 size 基准。
    final size = profile.renderSize(style.strokeWidth);

    Stopwatch? outlineWatch;
    if (metricsSink != null) {
      outlineWatch = Stopwatch()..start();
    }
    final outline = buildOutline(
      points,
      strokeWidth: style.strokeWidth,
      pressures: pressures,
      pressureEncoded: pressureEncoded,
      isComplete: isComplete,
      brushType: brushType,
      taperPhase: taperPhase,
      wholeStrokeRawLength: wholeStrokeRawLength,
    );
    final getStrokeDuration = outlineWatch != null
        ? (outlineWatch..stop()).elapsed
        : Duration.zero;

    // 单点(点击):outline 为空,画圆点
    if (outline.isEmpty) {
      final p = points[0];
      final basePaint = style.toStrokePaint();
      final paint = basePaint
        ..style = PaintingStyle.fill
        ..color = basePaint.color.withValues(
          alpha: basePaint.color.a * profile.opacityScale,
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
        alpha: basePaint.color.a * profile.opacityScale,
      );

    // 铅笔纹理：shader 可用时复用应用级单实例（每元素 set uniform 后立即
    // drawPath；engine 逐 draw 快照 uniform，跨元素安全）。
    if (brushType == BrushType.pencil && profile.usesPencilTexture) {
      final shader = PencilShader.acquire();
      final uniforms = PencilShader.uniforms();
      if (shader != null && uniforms != null) {
        final c = paint.color;
        uniforms.apply(c, c.a, _kPencilTextureFreq);
        paint.shader = shader;
        paint.color = const Color(0xFFFFFFFF); // shader 负责着色
      }
    }

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

  /// 原始输入点折线总长（未插值、未 streamline）。
  static double _polylineLength(List<Point> points) {
    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final dx = points[i + 1].x - points[i].x;
      final dy = points[i + 1].y - points[i].y;
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
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

/// 笔型 sizeScale 上界（highlighter = 4.2），供远端湿墨聚焦层计算
/// bounds 余量。新增笔型若超过该值必须同步上调。
/// 前提：现有笔型的压感 thinning 使最大半径 ≤ size/2×(1+thinning) ≤
/// size（brushPen thinning 1.0 时最大半径 = 1.15×strokeWidth，远小于
/// 4.2 上界推导的 2.1×strokeWidth）；若未来新增"高 sizeScale(≥3) +
/// thinning≈1.0"笔型，1.3 压感因子将不足，需把因子提到 2.0 或按笔型
/// 精确计算。（issue #5 T6 将删除本常量，改由 profile.visualHalfWidth 派生。）
const double kMaxBrushSizeScale = 4.2;
