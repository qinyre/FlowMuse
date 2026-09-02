import 'dart:math' as math;

import 'region_segment.dart';
import 'segmentation_policy.dart';
import 'spatial_grid_index.dart';

/// 确定性区域语义分类器（V3-103B）：line / formula / table / emphasis /
/// unknown，全部基于几何与排布规则，不训练模型。
///
/// 置信度是规则边际的确定性打分（非概率模型输出）；低于冻结阈值
/// [SegmentationPolicy.preserveConfidenceThreshold] 的区域进入 preserved
/// 语义（不自动重排），竖排区域无条件 preserved（保留模式）。
/// 分类不改变 stroke membership（membership 只由 103A 的几何管线决定）。
class RegionClassifier {
  const RegionClassifier({this.policy = SegmentationPolicy.development});

  final SegmentationPolicy policy;

  /// 完整语义：类型 + 置信 + preserved 原因。
  ///
  /// [pageScale] 为全页中位笔画高，作为装饰线/文本笔画的统一尺度锚
  ///（孤笔画区域的局部尺度会退化为自身高度，不能当锚用）。
  RegionClassification semanticOf(
    List<StrokeBox> boxes, {
    required SegmentLineDirection direction,
    required double localScale,
    required double pageScale,
  }) {
    final (type, confidence) = _classify(boxes, direction, localScale, pageScale);
    final preserved = direction == SegmentLineDirection.vertical
        ? RegionPreservedReason.verticalWriting
        : confidence < policy.preserveConfidenceThreshold
        ? RegionPreservedReason.lowConfidence
        : null;
    return RegionClassification(
      type: type,
      confidence: confidence,
      preservedReason: preserved,
    );
  }

  (RegionClass, double) _classify(
    List<StrokeBox> boxes,
    SegmentLineDirection direction,
    double localScale,
    double pageScale,
  ) {
    if (boxes.isEmpty || pageScale <= 0) return (RegionClass.unknown, 0);
    final n = boxes.length;

    // 尺度锚=pageScale：文本笔画高度落在 [0.4, 2.5]×；装饰笔画
    // 长而薄（宽 >6× 且高 <0.5×）或整体巨大（maxDim >6×）。
    final textlike = boxes
        .where(
          (b) =>
              b.height >= pageScale * 0.4 && b.height <= pageScale * 2.5,
        )
        .length;
    final decorative = boxes
        .where(
          (b) =>
              (b.width > pageScale * 6 && b.height < pageScale * 0.5) ||
              b.size > pageScale * 6,
        )
        .length;
    // 行/列结构：中心聚类。
    final rows = _clusters(
      [for (final b in boxes) b.centerY],
      policy.rowClusteringTolerance * localScale,
    );
    final cols = _clusters(
      [for (final b in boxes) b.centerX],
      policy.rowClusteringTolerance * localScale,
    );
    // x 区间显著重叠且 y 错位的堆叠对（上下标/公式形态）。
    var stackedPairs = 0;
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        final a = boxes[i];
        final b = boxes[j];
        final overlap = a.right > b.left && b.right > a.left;
        final overlapWidth =
            (a.right < b.right ? a.right : b.right) -
            (a.left > b.left ? a.left : b.left);
        final minWidth = a.width < b.width ? a.width : b.width;
        final ySeparated = (a.centerY - b.centerY).abs() > localScale * 0.5;
        if (overlap && overlapWidth > minWidth * 0.5 && ySeparated) {
          stackedPairs++;
        }
      }
    }

    // 1. emphasis：装饰笔画为主、几乎没有文本笔画。
    if (decorative >= 1 && textlike < 3) {
      return (RegionClass.emphasis, 0.7);
    }
    // 2. table：≥2 行 × ≥2 列的网格覆盖（至少 4 笔）。
    if (rows >= 2 &&
        cols >= 2 &&
        n >= 4 &&
        n >= rows * cols * policy.tableGridCoverage) {
      return (
        RegionClass.table,
        (n / (rows * cols)).clamp(0.0, 1.0) * 0.6 + 0.2,
      );
    }
    // 3. formula：显著的 x 重叠堆叠形态（至少 4 笔）。
    if (n >= 4 &&
        rows >= 2 &&
        stackedPairs >= math.max(2, n * policy.formulaStackRatio)) {
      return (RegionClass.formula, 0.6);
    }
    // 4. line：单行（≥2 笔）且高度贴合局部尺度。
    final heightRatio = _regionHeight(boxes) / localScale;
    if (n >= 2 && rows == 1 && heightRatio <= 2) {
      return (RegionClass.line, 0.9);
    }
    return (RegionClass.unknown, 0.35);
  }

  static int _clusters(List<double> values, double tolerance) {
    final sorted = [...values]..sort();
    var clusters = sorted.isEmpty ? 0 : 1;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] - sorted[i - 1] > tolerance) clusters++;
    }
    return clusters;
  }

  static double _regionHeight(List<StrokeBox> boxes) {
    var top = double.infinity;
    var bottom = double.negativeInfinity;
    for (final box in boxes) {
      if (box.top < top) top = box.top;
      if (box.bottom > bottom) bottom = box.bottom;
    }
    return bottom - top;
  }
}

/// 区域语义结果。
class RegionClassification {
  const RegionClassification({
    required this.type,
    required this.confidence,
    this.preservedReason,
  });

  final RegionClass type;
  final double confidence;
  final RegionPreservedReason? preservedReason;

  bool get preserved => preservedReason != null;
}
