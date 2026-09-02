import 'dart:ui' as ui;

import '../composition/layout_block.dart';
import '../composition/layout_block_assembler.dart';
import '../composition/layout_composition_planner.dart';
import '../design/smart_layout_design_tokens.dart';
import '../design/text_measure_adapter.dart';
import '../geometry/layout_rect.dart';

/// 放置失败稳定码（V3-402A）：不可满足时返回原因——
/// 不静默拆关系、不缩小越线、不裁字、不省略。
enum FlowPlacementFailureKind {
  /// 原子组（keep/list/section/formula/caption）整体高度超过栏高，
  /// 任何字号档都放不下。
  keepGroupTooTall,

  /// 单块在最小字号档仍溢出（原子字素簇宽于栏宽等）。
  blockOverflowsAtMinFontSize,

  /// 所有栏已用尽（阅读序要求继续放置但无处可放）。
  columnsExhausted,

  /// 文本块没有任何可测量文本且无文本来源（数据缺陷显式失败）。
  textualBlockWithoutContent,
}

/// 放置失败（带稳定码与首个失败块，确定性）。
class FlowPlacementFailure {
  const FlowPlacementFailure({
    required this.kind,
    required this.blockId,
    this.detail = '',
  });

  final FlowPlacementFailureKind kind;
  final String blockId;
  final String detail;

  @override
  String toString() => '${kind.name}($blockId${detail.isEmpty ? '' : ': $detail'})';
}

/// 放置游标（V3-402A）：栏序 + 栏内 y 位置；顺序填充语义
///（第一栏满再第二栏；栏平衡归 V3-402B）。
class PlacementCursor {
  PlacementCursor({required this.columnRects, required this.contentHeight})
    : assert(columnRects.isNotEmpty),
      assert(contentHeight > 0);

  final List<LayoutRect> columnRects;
  final double contentHeight;

  int columnIndex = 0;
  double y = 0;

  LayoutRect get currentColumn => columnRects[columnIndex];

  /// 当前栏剩余高度。
  double get remainingInColumn => currentColumn.height - y;

  /// 推进 [height]（不检查容量；容量检查由 placer 决策换栏/失败）。
  void advance(double height) => y += height;

  /// 换栏；已到末栏返回 false。
  bool nextColumn() {
    if (columnIndex + 1 >= columnRects.length) return false;
    columnIndex++;
    y = 0;
    return true;
  }

  /// 在当前栏底放置的高度（绝对坐标）。
  double get absoluteY => currentColumn.top + y;
}

/// 单块放置结果（V3-402A）。
class PlacedBlock {
  const PlacedBlock({
    required this.blockId,
    required this.rect,
    required this.columnIndex,
    required this.lineCount,
    required this.appliedFontSize,
    required this.shrunk,
  });

  final String blockId;

  /// 放置盒（绝对页面坐标；宽 ≤ 栏宽——溢出不会走到这里）。
  final LayoutRect rect;
  final int columnIndex;
  final int lineCount;

  /// 实际生效字号（缩档后的最终值）。
  final double appliedFontSize;
  final bool shrunk;
}

/// 放置成功结果。
class FlowPlacementSuccess {
  const FlowPlacementSuccess({required this.placed, required this.usedHeights});

  final List<PlacedBlock> placed;

  /// 各栏已用高度（栏平衡/密度控制的输入，V3-402B）。
  final List<double> usedHeights;
}

/// 流式排版器（V3-402A）：按语义阅读序放置，真实测量换行/高度，
/// keep/list/section/formula 原子组不拆；不可满足返回稳定原因。
///
/// 字号档（全部 token 推导）：title 从 titleFloorSize 起、正文从
/// bodySize 起，按 snapStep 步进下降，下限 minBodySize（不越线）。
/// v1 token 下即 28→20→12 三档。
///
/// preserved/protected 块不参与放置（保留原位；patch 层处理）。
class FlowPlacer {
  const FlowPlacer();

