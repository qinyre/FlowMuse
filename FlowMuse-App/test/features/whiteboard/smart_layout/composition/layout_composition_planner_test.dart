import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_composition_planner.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-401A：结构适用/拒绝 fixture、确定性顺序/hash、配额不饿死、
/// conservative 非 fallback、参数只来自 tokens。
void main() {
  const planner = LayoutCompositionPlanner();
  const tokens = SmartLayoutDesignTokens.v1;
  // min=240 max=560 gutter=24。

  CompositionConstraint at(double width) => CompositionConstraint(
    contentWidth: width,
    // 宽度专项测试默认给足内容量与图语义：门禁不触发。
    contentBlockCount: 12,
    contentFillRatio: 0.8,
    hasFigureContent: true,
    tokens: tokens,
  );

  test('宽页：四种结构全部有候选，域=10 ≤ 配额 12', () {
    final plan = planner.enumerate(constraint: at(1200));
    expect(plan.rejected, isEmpty);
    expect(plan.domainSize, 9, reason: 'single1+twoColumn1+mainSide6+conservative1');
    expect(plan.candidates, hasLength(9));
    final skeletons = plan.candidates.map((c) => c.skeleton).toSet();
    expect(skeletons, containsAll(LayoutSkeleton.values));
  });

  test('窄页 480：twoColumn 拒绝（栏 228<240），mainSide 侧栏 240 档部分拒绝',
      () {
    final plan = planner.enumerate(constraint: at(480));
    // twoColumn：(480-24)/2=228 < 240 → columnBelowMinLine。
    expect(
      plan.rejected.any(
        (r) =>
            r.skeleton == LayoutSkeleton.twoColumn &&
            r.reason == CompositionRejectReason.columnBelowMinLine,
      ),
      isTrue,
    );
    // mainSide side=240：main=480-240-24=216 < 240 → sideColumnInfeasible。
    expect(
      plan.rejected.any(
        (r) =>
            r.skeleton == LayoutSkeleton.mainSide &&
            r.reason == CompositionRejectReason.sideColumnInfeasible,
      ),
      isTrue,
    );
    // side=400 中点档：main=480-400-24=56 → 拒绝；域内不出现。
    expect(
      plan.candidates.where((c) => c.skeleton == LayoutSkeleton.mainSide),
      everyElement(
        predicate<CompositionCandidate>(
          (c) => c.params.mainColumnWidth >= 240 - 1e-9,
          '主栏 ≥ 最小行长',
        ),
      ),
    );
    // single(480≥240) 与 conservative 恒在。
    expect(
      plan.candidates.map((c) => c.skeleton),
      containsAll([LayoutSkeleton.single, LayoutSkeleton.conservativeLayout]),
    );
  });

  test('极窄页 200：single 拒绝 contentBelowMinLine，conservative 仍适用',
      () {
    final plan = planner.enumerate(constraint: at(200));
    expect(
      plan.rejected.any(
        (r) =>
            r.skeleton == LayoutSkeleton.single &&
            r.reason == CompositionRejectReason.contentBelowMinLine,
      ),
      isTrue,
    );
    expect(
      plan.candidates.map((c) => c.skeleton),
      contains(LayoutSkeleton.conservativeLayout),
      reason: '保守结构是真实重排兜底，恒适用',
    );
    // conservative 主栏宽 = clamp(200, 240, 560) = 240（最小行长大栏界）。
    final conservative = plan.candidates
        .singleWhere((c) => c.skeleton == LayoutSkeleton.conservativeLayout);
    expect(conservative.params.mainColumnWidth, 240);
  });

  test('确定性：双跑同序同 id 同 hash', () {
    final a = planner.enumerate(constraint: at(1200));
    final b = planner.enumerate(constraint: at(1200));
    expect(
      b.candidates.map((c) => c.id).toList(),
      a.candidates.map((c) => c.id).toList(),
    );
    expect(
      b.candidates.map((c) => c.structureHash).toList(),
      a.candidates.map((c) => c.structureHash).toList(),
    );
    // hash 随参数变化：左右两个 mainSide 候选 hash 不同。
    final mainSide = a.candidates
        .where((c) => c.skeleton == LayoutSkeleton.mainSide)
        .toList();
    expect(mainSide.length, greaterThanOrEqualTo(2));
    expect(
      mainSide.first.structureHash,
      isNot(mainSide.last.structureHash),
    );
  });

  test('配额不饿死结构：quota=4 时四种结构各留至少 1 个代表', () {
    final plan = planner.enumerate(constraint: at(1200), quota: 4);
    expect(plan.candidates, hasLength(4));
    expect(
      plan.candidates.map((c) => c.skeleton).toSet(),
      containsAll(LayoutSkeleton.values),
      reason: '轮转截断保证每结构至少 1 代表',
    );
    // 配额 2：只保留轮转前两结构（single/twoColumn），仍不越限。
    final plan2 = planner.enumerate(constraint: at(1200), quota: 2);
    expect(plan2.candidates, hasLength(2));
  });

  test('conservative-layout 不是零修改 fallback：参数是真实重排几何', () {
    final plan = planner.enumerate(constraint: at(1200));
    final conservative = plan.candidates
        .singleWhere((c) => c.skeleton == LayoutSkeleton.conservativeLayout);
    // 主栏 clamp 到行长界（560），不是"保持原位"的零修改标记——
    // 零修改另有 V3-403A preserveFallback 分型。
    expect(conservative.params.mainColumnWidth, 560);
    expect(conservative.id, startsWith('conservativeLayout#'));
  });

  test('参数只来自 tokens：每个数值可溯源 token 常数', () {
    final plan = planner.enumerate(constraint: at(1200));
    for (final c in plan.candidates) {
      expect(c.params.columnGutter, tokens.columnGutter);
      expect(c.params.pageMargin, tokens.pageMargin);
      // 侧栏档 ∈ token 行长界三档。
      final side = c.params.sideColumnWidth;
      if (side != null) {
        expect(
          side,
          anyOf(tokens.minLineLength, (tokens.minLineLength + tokens.maxLineLength) / 2, tokens.maxLineLength),
          reason: '${c.id} 侧栏宽必须来自 token 行长界档位',
        );
      }
    }
    // twoColumn 主栏 = (w-gutter)/2。
    final two = plan.candidates
        .singleWhere((c) => c.skeleton == LayoutSkeleton.twoColumn);
    expect(two.params.mainColumnWidth, (1200 - 24) / 2);
  });

  test('id 确定性格式与域序号稳定', () {
    final plan = planner.enumerate(constraint: at(1200));
    final ids = plan.candidates.map((c) => c.id).toList();
    expect(ids, containsAll(['single#0', 'twoColumn#1', 'conservativeLayout#8']));
    // mainSide 域序号 = 域内全局序 2..7（single0/twoColumn1 之后连续）。
    final mainSideIdx = plan.candidates
        .where((c) => c.skeleton == LayoutSkeleton.mainSide)
        .map((c) => int.parse(c.id.split('#')[1]))
        .toList();
    expect(mainSideIdx, [2, 3, 4, 5, 6, 7]);
  });

  group('内容量/侧栏语义门禁（真机 2026-09-03 案例：短清单被 mainSide 拆栏）', () {
    CompositionConstraint withFacts({
      required int blocks,
      required double fill,
      required bool figure,
    }) => CompositionConstraint(
      contentWidth: 1200,
      contentBlockCount: blocks,
      contentFillRatio: fill,
      hasFigureContent: figure,
      tokens: tokens,
    );

    test('纯文字稀疏：多栏全拒，单栏族保留', () {
      final plan = planner.enumerate(
        constraint: withFacts(blocks: 4, fill: 0.15, figure: false),
      );
      expect(
        plan.candidates.map((c) => c.skeleton).toSet(),
        {LayoutSkeleton.single, LayoutSkeleton.conservativeLayout},
        reason: '短内容只出单栏族，双栏/主侧栏不适用',
      );
      expect(
        plan.rejected
            .where((r) => r.skeleton == LayoutSkeleton.twoColumn)
            .map((r) => r.reason),
        everyElement(CompositionRejectReason.contentTooSparse),
      );
      expect(
        plan.rejected.where((r) => r.skeleton == LayoutSkeleton.mainSide),
        hasLength(6),
        reason: 'mainSide 六档全部留档拒绝（零静默跳过）',
      );
    });

    test('纯文字稠密：twoColumn 适用，mainSide 因无侧栏语义拒绝', () {
      final plan = planner.enumerate(
        constraint: withFacts(blocks: 12, fill: 0.8, figure: false),
      );
      expect(
        plan.candidates.map((c) => c.skeleton),
        contains(LayoutSkeleton.twoColumn),
      );
      expect(
        plan.rejected
            .where((r) => r.skeleton == LayoutSkeleton.mainSide)
            .map((r) => r.reason),
        everyElement(CompositionRejectReason.sidebarSemanticsRequired),
        reason: '空侧栏只会把正文挤出大空洞，mainSide 需图/图注语义',
      );
      expect(
        plan.rejected
            .where((r) => r.reason == CompositionRejectReason.contentTooSparse),
        isEmpty,
      );
    });

    test('图文稀疏：内容量门禁不触发（图语义放行多栏，交由宽度判定）', () {
      final plan = planner.enumerate(
        constraint: withFacts(blocks: 2, fill: 0.1, figure: true),
      );
      expect(
        plan.rejected.where(
          (r) =>
              r.reason == CompositionRejectReason.contentTooSparse ||
              r.reason == CompositionRejectReason.sidebarSemanticsRequired,
        ),
        isEmpty,
      );
      expect(plan.domainSize, 9);
    });
  });
}
