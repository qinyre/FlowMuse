import 'dart:math' as math;

import '../composition/hard_feasibility_pruning.dart';
import '../composition/layout_block.dart';
import '../composition/layout_block_assembler.dart';
import '../composition/layout_composition_planner.dart';
import '../design/smart_layout_design_tokens.dart';
import '../design/text_measure_adapter.dart';
import '../geometry/layout_rect.dart';
import 'balanced_flow_placer.dart';
import 'flow_placer.dart';

/// 用户可执行建议（V3-403A）：拒绝/失败原因 → 建议的确定性映射。
/// UI 层按枚举映射文案，不接收、不拼接自由文本。
enum LayoutSuggestion {
  /// 内容总量超过页面容量：拆分页面/减少内容。
  splitIntoPages,

  /// 原子内容宽于最窄栏：加宽栏/减少不可断行内容。
  widenColumns,

  /// protected 障碍吃满整栏：缩小/移动保护区。
  reduceProtectedZones,

  /// 源内容缺陷（文本块无可排文本）：修正识别/源数据。
  fixSourceContent,
}

/// 生成期硬 preflight 拒绝稳定原因（无解证据的最小粒度）。
///
/// 每个原因都是**单调硬证明**——该候选在任何合法摆放下都不可行，
/// 不依赖软分或排名。检查优先级冻结：textual > protected > width >
/// lowerBound（首个命中即拒绝，确定性）。
enum PreflightRejectReason {
  /// 文本块无可排文本且非 figure（源数据缺陷）。
  textualBlockWithoutContent,

  /// protected 障碍吃满候选的全部栏（无处放置任何单元）。
  protectedColumnFullyCovered,

  /// 原子内容在最小字号下仍宽于候选最窄栏。
  blockWiderThanNarrowestColumnAtMinSize,

  /// 硬高度下界超出（401B 单调下界 ⇒ 必然不可行）。
  hardHeightLowerBoundExceeded,
}

/// 候选级拒绝记录（稳定原因 + 审计明细 + 可映射建议）。
class PreflightRejection {
  const PreflightRejection({
    required this.candidateId,
    required this.reason,
    required this.detail,
  });

  final String candidateId;
  final PreflightRejectReason reason;
  final String detail;

  List<LayoutSuggestion> get suggestions => suggestionsFor(reason);

  @override
  String toString() => '$candidateId: ${reason.name} ($detail)';
}

/// preflight 拒绝原因 → 建议的稳定映射。
List<LayoutSuggestion> suggestionsFor(PreflightRejectReason reason) =>
    switch (reason) {
      PreflightRejectReason.textualBlockWithoutContent => const [
        LayoutSuggestion.fixSourceContent,
      ],
      PreflightRejectReason.protectedColumnFullyCovered => const [
        LayoutSuggestion.reduceProtectedZones,
      ],
      PreflightRejectReason.blockWiderThanNarrowestColumnAtMinSize => const [
        LayoutSuggestion.widenColumns,
      ],
      PreflightRejectReason.hardHeightLowerBoundExceeded => const [
        LayoutSuggestion.splitIntoPages,
      ],
    };

/// 放置失败稳定码（402A）→ 建议的稳定映射（无解分型共用）。
List<LayoutSuggestion> suggestionsForPlacementFailure(
  FlowPlacementFailureKind kind,
) => switch (kind) {
  FlowPlacementFailureKind.keepGroupTooTall => const [
    LayoutSuggestion.splitIntoPages,
  ],
  FlowPlacementFailureKind.blockOverflowsAtMinFontSize => const [
    LayoutSuggestion.widenColumns,
  ],
  FlowPlacementFailureKind.columnsExhausted => const [
    LayoutSuggestion.splitIntoPages,
  ],
  FlowPlacementFailureKind.textualBlockWithoutContent => const [
    LayoutSuggestion.fixSourceContent,
  ],
};

/// 零修改保留原因（V3-403A）。
enum PreserveFallbackReason {
  /// 全部生成候选被硬 preflight/放置拒绝。
  allCandidatesInfeasible,

  /// 文档没有可排内容（空文档或全部 preserved/protected）。
  emptyDocument,

  /// 依赖暂不可用且重试耗尽（安全保留原结构）。
  retryExhausted,
}

/// 零修改保留结果（V3-403A）：**不是** `LayoutCandidate`——没有结构、
/// 参数或软分字段，不进入 scorer、结构配额、合格率或 Top 3。
///
/// 保留只是安全路径的解释，**不宣称通过硬约束**：原场景本身可能越界、
/// 重叠或被障碍占满，本类型没有（也不允许有）"hardConstraintsPass"
/// 之类的字段；不得用它降低 no-candidate rate。
class PreserveFallback extends GenerationOutcome {
  const PreserveFallback({
    required this.reason,
    required this.preservedSourceIds,
  });

