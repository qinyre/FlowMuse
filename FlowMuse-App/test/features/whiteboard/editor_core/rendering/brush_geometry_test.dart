import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/brush_stroke_fixtures.dart';
import 'brush_path_metrics.dart';

/// 圆珠笔/钢笔/毛笔的几何差异断言（Issue #5 T3 / A1–A4、A15）。
void main() {
  // 毛笔专用收锋 fixture：恒压、折线 ≥20×size、采样间距 ≤0.5×size
  // （strokeWidth 2 → size 2.3 → 间距 1.0 ≤ 1.15 ✓，长度 100 ≥ 46 ✓）。
  final brushPenDense = List<Point>.generate(
    101,
    (i) => Point(1.0 * i, 0),
    growable: false,
  );
  const brushPenPressure = 0.5;
  List<double> constantPressures(int n, double v) => List<double>.filled(n, v);

  group('A1/A2/A3：压力对比', () {
    test('A1: 圆珠笔不同压力输入轮廓完全一致（恒宽）', () {
      final low = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: constantPressures(pressureRamp.points.length, 0.15),
        pressureEncoded: true,
        brushType: BrushType.ballpoint,
      );
      final high = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: constantPressures(pressureRamp.points.length, 0.9),
        pressureEncoded: true,
        brushType: BrushType.ballpoint,
      );
      expect(
        high.map((o) => '${o.dx},${o.dy}').toList(),
        equals(low.map((o) => '${o.dx},${o.dy}').toList()),
        reason: '圆珠笔必须忽略压力',
      );
    });

    test('A2: 钢笔低压/高压最大局部宽度差 ≥15%', () {
      final outlineLow = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: constantPressures(pressureRamp.points.length, 0.2),
        pressureEncoded: true,
        brushType: BrushType.fountainPen,
      );
      final outlineHigh = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: constantPressures(pressureRamp.points.length, 0.9),
        pressureEncoded: true,
        brushType: BrushType.fountainPen,
      );
      final wLow = BrushOutlineMetrics.maxWidthAtSamples(
        pressureRamp.points,
        outlineLow,
      );
      final wHigh = BrushOutlineMetrics.maxWidthAtSamples(
        pressureRamp.points,
        outlineHigh,
      );
      expect(wLow, greaterThan(0));
      expect(
        (wHigh - wLow) / wLow,
        greaterThan(0.15),
        reason: '钢笔压感宽度差 wLow=$wLow wHigh=$wHigh',
      );
    });

    test('A3: 毛笔压差 ≥25% 且强于钢笔', () {
      final brushLow = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: constantPressures(pressureRamp.points.length, 0.2),
        pressureEncoded: true,
        brushType: BrushType.brushPen,
      );
      final brushHigh = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: constantPressures(pressureRamp.points.length, 0.9),
        pressureEncoded: true,
        brushType: BrushType.brushPen,
      );
      final fountainLow = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: constantPressures(pressureRamp.points.length, 0.2),
        pressureEncoded: true,
        brushType: BrushType.fountainPen,
      );
      final fountainHigh = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: constantPressures(pressureRamp.points.length, 0.9),
        pressureEncoded: true,
        brushType: BrushType.fountainPen,
      );
      final brushDelta =
          (BrushOutlineMetrics.maxWidthAtSamples(
                pressureRamp.points,
                brushHigh,
              ) -
              BrushOutlineMetrics.maxWidthAtSamples(
                pressureRamp.points,
                brushLow,
              )) /
          BrushOutlineMetrics.maxWidthAtSamples(pressureRamp.points, brushLow);
      final fountainDelta =
          (BrushOutlineMetrics.maxWidthAtSamples(
                pressureRamp.points,
                fountainHigh,
              ) -
              BrushOutlineMetrics.maxWidthAtSamples(
                pressureRamp.points,
                fountainLow,
              )) /
          BrushOutlineMetrics.maxWidthAtSamples(
            pressureRamp.points,
            fountainLow,
          );
      expect(brushDelta, greaterThan(0.25), reason: '毛笔压差 $brushDelta');
      expect(
        brushDelta,
        greaterThan(fountainDelta),
        reason: '毛笔($brushDelta)必须强于钢笔($fountainDelta)',
      );
    });
  });

  group('A4：毛笔收锋（绝对距离判据）', () {
    test('距起/终点 1×size ≤中段 65%，2×size ≤85%', () {
      final size = BrushRenderProfile.forType(BrushType.brushPen).renderSize(2);
      final total = 100.0;
      final outline = FreedrawRenderer.buildOutline(
        brushPenDense,
        strokeWidth: 2,
        pressures: constantPressures(brushPenDense.length, brushPenPressure),
        pressureEncoded: true,
        brushType: BrushType.brushPen,
      );
      final midWidth = BrushOutlineMetrics.widthAtArc(
        brushPenDense,
        outline,
        0.5,
      );
      expect(midWidth, greaterThan(0), reason: '中段必须有可测宽度');

      double widthAtDistanceFromEnd(double dist) =>
          BrushOutlineMetrics.widthAtArc(
            brushPenDense,
            outline,
            (total - dist) / total,
          );
      double widthAtDistanceFromStart(double dist) =>
          BrushOutlineMetrics.widthAtArc(brushPenDense, outline, dist / total);

      final start1 = widthAtDistanceFromStart(1 * size);
      final start2 = widthAtDistanceFromStart(2 * size);
      final end1 = widthAtDistanceFromEnd(1 * size);
      final end2 = widthAtDistanceFromEnd(2 * size);
      expect(
        start1 / midWidth,
        lessThan(0.65),
        reason: '起 1×size: ${start1 / midWidth}',
      );
      expect(
        end1 / midWidth,
        lessThan(0.65),
        reason: '收 1×size: ${end1 / midWidth}',
      );
      expect(
        start2 / midWidth,
        lessThan(0.85),
        reason: '起 2×size: ${start2 / midWidth}',
      );
      expect(
        end2 / midWidth,
        lessThan(0.85),
        reason: '收 2×size: ${end2 / midWidth}',
      );
    });
  });

  group('taper 门控（<3×size 禁用）', () {
    test('A19: 单点/两点/低压短笔均产生可见结果', () {
      // 真实管线的压力地板是 0.18（input_policy pressureFloor），
      // 零压力不可达；用地板值验证最坏可见性。
      for (final brush in [BrushType.pencil, BrushType.brushPen]) {
        final size = BrushRenderProfile.forType(brush).renderSize(4);
        // 单点（0.5 压力）
        final dot = FreedrawRenderer.buildOutline(
          [const Point(50, 50)],
          strokeWidth: 4,
          pressures: const [0.5],
          brushType: brush,
        );
        final dotMetrics = BrushOutlineMetrics.measure(dot);
        expect(
          dotMetrics.bounds.width,
          greaterThan(size * 0.8),
          reason: '$brush 单点可见',
        );
        // 两点短划（<3×size，压力地板 0.18）
        final short = FreedrawRenderer.buildOutline(
          [const Point(10, 10), const Point(12, 10)],
          strokeWidth: 4,
          pressures: const [0.18, 0.18],
          brushType: brush,
        );
        final shortMetrics = BrushOutlineMetrics.measure(short);
        expect(
          shortMetrics.bounds.height,
          greaterThan(1.2),
          reason:
              '${brush.name} 低压短划厚度 ${shortMetrics.bounds.height}'
              ' 须肉眼可见（≥1.2px）',
        );
        expect(
          shortMetrics.bounds.width,
          greaterThan(2.0),
          reason: '${brush.name} 短划长度可见',
        );
      }
    });
  });

  group('A15：远端分段 + TaperPhase 合并一致', () {
    test('64 点分段渲染合并 bounds 与整笔 full 渲染 ≤2px/边，段边界无收针', () {
      // 300 点折线长笔（正弦摆动），恒压
      final points = [
        for (var i = 0; i < 300; i++) Point(2.0 * i, 20 * math.sin(i / 18)),
      ];
      const strokeWidth = 4.0;
      final size = BrushRenderProfile.forType(
        BrushType.brushPen,
      ).renderSize(strokeWidth);
      final wholeLength = _polylineLengthOf(points);
      final pressures = constantPressures(points.length, 0.6);

      final full = FreedrawRenderer.buildOutline(
        points,
        strokeWidth: strokeWidth,
        pressures: pressures,
        pressureEncoded: true,
        brushType: BrushType.brushPen,
      );
      final fullMetrics = BrushOutlineMetrics.measure(full);
      final midWidthFull = BrushOutlineMetrics.widthAtArc(points, full, 0.5);

      // 按 64 点分段（含 1 点重叠桥接，模拟 leading/trailing）渲染
      var merged = Rect.zero;
      final segmentCount = (points.length / 64).ceil();
      for (var s = 0; s < segmentCount; s++) {
        final start = s * 64;
        final end = math.min(start + 64, points.length);
        final bridgeStart = start > 0 ? start - 1 : start;
        final segment = points.sublist(bridgeStart, end);
        final phase = s == 0
            ? FreedrawTaperPhase.headOnly
            : s == segmentCount - 1
            ? FreedrawTaperPhase.tailOnly
            : FreedrawTaperPhase.none;
        final outline = FreedrawRenderer.buildOutline(
          segment,
          strokeWidth: strokeWidth,
          pressures: constantPressures(segment.length, 0.6),
          pressureEncoded: true,
          brushType: BrushType.brushPen,
          taperPhase: phase,
          wholeStrokeRawLength: wholeLength,
        );
        final m = BrushOutlineMetrics.measure(outline);
        merged = merged == Rect.zero
            ? m.bounds
            : merged.expandToInclude(m.bounds);
      }

      expect((merged.left - fullMetrics.bounds.left).abs(), lessThan(2.0));
      expect((merged.top - fullMetrics.bounds.top).abs(), lessThan(2.0));
      expect((merged.right - fullMetrics.bounds.right).abs(), lessThan(2.0));
      expect((merged.bottom - fullMetrics.bounds.bottom).abs(), lessThan(2.0));

      // 段边界宽度：在 64/128/192/256 点处（沿折线弧长比例）的分段渲染
      // 宽度不低于整笔中段宽度的 80%（除真实笔尾外不收针）。
      for (final boundaryIndex in [64, 128, 192, 256]) {
        final t = _arcFractionAtIndexOf(points, boundaryIndex);
        final widthHere = _segmentedWidthAt(
          points,
          strokeWidth,
          boundaryIndex,
          wholeLength,
        );
        // 用整笔渲染在同位置的宽度做对照（分段与整笔同宽 ±20%）
        final fullWidth = BrushOutlineMetrics.widthAtArc(points, full, t);
        expect(
          widthHere,
          greaterThan(midWidthFull * 0.8),
          reason:
              '边界 #$boundaryIndex 分段宽 ${widthHere.toStringAsFixed(2)}'
              ' vs 中段 ${midWidthFull.toStringAsFixed(2)}',
        );
        expect(
          (widthHere - fullWidth).abs() / fullWidth,
          lessThan(0.2),
          reason:
              '边界 #$boundaryIndex 与整笔差 '
              '${((widthHere - fullWidth).abs() / fullWidth).toStringAsFixed(2)}',
        );
      }
      // size 只用于门控读数，防误删
      expect(size, greaterThan(0));
    });
  });
}

