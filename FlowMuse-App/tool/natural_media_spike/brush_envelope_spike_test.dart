// tool/natural_media_spike/brush_envelope_spike_test.dart
//
// T0 可删除原型（计划 T0 工作项 7/8）：≤2 Path 的方向性毛笔包络
// 渲染原型。只用固定 fixture，不接生产 Scene。证明：
//  - 压力→接触宽度（提按量程 ≥2.2）、三 edge 固定窗口方向滞后、
//    受限 miter（1.5）、真实压力起收（无降压不出矛尖）可同时成立；
//  - 1k/16k 点结构与耗时线性。
// T0 收口时删除本文件（§3.7 正式实现进 T5）。
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/features/whiteboard/editor_core/fixtures/brush_stroke_fixtures.dart';
import '../../test/features/whiteboard/editor_core/rendering/canvas_spy.dart';
import '../../test/features/whiteboard/editor_core/rendering/natural_media/natural_media_image_metrics.dart';
import '../../test/features/whiteboard/editor_core/rendering/natural_media_visual_sheet_support.dart';
import 'natural_media_seed_spike.dart';

class BrushEnvelopeSpikePlan {
  BrushEnvelopeSpikePlan(
    this.draws,
    this.boundaryVertexCount,
    this.strandCount,
  );

  /// (path, alpha) ≤2 项：包络 + 可选毫丝复合 Path。
  final List<(ui.Path, double)> draws;
  final int boundaryVertexCount;
  final int strandCount;
}

class _Edge {
  _Edge(this.index, this.a, this.b, this.len, this.tx, this.ty, this.pressure);
  final int index;
  final Point a;
  final Point b;
  final double len;
  final double tx;
  final double ty;
  final double pressure;
}

class BrushEnvelopeSpike {
  /// §3.4 三 edge 固定 stencil 权重（当前 + 前 2 条 edge）。
  static const _stencilWeights = [0.5, 0.3, 0.2];

  /// §3.7 受限 miter。
  static const _miterLimit = 1.5;

  /// §3.5 候选曲线：接触半宽 = base×(0.16+1.34·p^0.72)/2。
  static double contactHalfWidth(double base, double p) =>
      base * (0.16 + 1.34 * math.pow(p.clamp(0.0, 1.0), 0.72)) / 2;

  static BrushEnvelopeSpikePlan build({
    required String strokeId,
    required List<Point> points,
    required List<double> pressures,
    required double strokeWidth,
    bool isComplete = true,
  }) {
    final seed = strokeSeedOf(strokeId);

    // 预处理有效 edge（跳过零长/非有限）。
    final edges = <_Edge>[];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (!len.isFinite || len < 1e-9) continue;
      edges.add(
        _Edge(
          i,
          a,
          b,
          len,
          dx / len,
          dy / len,
          ((pressures[i - 1] + pressures[i]) / 2).clamp(0.0, 1.0),
        ),
      );
    }

    // 单点/极短：teardrop 退化（不虚构方向）。
    final totalLen = [for (final e in edges) e.len].fold(0.0, (a, b) => a + b);
    if (edges.isEmpty) {
      final p = pressures.isEmpty ? 0.5 : pressures.first;
      final c = points.isEmpty ? Point.zero : points.first;
      final path = ui.Path();
      path.addOval(
        ui.Rect.fromCircle(
          center: ui.Offset(c.x, c.y),
          radius: contactHalfWidth(strokeWidth, p),
        ),
      );
      return BrushEnvelopeSpikePlan([(path, 1.0)], 4, 0);
    }
    if (totalLen < 2 * strokeWidth || points.length <= 2) {
      return _teardrop(edges.first, edges.last, strokeWidth, seed);
    }

    // 过滤切线：stencil 缺槽复用最早有效 edge 的单位切线（§3.4）。
    final filtered = List<Point>.filled(edges.length, const Point(1, 0));
    for (var i = 0; i < edges.length; i++) {
      var sx = 0.0;
      var sy = 0.0;
      var applied = 0;
      for (var j = 0; j < _stencilWeights.length && i - j >= 0; j++) {
        sx += _stencilWeights[j] * edges[i - j].tx;
        sy += _stencilWeights[j] * edges[i - j].ty;
        applied++;
      }
      // 笔画起点缺少历史 edge：缺失槽位复用最早一个有效 edge 的切线。
      for (var j = applied; j < _stencilWeights.length; j++) {
        sx += _stencilWeights[j] * edges.first.tx;
        sy += _stencilWeights[j] * edges.first.ty;
      }
      final len = math.sqrt(sx * sx + sy * sy);
      filtered[i] = len < 1e-9
          ? Point(edges[i].tx, edges[i].ty)
          : Point(sx / len, sy / len);
    }