  final PreserveFallbackReason reason;

  /// 被零修改保留的源 id（升序，确定性）。
  final List<String> preservedSourceIds;

  @override
  String toString() => 'PreserveFallback(${reason.name}, '
      '${preservedSourceIds.length} sources)';
}

/// 无解结果（V3-403A）：全部候选被硬拒绝的稳定证据集，伴随零修改
/// 保留路径。fallback 只是伴随解释——本结果本身仍计为无解，不得被
/// fallback 替代或稀释（no-candidate rate 不因此下降）。
class NoFeasibleLayout extends GenerationOutcome {
  NoFeasibleLayout({required this.rejections, required this.fallback});

  /// 由放置期失败构造（候选全部放置失败的兜底分型入口；
  /// 供 V3-405/406 编排复用，映射与 preflight 拒绝同源）。
  factory NoFeasibleLayout.fromPlacementFailures(
    List<(String candidateId, FlowPlacementFailure failure)> failures, {
    required List<String> documentSourceIds,
  }) => NoFeasibleLayout(
    rejections: [
      for (final f in failures)
        PreflightRejection(
          candidateId: f.$1,
          reason: switch (f.$2.kind) {
            FlowPlacementFailureKind.keepGroupTooTall =>
              PreflightRejectReason.hardHeightLowerBoundExceeded,
            FlowPlacementFailureKind.blockOverflowsAtMinFontSize =>
              PreflightRejectReason.blockWiderThanNarrowestColumnAtMinSize,
            FlowPlacementFailureKind.columnsExhausted =>
              PreflightRejectReason.hardHeightLowerBoundExceeded,
            FlowPlacementFailureKind.textualBlockWithoutContent =>
              PreflightRejectReason.textualBlockWithoutContent,
          },
          detail: f.$2.detail,
        ),
    ],
    fallback: PreserveFallback(
      reason: PreserveFallbackReason.allCandidatesInfeasible,
      preservedSourceIds: documentSourceIds,
    ),
  );

  final List<PreflightRejection> rejections;
  final PreserveFallback fallback;

  int get rejectedCandidateCount => rejections.length;

  /// 去重保序的建议并集（候选枚举序，确定性）。
  List<LayoutSuggestion> get suggestions => [
    ...{
      for (final r in rejections) ...r.suggestions,
    },
  ];
}

/// 可重试失败：外部依赖暂不可用（非无解、非程序缺陷）。
class RetryableGenerationFailure extends GenerationOutcome {
  const RetryableGenerationFailure({required this.dependency, this.detail = ''});

  /// 依赖标识（稳定码，如 'text-measure'）。
  final String dependency;
  final String detail;

  @override
  String toString() => 'RetryableGenerationFailure($dependency: $detail)';
}

/// 内部错误：不变量破坏/程序缺陷；不面向用户重试，必须修复。
class InternalGenerationError extends GenerationOutcome {
  const InternalGenerationError({required this.detail});

  final String detail;

  @override
  String toString() => 'InternalGenerationError($detail)';
}

/// 生成期结果四型 + 零修改保留（V3-403A 稳定分型；调用方 exhaustive
/// 分派，不得把 fallback 冒充成功）。
sealed class GenerationOutcome {
  const GenerationOutcome();
}

/// 硬筛查通过：accepted 继续进入放置/门禁；rejected 留档（可能部分
/// 拒绝——软排名前的唯一淘汰依据是硬不可行证明）。
class LayoutGenerationScreened extends GenerationOutcome {
  const LayoutGenerationScreened({required this.accepted, required this.rejected});

  final List<CompositionCandidate> accepted;
  final List<PreflightRejection> rejected;
}

/// 生成期硬 preflight（V3-403A）：**只做**单调硬可行性检查——
/// coverage 守恒、关系组完整性、粗几何（最小字号宽度、protected 障碍
/// 覆盖）与 401B 硬高度下界。
///
/// 输入封闭性：本 API 不存在 scorer/软分/profile/排名通道（编译期即
/// 无该依赖；源码门禁测试钉住）；测量经 [TextMeasureAdapter] 真实
/// 文本测量，不估算。
///
/// 分型契约：
/// - 全部候选硬拒绝 → [NoFeasibleLayout]（伴随 [PreserveFallback]，
///   不降低 no-candidate rate）；
/// - 测量依赖异常 → [RetryableGenerationFailure]；
/// - 不变量/程序缺陷（含参数违例）→ [InternalGenerationError]；
/// - 无可排内容 → [PreserveFallback]（emptyDocument，非无解）。
class LayoutPreflight {
  const LayoutPreflight();

