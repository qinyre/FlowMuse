import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/brush_stroke_fixtures.dart';
import 'natural_media/natural_media_image_metrics.dart';
import 'natural_media_visual_sheet_support.dart';

// ---------------------------------------------------------------------------
// T0：v1 视觉基线测试纸（铅笔与毛笔重构计划，2026-08-30）。
//
// 产物（生成图不提交）输出到 build/natural_media_baseline/：
//  - cells/<fixture>.png          每行单元格（指标与产物同源栅格）
//  - sheet_labeled.html           有标签测试纸（浏览器打开）
//  - sheet_unlabeled.html         无标签测试纸（行序冻结混淆）
//  - unlabeled_manifest.json      无标签行序映射（盲测复核）
//  - v1_*_metrics.json            指标与 draw 计数记录
//  - NOTES-v1.md                  当前视觉问题编号清单（P-01…）
//
// 本测试只记录基线并证明"指标能检出当前缺陷"，不把 v1 当成 v2 合格
// 值：断言方向都是 v1 应当【不满足】v2 目标（N6/N4 等本就满足的项
// 作为对照记录，防止 v2 改造时丢失既有量程）。
// ---------------------------------------------------------------------------

/// 全单元格着墨像素占比（ink coverage，T0 工作项 4 记录项）。
double inkCoverage(NaturalMediaRaster raster) {
  var ink = 0;
  var total = 0;
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      if (raster.isInk(x, y)) ink++;
      total++;
    }
  }
  return total == 0 ? 0 : ink / total;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory(kOutRoot).createSync(recursive: true);
  Directory('$kOutRoot/cells').createSync(recursive: true);

  Future<PlacedRender> renderFixtureCell(
    BrushStrokeFixture f,
    BrushType brush,
  ) async {
    final placed = fitFixtureToCell(f);
    // v1 基线：T4 分发生效后显式锁 classicV1（默认创建语义是 v2）。
    final render = await renderPlaced(
      placed,
      f.pressures,
      brush,
      f.name,
      renderVersion: BrushRenderVersion.classicV1,
    );
    writeCellPng('$kOutRoot/cells/${brush.name}_${f.name}.png', render);
    return render;
  }

  group('铅笔 v1 基线', () {
    test('恒压轻/中/重 + 坡道 + 轨迹 + 场景：指标记录与缺陷检出', () async {
      final record = <String, Object?>{};

      void recordStructure(String id, PlacedRender r) {
        record['$id@drawCalls'] = r.drawCallCount;
        record['$id@saveLayer'] = r.saveLayerCount;
        record['$id@shaderPaths'] = r.shaderPathCount;
        record['$id@inkCoverage'] = inkCoverage(r.raster);
      }

      final light = await renderFixtureCell(
        pencilLightStroke,
        BrushType.pencil,
      );
      final medium = await renderFixtureCell(
        pencilMediumStroke,
        BrushType.pencil,
      );
      final heavy = await renderFixtureCell(
        pencilHeavyStroke,
        BrushType.pencil,
      );
      recordStructure('lightStroke', light);
      recordStructure('mediumStroke', medium);
      recordStructure('heavyStroke', heavy);

      for (final f in [
        pencilPressureRamp,
        pencilSlowTrajectory,
        pencilFastTrajectory,
        pencilRightAngleCorner,
        pencilShortDot,
      ]) {
        recordStructure(f.name, await renderFixtureCell(f, BrushType.pencil));
      }

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
      final lightRms = EdgeIrregularity.residualRmsOverWidth(
        light.raster,
        lightGeom,
        strokeWidth: kNominalWidth,
      );
      final lightPeak = Periodicity.maxEdgeAutocorrelationPeak(
        light.raster,
        lightGeom,
        strokeWidth: kNominalWidth,
      );

      final widthRatio = heavyWidth / math.max(lightWidth, 1e-9);
      final darkRatio = heavyDark / math.max(lightDark, 1e-9);
      record['lightWidth'] = lightWidth;
      record['heavyWidth'] = heavyWidth;
      record['widthRatio'] = widthRatio;
      record['lightCenterDarkness'] = lightDark;
      record['heavyCenterDarkness'] = heavyDark;
      record['centerDarknessRatio'] = darkRatio;
      record['lightEdgeIrregularityRms'] = lightRms;
      record['lightAutocorrPeak'] = lightPeak;
      record['mediumCenterWidth'] = WidthProfile.medianCenterWidth(
        medium.raster,
        lightGeom,
        strokeWidth: kNominalWidth,
      );

      // P-01：压力主要改变宽度而非浓度——共同中心带 darkness 比远低于
      // N2 的 1.35 门禁（v1 铅笔 opacity 恒定，浓度不随压力走）。
      expect(
        darkRatio,
        lessThan(1.35),
        reason: 'v1 铅笔轻重压中心带浓度比 $darkRatio 应 < 1.35（N2 检出缺陷）',
      );

      // P-02：宽度增长超过 N3 的 1.35 上限。
      expect(
        widthRatio,
        greaterThan(1.35),
        reason: 'v1 铅笔轻重压宽度比 $widthRatio 应 > 1.35（N3 检出缺陷）',
      );

      // P-03：边缘不规则度（T0 实测改判为观察项）。连续段边缘口径下
      // v1 = 0.126、spike v2 = 0.072——v1 的高值来自喷枪式散点链
      //（§2 不接受"喷枪"，但它是视觉判定项），"边缘不规则度不足"这一
      // 预期未获指标支持，不硬造 v1 必然低于下限的断言。冻结下限
      // 0.05 的语义是 v2 防退化（防光滑钢笔边），由 T4/T11 断言。
      record['lightEdgeIrregularityRms'] = lightRms;
      record['lightWidthProfile'] = WidthProfile.centerBandWidths(
        light.raster,
        lightGeom,
        strokeWidth: kNominalWidth,
      );
      record['heavyWidthProfile'] = WidthProfile.centerBandWidths(
        heavy.raster,
        heavyGeom,
        strokeWidth: kNominalWidth,
      );

      // P-04：颗粒自相关峰（> 冻结上限即规则横纹，仅记录判定方向）。
      record['lightAutocorrPeakVerdict'] =
          lightPeak > NaturalMediaFrozen.autocorrPeakMax ? '规则横纹' : '未见周期横纹';

      File(
        '$kOutRoot/v1_pencil_metrics.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(record));
      writeNotes(pencilMetrics: record);
    });

    test('重复覆盖：1/2/3 次 darkness 严格递增（N4 对照记录）', () async {
      final base = pencilRepeatedOverlayScene.strokes.first;
      final placed = fitFixtureToCell(base);
      final overlays = <double>[];
      for (var n = 1; n <= 3; n++) {
        final render = await renderPlaced(
          placed,
          base.pressures,
          BrushType.pencil,
          'overlay$n',
          repeat: n,
        );
        final geom = StrokeArcGeometry(placed);
        final width = WidthProfile.medianCenterWidth(
          render.raster,
          geom,
          strokeWidth: kNominalWidth,
        );
        overlays.add(
          CenterBandDarkness.commonBandMeanDarkness(
            render.raster,
            geom,
            commonHalfWidth: CenterBandDarkness.commonHalfWidth(width, width),
          ),
        );
        if (n == 3) {
          writeCellPng('$kOutRoot/cells/pencil_overlay3.png', render);
        }
      }
      expect(overlays[0], lessThan(overlays[1]));
      expect(overlays[1], lessThan(overlays[2]));
      File('$kOutRoot/v1_pencil_overlay.json').writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'overlayDarkness': overlays}),
      );
    });

    test('采样率稳定性：稀疏/正常/密集恒压轻/重（冻结阈值门禁）', () async {
      Future<List<double>> threeRates(
        BrushStrokeFixture base,
        double Function(NaturalMediaRaster, StrokeArcGeometry) pick,
      ) async {
        final out = <double>[];
        for (final f in [
          resampleFixture(base, 18.0),
          base,
          resampleFixture(base, 4.5),
        ]) {
          final placed = fitFixtureToCell(f);
          final render = await renderPlaced(
            placed,
            f.pressures,
            BrushType.pencil,
            f.name,
          );
          out.add(pick(render.raster, StrokeArcGeometry(placed)));
        }
        return out;
      }

      // ignore: prefer_function_declarations_over_variables
      final widthOf = (NaturalMediaRaster r, StrokeArcGeometry g) =>
          WidthProfile.medianCenterWidth(r, g, strokeWidth: kNominalWidth);
      // ignore: prefer_function_declarations_over_variables
      final darkOf = (NaturalMediaRaster r, StrokeArcGeometry g) =>
          CenterBandDarkness.commonBandMeanDarkness(
            r,
            g,
            commonHalfWidth: CenterBandDarkness.commonHalfWidth(
              widthOf(r, g),
              widthOf(r, g),
            ),
          );

      final widthLight = await threeRates(pencilLightStroke, widthOf);
      final widthHeavy = await threeRates(pencilHeavyStroke, widthOf);
      final darkLight = await threeRates(pencilLightStroke, darkOf);

      double spread(List<double> v) =>
          (v.reduce(math.max) - v.reduce(math.min)) /
          math.max(v.reduce(math.min), 1e-9);

      final widthSpreadLight = spread(widthLight);
      final widthSpreadHeavy = spread(widthHeavy);
      final darkSpread = spread(darkLight);

      File('$kOutRoot/v1_sampling_rate_stability.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'widthLight': widthLight,
          'widthHeavy': widthHeavy,
          'darknessLight': darkLight,
          'widthSpreadLight': widthSpreadLight,
          'widthSpreadHeavy': widthSpreadHeavy,
          'darknessSpread': darkSpread,
          'thresholds': {
            'widthRelDevMax': NaturalMediaFrozen.samplingRateWidthRelDevMax,
            'darknessRelDevMax':
                NaturalMediaFrozen.samplingRateDarknessRelDevMax,
          },
        }),
      );

      expect(
        widthSpreadLight,
        lessThan(NaturalMediaFrozen.samplingRateWidthRelDevMax),
        reason: '轻压宽度三档偏差 $widthSpreadLight',
      );
      expect(
        widthSpreadHeavy,
        lessThan(NaturalMediaFrozen.samplingRateWidthRelDevMax),
        reason: '重压宽度三档偏差 $widthSpreadHeavy',
      );
      expect(
        darkSpread,
        lessThan(NaturalMediaFrozen.samplingRateDarknessRelDevMax),
        reason: '中心带浓度三档偏差 $darkSpread',
      );
    });
  });

  group('毛笔 v1 基线', () {
    test('八笔画 + 补充 fixture：指标记录与 taper 缺陷检出', () async {
      final record = <String, Object?>{};

      Future<PlacedRender> renderNamed(BrushStrokeFixture f) async {
        final render = await renderFixtureCell(f, BrushType.brushPen);
        final placed = fitFixtureToCell(f);
        final geom = StrokeArcGeometry(placed);
        record[f.name] = {
          'pointCount': f.points.length,
          'drawCalls': render.drawCallCount,
          'saveLayer': render.saveLayerCount,
          'inkCoverage': inkCoverage(render.raster),
          'centerWidth': WidthProfile.medianCenterWidth(
            render.raster,
            geom,
            strokeWidth: kNominalWidth,
          ),
        };
        return render;
      }

      for (final stroke in brushCalligraphyStrokes) {
        await renderNamed(stroke);
      }
      final noDrop = await renderNamed(brushHengNoTailDrop);
      await renderNamed(brushPressureRamp);
      await renderNamed(brushSCurve);
      await renderNamed(brushShortDot);

      // P-05：无尾部降压的横在距尾 2×size 处宽度（N8 无降压口径）。
      final noDropGeom = StrokeArcGeometry(
        fitFixtureToCell(brushHengNoTailDrop),
      );
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
      final tailRatio = tailWidth / math.max(midWidth, 1e-9);
      record['noTailDropMidWidth'] = midWidth;
      record['noTailDropTailWidth'] = tailWidth;
      record['noTailDropTailRatio'] = tailRatio;
      expect(
        tailRatio,
        lessThan(0.70),
        reason:
            'v1 毛笔无尾部降压横画距尾 2×size 宽度比 $tailRatio '
            '应 < 0.70（N8 检出固定对称 taper 缺陷）',
      );

      // P-06：有尾部降压的捺同位置宽度（对照组，记录）。
      final na = await renderFixtureCell(brushNa, BrushType.brushPen);
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
      record['naTailRatio'] = naTail / math.max(naMid, 1e-9);

      // P-07：轻重宽度量程（N6 对照：v1 靠 thinning=1.0 本就达标；记录
      // 防止 v2 方向性包络丢掉提按量程）。
      BrushStrokeFixture constantPressure(String name, double p) =>
          BrushStrokeFixture(
            name: name,
            description: 'N6 $p恒压探针',
            points: [for (var i = 0; i <= 40; i++) Point(9.0 * i, 0)],
            pressures: List<double>.filled(41, p),
          );

      final lightProbe = constantPressure('brushLightProbe', 0.20);
      final heavyProbe = constantPressure('brushHeavyProbe', 0.80);
      final lightRender = await renderPlaced(
        fitFixtureToCell(lightProbe),
        lightProbe.pressures,
        BrushType.brushPen,
        lightProbe.name,
      );
      final heavyRender = await renderPlaced(
        fitFixtureToCell(heavyProbe),
        heavyProbe.pressures,
        BrushType.brushPen,
        heavyProbe.name,
      );
      final brushWidthRatio =
          WidthProfile.medianCenterWidth(
            heavyRender.raster,
            StrokeArcGeometry(fitFixtureToCell(heavyProbe)),
            strokeWidth: kNominalWidth,
          ) /
          math.max(
            WidthProfile.medianCenterWidth(
              lightRender.raster,
              StrokeArcGeometry(fitFixtureToCell(lightProbe)),
              strokeWidth: kNominalWidth,
            ),
            1e-9,
          );
      record['brushWidthRatioP02P08'] = brushWidthRatio;
      expect(
        brushWidthRatio,
        greaterThan(2.2),
        reason: 'v1 毛笔轻重宽度比 $brushWidthRatio（N6 对照，应本就 ≥2.2）',
      );

      File(
        '$kOutRoot/v1_brush_metrics.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(record));
      writeNotes(brushMetrics: record);
    });

    test('SVG 产物：v1 毛笔笔画导出对照', () async {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      var row = 0;
      for (final stroke in [...brushCalligraphyStrokes, brushHengNoTailDrop]) {
        final placed = fitFixtureToCell(stroke);
        final xs = placed.map((p) => p.x);
        final ys = placed.map((p) => p.y);
        final minX = xs.reduce(math.min);
        final minY = ys.reduce(math.min);
        controller.applyResult(
          AddElementResult(
            FreedrawElement(
              id: ElementId('brush-v1-svg-${stroke.name}'),
              x: minX,
              y: minY + row * kCellHeight,
              width: xs.reduce(math.max) - minX,
              height: ys.reduce(math.max) - minY,
              points: [for (final p in placed) Point(p.x - minX, p.y - minY)],
              pressures: List<double>.from(stroke.pressures),
              simulatePressure: false,
              isComplete: true,
              customData: customDataWithFreedrawRender(
                null,
                BrushType.brushPen,
              ),
              strokeWidth: kNominalWidth,
            ),
          ),
        );
        row++;
      }
      final svg = controller.exportSvg(selectedOnly: false);
      expect(svg, isNotNull);
      File('$kOutRoot/v1_brush_strokes.svg').writeAsStringSync(svg);
    });
  });

  test('生成有标签/无标签测试纸与 manifest', () {
    final pencilRows = <String>[
      'pencil_lightStroke',
      'pencil_mediumStroke',
      'pencil_heavyStroke',
      'pencil_pressureRamp',
      'pencil_slowTrajectory',
      'pencil_fastTrajectory',
      'pencil_rightAngleCorner',
      'pencil_shortDot',
      'pencil_overlay3',
    ];
    final brushRows = <String>[
      for (final s in brushCalligraphyStrokes) 'brushPen_${s.name}',
      'brushPen_brushHengNoTailDrop',
      'brushPen_brushPressureRamp',
      'brushPen_brushSCurve',
      'brushPen_brushShortDot',
    ];

    // 无标签行序：确定性混淆（仅行排序用途，非协议种子）。
    int rowHash(String name) {
      var h = 0x811c9dc5;
      for (final c in name.codeUnits) {
        h = ((h ^ c) * 0x01000193) & 0x7fffffff;
      }
      return h;
    }

    final shuffled = [...pencilRows, ...brushRows]
      ..sort((a, b) => rowHash(a) - rowHash(b));
    File('$kOutRoot/unlabeled_manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        for (var i = 0; i < shuffled.length; i++) 'row${i + 1}': shuffled[i],
      }),
    );

    String imgTag(String file) =>
        '<img src="cells/$file.png" '
        'style="width:900px;height:150px;display:block;'
        'border:1px solid #ccc">';

    final labeled = StringBuffer('''
<html><head><meta charset="utf-8"><title>v1 基线测试纸（有标签）</title></head>
<body style="font-family:sans-serif;background:#f6f6f6">
<h2>FlowMuse v1 基线测试纸（有标签）</h2>
<p>铅笔/毛笔 fixture · 名义笔宽 $kNominalWidth · 黑色 · 白底 · zoom=1 · dpr=1</p>
''');
    for (final row in pencilRows) {
      labeled.write('<p>$row</p>${imgTag(row)}');
    }
    labeled.write('<hr>');
    for (final row in brushRows) {
      labeled.write('<p>$row</p>${imgTag(row)}');
    }
    labeled.write('</body></html>');
    File('$kOutRoot/sheet_labeled.html').writeAsStringSync(labeled.toString());

    final unlabeled = StringBuffer('''
<html><head><meta charset="utf-8"><title>v1 基线测试纸（无标签）</title></head>
<body style="font-family:sans-serif;background:#f6f6f6">
<h2>FlowMuse v1 基线测试纸（无标签）</h2>
''');
    for (var i = 0; i < shuffled.length; i++) {
      unlabeled.write('<p>row${i + 1}</p>${imgTag(shuffled[i])}');
    }
    unlabeled.write('</body></html>');
    File(
      '$kOutRoot/sheet_unlabeled.html',
    ).writeAsStringSync(unlabeled.toString());

    // 产物说明（重建方式 + 文件清单），随基线一起再生成。
    File('$kOutRoot/README.md').writeAsStringSync('''
# 自然介质 T0 基线产物说明（自动生成，勿手改）

重建命令（FlowMuse-App 目录下）：
- flutter test test/features/whiteboard/editor_core/rendering/natural_media_visual_sheet_test.dart
- flutter test tool/natural_media_spike/pencil_grain_spike_test.dart
- flutter test tool/natural_media_spike/brush_envelope_spike_test.dart

文件清单：
- cells/<brush>_<fixture>.png   v1 每行单元格（指标与产物同源栅格）
- sheet_labeled.html / sheet_unlabeled.html   v1 有/无标签测试纸
- unlabeled_manifest.json        无标签行序（冻结哈希混淆，盲测复核用）
- v1_pencil_metrics.json / v1_brush_metrics.json / v1_pencil_overlay.json
- v1_sampling_rate_stability.json
- v1_brush_strokes.svg           v1 毛笔笔画 SVG 对照
- NOTES-v1.md                    当前视觉问题编号清单（P-01…）
- spike/                         纯 Path 原型产物（T0 收口后随 spike 代码删除）
- spike_sheet_labeled.html       v1（左） vs spike v2（右）目标确认纸
- spike/*_evidence.json          spike 的 N2/N3/N6/N8/N7/线性度实测证据

十项冻结指标唯一来源：
test/features/whiteboard/editor_core/rendering/natural_media/natural_media_image_metrics.dart
''');
  });
}