  /// [columnRects]：候选结构的各栏几何（V3-401A 参数推导，
  /// 调用方按 candidate.params 计算）；[contentHeight] 栏高上限。
  Object place({
    required LayoutBlockAssembly assembly,
    required CompositionCandidate candidate,
    required List<LayoutRect> columnRects,
    required double contentHeight,
    required TextMeasureAdapter measure,
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
  }) {
    if (columnRects.isEmpty) {
      throw ArgumentError('columnRects must not be empty');
    }
    final cursor = PlacementCursor(
      columnRects: columnRects,
      contentHeight: contentHeight,
    );
    final placed = <PlacedBlock>[];

    // 有序放置单元：原子组保持成员顺序与连续性；孤立块单块成组。
    final units = placementUnits(assembly);

    for (var u = 0; u < units.length; u++) {
      final unit = units[u];
      final groupGap = u == 0 ? 0.0 : tokens.paragraphSpacing;

      // 1. 逐块真实测量（含字号缩档；失败即返回稳定原因）。
      final measured = <(LayoutBlock, TextMeasureResult, double)>[];
      var unitHeight = 0.0;
      for (var i = 0; i < unit.length; i++) {
        final block = unit[i];
        if (block.kind == LayoutBlockKind.figure) {
          final figure = block.figure;
          if (figure == null) {
            return FlowPlacementFailure(
              kind: FlowPlacementFailureKind.textualBlockWithoutContent,
              blockId: block.id,
              detail: 'figure block missing spec',
            );
          }
          final columnWidth = cursor.currentColumn.width;
          final ratio = figure.displayAspectRatio > 0
              ? figure.displayAspectRatio
              : 1.0;
          final height = columnWidth / ratio;
          measured.add((
            block,
            TextMeasureResult(
              width: columnWidth,
              height: height,
              lineCount: 1,
              maxWidth: columnWidth,
              overflows: false,
            ),
            0,
          ));
          unitHeight += height;
        } else if (block.isPreservedLike) {
          continue;
        } else {
          final outcome = _measureWithShrink(
            block,
            cursor.currentColumn.width,
            contentHeight,
            measure,
            tokens,
          );
          if (outcome is FlowPlacementFailure) return outcome;
          final result = outcome as (TextMeasureResult, double);
          measured.add((block, result.$1, result.$2));
          unitHeight += result.$1.height;
        }
        // 组内相邻块间距（compact 档；组间用 paragraphSpacing）。
        unitHeight += i == 0 ? 0.0 : tokens.compactGapFloor;
      }
      if (unitHeight > contentHeight + _eps) {
        return FlowPlacementFailure(
          kind: FlowPlacementFailureKind.keepGroupTooTall,
          blockId: unit.first.id,
          detail:
              'unit height ${unitHeight.toStringAsFixed(1)} > column '
              '${contentHeight.toStringAsFixed(1)} (members: '
              '${[for (final b in unit) b.id].join(',')})',
        );
      }

      // 2. 容量：当前栏放不下整组 → 换栏；末栏仍不足 → 失败。
      var needed = unitHeight + groupGap;
      if (cursor.remainingInColumn + _eps < needed) {
        if (!cursor.nextColumn()) {
          return FlowPlacementFailure(
            kind: FlowPlacementFailureKind.columnsExhausted,
            blockId: unit.first.id,
            detail:
                'need ${needed.toStringAsFixed(1)} at column '
                '${cursor.columnIndex}, remaining '
                '${cursor.remainingInColumn.toStringAsFixed(1)}',
          );
        }
        needed = unitHeight;
      } else {
        cursor.advance(groupGap);
      }

      // 3. 放置（连续、同栏、不拆）。
      for (var i = 0; i < measured.length; i++) {
        final (block, result, fontSize) = measured[i];
        final column = cursor.currentColumn;
        placed.add(PlacedBlock(
          blockId: block.id,
          rect: LayoutRect(
            left: column.left,
            top: column.top + cursor.y,
            width: result.width.clamp(0, column.width),
            height: result.height,
          ),
          columnIndex: cursor.columnIndex,
          lineCount: result.lineCount,
          appliedFontSize: fontSize,
          shrunk: block.text != null &&
              fontSize != _baseFontSizeOf(block, tokens),
        ));
        cursor.advance(result.height);
        if (i + 1 < measured.length) {
          cursor.advance(tokens.compactGapFloor);
        }
      }
    }

    // 各栏已用高度（最后游标位置）。
    final used = List<double>.filled(columnRects.length, 0);
    for (var c = 0; c < cursor.columnIndex; c++) {
      used[c] = columnRects[c].height;
    }
    used[cursor.columnIndex] = cursor.y;
    return FlowPlacementSuccess(
      placed: List.unmodifiable(placed),
      usedHeights: List.unmodifiable(used),
    );
  }