  GenerationOutcome screen({
    required LayoutBlockAssembly assembly,
    required List<CompositionCandidate> candidates,
    required double contentHeight,
    required TextMeasureAdapter measure,
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
  }) {
    try {
      return _screen(
        assembly: assembly,
        candidates: candidates,
        contentHeight: contentHeight,
        measure: measure,
        tokens: tokens,
      );
    } on _MeasurementDependencyFailure catch (f) {
      return RetryableGenerationFailure(
        dependency: f.dependency,
        detail: '${f.cause}',
      );
    } on Exception catch (e) {
      return InternalGenerationError(detail: '$e');
    } on Error catch (e) {
      return InternalGenerationError(detail: '${e.runtimeType}: $e');
    }
  }

  GenerationOutcome _screen({
    required LayoutBlockAssembly assembly,
    required List<CompositionCandidate> candidates,
    required double contentHeight,
    required TextMeasureAdapter measure,
    required SmartLayoutDesignTokens tokens,
  }) {
    if (candidates.isEmpty) {
      throw StateError('candidate domain must not be empty');
    }
    if (contentHeight <= 0 || !contentHeight.isFinite) {
      throw ArgumentError.value(contentHeight, 'contentHeight');
    }
    if (!assembly.ledgerConserved) {
      throw StateError('assembly ledger not conserved');
    }
    _assertGroupsResolve(assembly);

    final placeable = [
      for (final b in assembly.blocks)
        if (!b.isPreservedLike) b,
    ];
    final allSourceIds = {
      ...assembly.documentConsumedSourceIds,
      ...assembly.documentPreservedSourceIds,
    }.toList()
      ..sort();
    if (placeable.isEmpty) {
      return PreserveFallback(
        reason: PreserveFallbackReason.emptyDocument,
        preservedSourceIds: allSourceIds,
      );
    }

    final obstacles = <LayoutRect>[
      for (final b in assembly.blocks)
        if (b.kind == LayoutBlockKind.protected)
          _boundsOf(b),
    ];

    final accepted = <CompositionCandidate>[];
    final rejected = <PreflightRejection>[];
    for (final candidate in candidates) {
      final rejection = _checkCandidate(
        candidate: candidate,
        placeable: placeable,
        obstacles: obstacles,
        contentHeight: contentHeight,
        measure: measure,
        tokens: tokens,
      );
      if (rejection != null) {
        rejected.add(rejection);
      } else {
        accepted.add(candidate);
      }
    }
    if (accepted.isEmpty) {
      return NoFeasibleLayout(
        rejections: rejected,
        fallback: PreserveFallback(
          reason: PreserveFallbackReason.allCandidatesInfeasible,
          preservedSourceIds: allSourceIds,
        ),
      );
    }
    return LayoutGenerationScreened(accepted: accepted, rejected: rejected);
  }

