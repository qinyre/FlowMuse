import 'dart:math' as math;

import '../design/smart_layout_design_tokens.dart';
import '../snapshot/deterministic_hash.dart';

/// 宏观候选结构骨架（V3-401A）。
enum LayoutSkeleton {
  /// 单栏全宽。
  single,

  /// 双栏等分（栏沟取 token）。
  twoColumn,

  /// 主栏 + 侧栏（主/侧方向与侧栏宽档）。
  mainSide,

  /// 保守重排：单栏、保持阅读序、不改写字号比例的紧凑排布——
  /// 真实重排结构（会移动元素），不是零修改 fallback（那是
  /// V3-403A 的 preserveFallback，概念上独立）。
  conservativeLayout,
}

/// 结构级稳定拒绝码（适用性判定；块级可行性归 V3-402A flow）。
enum CompositionRejectReason {
  /// 内容区窄于最小行长：单栏/保守结构不可用。
  contentBelowMinLine,

  /// 栏宽（扣沟后）窄于最小行长：多栏结构不可用。
  columnBelowMinLine,

  /// 侧栏档在界外（内容区不足以容纳主栏下限+侧栏下限+沟）。
  sideColumnInfeasible,
}

/// 单条结构级约束结论。
class CompositionConstraintCheck {
  const CompositionConstraintCheck.allowed()
    : allowed = true,
      reason = null;

  const CompositionConstraintCheck.rejected(this.reason)
    : assert(reason != null),
      allowed = false;

  final bool allowed;
  final CompositionRejectReason? reason;
}

/// 结构适用性约束（V3-401A）：只依赖内容区宽度与冻结 tokens——
/// 参数域与判定全部可溯源 token 常数，不读软分、不读排名。
class CompositionConstraint {
  const CompositionConstraint({
    required this.contentWidth,
    required this.tokens,
  });

  final double contentWidth;
  final SmartLayoutDesignTokens tokens;

  /// 单栏适用：内容区 ≥ 最小行长。
  CompositionConstraintCheck singleColumn() =>
      contentWidth + _eps >= tokens.minLineLength
          ? const CompositionConstraintCheck.allowed()
          : const CompositionConstraintCheck.rejected(
              CompositionRejectReason.contentBelowMinLine,
            );

  /// 双栏适用：扣沟后每栏 ≥ 最小行长。
  CompositionConstraintCheck twoColumn() {
    final column = (contentWidth - tokens.columnGutter) / 2;
    if (column + _eps < tokens.minLineLength) {
      return const CompositionConstraintCheck.rejected(
        CompositionRejectReason.columnBelowMinLine,
      );
    }
    return const CompositionConstraintCheck.allowed();
  }

  /// 主侧栏适用（侧栏宽 [sideWidth]）：主栏 ≥ 最小行长。
  CompositionConstraintCheck mainSide(double sideWidth) {
    final main = contentWidth - sideWidth - tokens.columnGutter;
    if (main + _eps < tokens.minLineLength) {
      return const CompositionConstraintCheck.rejected(
        CompositionRejectReason.sideColumnInfeasible,
      );
    }
    return const CompositionConstraintCheck.allowed();
  }

  /// 保守结构恒适用（真实重排兜底；零修改另有 preserveFallback）。
  CompositionConstraintCheck conservative() =>
      const CompositionConstraintCheck.allowed();

  static const double _eps = 1e-9;
}

/// 候选参数（全部由 tokens 推导；记录溯源字段供审计）。
class CompositionParams {
  const CompositionParams({
    required this.columnGutter,
    required this.pageMargin,
    required this.mainColumnWidth,
    this.sideColumnWidth,
    this.sideOnRight = true,
  });

  /// 栏沟（tokens.columnGutter 直取）。
  final double columnGutter;

  /// 页边距（tokens.pageMargin 直取）。
  final double pageMargin;

  /// 主栏/单栏宽（内容区与结构几何推导）。
  final double mainColumnWidth;

  /// 侧栏宽（mainSide 专用；token 行长界档位）。
  final double? sideColumnWidth;

  /// 侧栏是否在右侧（mainSide 方向档）。
  final bool sideOnRight;

  Map<String, Object?> toJson() => {
    'columnGutter': columnGutter,
    'pageMargin': pageMargin,
    'mainColumnWidth': mainColumnWidth,
    if (sideColumnWidth != null) 'sideColumnWidth': sideColumnWidth,
    'sideOnRight': sideOnRight,
  };

  /// canonical 串（确定性 hash 输入；数字最短表示）。
  String canonical() {
    String n(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return [
      n(columnGutter),
      n(pageMargin),
      n(mainColumnWidth),
      if (sideColumnWidth != null) n(sideColumnWidth!),
      sideOnRight ? 'R' : 'L',
    ].join('~');
  }
}

/// 组合候选（V3-401A）：结构骨架 + token 参数域的一格。
class CompositionCandidate {
  const CompositionCandidate({
    required this.id,
    required this.skeleton,
    required this.params,
    required this.index,
  });

  /// 确定性 id：结构线名 + 域序号（如 `two-column#0`）。
  final String id;
  final LayoutSkeleton skeleton;
  final CompositionParams params;

  /// 枚举序（planner 输出位置；确定性）。
  final int index;

  /// 候选 canonical hash（结构 + 参数；跨端/双跑稳定）。
  String get structureHash => fingerprint64(
    'composition|${skeleton.name}|${params.canonical()}',
  );

