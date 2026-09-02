import 'region_segment.dart';

/// merge/split 防护（V3-103B）：任何区域结构调整必须满足
/// 1) 笔迹守恒（不丢、不重、不凭空增）；2) 高风险方向不可合并
/// （跨列、preserved 区域）；用户未修正时不确定区域保持原状，
/// 不自动替换（计划 §4.3）。
///
/// 返回 null 表示允许；否则返回确定性的阻断原因（供校正 UI/审计）。
class RegionMembershipGuard {
  const RegionMembershipGuard();

  /// 合并守卫。
  String? mergeBlockReason(
    RegionSegment a,
    RegionSegment b, {
    required Set<String> allStrokeIds,
  }) {
    if (a.columnIndex != b.columnIndex) {
      return 'cross-column(${a.columnIndex}!=${b.columnIndex})';
    }
    if (a.preserved || b.preserved) {
      final who = a.preserved ? a.id : b.id;
      return 'preserved($who)';
    }
    final union = {...a.strokeIds, ...b.strokeIds};
    if (union.length != a.strokeIds.length + b.strokeIds.length) {
      return 'overlapping-membership';
    }
    if (!allStrokeIds.containsAll(union)) {
      return 'foreign-strokes';
    }
    return null;
  }

  /// 拆分守卫：子集划分必须完整覆盖该区域全部笔画且互不重叠。
  String? splitBlockReason(RegionSegment region, List<List<String>> subsets) {
    if (subsets.length < 2) return 'too-few-subsets';
    final expected = region.strokeIds.toSet();
    final seen = <String>{};
    var total = 0;
    for (final subset in subsets) {
      if (subset.isEmpty) return 'empty-subset';
      for (final id in subset) {
        if (!expected.contains(id)) return 'foreign-stroke($id)';
        if (!seen.add(id)) return 'duplicated-stroke($id)';
        total++;
      }
    }
    if (total != expected.length) {
      return 'stroke-loss(${expected.length - total})';
    }
    return null;
  }
}
