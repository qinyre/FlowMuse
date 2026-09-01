import '../design/smart_layout_design_tokens.dart';
import 'layout_composition_planner.dart';

/// 剪枝判定（V3-401B）。
enum PruneVerdict {
  feasible,

  /// 硬高度下界超限：任何合法摆放都放不下（单调硬可行下界剪枝）。
  hardHeightLowerBoundExceeded,
}

/// 剪枝结论（带下界值与限制值，可审计）。
class PruneResult {
  const PruneResult._(this.verdict, this.lowerBound, this.contentLimit);

  final PruneVerdict verdict;

  /// 内容总高度硬下界。
  final double lowerBound;

  /// 高度限制（内容区高 × 栏数）。
  final double contentLimit;

  bool get pruned => verdict != PruneVerdict.feasible;
}

/// 单调硬可行下界剪枝器（V3-401B）。
///
/// 剪枝规则（唯一一条）与证明：
/// 任何合法摆放把 n 个块指派到 k 栏。同栏块垂直堆叠，块高 ≥
/// 其所在栏宽下的真实测量高（测量即该栏宽的精确换行高；图片等比高）；
/// 同栏相邻块间距 ≥ compactGapFloor（token 下限）。k 栏并排，跨栏
/// 块之间不消耗垂直间隙，故全页内容总高度 ≥
///   LB = Σhᵢ + max(0, n-k)·compactGapFloor
///（单栏 k=1 退化为 Σh+(n-1)·g）。可行必要条件 LB ≤ k·contentHeight。
/// LB 是必要条件（单调硬下界）——只剪"必然不可行"，不判可行。
///
/// 反例（规则收紧即误剪，全部有 fixture 固化）：
/// 1. 间距下界改用 paragraphSpacing(24)：Σh+8(n-1) ≤ H <
///    Σh+24(n-1) 的真实可行候选被误剪（h=130 两块 60 案例）。
/// 2. gap 项误取 (n-1)（忽略跨栏并排）：twoColumn 两块 600、H=603，
///    错误 LB=1208>1206 误剪，真实每栏一块 600≤603 合法。
/// 3. 多栏摊倍误取 1：h=700 时双栏 1208>700 误剪（真实摊倍 2 容纳）。
class HardFeasibilityPruner {
  const HardFeasibilityPruner();

  /// 判定单候选：[textHeights]/[figureHeights] 必须是该候选下每块的
  /// **最小可能栏高**——多栏结构对每块取 min(主栏测量高, 侧栏测量高)
  ///（块可放任一栏；取最小是合法下界且最紧）。按 skeleton 共享一值
  /// 会高估窄栏候选，按单一栏宽测量会高估可放宽栏的块。
  PruneResult prune({
    required CompositionCandidate candidate,
    required List<double> textHeights,
    required List<double> figureHeights,
    required double contentHeight,
    required SmartLayoutDesignTokens tokens,
  }) {
    final columnCount = _columnCountOf(candidate.skeleton);
    final blockCount = textHeights.length + figureHeights.length;
    var sum = 0.0;
    for (final h in textHeights) {
      sum += h;
    }
    for (final h in figureHeights) {
      sum += h;
    }
    // 跨栏并排不消耗垂直间隙：只有"同栏堆叠"产生间隙，
    // n 块分 k 栏至少 n-k 次同栏相邻（可能更多，下界取最少）。
    final gapLower = blockCount > columnCount
        ? (blockCount - columnCount) * tokens.compactGapFloor
        : 0.0;
    final lowerBound = sum + gapLower;
    final limit = contentHeight * columnCount;
    return PruneResult._(
      lowerBound <= limit + _eps
          ? PruneVerdict.feasible
          : PruneVerdict.hardHeightLowerBoundExceeded,
      lowerBound,
      limit,
    );
  }

  static int _columnCountOf(LayoutSkeleton skeleton) => switch (skeleton) {
    LayoutSkeleton.twoColumn || LayoutSkeleton.mainSide => 2,
    _ => 1,
  };

  static const double _eps = 1e-9;
}

/// planner 剪枝扩展（V3-401B）。
///
/// 输入封闭性：高度回调与签名只接受几何事实（候选参数 + 真实测量高），
/// 编译期不存在软分/排名/profile 通道；不读取未经过真实测量的估算值
/// 是调用方纪律，由差分 oracle 与 V3-402A 真实测量链共同约束。
extension LayoutCompositionPlannerPruning on LayoutCompositionPlanner {
  /// 枚举 + 硬下界剪枝。高度回调**按候选**分派（区分栏宽档）：
  /// [textHeightsOf]/[figureHeightsOf] 接收完整 candidate，调用方用
  /// candidate.params.mainColumnWidth 等做真实测量。
  PrunedPlanEnumeration enumeratePruned({
    required CompositionConstraint constraint,
    required double contentHeight,
    required List<double> Function(CompositionCandidate candidate)
    textHeightsOf,
    required List<double> Function(CompositionCandidate candidate)
    figureHeightsOf,
    required SmartLayoutDesignTokens tokens,
    int quota = LayoutCompositionPlanner.defaultQuota,
  }) {
    final base = enumerate(constraint: constraint, quota: quota);
    const pruner = HardFeasibilityPruner();
    final survivors = <CompositionCandidate>[];
    final pruned = <PrunedCandidate>[];
    for (final candidate in base.candidates) {
      final result = pruner.prune(
        candidate: candidate,
        textHeights: textHeightsOf(candidate),
        figureHeights: figureHeightsOf(candidate),
        contentHeight: contentHeight,
        tokens: tokens,
      );
      if (result.pruned) {
        pruned.add(PrunedCandidate(
          candidate: candidate,
          verdict: result.verdict,
          lowerBound: result.lowerBound,
          contentLimit: result.contentLimit,
        ));
      } else {
        survivors.add(candidate);
      }
    }
    return PrunedPlanEnumeration(
      candidates: List.unmodifiable(survivors),
      pruned: List.unmodifiable(pruned),
      structuralRejections: base.rejected,
      domainSize: base.domainSize,
    );
  }
}

/// 被剪候选留档。
class PrunedCandidate {
  const PrunedCandidate({
    required this.candidate,
    required this.verdict,
    required this.lowerBound,
    required this.contentLimit,
  });

  final CompositionCandidate candidate;
  final PruneVerdict verdict;
  final double lowerBound;
  final double contentLimit;

  @override
  String toString() =>
      'Pruned(${candidate.id}, ${verdict.name}, '
      'lb=${lowerBound.toStringAsFixed(1)} > limit=${contentLimit.toStringAsFixed(1)})';
}

/// 剪枝后枚举结果。
class PrunedPlanEnumeration {
  const PrunedPlanEnumeration({
    required this.candidates,
    required this.pruned,
    required this.structuralRejections,
    required this.domainSize,
  });

  final List<CompositionCandidate> candidates;
  final List<PrunedCandidate> pruned;

  /// 结构级拒绝（V3-401A 域拒绝，透传留档）。
  final List<({LayoutSkeleton skeleton, CompositionRejectReason reason})>
  structuralRejections;
  final int domainSize;
}
