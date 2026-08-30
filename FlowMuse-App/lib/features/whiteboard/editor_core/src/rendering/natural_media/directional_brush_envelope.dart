import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import 'natural_media_stroke_plan.dart';

/// 毛笔 v2 方向性包络几何（计划 §3.7，T5）。
///
/// 消费共享采样 plan 的包络顶点 / join / teardrop / 毫丝 primitive，
/// 产出 ≤2 条 Path（主体包络 + 可选毫丝复合 Path）。宽度、切线、join
/// 与种子全部来自 NaturalMediaStrokeSampler（四条渲染链共用真源），
/// 本模块只做 "primitive → Path"，不重新推导几何。
class DirectionalBrushEnvelope {
  DirectionalBrushEnvelope._();

  static const _kappa = 0.5522847498307936;

  /// [isComplete] 参与收笔判定：楔形收束只在完整笔画的尾部降压时形成
  ///（预览中间态不收尖，抬笔即补全——与 §3.2 预览/提交一致性兼容）。
  /// 返回 hasStrands 供渲染器决定第二条 drawPath 是否必要。
  static ({ui.Path body, ui.Path strands, bool hasStrands}) build(
    NaturalMediaStrokePlan plan,
    double strokeWidth, {
    required bool isComplete,
  }) {
    final body = ui.Path();
    final strands = ui.Path();
    var hasStrands = false;
    final profile = BrushRenderProfile.forType(BrushType.brushPen);

    // 退化：单点/短线 teardrop。无方向（单点）= 圆点；有方向 = 笔肚
    // 椭圆 + 沿末向的小尾锋。
    NaturalMediaPrimitive? teardrop;
    for (final p in plan.primitives) {
      if (p.kind == NaturalMediaPrimitiveKind.brushTeardrop) {
        teardrop = p;
        break;
      }
    }
    if (teardrop != null) {
      final hw = teardrop.halfLength!;
      final c = teardrop.center!;
      final t = teardrop.tangent;
      if (t == null) {
        body.addOval(
          ui.Rect.fromCircle(center: ui.Offset(c.x, c.y), radius: hw),
        );
      } else {
        _addRotatedEllipse(body, c, t, hw, hw * 0.8);
        final tip = Point(c.x + t.x * hw * 1.4, c.y + t.y * hw * 1.4);
        final base = Point(c.x + t.x * hw, c.y + t.y * hw);
        final side = Point(c.x - t.y * hw * 0.2, c.y + t.x * hw * 0.2);
        body.moveTo(base.x, base.y);
        body.lineTo(tip.x, tip.y);
        body.lineTo(side.x, side.y);
        body.close();
      }
      return (body: body, strands: strands, hasStrands: hasStrands);
    }

    // 主体：按发射顺序把顶点/join 拆到左右边界（包络顶点同时贡献
    // 两侧；miter join ordinal 0=左/1=右；锐转圆弧 join ordinal 0-2=左/
    // 3-5=右，与 sampler 的发射约定一致）。
    final left = <ui.Offset>[];
    final right = <ui.Offset>[];
    for (final p in plan.primitives) {
      switch (p.kind) {
        case NaturalMediaPrimitiveKind.brushEnvelopeVertex:
          final t = p.tangent!;
          final n = Point(-t.y, t.x);
          final c = p.center!;
          final hw = p.halfThickness!;
          left.add(ui.Offset(c.x + n.x * hw, c.y + n.y * hw));
          right.add(ui.Offset(c.x - n.x * hw, c.y - n.y * hw));
        case NaturalMediaPrimitiveKind.brushJoin:
          final side = p.paintBucket == 'brushJoinArc'
              ? (p.ordinal < 3 ? left : right)
              : (p.ordinal == 0 ? left : right);
          side.add(ui.Offset(p.center!.x, p.center!.y));
        case NaturalMediaPrimitiveKind.brushStrand:
          final t = p.tangent!;
          final c = p.center!;
          final hl = p.halfLength!;
          strands.moveTo(c.x - t.x * hl, c.y - t.y * hl);
          strands.lineTo(c.x + t.x * hl, c.y + t.y * hl);
          hasStrands = true;
        case NaturalMediaPrimitiveKind.brushTeardrop:
        case NaturalMediaPrimitiveKind.pencilBase:
        case NaturalMediaPrimitiveKind.pencilGrain:
          break;
      }
    }
    if (left.isEmpty) {
      return (body: body, strands: strands, hasStrands: hasStrands);
    }

    // 起收形状（真实压力驱动，§3.7）：轻入笔（首边压力 < 0.35）窄入
    // 口；完整笔画且尾部降压（< 0.30×pMax）形成楔形收束，长度
    // min(units×尾半宽, 6×尾半宽×衰减, baseCap×base)，无降压时对称
    // 圆帽（不生成统一长矛尖）。
    final edges = plan.edges;
    final firstEdge = edges.first;
    final lastEdge = edges.last;
    final firstPt = firstEdge.from;
    final lastPt = lastEdge.to;
    var pMax = 0.0;
    for (final e in edges) {
      if (e.pressure > pMax) pMax = e.pressure;
    }
    final startSharp = firstEdge.pressure < 0.35;
    final tailDrop =
        isComplete && lastEdge.pressure < 0.30 * math.max(pMax, 1e-9);

    body.moveTo(left.first.dx, left.first.dy);
    for (final o in left.skip(1)) {
      body.lineTo(o.dx, o.dy);
    }
    if (tailDrop) {
      final hwPrev = profile.brushNaturalMediaContactHalfWidth(
        strokeWidth,
        lastEdge.pressure,
      );
      final drop = 1 - lastEdge.pressure / math.max(pMax, 1e-9);
      final taper = math.min(
        math.min(
          BrushRenderProfile.brushV2TailTaperUnits * hwPrev,
          6 * hwPrev * drop,
        ),
        BrushRenderProfile.brushV2TailTaperBaseCap * strokeWidth,
      );
      final t = lastEdge.tangent;
      body.lineTo(lastPt.x + t.x * taper, lastPt.y + t.y * taper);
    } else {
      final hwLast = profile.brushNaturalMediaContactHalfWidth(
        strokeWidth,
        lastEdge.pressure,
      );
      final t = lastEdge.tangent;
      final n = Point(-t.y, t.x);
      body.lineTo(
        lastPt.x + n.x * hwLast * 0.72 + t.x * hwLast * 0.62,
        lastPt.y + n.y * hwLast * 0.72 + t.y * hwLast * 0.62,
      );
      body.lineTo(lastPt.x + t.x * hwLast, lastPt.y + t.y * hwLast);
      body.lineTo(
        lastPt.x - n.x * hwLast * 0.72 + t.x * hwLast * 0.62,
        lastPt.y - n.y * hwLast * 0.72 + t.y * hwLast * 0.62,
      );
    }
    for (final o in right.reversed) {
      body.lineTo(o.dx, o.dy);
    }
    if (startSharp) {
      // 轻入笔：垂直切线的窄入口（自然起笔，不出装饰性顿笔）。
      body.lineTo(firstPt.x, firstPt.y);
    } else {
      final hwFirst = profile.brushNaturalMediaContactHalfWidth(
        strokeWidth,
        firstEdge.pressure,
      );
      final t = firstEdge.tangent;
      final n = Point(-t.y, t.x);
      body.lineTo(
        firstPt.x - n.x * hwFirst * 0.72 - t.x * hwFirst * 0.62,
        firstPt.y - n.y * hwFirst * 0.72 - t.y * hwFirst * 0.62,
      );
      body.lineTo(firstPt.x - t.x * hwFirst, firstPt.y - t.y * hwFirst);
      body.lineTo(
        firstPt.x + n.x * hwFirst * 0.72 - t.x * hwFirst * 0.62,
        firstPt.y + n.y * hwFirst * 0.72 - t.y * hwFirst * 0.62,
      );
    }
    body.close();
    return (body: body, strands: strands, hasStrands: hasStrands);
  }

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