double _polylineLengthOf(List<Point> points) {
  var total = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    final dx = points[i + 1].x - points[i].x;
    final dy = points[i + 1].y - points[i].y;
    total += math.sqrt(dx * dx + dy * dy);
  }
  return total;
}

double _arcFractionAtIndexOf(List<Point> points, int index) {
  final total = _polylineLengthOf(points);
  var acc = 0.0;
  for (var i = 0; i < index && i < points.length - 1; i++) {
    final dx = points[i + 1].x - points[i].x;
    final dy = points[i + 1].y - points[i].y;
    acc += math.sqrt(dx * dx + dy * dy);
  }
  return total == 0 ? 0 : acc / total;
}

double _segmentedWidthAt(
  List<Point> points,
  double strokeWidth,
  int boundaryIndex,
  double wholeLength,
) {
  // 取边界点所在的分段（与其前一段桥接），按该段的 phase 渲染后测宽
  final segmentIndex = boundaryIndex ~/ 64;
  final start = segmentIndex * 64;
  final end = math.min(start + 64, points.length);
  final bridgeStart = start > 0 ? start - 1 : start;
  final segment = points.sublist(bridgeStart, end);
  final segmentCount = (points.length / 64).ceil();
  final phase = segmentIndex == 0
      ? FreedrawTaperPhase.headOnly
      : segmentIndex == segmentCount - 1
      ? FreedrawTaperPhase.tailOnly
      : FreedrawTaperPhase.none;
  final outline = FreedrawRenderer.buildOutline(
    segment,
    strokeWidth: strokeWidth,
    pressures: List<double>.filled(segment.length, 0.6),
    pressureEncoded: true,
    brushType: BrushType.brushPen,
    taperPhase: phase,
    wholeStrokeRawLength: wholeLength,
  );
  // 边界点在段内的相对位置（桥接 1 点偏移）
  final localIndex = boundaryIndex - bridgeStart;
  final localT = _arcFractionAtIndexOf(segment, localIndex);
  return BrushOutlineMetrics.widthAtArc(segment, outline, localT);
}
