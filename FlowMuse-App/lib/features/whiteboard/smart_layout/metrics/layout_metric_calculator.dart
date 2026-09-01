import 'dart:math' as math;

import '../composition/layout_block.dart';
import '../design/smart_layout_design_tokens.dart';
import '../geometry/layout_rect.dart';
import '../placement/flow_placer.dart';
import '../snapshot/deterministic_hash.dart';
import 'layout_metric_contract.dart';

/// 硬未通过：不存在软分（硬软隔离——硬失败不能被软分抵消）。
class MetricsHardRejected {
  const MetricsHardRejected({required this.hardViolationCount});

  final int hardViolationCount;
}

/// 软指标计算器（V3-404A）：纯函数，输入 [LayoutMetricInput]
/// （几何事实 + 冻结 token），输出七类有界指标。确定性：同输入
/// 双跑指纹一致。所有阈值要么来自冻结 tokens，要么为本文件冻结
/// 常数（v1），不接受调用方调节。
class LayoutMetricCalculator {
  const LayoutMetricCalculator();

  Object calculate(
    LayoutMetricInput input, {
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
  }) {
    if (!input.hardValidated) {
      return MetricsHardRejected(
        hardViolationCount: input.hardViolationCount,
      );
    }
    final values = <LayoutMetricId, double>{
      LayoutMetricId.hierarchy: _hierarchy(input, tokens),
      LayoutMetricId.readingOrder: _readingOrder(input),
      LayoutMetricId.figureTextAffinity: _figureTextAffinity(input, tokens),
      LayoutMetricId.alignmentRhythm: _alignmentRhythm(input, tokens),
      LayoutMetricId.densityWhitespace: _density(input),
      LayoutMetricId.visualBalance: _visualBalance(input),
      LayoutMetricId.modificationCost: _modificationCost(input),
    };
    return LayoutMetricVector(
      values: values,
      factsFingerprint: fingerprint64('metrics|${_factsCanonical(input)}'),
    );
  }

  // ---- 1. 层级：title/heading 生效字号必须高于正文生效字号中位数。

  double _hierarchy(LayoutMetricInput input, SmartLayoutDesignTokens tokens) {
    final bodySizes = <double>[];
    final headingSizes = <double>[];
    for (final p in input.placed) {
      final block = input.blockOf(p.blockId);
      if (block == null || !block.isTextual) continue;
      if (block.kind == LayoutBlockKind.title) {
        headingSizes.add(p.appliedFontSize);
      } else {
        bodySizes.add(p.appliedFontSize);
      }
    }
    if (headingSizes.isEmpty || bodySizes.isEmpty) return 1.0;
    bodySizes.sort();
    final median =
        bodySizes[bodySizes.length ~/ 2];
    var pass = 0;
    for (final size in headingSizes) {
      if (size > median + _eps) pass++;
    }
    return _clamp(pass / headingSizes.length);
  }

  // ---- 2. 顺序：相邻放置对的栏序单调、同栏内纵向有序。

  double _readingOrder(LayoutMetricInput input) {
    if (input.placed.length < 2) return 1.0;
    var ok = 0;
    for (var i = 0; i + 1 < input.placed.length; i++) {
      final a = input.placed[i];
      final b = input.placed[i + 1];
      final columnsMonotone = b.columnIndex >= a.columnIndex;
      final verticalOk = a.columnIndex == b.columnIndex
          ? b.rect.top >= a.rect.top - _eps
          : true;
      if (columnsMonotone && verticalOk) ok++;
    }
    return _clamp(ok / (input.placed.length - 1));
  }

  // ---- 3. 图文亲和：captionOf 关系对同栏且 caption 紧贴 figure 下方。

  double _figureTextAffinity(
    LayoutMetricInput input,
    SmartLayoutDesignTokens tokens,
  ) {
    final byId = {
      for (final p in input.placed) p.blockId: p,
    };
    final pairs = <BlockRelationship>[
      for (final r in input.assembly.relationships)
        if (r.kind == _captionRelation && byId.containsKey(r.fromBlockId) && byId.containsKey(r.toBlockId))
          r,
    ];
    if (pairs.isEmpty) return 1.0;
    final maxGap = tokens.paragraphSpacing + tokens.compactGapFloor;
    var pass = 0;
    for (final r in pairs) {
      final caption = byId[r.fromBlockId]!;
      final figure = byId[r.toBlockId]!;
      final sameColumn = caption.columnIndex == figure.columnIndex;
      final stacked = caption.rect.top >= figure.rect.bottom - _eps;
      final gap = caption.rect.top - figure.rect.bottom;
      if (sameColumn && stacked && gap <= maxGap + _eps) pass++;
    }
    return _clamp(pass / pairs.length);
  }

  // ---- 4. 对齐节奏：左缘对齐（≤snapStep 记满分的线性衰减）与
  //         栏内纵向间距规整度（变异系数）各占一半。

  double _alignmentRhythm(
    LayoutMetricInput input,
    SmartLayoutDesignTokens tokens,
  ) {
    if (input.placed.isEmpty) return 1.0;
    var alignScore = 0.0;
    for (final p in input.placed) {
      final column = _columnOf(input, p.columnIndex);
      final offset = column == null
          ? 0.0
          : (p.rect.left - column.left).abs();
      alignScore += 1 - (offset / tokens.snapStep).clamp(0.0, 1.0);
    }
    alignScore /= input.placed.length;
    final rhythmScore = _gapRegularity(input, tokens);
    return _clamp(0.5 * alignScore + 0.5 * rhythmScore);
  }

