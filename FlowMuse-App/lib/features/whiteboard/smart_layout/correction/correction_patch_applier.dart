import '../segmentation/membership_guard.dart';
import '../segmentation/region_segment.dart';
import '../segmentation/segmentation_policy.dart';
import '../segmentation/spatial_grid_index.dart';
import 'region_correction_patch.dart';

/// 分割状态：revision + 区域列表 + 笔画盒快照（几何重建依据）。
class SegmentationState {
  const SegmentationState({
    required this.revision,
    required this.regions,
    required this.strokeBoxes,
  });

  final int revision;
  final List<RegionSegment> regions;

  /// strokeId → 盒（分割时冻结，patch 不改笔画几何）。
  final Map<String, StrokeBox> strokeBoxes;

  Set<String> get allStrokeIds => strokeBoxes.keys.toSet();

  RegionSegment? regionById(String id) {
    for (final region in regions) {
      if (region.id == id) return region;
    }
    return null;
  }
}

/// patch 触达的失效范围：重建/移除的区域、membership 变化的笔画、
/// 需要重渲染的资产/裁剪键。语义重算范围（V3-205）与候选重跑
/// 范围（V3-504）都以本集合为输入。
class AffectedSourceSet {
  const AffectedSourceSet({
    required this.regionIds,
    required this.strokeSourceIds,
    required this.renderAssetKeys,
    required this.cropKeys,
  });

  /// 被移除或重建的区域 id（含新建 id）。
  final Set<String> regionIds;

  /// membership 发生变化的笔画 source id。
  final Set<String> strokeSourceIds;

  /// 受影响笔画拥有的渲染资产键（fileId|ownerSourceId）。
  final Set<String> renderAssetKeys;

  /// 受影响且带裁剪的资产键（fileId|ownerSourceId|crop）。
  final Set<String> cropKeys;

  bool get isEmpty =>
      regionIds.isEmpty && strokeSourceIds.isEmpty && renderAssetKeys.isEmpty;
}

/// apply 结果：接受时给新状态与逆 patch；拒绝时给确定性原因。
class CorrectionApplyResult {
  const CorrectionApplyResult.rejected(String reason)
    : state = null,
      inverse = null,
      rejectionReason = reason;

  const CorrectionApplyResult.applied(SegmentationState stateValue,
      RegionCorrectionPatch inverseValue)
    : state = stateValue,
      inverse = inverseValue,
      rejectionReason = null;

  final SegmentationState? state;
  final RegionCorrectionPatch? inverse;
  final String? rejectionReason;

  bool get accepted => state != null;
}

/// 校正 patch 应用器：合法性（revision 前置/区域存在/成员快照一致/
/// [RegionMembershipGuard] 守卫）→ membership 重建（内容派生 id）→
/// 逆 patch。重建区域的语义字段一律 unknown/低置信 preserved，
/// 强制 V3-205 局部语义重算；未触区域原样透传（对象与内容都不变）。
class CorrectionPatchApplier {
  const CorrectionPatchApplier({
    this.guard = const RegionMembershipGuard(),
    this.policy = SegmentationPolicy.development,
  });

  final RegionMembershipGuard guard;
  final SegmentationPolicy policy;

  CorrectionApplyResult apply(
    SegmentationState state,
    RegionCorrectionPatch patch,
  ) {
    if (patch.baseRevision != state.revision) {
      return CorrectionApplyResult.rejected(
        'stale-revision(${patch.baseRevision}!=${state.revision})',
      );
    }
    return switch (patch) {
      MergeRegionsPatch() => _applyMerge(state, patch),
      SplitRegionPatch() => _applySplit(state, patch),
    };
  }

  /// patch 的受影响集（不应用即可计算；接受路径与 apply 共用同一判定）。
  ///
  /// [assetByStrokeId] 提供笔画 → (fileId, 是否裁剪) 的资产归属
  ///（来自 LayoutPageSnapshot.renderAssets 的 ownerSourceId 映射）。
  AffectedSourceSet affectedSources(
    SegmentationState state,
    RegionCorrectionPatch patch, {
    Map<String, (String fileId, bool cropped)> assetByStrokeId = const {},
  }) {
    final regionIds = <String>{};
    final strokeIds = <String>{};
    final assetKeys = <String>{};
    final cropKeys = <String>{};

    void include(RegionSegment region) {
      regionIds.add(region.id);
      for (final strokeId in region.strokeIds) {
        strokeIds.add(strokeId);
        final asset = assetByStrokeId[strokeId];
        if (asset == null) continue;
        final key = '${asset.$1}|$strokeId';
        assetKeys.add(key);
        if (asset.$2) cropKeys.add('$key|crop');
      }
    }

    switch (patch) {
      case MergeRegionsPatch():
        for (final entry in patch.membersByRegionId.entries) {
          final region = state.regionById(entry.key);
          if (region != null) include(region);
        }
      case SplitRegionPatch():
        final region = state.regionById(patch.regionId);
        if (region != null) include(region);
    }
    return AffectedSourceSet(
      regionIds: regionIds,
      strokeSourceIds: strokeIds,
      renderAssetKeys: assetKeys,
      cropKeys: cropKeys,
    );
  }