    final left = <ui.Offset>[];
    final right = <ui.Offset>[];

    // 沿 edge 增量采样（2px 步进；顶点邻域 5px 内加密到 1px，消除台阶）。
    for (var i = 0; i < edges.length; i++) {
      final e = edges[i];
      final f = filtered[i];
      final nx = -f.y;
      final ny = f.x;
      var s = i == 0 ? 0.0 : 1.0;
      while (s < e.len || (i == edges.length - 1 && s <= e.len)) {
        final nearVertex = s < 5.0 || s > e.len - 5.0 || e.len <= 6.0;
        final step = nearVertex ? 1.0 : 2.0;
        final u = (s / e.len).clamp(0.0, 1.0);
        final px = e.a.x + (e.b.x - e.a.x) * u;
        final py = e.a.y + (e.b.y - e.a.y) * u;
        final hw = contactHalfWidth(strokeWidth, e.pressure);
        left.add(ui.Offset(px + nx * hw, py + ny * hw));
        right.add(ui.Offset(px - nx * hw, py - ny * hw));
        s += step;
      }
      // 顶点 join：>75° 用圆弧 join（防偏移折叠自交），其余受限 miter
      //（外凸侧笔肚，1.5×hw 截断）。视觉预审教训：锐转（钩）插 miter
      // 会折出三角填充与白缝。
      if (i + 1 < edges.length) {
        final v = e.b;
        final hw = contactHalfWidth(strokeWidth, e.pressure);
        final g = filtered[i + 1];
        final next = edges[i + 1];
        final dot = e.tx * next.tx + e.ty * next.ty;
        final det = e.tx * next.ty - e.ty * next.tx;
        final turn = math.atan2(det, dot).abs();
        if (turn > 75 * math.pi / 180) {
          for (var k = 1; k <= 3; k++) {
            final a = turn * k / 4 * (det >= 0 ? 1 : -1);
            final ca = math.cos(a);
            final sa = math.sin(a);
            final rkx = e.tx * ca - e.ty * sa;
            final rky = e.tx * sa + e.ty * ca;
            for (final side in [1, -1]) {
              final ox = -rky * side * hw;
              final oy = rkx * side * hw;
              (side == 1 ? left : right).add(ui.Offset(v.x + ox, v.y + oy));
            }
          }
        } else {
          for (final side in [1, -1]) {
            final m = _miterPoint(
              v,
              Point(nx * side, ny * side),
              Point(-g.y * side, g.x * side),
              Point(next.tx, next.ty),
              hw,
            );
            if (m != null) {
              (side == 1 ? left : right).add(m);
            }
          }
        }
      }
    }