  /// 放置单元：原子组（assembly.atomicGroups）按首块阅读序穿插到
  /// 块流中；孤立块单块成组。公开供 V3-402B 栏平衡切分使用。
  static List<List<LayoutBlock>> placementUnits(LayoutBlockAssembly assembly) {
    final groupOf = <String, int>{};
    for (var g = 0; g < assembly.atomicGroups.length; g++) {
      for (final id in assembly.atomicGroups[g]) {
        groupOf[id] = g;
      }
    }
    final consumedGroups = <int>{};
    final units = <List<LayoutBlock>>[];
    for (final block in assembly.blocks) {
      if (block.isPreservedLike) continue;
      final g = groupOf[block.id];
      if (g == null) {
        units.add([block]);
      } else if (!consumedGroups.contains(g)) {
        consumedGroups.add(g);
        final members = assembly.atomicGroups[g]
            .map((id) => assembly.blockById(id))
            .whereType<LayoutBlock>()
            .where((b) => !b.isPreservedLike)
            .toList();
        // 组内按阅读序（assembly.blocks 顺序即阅读序）。
        final orderIndex = {
          for (var i = 0; i < assembly.blocks.length; i++)
            assembly.blocks[i].id: i,
        };
        members.sort((a, b) => orderIndex[a.id]!.compareTo(orderIndex[b.id]!));
        units.add(members);
      }
    }
    return units;
  }

  /// 真实测量 + 字号缩档；失败返回稳定原因（不裁字、不越线）。
  Object _measureWithShrink(
    LayoutBlock block,
    double columnWidth,
    double contentHeight,
    TextMeasureAdapter measure,
    SmartLayoutDesignTokens tokens,
  ) {
    final spec = block.text;
    if (spec == null) {
      return FlowPlacementFailure(
        kind: FlowPlacementFailureKind.textualBlockWithoutContent,
        blockId: block.id,
        detail: 'textual block has no text spec',
      );
    }
    double size = _baseFontSizeOf(block, tokens);
    final floor = tokens.minBodySize;
    while (true) {
      final result = measure.measure(
        text: spec.text,
        fontFamily: spec.fontFamily,
        fontSize: size,
        lineHeight: spec.lineHeight,
        maxWidth: columnWidth,
        direction: spec.direction == TextDirectionSpec.rtl
            ? ui.TextDirection.rtl
            : ui.TextDirection.ltr,
      );
      // 原子字素簇宽于栏宽：overflows 且无更小档 → 显式失败。
      if (!result.overflows && result.height <= contentHeight + _eps) {
        return (result, size);
      }
      if (size - tokens.snapStep + _eps < floor) {
        return FlowPlacementFailure(
          kind: FlowPlacementFailureKind.blockOverflowsAtMinFontSize,
          blockId: block.id,
          detail:
              'size=$size overflow=${result.overflows} '
              'height=${result.height.toStringAsFixed(1)}',
        );
      }
      size -= tokens.snapStep;
    }
  }

  double _baseFontSizeOf(LayoutBlock block, SmartLayoutDesignTokens tokens) =>
      block.kind == LayoutBlockKind.title
          ? tokens.titleFloorSize
          : tokens.bodySize;

  static const double _eps = 1e-9;
}
