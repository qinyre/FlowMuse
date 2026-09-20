import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_budget.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/layout_page_snapshot.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rendering/draft_scene_renderer.dart';

/// 区域高清资产（spec §5）：真实 DraftSceneRenderer 渲染 + 像素级断言。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旋转长笔迹：区域与渲染视口包含完整可视外框', () async {
    final ink = FreedrawElement(
      id: const ElementId('rotated'),
      x: 100,
      y: 100,
      width: 200,
      height: 10,
      angle: 0.7853981633974483,
      points: const [Point(0, 5), Point(200, 5)],
      strokeWidth: 2,
      isComplete: true,
    );
    final scene = Scene().addElement(ink);
    final record = const RegionPartitioner().partition(scene).single.record;
    final visual = conservativeVisualBounds(ink);
    expect(record.bounds.top, lessThanOrEqualTo(visual.top));
    expect(
      record.bounds.top + record.bounds.height,
      greaterThanOrEqualTo(visual.bottom),
    );
    expect(record.bounds.height, greaterThan(100));
    final builder = RegionAssetBuilder(capturedScene: scene);
    addTearDown(builder.dispose);
    final asset =
        (await builder.build(record, const RecognitionBudget())
                as RegionAssetBuilt)
            .asset;
    expect(asset.pageBounds.top, lessThan(visual.top));
    expect(
      asset.pageBounds.top + asset.pageBounds.height,
      greaterThan(visual.bottom),
    );
  });

  FreedrawElement stroke(String id, double x, double y, String color) {
    return FreedrawElement(
      id: ElementId(id),
      x: x,
      y: y,
      width: 60,
      height: 8,
      points: const [Point(0, 4), Point(30, 4), Point(60, 4)],
      strokeColor: color,
      strokeWidth: 2,
      isComplete: true,
      seed: 7,
      versionNonce: 11,
      updated: 1000,
    );
  }

  group('缩放目标 / 上限 / 留白 / 坐标闭环', () {
    test('渲染在途取消：不返回迟到PNG，后续区域禁止启动', () async {
      final scene = Scene().addElement(stroke('s', 10, 20, '#1e1e1e'));
      final builder = RegionAssetBuilder(capturedScene: scene);
      addTearDown(builder.dispose);
      final record = const RegionPartitioner().partition(scene).single.record;
      final pending = builder.build(record, const RecognitionBudget());
      builder.cancel();
      await expectLater(pending, throwsA(isA<DraftRenderCancelled>()));
      await expectLater(
        builder.build(record, const RecognitionBudget()),
        throwsA(isA<DraftRenderCancelled>()),
      );
    });
    test('缩放使局部行高达到目标下限，留白=0.3×行高，坐标闭环一致', () async {
      final scene = Scene().addElement(stroke('stroke-a', 10, 20, '#1e1e1e'));
      final builder = RegionAssetBuilder(capturedScene: scene);
      addTearDown(builder.dispose);
      const budget = RecognitionBudget();
      const record = RegionRecord(
        regionId: 'r:stroke-a',
        bounds: RecognitionBounds(left: 10, top: 20, width: 60, height: 8),
        targetSourceIds: ['stroke-a'],
        localLineHeight: 25,
      );
      final outcome = await builder.build(record, budget);
      expect(outcome, isA<RegionAssetBuilt>());
      final asset = (outcome as RegionAssetBuilt).asset;
      expect(asset.assetId, 'a1');
      // scale = 48 / 25。
      expect(asset.scale, closeTo(1.92, 1e-9));
      // 留白页面单位 = 0.3 × 25。
      expect(asset.paddingPageUnits, closeTo(7.5, 1e-9));
      expect(asset.paddingPx, closeTo(7.5 * 1.92, 1e-9));
      // pageBounds = bounds 外扩留白。
      expect(asset.pageBounds.left, closeTo(2.5, 1e-9));
      expect(asset.pageBounds.top, closeTo(12.5, 1e-9));
      expect(asset.pageBounds.width, closeTo(75, 1e-9));
      expect(asset.pageBounds.height, closeTo(23, 1e-9));
      // 像素尺寸 = ceil(页面尺寸 × scale)。
      expect(asset.pixelWidth, (75 * 1.92).ceil());
      expect(asset.pixelHeight, (23 * 1.92).ceil());
      // PNG 可解码且尺寸一致。
      final decoded = await _decodePng(asset.pngBytes);
      expect(decoded.width, asset.pixelWidth);
      expect(decoded.height, asset.pixelHeight);
    });

    test('超单图上限 fail closed（tooLarge），由调用方分区或保留', () async {
      final scene = Scene().addElement(stroke('stroke-a', 0, 0, '#1e1e1e'));
      final builder = RegionAssetBuilder(capturedScene: scene);
      addTearDown(builder.dispose);
      final record = RegionRecord(
        regionId: 'r:stroke-a',
        bounds: const RecognitionBounds(
          left: 0,
          top: 0,
          width: 4000,
          height: 3000,
        ),
        targetSourceIds: const ['stroke-a'],
        localLineHeight: 40,
      );
      final outcome = await builder.build(record, const RecognitionBudget());
      expect(outcome, isA<RegionAssetFailed>());
      expect(
        (outcome as RegionAssetFailed).reason,
        RegionAssetFailureReason.tooLarge,
      );
    });

    test('可注入预算生效：小上限触发 tooLarge', () async {
      final scene = Scene().addElement(stroke('stroke-a', 0, 0, '#1e1e1e'));
      final builder = RegionAssetBuilder(capturedScene: scene);
      addTearDown(builder.dispose);
      final record = RegionRecord(
        regionId: 'r:stroke-a',
        bounds: const RecognitionBounds(
          left: 0,
          top: 0,
          width: 500,
          height: 400,
        ),
        targetSourceIds: const ['stroke-a'],
        localLineHeight: 25,
      );
      final outcome = await builder.build(
        record,
        const RecognitionBudget(regionMaxEdgePx: 256),
      );
      expect(
        (outcome as RegionAssetFailed).reason,
        RegionAssetFailureReason.tooLarge,
      );
    });
  });

  group('target/context 区分：邻区笔迹不进识别图', () {
    test('context 笔迹在留白范围内也不渲染（像素级验证）', () async {
      final scene = Scene()
          .addElement(stroke('stroke-a', 10, 20, '#1e1e1e'))
          .addElement(stroke('stroke-b', 10, 55, '#1e1e1e'));
      final builder = RegionAssetBuilder(capturedScene: scene);
      addTearDown(builder.dispose);
      // 区域框同时罩住 A（target）与 B（context，邻区边缘笔迹）。
      const record = RegionRecord(
        regionId: 'r:stroke-a',
        bounds: RecognitionBounds(left: 10, top: 20, width: 80, height: 50),
        targetSourceIds: ['stroke-a'],
        contextSourceIds: ['stroke-b'],
        localLineHeight: 25,
      );
      final outcome = await builder.build(record, const RecognitionBudget());
      final asset = (outcome as RegionAssetBuilt).asset;

      final targetPixel = _pageToPixel(
        asset,
        const ui.Offset(40, 24),
      ); // stroke-a 中心
      final contextPixel = _pageToPixel(
        asset,
        const ui.Offset(40, 59),
      ); // stroke-b 中心
      final image = await _decodePng(asset.pngBytes);
      final hasTargetInk = await _hasInk(image, targetPixel);
      final hasContextInk = await _hasInk(image, contextPixel);
      addTearDown(image.dispose);
      expect(hasTargetInk, isTrue, reason: 'target 笔迹必须出现在识别图内');
      expect(hasContextInk, isFalse, reason: 'context 笔迹禁止进入识别图');
    });
  });

  group('浅色铅笔：一次固定参数对比度增强', () {
    test('增强仅作用于临时资产且加深墨量；assetId 递增不双份', () async {
      final scene = Scene()
          .addElement(stroke('s-light-1', 10, 20, '#c8c8c8'))
          .addElement(stroke('s-light-2', 10, 120, '#c8c8c8'));
      final builder = RegionAssetBuilder(capturedScene: scene);
      addTearDown(builder.dispose);

      RegionRecord recordOf(String id, double top) => RegionRecord(
        regionId: 'r:$id',
        bounds: RecognitionBounds(left: 10, top: top, width: 60, height: 8),
        targetSourceIds: [id],
        localLineHeight: 25,
      );

      final plain = await builder.build(
        recordOf('s-light-1', 20),
        const RecognitionBudget(pencilLightnessThreshold: 0.9),
      );
      final enhanced = await builder.build(
        recordOf('s-light-2', 120),
        const RecognitionBudget(pencilLightnessThreshold: 0.5),
      );
      final plainAsset = (plain as RegionAssetBuilt).asset;
      final enhancedAsset = (enhanced as RegionAssetBuilt).asset;
      expect(plainAsset.assetId, 'a1');
      expect(enhancedAsset.assetId, 'a2');

      final plainImage = await _decodePng(plainAsset.pngBytes);
      final enhancedImage = await _decodePng(enhancedAsset.pngBytes);
      addTearDown(plainImage.dispose);
      addTearDown(enhancedImage.dispose);
      final plainInk = await _inkAmount(plainImage);
      final enhancedInk = await _inkAmount(enhancedImage);
      expect(
        enhancedInk,
        greaterThan(plainInk),
        reason: '固定参数 gamma 增强必须加深浅色墨量（原图与笔迹样式不变）',
      );
      // 增强后仍可解码为合法 PNG（尺寸不变）。
      expect(enhancedImage.width, enhancedAsset.pixelWidth);
      expect(enhancedImage.height, enhancedAsset.pixelHeight);
    });
  });

  group('逐区域失败隔离与资产释放', () {
    test('零长度笔画：渲染无可见像素 → 资产失败，区域保留不发送', () async {
      // 2026-09-18 真机事故原样元素：落笔即抬（两点重合）、width/height=1、
      // 钢笔笔刷带压力——渲染出 831×831 全透明空图，致 provider 挂死。
      final dot = FreedrawElement(
        id: const ElementId('dot'),
        x: 741.28,
        y: 394.25,
        width: 1,
        height: 1,
        points: const [Point(0, 0), Point(0, 0)],
        pressures: const [0.4124751281738281, 0.19854505334926154],
        simulatePressure: false,
        strokeColor: '#1e1e1e',
        strokeWidth: 6,
        isComplete: true,
        customData: const {
          'flowMuse': {
            'brushType': 'fountain-pen',
            'pressureEncoding': 1,
            'pageId': 'page-1',
          },
        },
      );
      final scene = Scene().addElement(dot);
      final builder = RegionAssetBuilder(capturedScene: scene);
      addTearDown(builder.dispose);
      final outcome = await builder.build(
        RegionRecord(
          regionId: 'r:dot',
          bounds: const RecognitionBounds(
            left: 10,
            top: 20,
            width: 8,
            height: 8,
          ),
          targetSourceIds: const ['dot'],
          localLineHeight: 1,
        ),
        const RecognitionBudget(),
      );
      final failed = outcome as RegionAssetFailed;
      expect(failed.reason, RegionAssetFailureReason.renderError);
      expect(failed.detail, contains('无可见像素'));
    });

    test('target 缺员：单区域失败不影响其他区域', () async {
      final scene = Scene().addElement(stroke('stroke-a', 10, 20, '#1e1e1e'));
      final builder = RegionAssetBuilder(capturedScene: scene);
      addTearDown(builder.dispose);
      final bad = RegionRecord(
        regionId: 'r:missing',
        bounds: const RecognitionBounds(left: 0, top: 0, width: 10, height: 10),
        targetSourceIds: const ['no-such-stroke'],
        localLineHeight: 25,
      );
      final good = RegionRecord(
        regionId: 'r:stroke-a',
        bounds: const RecognitionBounds(
          left: 10,
          top: 20,
          width: 60,
          height: 8,
        ),
        targetSourceIds: const ['stroke-a'],
        localLineHeight: 25,
      );
      final badOutcome = await builder.build(bad, const RecognitionBudget());
      final goodOutcome = await builder.build(good, const RecognitionBudget());
      expect(
        (badOutcome as RegionAssetFailed).reason,
        RegionAssetFailureReason.renderError,
      );
      expect(badOutcome.regionId, 'r:missing');
      expect(goodOutcome, isA<RegionAssetBuilt>());
    });

    test('连续构建后渲染资源归零；释放后拒绝构建', () async {
      final scene = Scene().addElement(stroke('stroke-a', 10, 20, '#1e1e1e'));
      final builder = RegionAssetBuilder(capturedScene: scene);
      for (var i = 0; i < 3; i++) {
        final outcome = await builder.build(
          RegionRecord(
            regionId: 'r:stroke-a',
            bounds: const RecognitionBounds(
              left: 10,
              top: 20,
              width: 60,
              height: 8,
            ),
            targetSourceIds: const ['stroke-a'],
            localLineHeight: 25,
          ),
          const RecognitionBudget(),
        );
        expect(outcome, isA<RegionAssetBuilt>());
      }
      builder.dispose();
      expect(builder.isDisposed, isTrue);
      expect(
        () => builder.build(
          RegionRecord(
            regionId: 'r:stroke-a',
            bounds: const RecognitionBounds(
              left: 10,
              top: 20,
              width: 60,
              height: 8,
            ),
            targetSourceIds: const ['stroke-a'],
            localLineHeight: 25,
          ),
          const RecognitionBudget(),
        ),
        throwsStateError,
      );
    });
  });

  group('资产索引与小笔迹归属', () {
    test('单笔迹多资产：target 与 context 关联均入索引，纠错失效全清', () {
      final index = RegionAssetIndex();
      final a1 = RegionAsset(
        assetId: 'a1',
        pngBytes: Uint8List.fromList([1]),
        scale: 2,
        paddingPageUnits: 6,
        paddingPx: 12,
        targetSourceIds: const ['s1'],
        contextSourceIds: const ['s2'],
        pageBounds: const RecognitionBounds(
          left: 0,
          top: 0,
          width: 10,
          height: 10,
        ),
        pixelWidth: 20,
        pixelHeight: 20,
      );
      final a2 = RegionAsset(
        assetId: 'a2',
        pngBytes: Uint8List.fromList([2]),
        scale: 2,
        paddingPageUnits: 6,
        paddingPx: 12,
        targetSourceIds: const ['s2'],
        contextSourceIds: const [],
        pageBounds: const RecognitionBounds(
          left: 0,
          top: 0,
          width: 10,
          height: 10,
        ),
        pixelWidth: 20,
        pixelHeight: 20,
      );
      index.register(a1);
      index.register(a2);
      expect(index.assetCount, 2);
      expect(index.assetIdsOf('s1'), ['a1']);
      expect(index.assetIdsOf('s2'), ['a1', 'a2']);
      expect(
        () => index.register(a1),
        throwsStateError,
        reason: 'assetId 重复登记拒绝',
      );
      final dead = index.invalidateForSources(const ['s2']);
      expect(dead, {'a1', 'a2'});
      expect(index.assetCount, 0);
      expect(index.assetIdsOf('s2'), isEmpty);
    });

    test('小笔迹归属：就近并入（<0.8×行高），远距/无邻独立保留', () {
      const attribution = SmallStrokeAttribution();
      const regions = [
        RegionRecord(
          regionId: 'r:a',
          bounds: RecognitionBounds(left: 0, top: 0, width: 100, height: 30),
          targetSourceIds: ['a1'],
          localLineHeight: 20,
        ),
        RegionRecord(
          regionId: 'r:b',
          bounds: RecognitionBounds(left: 200, top: 0, width: 100, height: 30),
          targetSourceIds: ['b1'],
          localLineHeight: 20,
        ),
      ];
      final result = attribution.attribute(
        regions: regions,
        smallStrokeBounds: {
          // 距 r:a 下缘 10（< 0.8×20=16）→ 归 r:a。
          'dot-1': const RecognitionBounds(
            left: 40,
            top: 40,
            width: 3,
            height: 3,
          ),
          // 距 r:a 下缘 100 > 16 → 独立保留。
          'dash-far': const RecognitionBounds(
            left: 40,
            top: 130,
            width: 6,
            height: 2,
          ),
          // 在 r:b 框内 → 距离 0，归 r:b。
          'dot-2': const RecognitionBounds(
            left: 240,
            top: 10,
            width: 3,
            height: 3,
          ),
        },
      );
      expect(result, {'dot-1': 'r:a', 'dot-2': 'r:b'});
    });

    test('target 归属唯一性断言：同源双 target 拒绝', () {
      expect(
        () => assertTargetOwnershipUniqueness(const [
          RegionRecord(
            regionId: 'r:a',
            bounds: RecognitionBounds(left: 0, top: 0, width: 10, height: 10),
            targetSourceIds: ['s1'],
            localLineHeight: 20,
          ),
          RegionRecord(
            regionId: 'r:b',
            bounds: RecognitionBounds(left: 50, top: 0, width: 10, height: 10),
            targetSourceIds: ['s1'],
            localLineHeight: 20,
          ),
        ]),
        throwsStateError,
      );
      // 同源作为 target + context 并存合法。
      expect(
        () => assertTargetOwnershipUniqueness(const [
          RegionRecord(
            regionId: 'r:a',
            bounds: RecognitionBounds(left: 0, top: 0, width: 10, height: 10),
            targetSourceIds: ['s1'],
            localLineHeight: 20,
          ),
          RegionRecord(
            regionId: 'r:b',
            bounds: RecognitionBounds(left: 50, top: 0, width: 10, height: 10),
            targetSourceIds: ['s2'],
            contextSourceIds: ['s1'],
            localLineHeight: 20,
          ),
        ]),
        returnsNormally,
      );
    });
  });
}

ui.Offset _pageToPixel(RegionAsset asset, ui.Offset pagePoint) {
  return ui.Offset(
    (pagePoint.dx - asset.pageBounds.left) * asset.scale,
    (pagePoint.dy - asset.pageBounds.top) * asset.scale,
  );
}

Future<ui.Image> _decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<bool> _hasInk(ui.Image image, ui.Offset pixel) async {
  final x = pixel.dx.round().clamp(0, image.width - 1);
  final y = pixel.dy.round().clamp(0, image.height - 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!;
  final i = (y * image.width + x) * 4;
  final a = bytes.getUint8(i + 3);
  final r = bytes.getUint8(i);
  final g = bytes.getUint8(i + 1);
  final b = bytes.getUint8(i + 2);
  if (a < 32) {
    return false; // 透明背景：无墨
  }
  final luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return luminance < 200;
}

Future<int> _inkAmount(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!;
  var ink = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    if (bytes.getUint8(i + 3) < 32) continue;
    ink +=
        (255 - bytes.getUint8(i)) +
        (255 - bytes.getUint8(i + 1)) +
        (255 - bytes.getUint8(i + 2));
  }
  return ink;
}
