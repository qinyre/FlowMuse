import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';

import 'structure_test_helpers.dart';

/// §9.3/§9.4 纠错上下文：不可变捕获、影响集四集合、资产失效、代次守卫。
void main() {
  test('capture：影响集 = before ∪ after，笔画 = 前后成员并集', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
    ]);
    final context = RecognitionCorrectionContext.capture(
      generation: 3,
      operationId: 'op-correction',
      session: result,
      beforeRegionIds: const {'r:a'},
      afterRegionIds: const {'r:a', 'r:new'},
      strokeSourceIds: const {'s-a', 's-new'},
    );
    expect(context.generation, 3);
    expect(context.operationId, 'op-correction');
    expect(context.affected.beforeRegionIds, {'r:a'});
    expect(context.affected.afterRegionIds, {'r:a', 'r:new'});
    expect(context.affected.strokeSourceIds, {'s-a', 's-new'});
    expect(context.regionRecords.map((r) => r.regionId), ['r:a']);
    expect(context.isCurrent(3), isTrue);
    expect(context.isCurrent(4), isFalse, reason: '代次守卫：过期上下文不得发布');
  });

  test('capture 副作用：会话资产索引按影响笔画失效', () async {
    final assetIndex = RegionAssetIndex();
    assetIndex.register(
      RegionAsset(
        assetId: 'a1',
        pngBytes: Uint8List.fromList([1, 2, 3]),
        scale: 2,
        paddingPageUnits: 3,
        paddingPx: 6,
        targetSourceIds: const ['s-a'],
        contextSourceIds: const ['s-b'],
        pageBounds: RecognitionBounds(left: 0, top: 0, width: 10, height: 10),
        pixelWidth: 20,
        pixelHeight: 20,
      ),
    );
    assetIndex.register(
      RegionAsset(
        assetId: 'a2',
        pngBytes: Uint8List.fromList([4, 5, 6]),
        scale: 2,
        paddingPageUnits: 3,
        paddingPx: 6,
        targetSourceIds: const ['s-c'],
        contextSourceIds: const [],
        pageBounds: RecognitionBounds(left: 0, top: 0, width: 10, height: 10),
        pixelWidth: 20,
        pixelHeight: 20,
      ),
    );
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
    ]);
    final session = RecognitionSessionResult(
      operationId: result.operationId,
      generation: result.generation,
      pageId: result.pageId,
      scene: result.scene,
      sceneRevision: result.sceneRevision,
      contentFingerprint: result.contentFingerprint,
      regionRecords: result.regionRecords,
      regionOutcomes: result.regionOutcomes,
      ledger: result.ledger,
      assetIndex: assetIndex,
      structureResult: result.structureResult,
    );
    final context = RecognitionCorrectionContext.capture(
      generation: 1,
      operationId: 'op-x',
      session: session,
      beforeRegionIds: const {'r:a'},
      afterRegionIds: const {},
      strokeSourceIds: const {'s-b'},
    );
    // s-b 是 a1 的 context 源：失效含多临时资产（target+context 反向索引）。
    expect(context.affected.invalidatedAssetIds, {'a1'});
    expect(assetIndex.assetIdsOf('s-b'), isEmpty, reason: '失效后反向索引同步清除');
    expect(assetIndex.assetIdsOf('s-c'), ['a2'], reason: '未触源资产保留');
  });

  test('四集合完整性：仅资产失效非空时 isEmpty 为 false', () {
    const affected = RecognitionCorrectionAffected(
      beforeRegionIds: {},
      afterRegionIds: {},
      strokeSourceIds: {},
      invalidatedAssetIds: {'a1'},
    );
    expect(
      affected.isEmpty,
      isFalse,
      reason: '不得单独依赖旧 AffectedSourceSet.isEmpty（不检查资产集）',
    );
    const empty = RecognitionCorrectionAffected(
      beforeRegionIds: {},
      afterRegionIds: {},
      strokeSourceIds: {},
      invalidatedAssetIds: {},
    );
    expect(empty.isEmpty, isTrue);
  });

  test('上下文不可变：影响集合与区域记录为不可变视图', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
    ]);
    final context = RecognitionCorrectionContext.capture(
      generation: 0,
      operationId: 'op-y',
      session: result,
      beforeRegionIds: {'r:a'},
      afterRegionIds: {},
      strokeSourceIds: {'s-a'},
    );
    expect(
      () => context.affected.beforeRegionIds.add('r:b'),
      throwsUnsupportedError,
    );
    expect(() => context.regionRecords.add(result.regionRecords.first),
        throwsUnsupportedError);
  });
}