  @override
  String toString() => 'CompositionCandidate($id, h=${structureHash.substring(0, 8)})';
}

/// 宏观候选 planner（V3-401A）：确定性枚举 single/two-column/
/// main-side/conservative-layout；参数只来自冻结 tokens；结构配额
/// [maxCandidates]（默认 12）下按结构轮转公平截断——任何结构不被
/// 饿死（每个适用结构至少保留 1 个代表）。
class LayoutCompositionPlanner {
  const LayoutCompositionPlanner();

  static const int defaultQuota = 12;

  /// 枚举适用候选（确定性顺序：结构枚举序 → 域内序）。
  ///
  /// 适用性由 [constraint] 判定；不适用的结构格被跳过且记录在
  /// [PlanEnumeration.rejected]（零静默跳过，供 fixture 断言）。
  PlanEnumeration enumerate({
    required CompositionConstraint constraint,
    int quota = defaultQuota,
  }) {
    final tokens = constraint.tokens;
    final w = constraint.contentWidth;

    // 域定义（全部 token 推导；顺序冻结；拒绝格同样入域留档——
    // 零静默跳过）。
    final domain = <(_DomainSlot, CompositionConstraintCheck)>[
      // single：全宽 1 档。
      (
        _DomainSlot(
          skeleton: LayoutSkeleton.single,
          params: CompositionParams(
            columnGutter: tokens.columnGutter,
            pageMargin: tokens.pageMargin,
            mainColumnWidth: w,
          ),
        ),
        constraint.singleColumn(),
      ),
      // two-column：等分 1 档（沟取 token）。
      (
        _DomainSlot(
          skeleton: LayoutSkeleton.twoColumn,
          params: CompositionParams(
            columnGutter: tokens.columnGutter,
            pageMargin: tokens.pageMargin,
            mainColumnWidth: (w - tokens.columnGutter) / 2,
          ),
        ),
        constraint.twoColumn(),
      ),
      // main-side：侧栏三档（min/中点/max 行长界）× 左右 2 方向 = 6 档。
      for (final sideWidth in _sideWidths(tokens))
        for (final sideOnRight in [true, false])
          (
            _DomainSlot(
              skeleton: LayoutSkeleton.mainSide,
              params: CompositionParams(
                columnGutter: tokens.columnGutter,
                pageMargin: tokens.pageMargin,
                mainColumnWidth: w - sideWidth - tokens.columnGutter,
                sideColumnWidth: sideWidth,
                sideOnRight: sideOnRight,
              ),
            ),
            constraint.mainSide(sideWidth),
          ),
      // conservative：单栏保守 1 档（恒适用）。
      (
        _DomainSlot(
          skeleton: LayoutSkeleton.conservativeLayout,
          params: CompositionParams(
            columnGutter: tokens.columnGutter,
            pageMargin: tokens.pageMargin,
            mainColumnWidth: math.max(
              math.min(w, tokens.maxLineLength),
              tokens.minLineLength,
            ),
          ),
        ),
        constraint.conservative(),
      ),
    ];

    final accepted =
        domain.where((slot) => slot.$2.allowed).map((s) => s.$1).toList();
    final rejected = [
      for (final slot in domain.where((s) => !s.$2.allowed))
        (skeleton: slot.$1.skeleton, reason: slot.$2.reason!),
    ];

    // 配额：结构轮转公平截断（每适用结构至少 1 代表）。
    final bySkeleton = <LayoutSkeleton, List<_DomainSlot>>{};
    for (final slot in accepted) {
      bySkeleton.putIfAbsent(slot.skeleton, () => []).add(slot);
    }
    final skeletonOrder = LayoutSkeleton.values
        .where(bySkeleton.containsKey)
        .toList();
    final selected = <_DomainSlot>[];
    var round = 0;
    var exhausted = false;
    while (selected.length < quota && !exhausted) {
      exhausted = true;
      for (final skeleton in skeletonOrder) {
        if (selected.length >= quota) break;
        final slots = bySkeleton[skeleton]!;
        if (round < slots.length) {
          selected.add(slots[round]);
          exhausted = false;
        }
      }
      round++;
    }

    final candidates = [
      for (var i = 0; i < selected.length; i++)
        CompositionCandidate(
          id: '${selected[i].skeleton.name}#${_domainIndex(selected[i], accepted)}',
          skeleton: selected[i].skeleton,
          params: selected[i].params,
          index: i,
        ),
    ];
    return PlanEnumeration(
      candidates: List.unmodifiable(candidates),
      rejected: List.unmodifiable(rejected),
      domainSize: accepted.length,
    );
  }

  /// 侧栏宽档：行长界三档（min / 中点 / max），token 推导。
  static List<double> _sideWidths(SmartLayoutDesignTokens tokens) => [
    tokens.minLineLength,
    (tokens.minLineLength + tokens.maxLineLength) / 2,
    tokens.maxLineLength,
  ];

  static int _domainIndex(
    _DomainSlot slot,
    List<_DomainSlot> accepted,
  ) => accepted.indexOf(slot);
}

/// 枚举结果：候选 + 拒绝留档（零静默跳过）。
class PlanEnumeration {
  const PlanEnumeration({
    required this.candidates,
    required this.rejected,
    required this.domainSize,
  });

  final List<CompositionCandidate> candidates;
  final List<({LayoutSkeleton skeleton, CompositionRejectReason reason})>
  rejected;

  /// 适用域大小（配额截断前）。
  final int domainSize;
}

class _DomainSlot {
  const _DomainSlot({required this.skeleton, required this.params});

  final LayoutSkeleton skeleton;
  final CompositionParams params;
}
