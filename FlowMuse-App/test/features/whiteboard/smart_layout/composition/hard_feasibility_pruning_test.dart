import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/smart_layout/composition/hard_feasibility_pruning.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_composition_planner.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-401B：硬下界剪枝 + 小 fixture 全枚举差分 oracle。
/// oracle 是真 ground truth：块→栏指派全枚举，块高按所在栏宽取值
///（heightsPerColumn），与 pruner 公式完全独立；
/// 误剪任何硬可行结构 = 差分不符直接失败。
void main() {
  const planner = LayoutCompositionPlanner();
  const tokens = SmartLayoutDesignTokens.v1;
  // compactGapFloor=8 paragraphSpacing=24 minLine=240。

  CompositionConstraint at(double width) => CompositionConstraint(
    // 宽度专项差分：给足内容量与图语义，门禁不触发。
    contentWidth: width,
    contentBlockCount: 12,
    contentFillRatio: 0.8,
    hasFigureContent: true,
    tokens: tokens,
  );

  /// 候选的栏宽序列（twoColumn 两等宽栏；mainSide 主+侧；其余单栏）。
  List<double> columnsOf(CompositionCandidate c) => switch (c.skeleton) {
    LayoutSkeleton.mainSide => [
      c.params.mainColumnWidth,
      c.params.sideColumnWidth!,
    ],
    LayoutSkeleton.twoColumn => [
      c.params.mainColumnWidth,
      c.params.mainColumnWidth,
    ],
    _ => [c.params.mainColumnWidth],
  };

  /// fixture：块内在宽 → 各栏宽下的换行高（ceil 比例换行，宽栏更低）。
  double heightAt(double intrinsicWidth, double baseHeight, double column) =>
      intrinsicWidth <= column
          ? baseHeight
          : baseHeight * (intrinsicWidth / column).ceilToDouble();

  /// pruner 输入：每块最小可能栏高（min over 候选栏宽）。
  List<double> minHeightsForCandidate(
    CompositionCandidate c,
    List<double> intrinsicWidths,
    List<double> baseHeights,
  ) {
    final columns = columnsOf(c);
    return [
      for (var i = 0; i < baseHeights.length; i++)
        columns
            .map((col) => heightAt(intrinsicWidths[i], baseHeights[i], col))
            .reduce(math.min),
    ];
  }

  /// 真 ground truth：枚举每块→栏全指派；块高按所在栏取
  ///（heightsPerColumn[i][j] = 块 i 在候选栏 j 的高），逐栏计间距。
  bool oracleFeasible({
    required List<List<double>> heightsPerColumn,
    required double contentHeight,
    double gap = 8,
  }) {
    final n = heightsPerColumn.length;
    final columns = heightsPerColumn.first.length;
    if (n == 0) return true;
    var total = 1;
    for (var i = 0; i < n; i++) {
      total *= columns;
    }
    final assignment = List<int>.filled(n, 0);
    for (var code = 0; code < total; code++) {
      var rest = code;
      for (var i = 0; i < n; i++) {
        assignment[i] = rest % columns;
        rest ~/= columns;
      }
      var ok = true;
      for (var c = 0; c < columns && ok; c++) {
        var sum = 0.0;
        var count = 0;
        for (var i = 0; i < n; i++) {
          if (assignment[i] == c) {
            sum += heightsPerColumn[i][c];
            count++;
          }
        }
        if (count > 0 && sum + (count - 1) * gap > contentHeight + 1e-9) {
          ok = false;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  /// oracle 输入构造：逐块逐栏高度矩阵。
  List<List<double>> perColumnHeights(
    CompositionCandidate c,
    List<double> intrinsicWidths,
    List<double> baseHeights,
  ) {
    final columns = columnsOf(c);
    return [
      for (var i = 0; i < baseHeights.length; i++)
        [
          for (final col in columns)
            heightAt(intrinsicWidths[i], baseHeights[i], col),
        ],
    ];
  }

  test('高余量：零剪枝', () {
    final plan = planner.enumeratePruned(
      constraint: at(1200),
      contentHeight: 3000,
      textHeightsOf: (c) => const [600],
      figureHeightsOf: (c) => const [],
      tokens: tokens,
    );
    expect(plan.pruned, isEmpty);
    expect(plan.candidates, isNotEmpty);
  });

  test('复审 F1 反例：twoColumn 两块 600、H=603 必须存活', () {
    final plan = planner.enumeratePruned(
      constraint: at(1200),
      contentHeight: 603,
      textHeightsOf: (c) => const [600],
      figureHeightsOf: (c) => const [600],
      tokens: tokens,
    );
    expect(
      plan.candidates.where((c) => c.skeleton == LayoutSkeleton.twoColumn),
      isNotEmpty,
      reason: '跨栏并排不消耗垂直间隙：LB=1200 ≤ 1206',
    );
    expect(
      plan.pruned.any((p) => p.candidate.skeleton == LayoutSkeleton.single),
      isTrue,
      reason: '单栏 LB=1208 > 603 正确剪除',
    );
  });

  /// 对一组 fixture 跑差分：返回 (剪枝集, oracle 不可行集)。
  (Set<String>, Set<String>) runDifferential(
    double h,
    List<double> widths,
    List<double> bases,
  ) {
    final plan = planner.enumeratePruned(
      constraint: at(1200),
      contentHeight: h,
      textHeightsOf: (c) => minHeightsForCandidate(c, widths, bases),
      figureHeightsOf: (c) => const [],
      tokens: tokens,
    );
    final base = planner.enumerate(constraint: at(1200));
    final oracleInfeasible = <String>{};
    for (final c in base.candidates) {
      if (!oracleFeasible(
        heightsPerColumn: perColumnHeights(c, widths, bases),
        contentHeight: h,
      )) {
        oracleInfeasible.add(c.id);
      }
    }
    return (
      plan.pruned.map((p) => p.candidate.id).toSet(),
      oracleInfeasible,
    );
  }

  test('差分 oracle 第一层（零误剪，全部 fixture）：剪枝集 ⊆ oracle 不可行集', () {
    // LB 是每块独立取最优栏的松弛下界（忽略栏容量竞争），只会欠剪
    // 不会过剪；"误剪任何硬可行结构直接失败"由本层在全部 fixture 上
    // 机器验证。
    final fixtures = <
      (
        double contentHeight,
        List<double> intrinsicWidths,
        List<double> baseHeights,
      )
    >[
      (3000, const [300], const [600]),
      (603, const [300, 300], const [600, 600]),
      (400, const [250], const [250]),
      (1200, const [200, 900], const [600, 300]),
      (127, const [200, 200], const [60, 60]),
      (128, const [200, 200], const [60, 60]),
      (700, const [300, 300], const [600, 600]),
      (95, const [200, 240], const [60, 20]),
      (602, const [300, 300], const [600, 600]),
      (260, const [250, 250], const [250, 250]),
    ];
    for (final (h, widths, bases) in fixtures) {
      final (prunedIds, oracleInfeasible) = runDifferential(h, widths, bases);
      expect(
        prunedIds.difference(oracleInfeasible),
        isEmpty,
        reason: '误剪硬可行候选 (h=$h): ${prunedIds.difference(oracleInfeasible)}',
      );
    }
  });

  test('差分 oracle 第二层（可行集等价）：无栏竞争 fixture 双向差分为空', () {
    // 等价层 fixture 刻意避开 LB 松弛带（每块内在宽 ≤ 候选最窄栏宽，
    // 块在任一栏高度相同——栏竞争不存在，均值下界即精确）。
    final fixtures = <
      (
        double contentHeight,
        List<double> intrinsicWidths,
        List<double> baseHeights,
      )
    >[
      (3000, const [240], const [600]),
      (127, const [200, 200], const [60, 60]),
      (128, const [200, 200], const [60, 60]),
      (95, const [200, 240], const [60, 20]),
      (700, const [240, 240], const [600, 600]),
    ];
    for (final (h, widths, bases) in fixtures) {
      final (prunedIds, oracleInfeasible) = runDifferential(h, widths, bases);
      expect(
        prunedIds.difference(oracleInfeasible),
        isEmpty,
        reason: '误剪 (h=$h)',
      );
      expect(
        oracleInfeasible.difference(prunedIds),
        isEmpty,
        reason: '漏剪 (h=$h): ${oracleInfeasible.difference(prunedIds)}',
      );
    }
  });

  test('反例 fixture：间距下界必须取 compact 档（收紧即误剪）', () {
    final plan = planner.enumeratePruned(
      constraint: at(1200),
      contentHeight: 130,
      textHeightsOf: (c) => const [60],
      figureHeightsOf: (c) => const [60],
      tokens: tokens,
    );
    expect(
      plan.candidates.where((c) => c.skeleton == LayoutSkeleton.single),
      isNotEmpty,
      reason: '128 ≤ 130：收紧间距下界会误剪此例',
    );
    final prunedPlan = planner.enumeratePruned(
      constraint: at(1200),
      contentHeight: 127,
      textHeightsOf: (c) => const [60],
      figureHeightsOf: (c) => const [60],
      tokens: tokens,
    );
    expect(
      prunedPlan.pruned.any(
        (p) => p.candidate.skeleton == LayoutSkeleton.single,
      ),
      isTrue,
      reason: '128 > 127 硬下界超限',
    );
  });

  test('反例 fixture：多栏摊倍不许提前（twoColumn 恒 2 栏）', () {
    final plan = planner.enumeratePruned(
      constraint: at(1200),
      contentHeight: 700,
      textHeightsOf: (c) => const [600],
      figureHeightsOf: (c) => const [600],
      tokens: tokens,
    );
    expect(
      plan.candidates.where((c) => c.skeleton == LayoutSkeleton.twoColumn),
      isNotEmpty,
      reason: '摊倍误取 1 会把 1200≤1400 误剪',
    );
  });

  test('按候选栏宽分派：mainSide 六档测量不同仍差分等价', () {
    final widths = [900.0];
    final bases = [600.0];
    const h = 610.0;
    final plan = planner.enumeratePruned(
      constraint: at(1200),
      contentHeight: h,
      textHeightsOf: (c) => minHeightsForCandidate(c, widths, bases),
      figureHeightsOf: (c) => const [],
      tokens: tokens,
    );
    final base = planner.enumerate(constraint: at(1200));
    final oracleInfeasible = <String>{};
    for (final c in base.candidates) {
      if (!oracleFeasible(
        heightsPerColumn: perColumnHeights(c, widths, bases),
        contentHeight: h,
      )) {
        oracleInfeasible.add(c.id);
      }
    }
    final prunedIds = plan.pruned.map((p) => p.candidate.id).toSet();
    // 该 fixture 内在宽 900 > 侧栏宽，存在栏容量竞争（LB 松弛带）——
    // 断言零误剪；等价性由第二层无竞争 fixture 覆盖。
    expect(prunedIds.difference(oracleInfeasible), isEmpty,
        reason: '按候选分派不得误剪');
    // fixture 有效性：不同候选产生不同最小高（936 栏 600 vs 616 栏 1200）。
    final distinctMin = base.candidates
        .map((c) => minHeightsForCandidate(c, widths, bases).first)
        .toSet();
    expect(distinctMin.length, greaterThan(1),
        reason: '六档栏宽必须产生不同最小测量高');
  });

  test('全部剪除时：候选空 + 全量留档 + conservative 同规', () {
    final plan = planner.enumeratePruned(
      constraint: at(1200),
      contentHeight: 50,
      textHeightsOf: (c) => const [600],
      figureHeightsOf: (c) => const [],
      tokens: tokens,
    );
    expect(plan.candidates, isEmpty);
    expect(plan.pruned, isNotEmpty);
    expect(
      plan.pruned.every(
        (p) => p.verdict == PruneVerdict.hardHeightLowerBoundExceeded,
      ),
      isTrue,
    );
    expect(
      plan.pruned.any(
        (p) => p.candidate.skeleton == LayoutSkeleton.conservativeLayout,
      ),
      isTrue,
    );
  });

  test('结构性拒绝透传留档（窄页 + 剪枝叠加）', () {
    final plan = planner.enumeratePruned(
      constraint: at(200),
      contentHeight: 3000,
      textHeightsOf: (c) => const [100],
      figureHeightsOf: (c) => const [],
      tokens: tokens,
    );
    expect(plan.structuralRejections, isNotEmpty);
    expect(
      plan.candidates.map((c) => c.skeleton),
      contains(LayoutSkeleton.conservativeLayout),
    );
  });

  test('图片等比高参与下界（figureHeightsOf 按候选栏宽缩放）', () {
    double figureHeight(CompositionCandidate c) {
      final columns = columnsOf(c);
      const natural = 1200.0;
      final heights = [
        for (final col in columns) math.min(natural, col) / 2.0,
      ];
      return heights.reduce(math.min);
    }

    final plan = planner.enumeratePruned(
      constraint: at(1200),
      contentHeight: 305,
      textHeightsOf: (c) => const [],
      figureHeightsOf: (c) => [figureHeight(c)],
      tokens: tokens,
    );
    expect(
      plan.pruned.any((p) => p.candidate.skeleton == LayoutSkeleton.single),
      isTrue,
      reason: '600 > 305',
    );
    expect(
      plan.candidates.where((c) => c.skeleton == LayoutSkeleton.twoColumn),
      isNotEmpty,
      reason: '294 ≤ 305',
    );
  });
}
