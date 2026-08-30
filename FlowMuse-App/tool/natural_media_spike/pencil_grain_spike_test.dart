// tool/natural_media_spike/pencil_grain_spike_test.dart
//
// T0 可删除原型（计划 T0 工作项 7/8）：≤4 复合 Path 的确定性铅笔颗粒
// 渲染原型。只用固定 fixture，不接生产 Scene。证明：
//  - 无 shader、无 saveLayer 的纯 Path 路线可得到 HB 铅笔目标效果；
//  - 1k/16k 点结构与耗时线性（无 O(n²)）。
// T0 收口时删除本文件（§3.6 正式实现进 T4）。
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

const _kappa = 0.5522847498307936;

class PencilGrainSpikePlan {
  PencilGrainSpikePlan(this.draws, this.particleCount);

  /// (path, alpha) ≤4 项：基底 + 低/中/重三个密度桶（重压桶可缺省）。
  final List<(ui.Path, double)> draws;
  final int particleCount;
}

class PencilGrainSpike {
  /// 密度桶（spike 校准值；T4 由 profile 冻结）。
  static const _buckets = [
    (
      channel: 1,
      minPressure: 0.00,
      spacingA: 3.4,
      spacingB: 1.6,
      minSpacing: 1.6,
      alpha: 0.20,
    ),
    (
      channel: 2,
      minPressure: 0.30,
      spacingA: 6.0,
      spacingB: 5.0,
      minSpacing: 2.2,
      alpha: 0.28,
    ),
    (
      channel: 3,
      minPressure: 0.65,
      spacingA: 7.5,
      spacingB: 6.0,
      minSpacing: 2.6,
      alpha: 0.38,
    ),
  ];

  /// §3.5 候选曲线（非验收常数）：宽度只随压力温和变化。
  static double localWidth(double base, double p) => base * (0.82 + 0.28 * p);

  static PencilGrainSpikePlan build({
    required String strokeId,
    required List<Point> points,
    required List<double> pressures,
    required double strokeWidth,
    bool isComplete = true,
    int particleCap = 4096,
  }) {
    final seed = strokeSeedOf(strokeId);
    final base = ui.Path();
    final bucketPaths = [ui.Path(), ui.Path(), ui.Path()];
    final bucketActive = [false, false, false];
    var particles = 0;

    // 粒子先收集（edge, ordinal, channel, cx, cy, tx, ty, w），统一限流。
    final grains = <(int, int, int, double, double, double, double, double)>[];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final len = a.distanceTo(b);
      if (len < 1e-9) continue;
      final tx = (b.x - a.x) / len;
      final ty = (b.y - a.y) / len;
      final nx = -ty;
      final ny = tx;
      final p = ((pressures[i - 1] + pressures[i]) / 2).clamp(0.0, 1.0);
      final w = localWidth(strokeWidth, p);
      for (var bi = 0; bi < _buckets.length; bi++) {
        final bkt = _buckets[bi];
        if (p < bkt.minPressure) continue;
        final spacing = math.max(
          bkt.minSpacing,
          bkt.spacingA - bkt.spacingB * p,
        );
        var ordinal = 0;
        for (var s = 0.0; s < len; s += spacing) {
          final gseed = mix32(seed, i, ordinal, bkt.channel);
          final alongJitter = (rand01(gseed, 0x11) - 0.5) * spacing * 0.6;
          final sJit = (s + alongJitter).clamp(0.0, len);
          final normalOffset = (rand01(gseed, 0x22) * 2 - 1) * w * 0.225;
          grains.add((
            i,
            ordinal,
            bkt.channel,
            a.x + tx * sJit + nx * normalOffset,
            a.y + ty * sJit + ny * normalOffset,
            tx,
            ty,
            w,
          ));
          ordinal++;
        }
      }
    }

    // 稳定降采样：超限时按稳定步长取整索引，保留首尾。
    var selected = grains;
    if (grains.length > particleCap) {
      final stride = grains.length / particleCap;
      selected = [
        for (var k = 0; k < particleCap; k++) grains[(k * stride).floor()],
      ]..[particleCap - 1] = grains.last;
    }
    particles = selected.length;

    // 基底：低 alpha 连续带轻微宽度抖动的偏移多边形 + 圆端帽。
    _buildBasePath(base, seed, points, pressures, strokeWidth);

    for (final g in selected) {
      final (edge, ordinal, channel, cx, cy, tx, ty, w) = g;
      final gseed = mix32(seed, edge, ordinal, channel);
      final halfLen = math.max(0.55, w * (0.30 + 0.22 * rand01(gseed, 0x33)));
      final halfThick = math.max(0.45, 0.10 * w + 0.25 * rand01(gseed, 0x44));
      final bi = channel - 1;
      _addRotatedEllipse(bucketPaths[bi], cx, cy, tx, ty, halfLen, halfThick);
      bucketActive[bi] = true;
    }