    // 起收形状：真实压力驱动（§3.7）。
    final pMax = pressures.fold<double>(0, math.max);
    final startSharp = pressures.first < 0.35;
    final tailDrop = isComplete && pressures.last < 0.30 * pMax;
    final envelope = ui.Path();
    final firstPt = points.first;
    final lastPt = points.last;
    envelope.moveTo(left.first.dx, left.first.dy);
    for (final o in left.skip(1)) {
      envelope.lineTo(o.dx, o.dy);
    }
    if (tailDrop) {
      // 收笔：沿最终切线的楔形收束，长度随尾部压力衰减，不强制矛尖。
      final last = edges.last;
      final hwPrev = contactHalfWidth(strokeWidth, last.pressure);
      final drop = 1 - pressures.last / math.max(pMax, 1e-9);
      final taper = math.min(4 * hwPrev, hwPrev * drop * 6);
      final tip = ui.Offset(
        lastPt.x + last.tx * taper,
        lastPt.y + last.ty * taper,
      );
      envelope.lineTo(tip.dx, tip.dy);
    } else {
      // 圆端帽（3 点近似半圆）。
      final hwLast = contactHalfWidth(strokeWidth, edges.last.pressure);
      final last = edges.last;
      envelope.lineTo(
        lastPt.x + (-last.ty) * hwLast + last.tx * hwLast * 0.8,
        lastPt.y + (last.tx) * hwLast + last.ty * hwLast * 0.8,
      );
      envelope.lineTo(
        lastPt.x + (-last.ty) * hwLast - last.tx * hwLast * 0.8,
        lastPt.y + (last.tx) * hwLast - last.ty * hwLast * 0.8,
      );
    }
    for (final o in right.reversed) {
      envelope.lineTo(o.dx, o.dy);
    }
    if (startSharp) {
      // 轻入笔：垂直切线的窄入口（自然起笔，不出装饰性顿笔）。
      envelope.lineTo(firstPt.x, firstPt.y);
      envelope.lineTo(left.first.dx, left.first.dy);
    } else {
      final hwFirst = contactHalfWidth(strokeWidth, edges.first.pressure);
      final first = edges.first;
      envelope.lineTo(
        firstPt.x + (first.ty) * hwFirst - first.tx * hwFirst * 0.8,
        firstPt.y + (-first.tx) * hwFirst - first.ty * hwFirst * 0.8,
      );
      envelope.lineTo(
        firstPt.x + (first.ty) * hwFirst + first.tx * hwFirst * 0.8,
        firstPt.y + (-first.tx) * hwFirst + first.ty * hwFirst * 0.8,
      );
    }
    envelope.close();

    // 毫丝：≤2 通道（channel 4/5），宽笔与出锋区的短毫丝细节。
    final strands = ui.Path();
    var strandCount = 0;
    var arc = 0.0;
    for (var i = 0; i < edges.length; i++) {
      final e = edges[i];
      final f = filtered[i];
      final hw = contactHalfWidth(strokeWidth, e.pressure);
      final nearTail = arc > totalLen * 0.75;
      if (hw >= 2.6 && (nearTail || i % 3 == 0)) {
        for (var ch = 0; ch < 2; ch++) {
          final gseed = mix32(seed, e.index, i, 4 + ch);
          final r1 = rand01(gseed, 0x11);
          final r2 = rand01(gseed, 0x22);
          final offsetMag = hw * (0.35 + 0.35 * r1) * (ch == 0 ? 1 : -1);
          final halfLen = 1.2 + 1.3 * r2;
          final cx = e.a.x + f.x * e.len * 0.5 - f.y * offsetMag;
          final cy = e.a.y + f.y * e.len * 0.5 + f.x * offsetMag;
          strands.moveTo(cx - f.x * halfLen, cy - f.y * halfLen);
          strands.lineTo(cx + f.x * halfLen, cy + f.y * halfLen);
          strandCount++;
        }
      }
      arc += e.len;
    }