  CorrectionApplyResult _applyMerge(
    SegmentationState state,
    MergeRegionsPatch patch,
  ) {
    if (patch.membersByRegionId.length < 2) {
      return const CorrectionApplyResult.rejected('merge-needs-two-regions');
    }
    final regions = <RegionSegment>[];
    for (final entry in patch.membersByRegionId.entries) {
      final region = state.regionById(entry.key);
      if (region == null) {
        return CorrectionApplyResult.rejected('unknown-region(${entry.key})');
      }
      if (!_sameMembers(region.strokeIds, entry.value)) {
        return CorrectionApplyResult.rejected(
          'membership-changed(${entry.key})',
        );
      }
      regions.add(region);
    }
    // 守卫：两两（首个 vs 其余）+成员守恒。
    for (final other in regions.skip(1)) {
      final reason = guard.mergeBlockReason(
        regions.first,
        other,
        allStrokeIds: state.allStrokeIds,
      );
      if (reason != null) {
        return CorrectionApplyResult.rejected(reason);
      }
    }
    final mergedStrokes = [for (final region in regions) ...region.strokeIds]
      ..sort();
    final merged = _rebuild(state, mergedStrokes, regions);
    final removedIds = patch.membersByRegionId.keys.toSet();
    final nextRegions = <RegionSegment>[
      for (final region in state.regions)
        if (!removedIds.contains(region.id)) region,
      merged,
    ]..sort((a, b) => _regionSortKey(a).compareTo(_regionSortKey(b)));

    final inverse = SplitRegionPatch(
      baseRevision: state.revision + 1,
      regionId: merged.id,
      regionStrokeIdsSnapshot: merged.strokeIds,
      subsets: [
        for (final region in regions) List<String>.of(region.strokeIds),
      ],
    );
    return CorrectionApplyResult.applied(
      SegmentationState(
        revision: state.revision + 1,
        regions: nextRegions,
        strokeBoxes: state.strokeBoxes,
      ),
      inverse,
    );
  }

  CorrectionApplyResult _applySplit(
    SegmentationState state,
    SplitRegionPatch patch,
  ) {
    final region = state.regionById(patch.regionId);
    if (region == null) {
      return CorrectionApplyResult.rejected(
        'unknown-region(${patch.regionId})',
      );
    }
    if (!_sameMembers(region.strokeIds, patch.regionStrokeIdsSnapshot)) {
      return CorrectionApplyResult.rejected(
        'membership-changed(${patch.regionId})',
      );
    }
    final reason = guard.splitBlockReason(region, patch.subsets);
    if (reason != null) {
      return CorrectionApplyResult.rejected(reason);
    }
    final pieces = <RegionSegment>[
      for (final subset in patch.subsets)
        _rebuild(state, [...subset]..sort(), [region]),
    ];
    final nextRegions = <RegionSegment>[
      for (final other in state.regions)
        if (other.id != region.id) other,
      ...pieces,
    ]..sort((a, b) => _regionSortKey(a).compareTo(_regionSortKey(b)));

    final inverse = MergeRegionsPatch(
      baseRevision: state.revision + 1,
      membersByRegionId: {
        for (final piece in pieces) piece.id: List<String>.of(piece.strokeIds),
      },
    );
    return CorrectionApplyResult.applied(
      SegmentationState(
        revision: state.revision + 1,
        regions: nextRegions,
        strokeBoxes: state.strokeBoxes,
      ),
      inverse,
    );
  }

  /// 重建区域：内容派生 id、笔画盒并集几何、成员局部尺度中位。
  ///
  /// 语义字段置 unknown/置信 0/preservedReason null——"结构已定、
  /// 语义待算"，不是 preserved（preserved 会阻断后续结构校正）；
  /// 语义重算归 V3-205，其结果可再给出置信与 preserved 判定。
  RegionSegment _rebuild(
    SegmentationState state,
    List<String> strokeIds,
    List<RegionSegment> sources,
  ) {
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final strokeId in strokeIds) {
      final box = state.strokeBoxes[strokeId];
      if (box == null) {
        throw StateError('未知笔画: $strokeId');
      }
      if (box.left < left) left = box.left;
      if (box.top < top) top = box.top;
      if (box.right > right) right = box.right;
      if (box.bottom > bottom) bottom = box.bottom;
    }
    final width = right - left;
    final height = bottom - top;
    final direction = height > width * policy.verticalAspectThreshold
        ? SegmentLineDirection.vertical
        : width > height * policy.horizontalAspectThreshold
        ? SegmentLineDirection.horizontal
        : SegmentLineDirection.mixed;
    final localScale = _median([
      for (final source in sources) source.localScale,
    ]);
    return RegionSegment(
      id: regionIdOf(strokeIds),
      strokeIds: List.unmodifiable(strokeIds),
      left: left,
      top: top,
      width: width,
      height: height,
      lineDirection: direction,
      columnIndex: sources.first.columnIndex,
      skewRadians: sources.first.skewRadians,
      localScale: localScale,
      regionClass: RegionClass.unknown,
      classificationConfidence: 0,
      preservedReason: null,
    );
  }

  static String _regionSortKey(RegionSegment region) =>
      '${region.top.toStringAsFixed(3)}|${region.left.toStringAsFixed(3)}|'
      '${region.id}';

  static bool _sameMembers(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final setA = a.toSet();
    return b.every(setA.contains);
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }
}