    final draws = <(ui.Path, double)>[(base, 0.30)];
    for (var bi = 0; bi < _buckets.length; bi++) {
      if (bucketActive[bi]) {
        draws.add((bucketPaths[bi], _buckets[bi].alpha));
      }
    }
    return PencilGrainSpikePlan(draws, particles);
  }

  /// 基底：沿折线 2px 步进，半宽 = w/2×(0.85+0.3×seed)，端帽圆弧。
  /// 单遍增量弧长行走（O(n)）：逐边推进累计弧长，在边内插值发射采样，
  /// 禁止每个采样点从头扫描折线（1k/16k 线性度探针实测 O(n²) 会到
  /// 200+ 倍比）。
  static void _buildBasePath(
    ui.Path path,
    int seed,
    List<Point> points,
    List<double> pressures,
    double strokeWidth,
  ) {
    if (points.length < 2) {
      if (points.isNotEmpty) {
        final w = localWidth(strokeWidth, pressures.first);
        path.addOval(
          ui.Rect.fromCircle(
            center: ui.Offset(points.first.x, points.first.y),
            radius: w / 2,
          ),
        );
      }
      return;
    }
    final left = <ui.Offset>[];
    final right = <ui.Offset>[];
    var acc = 0.0;
    var nextT = 0.0;
    var k = 0;
    var lastTan = const Point(1, 0);
    var lastPressure = pressures.first;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final seg = a.distanceTo(b);
      if (seg < 1e-9) continue;
      final tx = (b.x - a.x) / seg;
      final ty = (b.y - a.y) / seg;
      while (nextT <= acc + seg + 1e-9) {
        final u = ((nextT - acc) / seg).clamp(0.0, 1.0);
        final px = a.x + (b.x - a.x) * u;
        final py = a.y + (b.y - a.y) * u;
        final p = pressures[i - 1] + (pressures[i] - pressures[i - 1]) * u;
        final w = localWidth(strokeWidth, p);
        final wob = 0.85 + 0.30 * rand01(mix32(seed, k, 0, 0), 0x55);
        final hw = w / 2 * wob;
        left.add(ui.Offset(px - ty * hw, py + tx * hw));
        right.add(ui.Offset(px + ty * hw, py - tx * hw));
        lastTan = Point(tx, ty);
        lastPressure = p;
        k++;
        nextT += 2.0;
      }
      acc += seg;
    }
    // 尾点（nextT 未精确覆盖 total 时补齐）。
    {
      final w = localWidth(strokeWidth, lastPressure);
      final hw = w / 2 * (0.85 + 0.30 * rand01(mix32(seed, k, 0, 0), 0x55));
      final pos = points.last;
      left.add(ui.Offset(pos.x - lastTan.y * hw, pos.y + lastTan.x * hw));
      right.add(ui.Offset(pos.x + lastTan.y * hw, pos.y - lastTan.x * hw));
    }
    path.moveTo(left.first.dx, left.first.dy);
    for (final o in left.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    _addCap(path, points.last, left.last, right.last);
    for (final o in right.reversed) {
      path.lineTo(o.dx, o.dy);
    }
    _addCap(path, points.first, right.last, left.first);
    path.close();
  }

  static void _addCap(ui.Path path, Point end, ui.Offset a, ui.Offset b) {
    // 端帽：a→end→b 的三段折线近似半圆（granular 风格无需真圆弧）。
    path.lineTo(end.x, end.y);
    path.lineTo(b.dx, b.dy);
  }

  static void _addRotatedEllipse(
    ui.Path path,
    double cx,
    double cy,
    double tx,
    double ty,
    double halfLen,
    double halfThick,
  ) {
    // 长轴基向量（切向）与短轴基向量（法向）。
    final ux = tx * halfLen;
    final uy = ty * halfLen;
    final vx = -ty * halfThick;
    final vy = tx * halfThick;
    ui.Offset at(double s, double c) =>
        ui.Offset(cx + ux * s + vx * c, cy + uy * s + vy * c);
    final p0 = at(1, 0);
    final p1 = at(0, 1);
    final p2 = at(-1, 0);
    final p3 = at(0, -1);
    final kl = _kappa * halfLen;
    final kt = _kappa * halfThick;
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

/// 渲染 spike plan 到白底单元格栅格（含结构计数）。
Future<(NaturalMediaRaster, Uint8List, SpyCanvasCounts)> renderSpike(
  PencilGrainSpikePlan plan,
) async {
  final recorder = ui.PictureRecorder();
  final spy = SpyCanvas(ui.Canvas(recorder));
  spy.drawRect(
    ui.Rect.fromLTWH(0, 0, 900, 150),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  for (final (path, alpha) in plan.draws) {
    spy.drawPath(
      path,
      ui.Paint()..color = const ui.Color(0xFF000000).withValues(alpha: alpha),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(900, 150);
  picture.dispose();
  final raster = await NaturalMediaRaster.fromImage(image);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return (
    raster,
    png!.buffer.asUint8List(),
    SpyCanvasCounts(spy.drawCallCount, spy.saveLayerCount, spy.shaderPathCount),
  );
}

class SpyCanvasCounts {
  const SpyCanvasCounts(this.drawCalls, this.saveLayers, this.shaderPaths);
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

  test('结构门禁：≤4 draw、0 saveLayer、0 shader、粒子上限', () async {
    for (final f in [
      pencilLightStroke,
      pencilMediumStroke,
      pencilHeavyStroke,
      pencilPressureRamp,
      pencilRightAngleCorner,
      pencilShortDot,
    ]) {
      final placed = fitFixtureToCell(f);
      final plan = PencilGrainSpike.build(
        strokeId: 'spike-${f.name}',
        points: placed,
        pressures: f.pressures,
        strokeWidth: kNominalWidth,
      );
      expect(
        plan.draws.length,
        lessThanOrEqualTo(4),
        reason: '${f.name} draw 数 ${plan.draws.length}',
      );
      expect(
        plan.particleCount,
        lessThanOrEqualTo(4096),
        reason: '${f.name} 粒子数 ${plan.particleCount}',
      );
      final (_, png, counts) = await renderSpike(plan);
      expect(counts.saveLayers, 0);
      expect(counts.shaderPaths, 0);
      File(
        '${outDir.path}/pencil_${f.name}.png',
      ).writeAsBytesSync(png.buffer.asUint8List());
    }
  });

  test('确定性：同输入两次构建渲染逐字节一致', () async {
    var plan = PencilGrainSpike.build(
      strokeId: 'spike-det',
      points: pencilPressureRamp.points,
      pressures: pencilPressureRamp.pressures,
      strokeWidth: 6,
    );
    final (_, pngA, _) = await renderSpike(plan);
    plan = PencilGrainSpike.build(
      strokeId: 'spike-det',
      points: pencilPressureRamp.points,
      pressures: pencilPressureRamp.pressures,
      strokeWidth: 6,
    );
    final (_, pngB, _) = await renderSpike(plan);
    expect(pngA, equals(pngB));
  });

  test('压感口径：浓淡主导、宽度受限（spike 证据）', () async {
    Future<double> widthOf(BrushStrokeFixture f) async {
      final placed = fitFixtureToCell(f);
      final plan = PencilGrainSpike.build(
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

    Future<double> darknessOf(BrushStrokeFixture f, double hw) async {
      final placed = fitFixtureToCell(f);
      final plan = PencilGrainSpike.build(
        strokeId: 'spike-${f.name}',
        points: placed,
        pressures: f.pressures,
        strokeWidth: kNominalWidth,
      );
      final (raster, _, _) = await renderSpike(plan);
      return CenterBandDarkness.commonBandMeanDarkness(
        raster,
        StrokeArcGeometry(placed),
        commonHalfWidth: hw,
      );
    }

    final lightW = await widthOf(pencilLightStroke);
    final heavyW = await widthOf(pencilHeavyStroke);
    final hw = CenterBandDarkness.commonHalfWidth(lightW, heavyW);
    final lightD = await darknessOf(pencilLightStroke, hw);
    final heavyD = await darknessOf(pencilHeavyStroke, hw);

    final darkRatio = heavyD / math.max(lightD, 1e-9);
    final widthRatio = heavyW / math.max(lightW, 1e-9);

    // fixture 坐标未归一化到单元格：放大 2.5 倍再渲染（与 v1 基线同视野）。
    File('${outDir.path}/pencil_pressure_evidence.json').writeAsStringSync('''
{
  "lightWidth": $lightW,
  "heavyWidth": $heavyW,
  "widthRatio": $widthRatio,
  "lightDarkness": $lightD,
  "heavyDarkness": $heavyD,
  "darknessRatio": $darkRatio,
  "lightRms": "见 spike_edge_metrics",
  "note": "placed 单元格坐标，与 v1 基线同视野同算式"
}
''');

    expect(
      darkRatio,
      greaterThan(1.35),
      reason: 'spike 浓度比 $darkRatio 应 > 1.35（N2 方向可行）',
    );
    expect(
      widthRatio,
      lessThanOrEqualTo(1.40),
      reason:
          'spike 宽度比 $widthRatio 应 ≤1.40（1px 采样量化容差；'
          'T4 正式门禁 1.35）',
    );
  });

  test('边缘指标：不规则度与周期峰（spike 校准测量）', () async {
    final placed = fitFixtureToCell(pencilLightStroke);
    final plan = PencilGrainSpike.build(
      strokeId: 'spike-light',
      points: placed,
      pressures: pencilLightStroke.pressures,
      strokeWidth: kNominalWidth,
    );
    final (raster, _, _) = await renderSpike(plan);
    final geom = StrokeArcGeometry(placed);
    final rms = EdgeIrregularity.residualRmsOverWidth(
      raster,
      geom,
      strokeWidth: kNominalWidth,
    );
    final peak = Periodicity.maxEdgeAutocorrelationPeak(
      raster,
      geom,
      strokeWidth: kNominalWidth,
    );
    File('${outDir.path}/pencil_edge_metrics.json').writeAsStringSync('''
{
  "spikeLightRms": $rms,
  "spikeLightAutocorrPeak": $peak,
  "v1LightRms": 0.12555393464860268,
  "v1LightAutocorrPeak": 0.2783018867924519
}
''');
    expect(
      peak,
      lessThan(NaturalMediaFrozen.autocorrPeakMax),
      reason: 'spike 周期峰 $peak 应 < 冻结上限',
    );
    expect(rms, greaterThan(0), reason: 'spike 应有可测边缘不规则度');
  });

  test('生成 v1-vs-spike 对比测试纸（有标签）', () {
    // v1 单元格在 build/natural_media_baseline/cells/，spike 在 spike/。
    // 按 fixture 名配对成 [v1 | spike] 两列行，供用户目标确认。
    final v1Dir = Directory('build/natural_media_baseline/cells');
    final spikeDir = Directory('build/natural_media_baseline/spike');
    if (!v1Dir.existsSync() || !spikeDir.existsSync()) {
      return; // v1 基线未跑时不阻塞 spike 单测
    }
    final spikePngs = {
      for (final f in spikeDir.listSync())
        if (f.path.endsWith('.png')) f.uri.pathSegments.last,
    };
    // v1 单元格与 spike 产物按同一命名规则生成（<brush>_<fixture>.png），
    // 直接同名配对。
    final buffer = StringBuffer('''
<html><head><meta charset="utf-8"><title>v1 vs spike v2 目标确认纸</title></head>
<body style="font-family:sans-serif;background:#f6f6f6">
<h2>铅笔与毛笔自然介质：v1（左） vs 纯 Path spike v2（右）</h2>
<p>同名 fixture · 名义笔宽 6 · 黑色 · 白底 · zoom=1 · dpr=1。
左列是当前 v1 渲染，右列是 T0 可删除原型（无 shader、无 saveLayer、
铅笔 ≤4 Path / 毛笔 ≤2 Path）。确认口径见计划 §2。</p>
''');
    var paired = 0;
    for (final f in v1Dir.listSync()) {
      if (!f.path.endsWith('.png')) continue;
      final name = f.uri.pathSegments.last;
      final match = spikePngs.lookup(name);
      if (match == null) continue;
      buffer.write('''
<p>$name</p>
<table><tr>
<td><img src="cells/$name" style="width:440px;height:73px;border:1px solid #ccc"></td>
<td><img src="spike/$match" style="width:440px;height:73px;border:1px solid #ccc"></td>
</tr></table>''');
      paired++;
    }
    buffer.write('</body></html>');
    File(
      'build/natural_media_baseline/spike_sheet_labeled.html',
    ).writeAsStringSync(buffer.toString());
    expect(paired, greaterThan(8), reason: '至少配对 8 行（铅笔+毛笔）');
  });

  test('1k/16k 线性度与耗时探针', () {
    final results = <int, double>{};
    final counts = <int, int>{};
    for (final n in [1000, 16000]) {
      final pts = serpentine(n);
      final pressures = [
        for (var i = 0; i < n; i++) 0.3 + 0.5 * math.sin(math.pi * i / n),
      ];
      final sw = Stopwatch()..start();
      final plan = PencilGrainSpike.build(
        strokeId: 'spike-serpentine-$n',
        points: pts,
        pressures: pressures,
        strokeWidth: 6,
      );
      sw.stop();
      results[n] = sw.elapsedMicroseconds / 1000.0;
      counts[n] = plan.particleCount;
      expect(plan.particleCount, lessThanOrEqualTo(4096));
    }
    final ratio = results[16000]! / math.max(results[1000]!, 1e-9);
    File('${outDir.path}/pencil_linearity.json').writeAsStringSync('''
{
  "time1kMs": ${results[1000]},
  "time16kMs": ${results[16000]},
  "ratio": $ratio,
  "particles1k": ${counts[1000]},
  "particles16k": ${counts[16000]}
}
''');
    expect(
      ratio,
      lessThanOrEqualTo(20),
      reason: '16k/1k 构建耗时比 $ratio 应 ≤20（无 O(n²)）',
    );
  });
}