    final draws = <(ui.Path, double)>[
      (envelope, 1.0),
      if (strandCount > 0) (strands, 0.5),
    ];
    return BrushEnvelopeSpikePlan(
      draws,
      left.length + right.length,
      strandCount,
    );
  }

  /// 两条偏移边界线的交点（受限 miter）。
  ///
  /// 边界线 A 过 v + n1·hw、方向 t（当前 edge 切线）；边界线 B 过
  /// v + n2·hw、方向同 t（相邻 edge 在顶点处共用同一切线方向的偏移
  /// 线族）。解 v + n1·hw + t·a = v + n2·hw → t·a = (n2-n1)·hw。
  /// 距顶点超过 1.5×hw 时按方向截断（防尖刺）。
  static ui.Offset? _miterPoint(
    Point v,
    Point n1,
    Point n2,
    Point t,
    double hw,
  ) {
    final wx = (n2.x - n1.x) * hw;
    final wy = (n2.y - n1.y) * hw;
    final tlen = math.sqrt(t.x * t.x + t.y * t.y);
    if (tlen < 1e-9) return null;
    final tx = t.x / tlen;
    final ty = t.y / tlen;
    final denom = tx * wx + ty * wy;
    final num = wx * wx + wy * wy;
    if (denom.abs() < 1e-9) return null;
    final a = num / denom;
    final ix = v.x + n1.x * hw + tx * a;
    final iy = v.y + n1.y * hw + ty * a;
    final dist = math.sqrt((ix - v.x) * (ix - v.x) + (iy - v.y) * (iy - v.y));
    if (!dist.isFinite) return null;
    if (dist <= _miterLimit * hw) {
      return ui.Offset(ix, iy);
    }
    final scale = _miterLimit * hw / dist;
    return ui.Offset(v.x + (ix - v.x) * scale, v.y + (iy - v.y) * scale);
  }

  static BrushEnvelopeSpikePlan _teardrop(
    _Edge first,
    _Edge last,
    double strokeWidth,
    int seed,
  ) {
    final path = ui.Path();
    // 尺寸按整笔平均压力（短点无起收可言），略放大形成笔肚感；
    // 视觉预审教训：按末边压力定尺寸会让短点塌缩成 ~1/3 线宽。
    final pAvg = (first.pressure + last.pressure) / 2;
    final hw = contactHalfWidth(strokeWidth, pAvg) * 1.3;
    final cx = (first.a.x + last.b.x) / 2;
    final cy = (first.a.y + last.b.y) / 2;
    final ang = math.atan2(last.ty, last.tx);
    path.addOval(
      ui.Rect.fromCenter(
        center: ui.Offset(cx, cy),
        width: hw * 2.0,
        height: hw * 1.6,
      ),
    );
    // 小尾锋（沿末端方向）。
    final tip = ui.Offset(
      cx + math.cos(ang) * hw * 1.4,
      cy + math.sin(ang) * hw * 1.4,
    );
    path.moveTo(cx + math.cos(ang) * hw, cy + math.sin(ang) * hw);
    path.lineTo(tip.dx, tip.dy);
    path.lineTo(cx - math.sin(ang) * hw * 0.2, cy + math.cos(ang) * hw * 0.2);
    path.close();
    return BrushEnvelopeSpikePlan([(path, 1.0)], 6, 0);
  }
}

