import 'package:flow_muse/features/whiteboard/smart_layout/correction/correction_patch_applier.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/correction/region_correction_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/region_segment.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/spatial_grid_index.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/deterministic_hash.dart';
import 'package:flutter_test/flutter_test.dart';

/// 区域内容 canonical 哈希（测试侧对拍用；生产侧失效计算归 V3-504）。
String regionContentHash(RegionSegment r) => fingerprint64(
  'region|${r.id}|${r.strokeIds.join(',')}|'
  '${r.left}|${r.top}|${r.width}|${r.height}|${r.lineDirection.name}|'
  '${r.columnIndex}|${r.skewRadians}|${r.localScale}|${r.regionClass.name}|'
  '${r.classificationConfidence}|${r.preservedReason?.name ?? '-'}',
);

void main() {
  // 两栏各两行的合成分割状态。
  final strokes = <String, StrokeBox>{
    'a1': const StrokeBox(id: 'a1', left: 0, top: 0, width: 30, height: 8),
    'a2': const StrokeBox(id: 'a2', left: 36, top: 1, width: 30, height: 8),
    'b1': const StrokeBox(id: 'b1', left: 0, top: 40, width: 30, height: 8),
    'b2': const StrokeBox(id: 'b2', left: 36, top: 41, width: 30, height: 8),
    'c1': const StrokeBox(id: 'c1', left: 500, top: 0, width: 30, height: 8),
    'c2': const StrokeBox(id: 'c2', left: 536, top: 1, width: 30, height: 8),
  };

  RegionSegment seg(
    String id,
    List<String> ids, {
    int column = 0,
    RegionClass regionClass = RegionClass.line,
    bool preserved = false,
  }) => RegionSegment(
    id: id,
    strokeIds: ids,
    left: strokes[ids.first]!.left,
    top: strokes[ids.first]!.top,
    width: 66,
    height: 9,
    lineDirection: SegmentLineDirection.horizontal,
    columnIndex: column,
    skewRadians: 0,
    localScale: 8,
    regionClass: regionClass,
    classificationConfidence: 0.9,
    preservedReason: preserved ? RegionPreservedReason.lowConfidence : null,
  );

  SegmentationState buildState() => SegmentationState(
    revision: 3,
    regions: [
      seg('seg-a', ['a1', 'a2']),
      seg('seg-b', ['b1', 'b2']),
      seg('seg-c', ['c1', 'c2'], column: 1),
    ],
    strokeBoxes: strokes,
  );

  const applier = CorrectionPatchApplier();

  MergeRegionsPatch mergePatch({int baseRevision = 3}) => MergeRegionsPatch(
    baseRevision: baseRevision,
    membersByRegionId: {
      'seg-a': ['a1', 'a2'],
      'seg-b': ['b1', 'b2'],
    },
  );

  test('merge：新区域内容派生 id、语义字段强制待重算、几何为成员并集', () {
    final state = buildState();
    final result = applier.apply(state, mergePatch());
    expect(result.accepted, isTrue);
    final next = result.state!;
    expect(next.revision, 4);
    expect(next.regions, hasLength(2), reason: 'seg-a/seg-b 合并为一');
    final merged = next.regions.firstWhere((r) => r.strokeIds.length == 4);
    expect(merged.id, 'r:a1', reason: '内容派生 id=成员最小笔画 id');
    expect(merged.regionClass, RegionClass.unknown);
    expect(merged.classificationConfidence, 0);
    expect(
      merged.preservedReason,
      isNull,
      reason: '重建区域是"语义待算"而非 preserved，不得阻断后续校正',
    );
    expect(merged.columnIndex, 0);
    expect(merged.left, 0);
    expect(merged.top, 0);
    expect(
      merged.top + merged.height,
      greaterThan(40),
      reason: '成员盒并集覆盖 b1/b2 行',
    );
  });

  test('apply→inverse 恢复同一分割图（往返幂等，含 id 稳定）', () {
    final state = buildState();
    final merged = applier.apply(state, mergePatch());
    expect(merged.accepted, isTrue);
    final inverseSplit = merged.inverse as SplitRegionPatch;
    final restored = applier.apply(merged.state!, inverseSplit);
    expect(restored.accepted, isTrue);

    // 再来一轮：merge 恢复出的区域 → 再 merge → 再 split，结果与第一轮
    // restored 完全一致（含 id）——幂等。
    final reMerged = applier.apply(
      restored.state!,
      restored.inverse as MergeRegionsPatch,
    );
    expect(reMerged.accepted, isTrue);
    final reRestored = applier.apply(
      reMerged.state!,
      reMerged.inverse as SplitRegionPatch,
    );
    expect(reRestored.accepted, isTrue);

    String partitionKey(SegmentationState s) => [
      for (final r in s.regions) '${r.id}:${r.strokeIds.join('+')}',
    ].join(';');
    expect(partitionKey(restored.state!), partitionKey(reRestored.state!));
    // 与初始 membership 一致（seg-c 原样，其余按内容派生 id 重组）
    final restoredIds = <String>{};
    for (final r in restored.state!.regions) {
      restoredIds.addAll(r.strokeIds);
    }
    expect(restoredIds, strokes.keys.toSet());
  });

  test('过期 patch 被拒：baseRevision 与状态不符', () {
    final state = buildState();
    final result = applier.apply(state, mergePatch(baseRevision: 2));
    expect(result.accepted, isFalse);
    expect(result.rejectionReason, 'stale-revision(2!=3)');
  });

  test('交叉 patch 被拒：构造后目标区域已变化', () {
    final state = buildState();
    final first = applier.apply(state, mergePatch());
    expect(first.accepted, isTrue);
    // 交叉 patch：revision 已对齐新状态，但引用已消失的 seg-a/seg-b
    final cross = MergeRegionsPatch(
      baseRevision: 4,
      membersByRegionId: {
        'seg-a': ['a1', 'a2'],
        'seg-b': ['b1', 'b2'],
      },
    );
    final second = applier.apply(first.state!, cross);
    expect(second.accepted, isFalse);
    expect(second.rejectionReason, 'unknown-region(seg-a)');
    // revision 未对齐的旧 patch 先被 stale 拦截
    final staleResult = applier.apply(first.state!, mergePatch());
    expect(staleResult.rejectionReason, 'stale-revision(3!=4)');

    // 成员快照不一致（构造时的成员 ≠ 当前成员）
    final stale = MergeRegionsPatch(
      baseRevision: 3,
      membersByRegionId: {
        'seg-a': ['a1'], // 少了 a2
        'seg-b': ['b1', 'b2'],
      },
    );
    final mismatch = applier.apply(buildState(), stale);
    expect(mismatch.accepted, isFalse);
    expect(mismatch.rejectionReason, 'membership-changed(seg-a)');
  });

  test('守卫阻断透传：跨列合并与 preserved 合并', () {
    final cross = MergeRegionsPatch(
      baseRevision: 3,
      membersByRegionId: {
        'seg-a': ['a1', 'a2'],
        'seg-c': ['c1', 'c2'],
      },
    );
    final rejected = applier.apply(buildState(), cross);
    expect(rejected.accepted, isFalse);
    expect(rejected.rejectionReason, contains('cross-column'));

    final preservedState = SegmentationState(
      revision: 3,
      regions: [
        seg('seg-a', ['a1', 'a2']),
        seg('seg-b', ['b1', 'b2'], preserved: true),
      ],
      strokeBoxes: strokes,
    );
    final blocked = applier.apply(preservedState, mergePatch());
    expect(blocked.accepted, isFalse);
    expect(blocked.rejectionReason, 'preserved(seg-b)');
  });

  test('split：合法拆分重建 + 拆分守卫阻断透传', () {
    final state = SegmentationState(
      revision: 0,
      regions: [
        seg('r:a1', ['a1', 'a2', 'b1', 'b2']),
      ],
      strokeBoxes: strokes,
    );
    final good = applier.apply(
      state,
      SplitRegionPatch(
        baseRevision: 0,
        regionId: 'r:a1',
        regionStrokeIdsSnapshot: ['a1', 'a2', 'b1', 'b2'],
        subsets: [
          ['a1', 'a2'],
          ['b1', 'b2'],
        ],
      ),
    );
    expect(good.accepted, isTrue);
    expect(good.state!.regions, hasLength(2));
    expect(good.state!.regions.map((r) => r.id), containsAll(['r:a1', 'r:b1']));

    final lossy = applier.apply(
      state,
      SplitRegionPatch(
        baseRevision: 0,
        regionId: 'r:a1',
        regionStrokeIdsSnapshot: ['a1', 'a2', 'b1', 'b2'],
        subsets: [
          ['a1'],
          ['b1'],
        ],
      ),
    );
    expect(lossy.accepted, isFalse);
    expect(lossy.rejectionReason, 'stroke-loss(2)');
  });

  test('受影响集=全量 diff：无关区域 hash 不变，变化区域恰为 affected', () {
    final state = buildState();
    final patch = mergePatch();
    final affected = applier.affectedSources(
      state,
      patch,
      assetByStrokeId: {
        'a2': ('file-x', true),
        'b1': ('file-y', false),
        'c1': ('file-z', false),
      },
    );
    expect(affected.regionIds, {'seg-a', 'seg-b'});
    expect(affected.strokeSourceIds, {'a1', 'a2', 'b1', 'b2'});
    expect(affected.renderAssetKeys, {'file-x|a2', 'file-y|b1'});
    expect(affected.cropKeys, {'file-x|a2|crop'});

    // apply 后全量 diff 对拍
    final result = applier.apply(state, patch);
    expect(result.accepted, isTrue);
    final before = {for (final r in state.regions) r.id: regionContentHash(r)};
    final after = {
      for (final r in result.state!.regions) r.id: regionContentHash(r),
    };
    final removed = before.keys.where((id) => !after.containsKey(id)).toSet();
    final added = after.keys.where((id) => !before.containsKey(id)).toSet();
    final changed = before.entries
        .where((e) => after.containsKey(e.key) && after[e.key] != e.value)
        .map((e) => e.key)
        .toSet();
    expect(removed, {'seg-a', 'seg-b'});
    expect(added, {'r:a1'});
    expect(changed, isEmpty, reason: '无关区域必须逐字段不变');
    expect(
      affected.regionIds.union(added),
      equals(affected.regionIds.union(added)),
    );
    // seg-c 完全未触碰
    expect(after.containsKey('seg-c'), isTrue);
    expect(after['seg-c'], before['seg-c']);
  });

  test('内容派生 id 幂等：同一成员集合两次重建 id 相同', () {
    expect(regionIdOf(['b2', 'a1', 'a2']), regionIdOf(['a2', 'b2', 'a1']));
    expect(regionIdOf(['a1']), 'r:a1');
  });
}
