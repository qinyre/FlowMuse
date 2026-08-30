import 'dart:ui' as ui;

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../rough/draw_style.dart';
import 'deterministic_stroke_seed.dart';
import 'natural_media_stroke_plan.dart';
import 'natural_media_stroke_sampler.dart';

// ---------------------------------------------------------------------------
// 铅笔 v2 渲染器（计划 §3.6，T4）：消费共享采样 plan 的确定性 HB 铅笔。
//
// 结构契约：每元素主要 drawPath ≤4（基底 + 最多三个密度桶）、
// saveLayer = 0、不申请 shader；几何与种子全部来自
// NaturalMediaStrokeSampler（四条渲染链共用真源），渲染器只做
// "plan → Path → drawPath"，不重新推导几何。
// ---------------------------------------------------------------------------

class PencilStrokeRendererV2 {
  PencilStrokeRendererV2._();

  /// plan 构建计数探针（T4 验收：证明普通静态重绘的实际构造成本；
  /// 本任务默认不新增静态缓存，T4-C 仅在性能实测越线时立项）。
  static int planBuildCount = 0;

  /// 测试用复位。
  static void resetPlanBuildCountForTest() => planBuildCount = 0;

  /// 远端湿墨分段渲染：[ownedEdgeStart]/[ownedEdgeEndExclusive] 以全局
  /// 边索引指定本段 owned 边（§3.4，context 点不拥有绘制权），
  /// [edgeIndexOffset] 把边索引对齐到全局笔迹索引（段起点 − leading 数）。
  static void draw(
    ui.Canvas canvas,
    FreedrawElement element,
    DrawStyle style, {
    int? ownedEdgeStart,
    int? ownedEdgeEndExclusive,
    int edgeIndexOffset = 0,
  }) {
    final profile = BrushRenderProfile.forType(BrushType.pencil);
    final abs = [
      for (final p in element.points) Point(p.x + element.x, p.y + element.y),
    ];
    planBuildCount++;
    final plan = NaturalMediaStrokeSampler.sample(
      strokeId: element.id.value,
      points: abs,
      pressures: element.pressures,
      strokeWidth: style.strokeWidth,
      brushType: BrushType.pencil,
      isComplete: element.isComplete,
      ownedEdgeStart: ownedEdgeStart,
      ownedEdgeEndExclusive: ownedEdgeEndExclusive,
      edgeIndexOffset: edgeIndexOffset,
    );

    // 基底：沿采样槽的抖动偏移多边形（wobble 种子 (edge, ordinal, base)，
    // 分块/整笔一致），端部方帽。
    final base = _buildBasePath(plan, style.strokeWidth);
    canvas.drawPath(base, _paint(style, profile.pencilV2BaseAlpha));

    // 颗粒：按 channel 分桶合成复合 Path（≤3 桶）。
    final bucketPaths = <int, ui.Path>{};
    for (final p in plan.primitives) {
      if (p.kind != NaturalMediaPrimitiveKind.pencilGrain) continue;
      final path = bucketPaths.putIfAbsent(p.channel, ui.Path.new);
      _addRotatedEllipse(
        path,
        p.center!,
        p.tangent!,
        p.halfLength!,
        p.halfThickness!,
      );
    }
    final channels = bucketPaths.keys.toList()..sort();
    for (final channel in channels) {
      canvas.drawPath(
        bucketPaths[channel]!,
        _paint(style, profile.pencilV2GrainAlpha(channel)),
      );
    }
  }

  static ui.Paint _paint(DrawStyle style, double alpha) => ui.Paint()
    ..color = style.strokeColor.withValues(
      alpha: style.strokeColor.a * alpha * style.opacity,
    );