  /// 单候选硬检查（冻结优先级：textual > protected > width > LB）。
  PreflightRejection? _checkCandidate({
    required CompositionCandidate candidate,
    required List<LayoutBlock> placeable,
    required List<LayoutRect> obstacles,
    required double contentHeight,
    required TextMeasureAdapter measure,
    required SmartLayoutDesignTokens tokens,
  }) {
    // 1. 文本块无可排文本（源缺陷；不测量即可判定）。
    for (final b in placeable) {
      if (b.figure == null && b.text == null) {
        return PreflightRejection(
          candidateId: candidate.id,
          reason: PreflightRejectReason.textualBlockWithoutContent,
          detail: 'block ${b.id} has no text spec and is not a figure',
        );
      }
    }

    // 2. protected 障碍吃满全部栏（构造性无处放置；不测量）。
    final columns = _columnRectsOf(candidate, contentHeight);
    const splitter = ColumnRegionBuilder();
    var usableColumns = 0;
    for (final column in columns) {
      if (splitter.splitColumn(column, obstacles).isNotEmpty) usableColumns++;
    }
    if (usableColumns == 0) {
      return PreflightRejection(
        candidateId: candidate.id,
        reason: PreflightRejectReason.protectedColumnFullyCovered,
        detail: 'protected obstacles consume all ${columns.length} columns',
      );
    }

    // 3. 原子内容最小字号仍宽于最窄栏（单调：字号只升不降、栏宽只
    //    取最窄 ⇒ 必然 blockOverflowsAtMinFontSize）。
    final narrowest = columns
        .map((c) => c.width)
        .reduce((a, b) => a < b ? a : b);
    for (final b in placeable) {
      final spec = b.text;
      if (spec == null) continue;
      final result = _measureGuarded(
        measure,
        text: spec.text,
        fontFamily: spec.fontFamily,
        fontSize: tokens.minBodySize,
        lineHeight: spec.lineHeight,
        maxWidth: narrowest,
      );
      if (result.overflows) {
        return PreflightRejection(
          candidateId: candidate.id,
          reason: PreflightRejectReason.blockWiderThanNarrowestColumnAtMinSize,
          detail: 'block ${b.id} width ${result.width.toStringAsFixed(1)} '
              '> narrowest column ${narrowest.toStringAsFixed(1)} at '
              'min font ${tokens.minBodySize}',
        );
      }
    }

    // 4. 硬高度下界（401B pruner 同源判定；k 取结构栏数——被障碍
    //    吃掉的栏使下界偏松，只会漏拒不会误拒，落到放置期稳定失败）。
    final textHeights = <double>[];
    final figureHeights = <double>[];
    for (final b in placeable) {
      if (b.figure != null) {
        final ratio = b.figure!.displayAspectRatio > 0
            ? b.figure!.displayAspectRatio
            : 1.0;
        figureHeights.add(
          columns.map((c) => c.width / ratio).reduce(math.min),
        );
        continue;
      }
      final spec = b.text!;
      var minHeight = double.infinity;
      for (final column in columns) {
        final result = _measureGuarded(
          measure,
          text: spec.text,
          fontFamily: spec.fontFamily,
          fontSize: tokens.minBodySize,
          lineHeight: spec.lineHeight,
          maxWidth: column.width,
        );
        if (result.height < minHeight) minHeight = result.height;
      }
      textHeights.add(minHeight);
    }
    final prune = const HardFeasibilityPruner().prune(
      candidate: candidate,
      textHeights: textHeights,
      figureHeights: figureHeights,
      contentHeight: contentHeight,
      tokens: tokens,
    );
    if (prune.verdict == PruneVerdict.hardHeightLowerBoundExceeded) {
      return PreflightRejection(
        candidateId: candidate.id,
        reason: PreflightRejectReason.hardHeightLowerBoundExceeded,
        detail: 'lower bound ${prune.lowerBound.toStringAsFixed(1)} > '
            'capacity ${prune.contentLimit.toStringAsFixed(1)}',
      );
    }
    return null;
  }

  /// 候选栏几何（左→右；与 401A 域推导同源：single/conservative 全宽、
  /// twoColumn 等分、mainSide 主+侧按 sideOnRight 排列）。
  List<LayoutRect> _columnRectsOf(
    CompositionCandidate candidate,
    double contentHeight,
  ) {
    final p = candidate.params;
    List<LayoutRect> build(List<double> widths) {
      final rects = <LayoutRect>[];
      var left = 0.0;
      for (var i = 0; i < widths.length; i++) {
        rects.add(
          LayoutRect(left: left, top: 0, width: widths[i], height: contentHeight),
        );
        left += widths[i] + p.columnGutter;
      }
      return rects;
    }

    return switch (candidate.skeleton) {
      LayoutSkeleton.single => build([p.mainColumnWidth]),
      LayoutSkeleton.twoColumn => build([p.mainColumnWidth, p.mainColumnWidth]),
      LayoutSkeleton.mainSide => p.sideOnRight
          ? build([p.mainColumnWidth, p.sideColumnWidth!])
          : build([p.sideColumnWidth!, p.mainColumnWidth]),
      LayoutSkeleton.conservativeLayout => build([p.mainColumnWidth]),
    };
  }

  void _assertGroupsResolve(LayoutBlockAssembly assembly) {
    final ids = {for (final b in assembly.blocks) b.id};
    for (final group in assembly.atomicGroups) {
      for (final id in group) {
        if (!ids.contains(id)) {
          throw StateError('atomic group references missing block: $id');
        }
      }
    }
  }

  LayoutRect _boundsOf(LayoutBlock block) {
    final json = block.extras['bounds'];
    if (json is Map<String, Object?>) {
      return LayoutRect(
        left: (json['left'] as num).toDouble(),
        top: (json['top'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );
    }
    throw StateError('protected block ${block.id} missing bounds');
  }

  /// 测量守卫：适配器契约只允许 ArgumentError（参数违例，Error）；
  /// 其余异常视为测量依赖不可用 → 可重试分型。
  TextMeasureResult _measureGuarded(
    TextMeasureAdapter measure, {
    required String text,
    required String fontFamily,
    required double fontSize,
    required double lineHeight,
    required double maxWidth,
  }) {
    try {
      return measure.measure(
        text: text,
        fontFamily: fontFamily,
        fontSize: fontSize,
        lineHeight: lineHeight,
        maxWidth: maxWidth,
      );
    } on Exception catch (e) {
      throw _MeasurementDependencyFailure('text-measure', e);
    }
  }
}

class _MeasurementDependencyFailure {
  const _MeasurementDependencyFailure(this.dependency, this.cause);

  final String dependency;
  final Object cause;
}
