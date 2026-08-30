import 'dart:io';
import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/pencil_stroke_renderer_v2.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/brush_stroke_fixtures.dart';
import 'natural_media/natural_media_image_metrics.dart';
import 'natural_media_visual_sheet_support.dart';

// ---------------------------------------------------------------------------
// T4：铅笔 v2 渲染器验收（计划任务卡）：结构门禁（N18）、浓淡主导
//（N2）、宽度受限（N3）、重复覆盖递增（N4）、纹理（N5）、确定性
//（N10）、v1 不受影响、planBuildCount 探针。
//
// 渲染经由 ElementRenderer 唯一分发点（v2 元素自动进 PencilStrokeRendererV2），
// 像素口径全部来自 T0 冻结指标（natural_media_image_metrics.dart）。
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final outDir = Directory('build/natural_media_baseline/v2_pencil');
  outDir.createSync(recursive: true);

  Future<PlacedRender> renderFixture(
    BrushStrokeFixture f, {
    int repeat = 1,
  }) async {
    final placed = fitFixtureToCell(f);
    final render = await renderPlaced(
      placed,
      f.pressures,
      BrushType.pencil,
      f.name,
      repeat: repeat,
    );
    writeCellPng('${outDir.path}/${f.name}.png', render);
    return render;
  }

  test('N18 结构：≤4 draw、0 saveLayer、0 shader、粒子上限、planBuildCount', () async {
    PencilStrokeRendererV2.resetPlanBuildCountForTest();
    for (final f in [
      pencilLightStroke,
      pencilMediumStroke,
      pencilHeavyStroke,
      pencilPressureRamp,
      pencilRightAngleCorner,
      pencilShortDot,
    ]) {
      final render = await renderFixture(f);
      expect(
        render.drawCallCount - 1,
        lessThanOrEqualTo(4),
        reason:
            '${f.name} 主要 draw（-1 背景矩形）'
            ' ${render.drawCallCount - 1} 应 ≤4',
      );
      expect(render.saveLayerCount, 0, reason: '${f.name} saveLayer');
      expect(render.shaderPathCount, 0, reason: '${f.name} shader');
    }
    expect(
      PencilStrokeRendererV2.planBuildCount,
      6,
      reason: '每次静态渲染恰好构建一次 plan（无缓存预建）',
    );
  });

  test('N2 浓淡主导：p=.8 中心带 darkness 比 p=.2 高 ≥35%', () async {
    final light = await renderFixture(pencilLightStroke);
    final heavy = await renderFixture(pencilHeavyStroke);
    final lightGeom = StrokeArcGeometry(fitFixtureToCell(pencilLightStroke));
    final heavyGeom = StrokeArcGeometry(fitFixtureToCell(pencilHeavyStroke));
    final lightWidth = WidthProfile.medianCenterWidth(
      light.raster,
      lightGeom,
      strokeWidth: kNominalWidth,
    );
    final heavyWidth = WidthProfile.medianCenterWidth(
      heavy.raster,
      heavyGeom,
      strokeWidth: kNominalWidth,
    );
    final hw = CenterBandDarkness.commonHalfWidth(lightWidth, heavyWidth);
    final lightDark = CenterBandDarkness.commonBandMeanDarkness(
      light.raster,
      lightGeom,
      commonHalfWidth: hw,
    );
    final heavyDark = CenterBandDarkness.commonBandMeanDarkness(
      heavy.raster,
      heavyGeom,
      commonHalfWidth: hw,
    );
    final ratio = heavyDark / math.max(lightDark, 1e-9);
    File('${outDir.path}/n2_n3_evidence.json').writeAsStringSync('''
{
  "lightWidth": $lightWidth,
  "heavyWidth": $heavyWidth,
  "widthRatio": ${heavyWidth / math.max(lightWidth, 1e-9)},
  "lightDarkness": $lightDark,
  "heavyDarkness": $heavyDark,
  "darknessRatio": $ratio
}
''');
    expect(ratio, greaterThan(1.35), reason: 'N2 共同中心带浓度比 $ratio 应 >1.35');
  });

  test('N3 宽度受限：p=.8/p=.2 中位有效宽度比 ≤1.35', () async {
    final light = await renderFixture(pencilLightStroke);
    final heavy = await renderFixture(pencilHeavyStroke);
    final lightW = WidthProfile.medianCenterWidth(
      light.raster,
      StrokeArcGeometry(fitFixtureToCell(pencilLightStroke)),
      strokeWidth: kNominalWidth,
    );
    final heavyW = WidthProfile.medianCenterWidth(
      heavy.raster,
      StrokeArcGeometry(fitFixtureToCell(pencilHeavyStroke)),
      strokeWidth: kNominalWidth,
    );
    expect(
      heavyW / math.max(lightW, 1e-9),
      lessThanOrEqualTo(1.35),
      reason: 'N3 宽度比 ${heavyW / math.max(lightW, 1e-9)}',
    );
  });

  test('N4 重复覆盖：1/2/3 次中心带 darkness 严格递增', () async {
    final base = pencilRepeatedOverlayScene.strokes.first;
    final placed = fitFixtureToCell(base);
    final darknesses = <double>[];
    for (var n = 1; n <= 3; n++) {
      final render = await renderPlaced(
        placed,
        base.pressures,
        BrushType.pencil,
        'v2overlay$n',
        repeat: n,
      );
      final geom = StrokeArcGeometry(placed);
      final w = WidthProfile.medianCenterWidth(
        render.raster,
        geom,
        strokeWidth: kNominalWidth,
      );
      darknesses.add(
        CenterBandDarkness.commonBandMeanDarkness(
          render.raster,
          geom,
          commonHalfWidth: CenterBandDarkness.commonHalfWidth(w, w),
        ),
      );
    }
    expect(darknesses[0], lessThan(darknesses[1]));
    expect(darknesses[1], lessThan(darknesses[2]));
  });

  test('N5 纹理：边缘不规则度达冻结下限，周期峰低于冻结上限', () async {
    final light = await renderFixture(pencilLightStroke);
    final geom = StrokeArcGeometry(fitFixtureToCell(pencilLightStroke));
    final rms = EdgeIrregularity.residualRmsOverWidth(
      light.raster,
      geom,
      strokeWidth: kNominalWidth,
    );
    final peak = Periodicity.maxEdgeAutocorrelationPeak(
      light.raster,
      geom,
      strokeWidth: kNominalWidth,
    );
    File('${outDir.path}/n5_evidence.json').writeAsStringSync('''
{
  "v2Rms": $rms,
  "v2AutocorrPeak": $peak,
  "frozenRmsMin": ${NaturalMediaFrozen.edgeIrregularityMinRms},
  "frozenPeakMax": ${NaturalMediaFrozen.autocorrPeakMax},
  "v1Rms": 0.12555393464860268,
  "v1Peak": 0.2783018867924519
}
''');
    expect(
      rms,
      greaterThan(NaturalMediaFrozen.edgeIrregularityMinRms),
      reason: 'N5 RMS $rms 应 > ${NaturalMediaFrozen.edgeIrregularityMinRms}',
    );
    expect(
      peak,
      lessThan(NaturalMediaFrozen.autocorrPeakMax),
      reason: 'N5 周期峰 $peak 应 < ${NaturalMediaFrozen.autocorrPeakMax}',
    );
  });

  test('N10 确定性：同元素两次渲染 PNG 逐字节一致', () async {
    final a = await renderFixture(pencilPressureRamp);
    final b = await renderFixture(pencilPressureRamp);
    expect(a.pngBytes, equals(b.pngBytes));
  });

  test('工作项9 可视 bounds：散布/AA 墨迹包络不越 elementVisualBounds', () async {
    for (final f in [
      pencilLightStroke,
      pencilHeavyStroke,
      pencilPressureRamp,
      pencilRightAngleCorner,
      pencilShortDot,
    ]) {
      final placed = fitFixtureToCell(f);
      final render = await renderFixture(f);
      var x0 = render.raster.width;
      var y0 = render.raster.height;
      var x1 = -1;
      var y1 = -1;
      for (var y = 0; y < render.raster.height; y++) {
        for (var x = 0; x < render.raster.width; x++) {
          // 白底的 darkness 浮点残差 ~1e-16；真实 AA 像素步长 ≥1/255。
          if (render.raster.darkness(x, y) > 0.001) {
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            if (y > y1) y1 = y;
          }
        }
      }
      expect(x1, greaterThan(-1), reason: '${f.name} 必须有墨迹');
      final element = placedElement(
        placed,
        f.pressures,
        BrushType.pencil,
        f.name,
      );
      final vb = elementVisualBounds(element);
      // 像素 x 覆盖 [x, x+1)；AA 只会采样到几何边界外 <1px。
      expect(
        x0.toDouble(),
        greaterThanOrEqualTo(vb.left - 1),
        reason: '${f.name} 左缘墨迹越界',
      );
      expect(
        y0.toDouble(),
        greaterThanOrEqualTo(vb.top - 1),
        reason: '${f.name} 上缘墨迹越界',
      );
      expect(
        (x1 + 1).toDouble(),
        lessThanOrEqualTo(vb.right + 1),
        reason: '${f.name} 右缘墨迹越界',
      );
      expect(
        (y1 + 1).toDouble(),
        lessThanOrEqualTo(vb.bottom + 1),
        reason: '${f.name} 下缘墨迹越界',
      );
    }
  });

  test('工作项10a 元素低 opacity：更浅、确定、不新增 draw/saveLayer', () async {
    final placed = fitFixtureToCell(pencilMediumStroke);
    final full = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.pencil,
      'opacity10',
    );
    final half1 = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.pencil,
      'opacity10',
      opacity: 0.5,
    );
    final half2 = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.pencil,
      'opacity10',
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
      reason: '低 opacity 不允许改变 draw 结构',
    );
    expect(half1.saveLayerCount, 0, reason: '低 opacity 不允许引入 saveLayer');
    expect(half1.pngBytes, equals(half2.pngBytes), reason: '低 opacity 下仍逐字节确定');
  });

  test('工作项10b 聚焦 dim：白 0.22 saveLayer 三明治下更浅、确定、结构不变', () async {
    final placed = fitFixtureToCell(pencilMediumStroke);
    final plain = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.pencil,
      'focusDim',
    );
    final dim1 = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.pencil,
      'focusDim',
      dimWrap: true,
    );
    final dim2 = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.pencil,
      'focusDim',
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
    expect(
      dim1.saveLayerCount,
      equals(1),
      reason: '恰好一个 dim saveLayer（复刻 static_canvas_painter 配方）',
    );
    expect(dim1.pngBytes, equals(dim2.pngBytes), reason: 'dim 包裹下仍逐字节确定');
  });

  test('v1 元素不受影响：classic 元数据走 v1 路径且像素不同于 v2', () async {
    final placed = fitFixtureToCell(pencilMediumStroke);
    final v1 = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.pencil,
      'v1lock',
      renderVersion: BrushRenderVersion.classicV1,
    );
    final v2 = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.pencil,
      'v1lock',
    );
    expect(v1.pngBytes, isNot(equals(v2.pngBytes)), reason: 'v1/v2 分发必须产生不同渲染');
    // v1 铅笔的结构计数与 T0 基线一致（背景 + 轮廓 + 颗粒 = 3）。
    expect(v1.drawCallCount, 3);
    writeCellPng('${outDir.path}/v1_lock_mediumStroke.png', v1);
  });

  test('非法组合安全回退：v2 元数据 + 非铅笔笔形 → 与纯 v1 逐字节一致', () async {
    final placed = fitFixtureToCell(pencilMediumStroke);
    final v1Ref = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.highlighter,
      'v2invalid',
    );
    final v2Meta = await renderPlaced(
      placed,
      pencilMediumStroke.pressures,
      BrushType.highlighter,
      'v2invalid',
      renderVersion: BrushRenderVersion.naturalMediaV2,
    );
    expect(
      v2Meta.pngBytes,
      equals(v1Ref.pngBytes),
      reason: 'v2 元数据对非自然介质笔形必须安全回退 v1（§3.1）',
    );
  });
}
