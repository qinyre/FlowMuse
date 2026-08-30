import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'natural_media_image_metrics.dart';

// ---------------------------------------------------------------------------
// 十项冻结指标自测（T0 验收：每项指标必须有代码、注释、固定 fixture 和
// 失败示例；T11 只能复用不得重定义）。
//
// 本文件用受控合成栅格验证指标行为：
//  - 指标 4/5/6 的"失败示例"是人为构造的规则横纹与随机糙边栅格，
//    证明指标确实能检出它们对应的视觉缺陷；
//  - 阈值常量的取值依据在 NaturalMediaFrozen 注释中说明。
// ---------------------------------------------------------------------------

Future<NaturalMediaRaster> rasterOf(
  int width,
  int height,
  void Function(ui.Canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final raster = await NaturalMediaRaster.fromImage(image);
  image.dispose();
  return raster;
}

/// 合成水平条带：中线 y=center，底半高 [baseHalf]，上缘加 [topJitter]。
Future<NaturalMediaRaster> horizontalBand(
  int width,
  int height,
  int center,
  double baseHalf,
  double Function(int x) topJitter, {
  int color = 0xFF000000,
}) {
  return rasterOf(width, height, (canvas) {
    final paint = ui.Paint()..color = ui.Color(color);
    for (var x = 0; x < width; x++) {
      final top = center - baseHalf - topJitter(x);
      canvas.drawRect(
        ui.Rect.fromLTRB(x.toDouble(), top, x + 1.0, center + baseHalf),
        paint,
      );
    }
  });
}

/// 确定性伪噪声（仅测试合成数据用；生产种子另有 §3.3 冻结算法）。
/// 用 fract(sin·大数) 混合：步进采点（如每 2px 取一）无乘法 LCG 的
/// 隐藏周期性——后者会让"非周期糙边"假样本在自相关指标上误报峰值。
double testNoise(int x) {
  final v = math.sin(x * 12.9898) * 43758.5453;
  return v - v.floorToDouble();
}

/// 规则横纹：周期 6px（= 3 个 2px 边缘采样步），模拟 v1 类颗粒横纹。
double testBanding(int x) => 4.0 * (math.sin(2 * math.pi * x / 6) + 1) / 2;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bandW = 300;
  const bandH = 200;
  const bandCenter = 100;
  const bandBaseHalf = 15.0;

  // 中心线为水平线的弧长几何（edge/width 指标共用）。
  final bandGeometry = StrokeArcGeometry(const [
    Point(0, 100),
    Point(300, 100),
  ]);
  const bandStrokeWidth = 6.0;

  group('指标 1/2：渲染底图与着墨像素', () {
    test('darkness/luma 口径与 16/255 着墨边界', () async {
      final boundary = await rasterOf(4, 2, (canvas) {
        canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, 2, 2),
          ui.Paint()..color = const ui.Color(0xFFEFEFEF), // 239 灰
        );
        canvas.drawRect(
          ui.Rect.fromLTWH(2, 0, 2, 2),
          ui.Paint()..color = const ui.Color(0xFFF0F0F0), // 240 灰
        );
      });
      expect(boundary.darkness(0, 0), closeTo(16 / 255, 1e-4));
      expect(boundary.darkness(2, 0), closeTo(15 / 255, 1e-4));
      expect(boundary.isInk(0, 0), isTrue, reason: 'darkness=16/255 应着墨');
      expect(boundary.isInk(2, 0), isFalse, reason: 'darkness=15/255 不着墨');
    });

    test('透明底变体：alpha=0 像素不误判为墨', () async {
      final raster = await NaturalMediaSheetRenderer.renderScene(
        elements: const [],
        size: const ui.Size(8, 8),
        opaqueWhiteBackground: false,
      );
      expect(raster.isInk(4, 4), isFalse);
      expect(raster.darkness(4, 4), 0);
    });

    test('白底契约：背景为纯白、黑矩形着墨', () async {
      final raster = await rasterOf(8, 8, (canvas) {
        canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, 8, 8),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
        canvas.drawRect(
          ui.Rect.fromLTWH(2, 2, 4, 4),
          ui.Paint()..color = const ui.Color(0xFF000000),
        );
      });
      expect(raster.darkness(0, 0), closeTo(0, 1e-6));
      expect(raster.darkness(4, 4), closeTo(1, 1e-6));
      expect(raster.isInk(4, 4), isTrue);
      expect(raster.isInk(0, 0), isFalse);
    });
  });

  group('指标 4：有效宽度', () {
    test('直条带中位有效宽度 ≈ 已知宽度', () async {
      final raster = await horizontalBand(
        bandW,
        bandH,
        bandCenter,
        bandBaseHalf,
        (_) => 0,
      );
      final width = WidthProfile.medianCenterWidth(
        raster,
        bandGeometry,
        strokeWidth: bandStrokeWidth,
      );
      expect(width, closeTo(bandBaseHalf * 2, 2.0));
    });
  });

  group('指标 3：共同中心带浓度', () {
    test('灰条 vs 黑条：共同中心带 darkness 比值 ≈ 2', () async {
      final gray = await horizontalBand(
        bandW,
        bandH,
        bandCenter,
        bandBaseHalf,
        (_) => 0,
        color: 0xFF808080, // darkness ≈ 0.5
      );
      final black = await rasterOf(bandW, bandH, (canvas) {
        final paint = ui.Paint()..color = const ui.Color(0xFF000000);
        canvas.drawRect(
          ui.Rect.fromLTWH(
            0,
            bandCenter - bandBaseHalf,
            bandW.toDouble(),
            bandBaseHalf * 2,
          ),
          paint,
        );
      });
      final hw = CenterBandDarkness.commonHalfWidth(
        WidthProfile.medianCenterWidth(
          gray,
          bandGeometry,
          strokeWidth: bandStrokeWidth,
        ),
        WidthProfile.medianCenterWidth(
          black,
          bandGeometry,
          strokeWidth: bandStrokeWidth,
        ),
      );
      final grayDark = CenterBandDarkness.commonBandMeanDarkness(
        gray,
        bandGeometry,
        commonHalfWidth: hw,
      );
      final blackDark = CenterBandDarkness.commonBandMeanDarkness(
        black,
        bandGeometry,
        commonHalfWidth: hw,
      );
      expect(blackDark, greaterThan(0.95));
      expect(grayDark, greaterThan(0.4));
      expect(blackDark / grayDark, greaterThan(1.3), reason: 'N2 式口径能区分浓淡');
    });
  });

  group('指标 5/6：边缘不规则度与固定周期峰', () {
    test('直边：RMS≈0、自相关峰≈0（指标不误报）', () async {
      final raster = await horizontalBand(
        bandW,
        bandH,
        bandCenter,
        bandBaseHalf,
        (_) => 0,
      );
      final rms = EdgeIrregularity.residualRmsOverWidth(
        raster,
        bandGeometry,
        strokeWidth: bandStrokeWidth,
      );
      final peak = Periodicity.maxEdgeAutocorrelationPeak(
        raster,
        bandGeometry,
        strokeWidth: bandStrokeWidth,
      );
      expect(rms, lessThan(0.02), reason: '完全平直边缘残差应≈0，实测 $rms');
      expect(peak, lessThan(0.10), reason: '无周期成分峰值应≈0，实测 $peak');
    });

    test('失败示例：随机糙边被不规则度指标检出（超过冻结下限）', () async {
      final raster = await horizontalBand(
        bandW,
        bandH,
        bandCenter,
        bandBaseHalf,
        (x) => 18.0 * testNoise(x),
      );
      final rms = EdgeIrregularity.residualRmsOverWidth(
        raster,
        bandGeometry,
        strokeWidth: bandStrokeWidth,
      );
      expect(
        rms,
        greaterThan(NaturalMediaFrozen.edgeIrregularityMinRms),
        reason:
            '随机糙边 RMS=$rms 应超过冻结下限 '
            '${NaturalMediaFrozen.edgeIrregularityMinRms}',
      );
    });

    test('失败示例：6px 周期规则横纹被自相关峰检出（超过冻结上限）', () async {
      final raster = await horizontalBand(
        bandW,
        bandH,
        bandCenter,
        bandBaseHalf,
        testBanding,
      );
      final peak = Periodicity.maxEdgeAutocorrelationPeak(
        raster,
        bandGeometry,
        strokeWidth: bandStrokeWidth,
      );
      expect(
        peak,
        greaterThan(NaturalMediaFrozen.autocorrPeakMax),
        reason:
            '规则横纹峰=$peak 应超过冻结上限 '
            '${NaturalMediaFrozen.autocorrPeakMax}',
      );
    });

    test('随机糙边不触发周期峰门禁（无周期成分）', () async {
      final raster = await horizontalBand(
        bandW,
        bandH,
        bandCenter,
        bandBaseHalf,
        (x) => 3.0 * testNoise(x),
      );
      final peak = Periodicity.maxEdgeAutocorrelationPeak(
        raster,
        bandGeometry,
        strokeWidth: bandStrokeWidth,
      );
      expect(
        peak,
        lessThan(NaturalMediaFrozen.autocorrPeakMax),
        reason: '非周期糙边峰=$peak',
      );
    });
  });

  group('指标 7：弧长前缀', () {
    test('"前 90%" 按原始弧长判定，不按像素排序', () {
      final mask = ArcPrefixMask.default90(bandGeometry);
      expect(mask.containsPixel(50, 100), isTrue, reason: '弧长 50/300=0.17');
      expect(mask.containsPixel(269, 100), isTrue, reason: '0.897<=0.9');
      expect(mask.containsPixel(280, 100), isFalse, reason: '0.933>0.9');
    });
  });

  group('指标 8：像素差', () {
    test('同图差为 0；缺口按 8/255 阈值与并集归一', () async {
      final a = await horizontalBand(
        bandW,
        bandH,
        bandCenter,
        bandBaseHalf,
        (_) => 0,
      );
      final same = await horizontalBand(
        bandW,
        bandH,
        bandCenter,
        bandBaseHalf,
        (_) => 0,
      );
      expect(PixelDiff.differingInkRatio(a, same), 0);

      final notched = await rasterOf(bandW, bandH, (canvas) {
        final paint = ui.Paint()..color = const ui.Color(0xFF000000);
        canvas.drawRect(
          ui.Rect.fromLTWH(
            0,
            bandCenter - bandBaseHalf,
            bandW.toDouble(),
            bandBaseHalf * 2,
          ),
          paint,
        );
        canvas.drawRect(
          ui.Rect.fromLTWH(150, bandCenter - 5, 10, 10),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
      });
      final ratio = PixelDiff.differingInkRatio(a, notched);
      expect(ratio, greaterThan(0), reason: '缺口应被检出');
      // 缺口 10×10=100 像素 / 全条带着墨并集 300×30=9000。
      expect(ratio, closeTo(100 / 9000, 0.005));
    });

    test('低于 8/255 的亮度差不计差异', () async {
      final a = await rasterOf(4, 4, (canvas) {
        canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, 4, 4),
          ui.Paint()..color = const ui.Color(0xFF000000),
        );
      });
      final b = await rasterOf(4, 4, (canvas) {
        canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, 4, 4),
          ui.Paint()..color = const ui.Color(0xFF030303), // darkness 差 3/255
        );
      });
      expect(PixelDiff.differingInkRatio(a, b), 0);
    });
  });

  group('指标 9：SVG 趋势排序', () {
    test('sameOrdering 判定方向一致/相反/相等', () {
      expect(sameOrdering(0.2, 0.8, 0.3, 0.9), isTrue);
      expect(sameOrdering(0.8, 0.2, 0.9, 0.3), isTrue);
      expect(sameOrdering(0.2, 0.8, 0.9, 0.3), isFalse);
      expect(sameOrdering(0.5, 0.5, 0.2, 0.8), isFalse, reason: '相等序只匹配相等序');
      expect(sameOrdering(0.5, 0.5, 0.4, 0.4), isTrue);
    });
  });

  group('指标 10：分块结构比较', () {
    const refsA = [
      NaturalMediaPrimitiveRef(edgeStartIndex: 0, sampleOrdinal: 0, channel: 1),
      NaturalMediaPrimitiveRef(edgeStartIndex: 0, sampleOrdinal: 1, channel: 1),
      NaturalMediaPrimitiveRef(edgeStartIndex: 1, sampleOrdinal: 0, channel: 4),
    ];

    test('multiset 相等返回 null；缺失/重复被描述', () {
      expect(multisetDiff(refsA, refsA), isNull);
      expect(multisetDiff(refsA, refsA.take(2)), contains('数量不一致'));
      expect(multisetDiff(refsA.take(2), refsA), contains('仅 B 有'));
    });

    test('bucket 映射不一致被检出（key 相等不能代替 bucket 相等）', () {
      final withBucket = [
        for (final r in refsA)
          NaturalMediaPrimitiveRef(
            edgeStartIndex: r.edgeStartIndex,
            sampleOrdinal: r.sampleOrdinal,
            channel: r.channel,
            paintBucket: 'grainMedium',
          ),
      ];
      final otherBucket = [
        for (final r in refsA)
          NaturalMediaPrimitiveRef(
            edgeStartIndex: r.edgeStartIndex,
            sampleOrdinal: r.sampleOrdinal,
            channel: r.channel,
            paintBucket: 'grainHeavy',
          ),
      ];
      expect(
        multisetDiff(withBucket, otherBucket),
        isNull,
        reason: 'key 层面确实相等',
      );
      expect(bucketMappingEqual(withBucket, otherBucket), isFalse);
      expect(bucketMappingEqual(withBucket, withBucket), isTrue);
    });

    test('顶点逐值相等：1e-9 容差', () {
      final v = [const ui.Offset(1, 2), const ui.Offset(3, 4)];
      final w = [const ui.Offset(1 + 5e-10, 2), const ui.Offset(3, 4 + 5e-10)];
      final u = [const ui.Offset(1 + 5e-9, 2), const ui.Offset(3, 4)];
      expect(verticesEqual(v, w), isTrue);
      expect(verticesEqual(v, u), isFalse, reason: '超过 1e-9 容差');
      expect(verticesEqual(v, v.take(1).toList()), isFalse, reason: '长度不等');
    });
  });
}
