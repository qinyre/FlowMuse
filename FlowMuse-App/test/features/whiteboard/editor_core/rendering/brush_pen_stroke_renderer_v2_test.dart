import 'dart:io';
import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/brush_pen_stroke_renderer_v2.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_stroke_plan.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_stroke_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/brush_stroke_fixtures.dart';
import 'natural_media/natural_media_image_metrics.dart';
import 'natural_media_visual_sheet_support.dart';

// ---------------------------------------------------------------------------
// T5：毛笔 v2 渲染器验收（计划任务卡）：结构门禁（≤2 draw）、宽度量程
//（N6）、轻压可见（N7）、起收形状（N8）、转角尖刺防护、分块一致性、
// 可视 bounds（工作项 8）、透明度/dim（工作项 9）、确定性、v1 不变。
//
// 渲染经由 ElementRenderer 唯一分发点（v2 元素自动进
// BrushPenStrokeRendererV2），像素口径全部来自 T0 冻结指标。
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final outDir = Directory('build/natural_media_baseline/v2_brush');
  outDir.createSync(recursive: true);

  Future<PlacedRender> renderFixture(
    BrushStrokeFixture f, {
    int repeat = 1,
  }) async {
    final placed = fitFixtureToCell(f);
    final render = await renderPlaced(
      placed,
      f.pressures,
      BrushType.brushPen,
      f.name,
      repeat: repeat,
    );
    writeCellPng('${outDir.path}/${f.name}.png', render);
    return render;
  }

  BrushStrokeFixture constantPressure(String name, double p) =>
      BrushStrokeFixture(
        name: name,
        description: '$name 恒压探针',
        points: [for (var i = 0; i <= 40; i++) Point(9.0 * i, 0)],
        pressures: List<double>.filled(41, p),
      );

  test('N18 结构：≤2 主要 draw、0 saveLayer、0 shader、planBuildCount', () async {
    BrushPenStrokeRendererV2.resetPlanBuildCountForTest();
    final all = [
      ...brushCalligraphyStrokes,
      brushHengNoTailDrop,
      brushPressureRamp,
      brushSCurve,
      brushShortDot,
    ];
    for (final f in all) {
      final render = await renderFixture(f);
      expect(
        render.drawCallCount - 1,
        lessThanOrEqualTo(2),
        reason:
            '${f.name} 主要 draw（-1 背景矩形）'
            ' ${render.drawCallCount - 1} 应 ≤2',
      );
      expect(render.saveLayerCount, 0, reason: '${f.name} saveLayer');
      expect(render.shaderPathCount, 0, reason: '${f.name} shader');
    }
    expect(
      BrushPenStrokeRendererV2.planBuildCount,
      all.length,
      reason: '每次静态渲染恰好构建一次 plan（无缓存预建）',
    );
  });

  test('N6 宽度量程：p=.8/p=.2 恒压中位宽度比 ≥2.2', () async {
    final light = constantPressure('v2BrushLightProbe', 0.20);
    final heavy = constantPressure('v2BrushHeavyProbe', 0.80);
    final lightRender = await renderFixture(light);
    final heavyRender = await renderFixture(heavy);
    final lightW = WidthProfile.medianCenterWidth(
      lightRender.raster,
      StrokeArcGeometry(fitFixtureToCell(light)),
      strokeWidth: kNominalWidth,
    );
    final heavyW = WidthProfile.medianCenterWidth(
      heavyRender.raster,
      StrokeArcGeometry(fitFixtureToCell(heavy)),
      strokeWidth: kNominalWidth,
    );
    final ratio = heavyW / math.max(lightW, 1e-9);
    File('${outDir.path}/n6_n7_evidence.json').writeAsStringSync('''
{
  "lightWidth": $lightW,
  "heavyWidth": $heavyW,
  "widthRatio": $ratio
}
''');
    expect(ratio, greaterThan(2.2), reason: 'N6 中段宽度比 $ratio 应 >2.2');
    // N7：轻压线持续可见（不受 0.5 地板影响）。
    expect(lightW, greaterThan(2.0), reason: 'N7 轻压中位有效宽度 $lightW px 应 >2px');
  });

  test('N8 起收：无尾部降压不收矛尖；有降压的捺自然收束', () async {
    final noDrop = await renderFixture(brushHengNoTailDrop);
    final noDropGeom = StrokeArcGeometry(fitFixtureToCell(brushHengNoTailDrop));
    final midWidth = WidthProfile.medianCenterWidth(
      noDrop.raster,
      noDropGeom,
      strokeWidth: kNominalWidth,
    );
    final tailFraction =
        1.0 - 2 * kNominalWidth / math.max(noDropGeom.totalLength, 1e-9);
    final tailWidth = WidthProfile.widthAtArcFraction(
      noDrop.raster,
      noDropGeom,
      tailFraction.clamp(0.0, 1.0),
      strokeWidth: kNominalWidth,
    );
    final noDropRatio = tailWidth / math.max(midWidth, 1e-9);
    expect(
      noDropRatio,
      greaterThanOrEqualTo(0.70),
      reason: 'N8 无尾部降压横画距尾 2×size 宽度比 $noDropRatio 应 ≥0.70',
    );

    final na = await renderFixture(brushNa);
    final naGeom = StrokeArcGeometry(fitFixtureToCell(brushNa));
    final naMid = WidthProfile.medianCenterWidth(
      na.raster,
      naGeom,
      strokeWidth: kNominalWidth,
    );
    final naTailFraction =
        1.0 - 2 * kNominalWidth / math.max(naGeom.totalLength, 1e-9);
    final naTail = WidthProfile.widthAtArcFraction(
      na.raster,
      naGeom,
      naTailFraction.clamp(0.0, 1.0),
      strokeWidth: kNominalWidth,
    );
    final naRatio = naTail / math.max(naMid, 1e-9);
    File('${outDir.path}/n8_evidence.json').writeAsStringSync('''
{
  "noDropMidWidth": $midWidth,
  "noDropTailWidth": $tailWidth,
  "noDropTailRatio": $noDropRatio,
  "naMidWidth": $naMid,
  "naTailWidth": $naTail,
  "naTailRatio": $naRatio
}
''');
    expect(
      naRatio,
      lessThan(noDropRatio),
      reason: 'N8 有尾部降压的捺（$naRatio）应比无降压横（$noDropRatio）收束',
    );
    // 收笔楔形：isComplete + 尾部降压时，墨迹越过最后一个输入点
    //（出锋），无降压时不越过。
    final naInk = _inkBounds(na.raster)!;
    final naLast = fitFixtureToCell(brushNa).last;
    expect(naInk.$3, greaterThan(naLast.x), reason: '捺的出锋墨迹应越过最后输入点（收笔楔形存在）');
  });

  test('转角尖刺防护：90°/135° join 突出 ≤ 局部接触宽度 1.6 倍且锐走圆弧', () async {
    final corner90 = <Point>[
      for (var i = 0; i <= 12; i++) Point(10.0 * i, 0),
      for (var i = 1; i <= 12; i++) Point(120.0, 10.0 * i),
    ];
    // 135° 转角：水平向右 → 左上方向（方向变化 135°）。
    final dirX = math.cos(3 * math.pi / 4);
    final dirY = math.sin(3 * math.pi / 4);
    final corner135 = <Point>[
      for (var i = 0; i <= 10; i++) Point(10.0 * i, 0),
      for (var i = 1; i <= 10; i++)
        Point(100 + 10.0 * i * dirX, 10.0 * i * dirY),
    ];
    for (final (name, pts) in [('90°', corner90), ('135°', corner135)]) {
      final plan = NaturalMediaStrokeSampler.sample(
        strokeId: 'v2-corner-$name',
        points: pts,
        pressures: List<double>.filled(pts.length, 0.6),
        strokeWidth: kNominalWidth,
        brushType: BrushType.brushPen,
        isComplete: true,
      );
      final profile = BrushRenderProfile.forType(BrushType.brushPen);
      final hwLocal = profile.brushNaturalMediaContactHalfWidth(
        kNominalWidth,
        0.6,
      );
      // 转角边（方向突变处）的 join 突出度：join 点到转角顶点的距离
      // ≤ 1.6×局部接触半宽（尖刺防护，T5 验收口径）。90° 转角在像素
      // 法向扫描下会沿另一条腿读到假宽度，故以 plan 几何直接断言。
      var checkedJoins = 0;
      for (var i = 1; i < pts.length - 1; i++) {
        final turn = _turnAngle(pts[i - 1], pts[i], pts[i + 1]);
        if (turn < math.pi / 4) continue; // 只查显著转角
        for (final p in plan.primitives) {
          if (p.kind != NaturalMediaPrimitiveKind.brushJoin) continue;
          if (p.edgeIndex != i + 1) continue;
          checkedJoins++;
          final d = math.sqrt(
            math.pow(p.center!.x - pts[i].x, 2) +
                math.pow(p.center!.y - pts[i].y, 2),
          );
          expect(
            d,
            lessThanOrEqualTo(1.6 * hwLocal + 1e-9),
            reason: '$name 转角 join 突出 $d 应 ≤1.6×局部半宽 ${1.6 * hwLocal}',
          );
          // 锐转（>75°）必须走圆弧 join（防偏移折叠自交）。
          if (turn > 75 * math.pi / 180) {
            expect(
              p.paintBucket,
              'brushJoinArc',
              reason: '$name 锐转 ${turn * 180 / math.pi}° 应使用圆弧 join',
            );
          }
        }
      }
      expect(checkedJoins, greaterThan(0), reason: '$name 必须发射转角 join');
    }
  });

  test('分块一致性：两段 owned 边的 primitive 并集 = 整笔，边界逐值相等', () async {
    final placed = fitFixtureToCell(brushZhe);
    final abs = placed;
    final prs = brushZhe.pressures;
    Future<NaturalMediaStrokePlan> sample(int? s, int? e) => Future.value(
      NaturalMediaStrokeSampler.sample(
        strokeId: 'chunk-brush-zhe',
        points: abs,
        pressures: prs,
        strokeWidth: kNominalWidth,
        brushType: BrushType.brushPen,
        isComplete: true,
        ownedEdgeStart: s,
        ownedEdgeEndExclusive: e,
      ),
    );
    final full = await sample(null, null);
    final totalEdges = full.edges.last.index;
    final k = totalEdges ~/ 2;
    final c1 = await sample(null, k);
    final c2 = await sample(k, null);
    final fullKeys = full.primitiveKeyDigest().toSet();
    final chunkKeys = <String>{
      ...c1.primitiveKeyDigest(),
      ...c2.primitiveKeyDigest(),
    };
    expect(chunkKeys, equals(fullKeys), reason: '分块 primitive key 并集必须与整笔完全相等');
    // 边界边（k-1 与 k）的包络顶点逐值相等（含切线与半宽）。
    String vertexFingerprint(NaturalMediaStrokePlan plan, int edgeIndex) {
      final buf = StringBuffer();
      for (final p in plan.primitives) {
        if (p.kind != NaturalMediaPrimitiveKind.brushEnvelopeVertex ||
            p.edgeIndex != edgeIndex) {
          continue;
        }
        buf
          ..write(p.center!.x.toStringAsFixed(9))
          ..write(',')
          ..write(p.center!.y.toStringAsFixed(9))
          ..write(',')
          ..write(p.halfThickness!.toStringAsFixed(9))
          ..write(';');
      }
      return buf.toString();
    }

    // 边界边按所有权分属两块：k-1 归前块、k 归后块，各与整笔逐值相等。
    expect(
      vertexFingerprint(c1, k - 1),
      equals(vertexFingerprint(full, k - 1)),
      reason: '边 ${k - 1}（前块）与整笔包络顶点应逐值相等',
    );
    expect(
      vertexFingerprint(c2, k),
      equals(vertexFingerprint(full, k)),
      reason: '边 $k（后块）与整笔包络顶点应逐值相等',
    );
    // 交界 join(k-1→k) 归较后 edge（k），后块必须完整复现整笔的
    // 入口 join（bucket+ordinal 序列一致）。
    List<String> joinKeys(NaturalMediaStrokePlan plan, int edgeIndex) => [
      for (final p in plan.primitives)
        if (p.kind == NaturalMediaPrimitiveKind.brushJoin &&
            p.edgeIndex == edgeIndex)
          '${p.paintBucket}:${p.ordinal}',
    ];
    expect(
      joinKeys(c2, k),
      equals(joinKeys(full, k)),
      reason: '交界 join 归后块且与整笔一致',
    );
    expect(full.stats.droppedNonFinite, 0, reason: '非有限坐标为 0');
  });

  test('工作项8 可视 bounds：包络/出锋墨迹包络不越 elementVisualBounds', () async {
    for (final f in [
      brushHeng,
      brushNa,
      brushTi,
      brushZhe,
      brushGou,
      brushShortDot,
    ]) {
      final placed = fitFixtureToCell(f);
      final render = await renderFixture(f);
      final ink = _inkBounds(render.raster);
      expect(ink, isNotNull, reason: '${f.name} 必须有墨迹');
      final element = placedElement(
        placed,
        f.pressures,
        BrushType.brushPen,
        f.name,
      );
      final vb = elementVisualBounds(element);
      // 像素 x 覆盖 [x, x+1)；AA 只会采样到几何边界外 <1px。
      expect(
        ink!.$1,
        greaterThanOrEqualTo(vb.left - 1),
        reason: '${f.name} 左缘墨迹越界',
      );
      expect(
        ink.$2,
        greaterThanOrEqualTo(vb.top - 1),
        reason: '${f.name} 上缘墨迹越界',
      );
      expect(
        ink.$3 + 1,
        lessThanOrEqualTo(vb.right + 1),
        reason: '${f.name} 右缘墨迹越界',
      );
      expect(
        ink.$4 + 1,
        lessThanOrEqualTo(vb.bottom + 1),
        reason: '${f.name} 下缘墨迹越界',
      );
    }
  });

  test('工作项9a 元素低 opacity：更浅、确定、不新增 draw/saveLayer', () async {
    final placed = fitFixtureToCell(brushHeng);
    final full = await renderPlaced(
      placed,
      brushHeng.pressures,
      BrushType.brushPen,
      'brushOpacity',
    );
    final half1 = await renderPlaced(
      placed,
      brushHeng.pressures,
      BrushType.brushPen,
      'brushOpacity',
      opacity: 0.5,
    );
    final half2 = await renderPlaced(
      placed,
      brushHeng.pressures,
      BrushType.brushPen,
      'brushOpacity',
      opacity: 0.5,
    );
    final geom = StrokeArcGeometry(placed);
    final width = WidthProfile.medianCenterWidth(
      full.raster,
      geom,
      strokeWidth: kNominalWidth,
    );
    final fullDark = CenterBandDarkness.commonBandMeanDarkness(
      full.raster,
      geom,
      commonHalfWidth: width / 2,
    );
    final halfDark = CenterBandDarkness.commonBandMeanDarkness(
      half1.raster,
      geom,
      commonHalfWidth: width / 2,
    );
    expect(
      halfDark,
      lessThan(fullDark),
      reason: '元素 opacity=0.5 中心带必须更浅（$halfDark vs $fullDark）',
    );
    expect(
      half1.drawCallCount,
      equals(full.drawCallCount),
      reason: '低 opacity 不允许改变 draw 结构（无重复合成接缝）',
    );
    expect(half1.saveLayerCount, 0);
    expect(half1.pngBytes, equals(half2.pngBytes), reason: '低 opacity 下仍逐字节确定');
  });

  test('工作项9b 聚焦 dim：白 0.22 saveLayer 三明治下更浅、确定、结构不变', () async {
    final placed = fitFixtureToCell(brushHeng);
    final plain = await renderPlaced(
      placed,
      brushHeng.pressures,
      BrushType.brushPen,
      'brushDim',
    );
    final dim1 = await renderPlaced(
      placed,
      brushHeng.pressures,
      BrushType.brushPen,
      'brushDim',
      dimWrap: true,
    );
    final dim2 = await renderPlaced(
      placed,
      brushHeng.pressures,
      BrushType.brushPen,
      'brushDim',
      dimWrap: true,
    );
    final geom = StrokeArcGeometry(placed);
    final width = WidthProfile.medianCenterWidth(
      plain.raster,
      geom,
      strokeWidth: kNominalWidth,
    );
    final plainDark = CenterBandDarkness.commonBandMeanDarkness(
      plain.raster,
      geom,
      commonHalfWidth: width / 2,
    );
    final dimDark = CenterBandDarkness.commonBandMeanDarkness(
      dim1.raster,
      geom,
      commonHalfWidth: width / 2,
    );
    expect(
      dimDark,
      lessThan(plainDark),
      reason: 'dim 三明治下中心带必须更浅（$dimDark vs $plainDark）',
    );
    expect(
      dim1.drawCallCount,
      equals(plain.drawCallCount),
      reason: 'dim 是画布级包裹，渲染器 draw 结构必须不变',
    );
    expect(dim1.saveLayerCount, 1);
    expect(dim1.pngBytes, equals(dim2.pngBytes));
  });

  test('N10 确定性：同元素两次渲染 PNG 逐字节一致', () async {
    final a = await renderFixture(brushSCurve);
    final b = await renderFixture(brushSCurve);
    expect(a.pngBytes, equals(b.pngBytes));
  });

  test('v1 毛笔不受影响：classic 元数据走 v1 路径且像素不同于 v2', () async {
    final placed = fitFixtureToCell(brushHeng);
    final v1 = await renderPlaced(
      placed,
      brushHeng.pressures,
      BrushType.brushPen,
      'v1lock',
      renderVersion: BrushRenderVersion.classicV1,
    );
    final v2 = await renderPlaced(
      placed,
      brushHeng.pressures,
      BrushType.brushPen,
      'v1lock',
    );
    expect(v1.pngBytes, isNot(equals(v2.pngBytes)), reason: 'v1/v2 分发必须产生不同渲染');
    // v1 毛笔的结构计数（背景 + 单次轮廓填充 = 2，T0 基线）。
    expect(v1.drawCallCount, 2);
    writeCellPng('${outDir.path}/v1_lock_heng.png', v1);
  });
}

/// 墨迹像素包络（left, top, right, bottom；任何 darkness>0.001 的
/// 非白像素，含 AA 半透明）。无墨返回 null。
(double, double, double, double)? _inkBounds(NaturalMediaRaster raster) {
  var x0 = raster.width;
  var y0 = raster.height;
  var x1 = -1;
  var y1 = -1;
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      // 白底的 darkness 浮点残差 ~1e-16；真实 AA 像素步长 ≥1/255。
      if (raster.darkness(x, y) > 0.001) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  return (x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble());
}

/// 三点转角（方向变化角，弧度）。
double _turnAngle(Point a, Point v, Point b) {
  final t1x = v.x - a.x, t1y = v.y - a.y;
  final t2x = b.x - v.x, t2y = b.y - v.y;
  final l1 = math.sqrt(t1x * t1x + t1y * t1y);
  final l2 = math.sqrt(t2x * t2x + t2y * t2y);
  if (l1 < 1e-9 || l2 < 1e-9) return 0;
  final dot = (t1x * t2x + t1y * t2y) / (l1 * l2);
  return math.acos(dot.clamp(-1.0, 1.0));
}