  static ui.Path _buildBasePath(NaturalMediaStrokePlan plan, double base) {
    final path = ui.Path();
    if (plan.samples.isEmpty) return path;
    final profile = BrushRenderProfile.forType(BrushType.pencil);
    final left = <ui.Offset>[];
    final right = <ui.Offset>[];
    void appendSample(NaturalMediaSample s) {
      final n = s.filteredNormal;
      final wobble =
          0.85 +
          0.30 *
              rand01(
                mix32(
                  plan.strokeSeed,
                  s.edgeIndex,
                  s.ordinal,
                  NaturalMediaChannel.base,
                ),
                0x55,
              );
      final hw =
          profile.pencilNaturalMediaLocalWidth(base, s.pressure) / 2 * wobble;
      left.add(ui.Offset(s.position.x + n.x * hw, s.position.y + n.y * hw));
      right.add(ui.Offset(s.position.x - n.x * hw, s.position.y - n.y * hw));
    }

    // 分块边界连续性：每条 owned 边的最后一个采样后补边终点顶点
    //（用该采样的法向/半宽），整笔与分块渲染含同样的边界顶点，
    // 前块多边形到达边端点、后块从端点起笔，无白缝（§3.4）。
    final edgeByIndex = {for (final e in plan.edges) e.index: e};
    double halfWidthOf(NaturalMediaSample s) {
      final wobble =
          0.85 +
          0.30 *
              rand01(
                mix32(
                  plan.strokeSeed,
                  s.edgeIndex,
                  s.ordinal,
                  NaturalMediaChannel.base,
                ),
                0x55,
              );
      return profile.pencilNaturalMediaLocalWidth(base, s.pressure) /
          2 *
          wobble;
    }

    void appendEdgeEndpoint(int edgeIndex, NaturalMediaSample last) {
      final e = edgeByIndex[edgeIndex];
      if (e == null) return;
      final n = last.filteredNormal;
      final hw = halfWidthOf(last);
      left.add(ui.Offset(e.to.x + n.x * hw, e.to.y + n.y * hw));
      right.add(ui.Offset(e.to.x - n.x * hw, e.to.y - n.y * hw));
    }

    NaturalMediaSample? lastSample;
    var currentEdge = plan.samples.first.edgeIndex;
    for (final s in plan.samples) {
      if (lastSample != null && s.edgeIndex != currentEdge) {
        appendEdgeEndpoint(currentEdge, lastSample);
        currentEdge = s.edgeIndex;
      }
      appendSample(s);
      lastSample = s;
    }
    if (lastSample != null) {
      appendEdgeEndpoint(currentEdge, lastSample);
    }
    path.moveTo(left.first.dx, left.first.dy);
    for (final o in left.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    path.lineTo(right.last.dx, right.last.dy);
    for (final o in right.reversed) {
      path.lineTo(o.dx, o.dy);
    }
    path.close();
    return path;
  }

  static const _kappa = 0.5522847498307936;

  static void _addRotatedEllipse(
    ui.Path path,
    Point center,
    Point tangent,
    double halfLength,
    double halfThickness,
  ) {
    final ux = tangent.x * halfLength;
    final uy = tangent.y * halfLength;
    final vx = -tangent.y * halfThickness;
    final vy = tangent.x * halfThickness;
    final cx = center.x;
    final cy = center.y;
    ui.Offset at(double s, double c) =>
        ui.Offset(cx + ux * s + vx * c, cy + uy * s + vy * c);
    final p0 = at(1, 0);
    final p1 = at(0, 1);
    final p2 = at(-1, 0);
    final p3 = at(0, -1);
    final kl = _kappa * halfLength;
    final kt = _kappa * halfThickness;
    path.moveTo(p0.dx, p0.dy);
    path.cubicTo(
      cx + ux + vx * kt,
      cy + uy + vy * kt,
      cx + ux * kl + vx,
      cy + uy * kl + vy,
      p1.dx,
      p1.dy,
    );
    path.cubicTo(
      cx - ux * kl + vx,
      cy - uy * kl + vy,
      cx - ux + vx * kt,
      cy - uy + vy * kt,
      p2.dx,
      p2.dy,
    );
    path.cubicTo(
      cx - ux - vx * kt,
      cy - uy - vy * kt,
      cx - ux * kl - vx,
      cy - uy * kl - vy,
      p3.dx,
      p3.dy,
    );
    path.cubicTo(
      cx + ux * kl - vx,
      cy + uy * kl - vy,
      cx + ux - vx * kt,
      cy + uy - vy * kt,
      p0.dx,
      p0.dy,
    );
    path.close();
  }
}
