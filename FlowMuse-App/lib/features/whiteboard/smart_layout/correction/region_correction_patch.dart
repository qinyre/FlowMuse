/// 内容派生的区域 id：成员笔画最小 id。同一笔画集合永远得到同一 id
///（merge/split 往返与重复应用幂等的基础）。
String regionIdOf(List<String> strokeIds) {
  assert(strokeIds.isNotEmpty);
  final sorted = [...strokeIds]..sort();
  return 'r:${sorted.first}';
}

/// 可逆的区域校正 patch（V3-104A）：只做 merge/split 的 membership 与
/// 几何重建；语义（role/分类）重算归 V3-205，候选与评分重跑归 V3-504。
///
/// [baseRevision] 是构造时的分割状态 revision 前置条件；过期或成员
/// 已变化的 patch 会被 [CorrectionPatchApplier] 拒绝。
sealed class RegionCorrectionPatch {
  const RegionCorrectionPatch({required this.baseRevision});

  final int baseRevision;

  String get kind;
}

/// 合并 k 个相邻区域。
class MergeRegionsPatch extends RegionCorrectionPatch {
  const MergeRegionsPatch({
    required super.baseRevision,
    required this.membersByRegionId,
  });

  /// regionId → 构造时的成员笔画快照（用于交叉/过期检测）。
  final Map<String, List<String>> membersByRegionId;

  @override
  String get kind => 'merge';
}

/// 把一个区域拆成 ≥2 个子集。
class SplitRegionPatch extends RegionCorrectionPatch {
  const SplitRegionPatch({
    required super.baseRevision,
    required this.regionId,
    required this.regionStrokeIdsSnapshot,
    required this.subsets,
  });

  final String regionId;

  /// 构造时该区域的成员笔画快照。
  final List<String> regionStrokeIdsSnapshot;

  /// 划分（≥2 个非空子集，完整覆盖）。
  final List<List<String>> subsets;

  @override
  String get kind => 'split';
}