/// 渲染到白底单元格（placed 坐标，与 v1 基线同视野）。
Future<(NaturalMediaRaster, Uint8List, SpyCanvasCounts2)> renderSpike(
  BrushEnvelopeSpikePlan plan,
) async {
  final recorder = ui.PictureRecorder();
  final spy = SpyCanvas(ui.Canvas(recorder));
  spy.drawRect(
    ui.Rect.fromLTWH(0, 0, kCellWidth, kCellHeight),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  for (final (path, alpha) in plan.draws) {
    spy.drawPath(
      path,
      ui.Paint()..color = const ui.Color(0xFF000000).withValues(alpha: alpha),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(kCellWidth.round(), kCellHeight.round());
  picture.dispose();
  final raster = await NaturalMediaRaster.fromImage(image);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return (
    raster,
    png!.buffer.asUint8List(),
    SpyCanvasCounts2(
      spy.drawCallCount,
      spy.saveLayerCount,
      spy.shaderPathCount,
    ),
  );
}

class SpyCanvasCounts2 {
  const SpyCanvasCounts2(this.drawCalls, this.saveLayers, this.shaderPaths);
  final int drawCalls;
  final int saveLayers;
  final int shaderPaths;
}

List<Point> serpentine(int pointCount) {
  final out = <Point>[];
  var row = 0;
  var goingRight = true;
  while (out.length < pointCount) {
    final y = 20.0 + row * 14.0;
    if (goingRight) {
      for (var x = 20.0; x <= 880 && out.length < pointCount; x += 8) {
        out.add(Point(x, y));
      }
    } else {
      for (var x = 880.0; x >= 20 && out.length < pointCount; x -= 8) {
        out.add(Point(x, y));
      }
    }
    row++;
    goingRight = !goingRight;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final outDir = Directory('build/natural_media_baseline/spike');
  outDir.createSync(recursive: true);

  test('结构门禁：≤2 draw、0 saveLayer、0 shader、有限顶点', () async {
    for (final f in [
      ...brushCalligraphyStrokes,
      brushHengNoTailDrop,
      brushPressureRamp,
      brushSCurve,
      brushShortDot,
    ]) {
      final placed = fitFixtureToCell(f);
      final plan = BrushEnvelopeSpike.build(
        strokeId: 'spike-${f.name}',
        points: placed,
        pressures: f.pressures,
        strokeWidth: kNominalWidth,
      );
      expect(
        plan.draws.length,
        lessThanOrEqualTo(2),
        reason: '${f.name} draw 数 ${plan.draws.length}',
      );
      final (raster, png, counts) = await renderSpike(plan);
      expect(counts.saveLayers, 0);
      expect(counts.shaderPaths, 0);
      expect(plan.boundaryVertexCount, greaterThan(0));
      File('${outDir.path}/brushPen_${f.name}.png').writeAsBytesSync(png);
      // 着墨非空（渲染有效性）。
      var ink = 0;
      for (var y = 0; y < 150; y += 2) {
        for (var x = 0; x < 900; x += 2) {
          if (raster.isInk(x, y)) ink++;
        }
      }
      expect(ink, greaterThan(5), reason: '${f.name} 应着墨（短点 teardrop 采样稀疏）');
    }
  });

  test('确定性：同输入两次构建渲染逐字节一致', () async {
    var plan = BrushEnvelopeSpike.build(
      strokeId: 'spike-det',
      points: fitFixtureToCell(brushSCurve),
      pressures: brushSCurve.pressures,
      strokeWidth: kNominalWidth,
    );
    final (_, pngA, _) = await renderSpike(plan);
    plan = BrushEnvelopeSpike.build(
      strokeId: 'spike-det',
      points: fitFixtureToCell(brushSCurve),
      pressures: brushSCurve.pressures,
      strokeWidth: kNominalWidth,
    );
    final (_, pngB, _) = await renderSpike(plan);
    expect(pngA, equals(pngB));
  });

  test('提按量程（N6 spike 证据）：p=.8/p=.2 宽度比 ≥2.2', () async {
    BrushStrokeFixture probe(String name, double p) => BrushStrokeFixture(
      name: name,
      description: 'N6 $p 恒压探针',
      points: [for (var i = 0; i <= 40; i++) Point(9.0 * i, 0)],
      pressures: List<double>.filled(41, p),
    );

    Future<double> widthOf(BrushStrokeFixture f) async {
      final placed = fitFixtureToCell(f);
      final plan = BrushEnvelopeSpike.build(
        strokeId: 'spike-${f.name}',
        points: placed,
        pressures: f.pressures,
        strokeWidth: kNominalWidth,
      );
      final (raster, _, _) = await renderSpike(plan);
      return WidthProfile.medianCenterWidth(
        raster,
        StrokeArcGeometry(placed),
        strokeWidth: kNominalWidth,
      );
    }

    final lightW = await widthOf(probe('brushLightProbe', 0.20));
    final heavyW = await widthOf(probe('brushHeavyProbe', 0.80));
    final ratio = heavyW / math.max(lightW, 1e-9);
    File('${outDir.path}/brush_pressure_evidence.json').writeAsStringSync('''
{
  "lightWidth": $lightW,
  "heavyWidth": $heavyW,
  "widthRatio": $ratio,
  "theoryRatio": 2.255
}
''');
    expect(ratio, greaterThan(2.2), reason: 'spike 提按宽度比 $ratio 应 > 2.2');
  });

  test('起收口径（N8 spike 证据）：无降压不出矛尖、有降压自然收束', () async {
    Future<double> tailRatioOf(BrushStrokeFixture f) async {
      final placed = fitFixtureToCell(f);
      final plan = BrushEnvelopeSpike.build(
        strokeId: 'spike-${f.name}',
        points: placed,
        pressures: f.pressures,
        strokeWidth: kNominalWidth,
      );
      final (raster, _, _) = await renderSpike(plan);
      final geom = StrokeArcGeometry(placed);
      final mid = WidthProfile.medianCenterWidth(
        raster,
        geom,
        strokeWidth: kNominalWidth,
      );
      final tailFraction =
          1.0 - 2 * kNominalWidth / math.max(geom.totalLength, 1e-9);
      final tail = WidthProfile.widthAtArcFraction(
        raster,
        geom,
        tailFraction.clamp(0.0, 1.0),
        strokeWidth: kNominalWidth,
      );
      return tail / math.max(mid, 1e-9);
    }

    final noDrop = await tailRatioOf(brushHengNoTailDrop);
    final withDrop = await tailRatioOf(brushNa);
    File('${outDir.path}/brush_tail_evidence.json').writeAsStringSync('''
{
  "noTailDropRatio": $noDrop,
  "withDropNaRatio": $withDrop,
  "v1NoTailDropRatio": 0.375,
  "v1WithDropNaRatio": 0.571
}
''');
    expect(
      noDrop,
      greaterThan(0.70),
      reason: 'spike 无降压尾部宽度比 $noDrop 应 ≥0.70（不生成矛尖）',
    );
    expect(
      withDrop,
      lessThan(0.45),
      reason: 'spike 有降压捺尾部宽度比 $withDrop 应 ≤0.45（自然收束）',
    );
  });

  test('转角防护（N7 spike 证据）：包络不超局部目标半宽 1.6 倍', () async {
    final f = brushZhe;
    final placed = fitFixtureToCell(f);
    final plan = BrushEnvelopeSpike.build(
      strokeId: 'spike-${f.name}',
      points: placed,
      pressures: f.pressures,
      strokeWidth: kNominalWidth,
    );
    final (raster, _, _) = await renderSpike(plan);
    final geom = StrokeArcGeometry(placed);
    // 沿弧长 5%～95% 每 2px 法向扫描宽度，与该点目标宽度比较。
    var maxOver = 0.0;
    final step = 2.0 / geom.totalLength;
    for (var t = 0.05; t <= 0.95; t += step) {
      final c = geom.pointAtFraction(t);
      final pAt = _pressureAt(geom, f, t);
      final target =
          2 * BrushEnvelopeSpike.contactHalfWidth(kNominalWidth, pAt);
      final measured = WidthProfile.widthAtArcFraction(
        raster,
        geom,
        t,
        strokeWidth: kNominalWidth,
      );
      if (target > 1e-9) {
        final over = measured / target;
        if (over > maxOver) maxOver = over;
      }
    }
    File('${outDir.path}/brush_corner_evidence.json').writeAsStringSync('''
{
  "maxMeasuredOverTarget": $maxOver,
  "gate": 1.6
}
''');
    expect(
      maxOver,
      lessThan(1.6),
      reason: 'spike 折角实测/目标宽度最大比 $maxOver 应 <1.6',
    );
  });

  test('1k/16k 线性度与耗时探针', () {
    final results = <int, double>{};
    for (final n in [1000, 16000]) {
      final pts = serpentine(n);
      final pressures = [
        for (var i = 0; i < n; i++) 0.3 + 0.5 * math.sin(math.pi * i / n),
      ];
      final sw = Stopwatch()..start();
      final plan = BrushEnvelopeSpike.build(
        strokeId: 'spike-serpentine-$n',
        points: pts,
        pressures: pressures,
        strokeWidth: kNominalWidth,
      );
      sw.stop();
      results[n] = sw.elapsedMicroseconds / 1000.0;
      // 顶点数按弧长界：顶点邻域 1px 加密 + 每 edge 双侧 join
      //（miter ≤2 点或圆弧 6 点），线性上界。
      final arcPx = 8.0 * n;
      expect(
        plan.boundaryVertexCount,
        lessThanOrEqualTo(2 * arcPx + 8 * n + 64),
      );
    }
    final ratio = results[16000]! / math.max(results[1000]!, 1e-9);
    File('${outDir.path}/brush_linearity.json').writeAsStringSync('''
{
  "time1kMs": ${results[1000]},
  "time16kMs": ${results[16000]},
  "ratio": $ratio
}
''');
    expect(
      ratio,
      lessThanOrEqualTo(20),
      reason: '16k/1k 构建耗时比 $ratio 应 ≤20（无 O(n²)）',
    );
  });
}

double _pressureAt(StrokeArcGeometry geom, BrushStrokeFixture f, double t) {
  // 弧长比例 t 处线性插值压力（fixture 点距均匀近似）。
  final want = t * geom.totalLength;
  var acc = 0.0;
  for (var i = 1; i < f.points.length; i++) {
    final seg = f.points[i - 1].distanceTo(f.points[i]);
    if (acc + seg >= want || i == f.points.length - 1) {
      final u = seg <= 0 ? 0.0 : ((want - acc) / seg).clamp(0.0, 1.0);
      return f.pressures[i - 1] + (f.pressures[i] - f.pressures[i - 1]) * u;
    }
    acc += seg;
  }
  return f.pressures.last;
}