  double _gapRegularity(
    LayoutMetricInput input,
    SmartLayoutDesignTokens tokens,
  ) {
    final gaps = <double>[];
    for (var c = 0; c < input.columnRects.length; c++) {
      final inColumn = <PlacedBlock>[
        for (final p in input.placed)
          if (p.columnIndex == c) p,
      ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
      for (var i = 0; i + 1 < inColumn.length; i++) {
        final gap = inColumn[i + 1].rect.top - inColumn[i].rect.bottom;
        if (gap >= 0) gaps.add(gap);
      }
    }
    if (gaps.length < 2) return 1.0;
    final mean = gaps.reduce((a, b) => a + b) / gaps.length;
    if (mean <= _eps) return 1.0;
    final variance =
        gaps.map((g) => (g - mean) * (g - mean)).reduce((a, b) => a + b) /
            gaps.length;
    final cv = math.sqrt(variance) / mean;
    return _clamp(1 - cv.clamp(0.0, 1.0));
  }

  // ---- 5. 密度留白：各栏填充率均值落在健康带 [0.30, 0.85]
  //         （带内满分，带外线性衰减；空栏计入 0 填充）。

  double _density(LayoutMetricInput input) {
    if (input.columnRects.isEmpty || input.contentHeight <= 0) return 1.0;
    var fillSum = 0.0;
    for (var c = 0; c < input.columnRects.length; c++) {
      var deepest = 0.0;
      for (final p in input.placed) {
        if (p.columnIndex != c) continue;
        final depth = p.rect.bottom - input.columnRects[c].top;
        if (depth > deepest) deepest = depth;
      }
      fillSum += (deepest / input.contentHeight).clamp(0.0, 1.0);
    }
    final density = fillSum / input.columnRects.length;
    const lower = 0.30;
    const upper = 0.85;
    if (density < lower) return _clamp(density / lower);
    if (density > upper) return _clamp((1 - density) / (1 - upper));
    return 1.0;
  }

  // ---- 6. 视觉平衡：多栏有内容时取两极栏填充差的归一；单内容栏
  //         取面积加权质心相对栏心的偏移。

  double _visualBalance(LayoutMetricInput input) {
    final usedColumns = <int, double>{};
    for (final p in input.placed) {
      final column = _columnOf(input, p.columnIndex);
      if (column == null) continue;
      final depth = p.rect.bottom - column.top;
      final current = usedColumns[p.columnIndex] ?? 0;
      if (depth > current) usedColumns[p.columnIndex] = depth;
    }
    final active = usedColumns.values.toList()..sort();
    if (active.length >= 2) {
      final spread = active.last - active.first;
      return _clamp(1 - (spread / input.contentHeight).clamp(0.0, 1.0));
    }
    if (input.placed.isEmpty) return 1.0;
    // 质心：面积加权 block 中心。
    var weightSum = 0.0;
    var weightedY = 0.0;
    for (final p in input.placed) {
      final w = p.rect.width * p.rect.height;
      weightSum += w;
      weightedY += w * (p.rect.top + p.rect.height / 2);
    }
    if (weightSum <= _eps) return 1.0;
    final comY = weightedY / weightSum;
    final half = input.contentHeight / 2;
    final offset = (comY - half).abs();
    return _clamp(1 - (offset / (half > 0 ? half : 1)).clamp(0.0, 1.0));
  }

  // ---- 7. 改动成本：块移动距离（中心欧氏距/页面对角线）均值，
  //         1 = 全部未动。无原位投影的块不参与（诚实缺失）。

  double _modificationCost(LayoutMetricInput input) {
    var diag = 0.0;
    for (final column in input.columnRects) {
      diag = math.max(diag, column.right);
    }
    diag = math.sqrt(diag * diag + input.contentHeight * input.contentHeight);
    if (diag <= _eps) return 1.0;
    var costSum = 0.0;
    var count = 0;
    for (final p in input.placed) {
      final original = input.originalBounds[p.blockId];
      if (original == null) continue;
      final dx = (p.rect.left + p.rect.width / 2) -
          (original.left + original.width / 2);
      final dy = (p.rect.top + p.rect.height / 2) -
          (original.top + original.height / 2);
      costSum += math.sqrt(dx * dx + dy * dy) / diag;
      count++;
    }
    if (count == 0) return 1.0;
    return _clamp(1 - (costSum / count).clamp(0.0, 1.0));
  }

  // ---- 工具。

  LayoutRect? _columnOf(LayoutMetricInput input, int index) =>
      index >= 0 && index < input.columnRects.length
          ? input.columnRects[index]
          : null;

  double _clamp(double v) => v.clamp(0.0, 1.0);

  String _factsCanonical(LayoutMetricInput input) {
    String n(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    final placedPart = [
      for (final p in input.placed)
        '${p.blockId}#${p.columnIndex}#${p.appliedFontSize}'
        '@${n(p.rect.left)},${n(p.rect.top)},${n(p.rect.width)},${n(p.rect.height)}',
    ].join('|');
    final columnsPart = [
      for (final c in input.columnRects)
        '${n(c.left)},${n(c.top)},${n(c.width)},${n(c.height)}',
    ].join('|');
    final originalIds = input.originalBounds.keys.toList()..sort();
    final originalPart = [
      for (final id in originalIds)
        '$id@${n(input.originalBounds[id]!.left)},'
        '${n(input.originalBounds[id]!.top)},'
        '${n(input.originalBounds[id]!.width)},'
        '${n(input.originalBounds[id]!.height)}',
    ].join('|');
    return 'v=${input.hardValidated ? 1 : 0};$placedPart;$columnsPart;$originalPart;h=${n(input.contentHeight)}';
  }

  static const BlockRelationKind _captionRelation = BlockRelationKind.captionOf;

  static const double _eps = 1e-9;
}
