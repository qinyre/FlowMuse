import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import 'region_classifier.dart';
import 'region_segment.dart';
import 'segmentation_policy.dart';
import 'spatial_grid_index.dart';

/// 确定性笔迹区域分割器（首版纯 Dart，不训练模型，计划 §4.3）。
///
/// 管线：局部尺度 → deskew 估计 → 旋转帧网格邻接 → 连通分量 →
/// 列聚类 → 区域 reading geometry。全部阈值按局部尺度归一化
///（不是跨页面固定 pt）；3000 笔画页经 [SpatialGridIndex] 避免
/// O(N²) 全配对。
class InkRegionSegmenter {
  final SegmentationPolicy policy;

  final RegionClassifier _classifier;

  InkRegionSegmenter({this.policy = SegmentationPolicy.development})
    : _classifier = RegionClassifier(policy: policy);

  int _lastEvaluationCount = 0;

  /// 上一次 [segment] 的网格候选盒评估总次数（两个索引合计），
  /// 供性能断言：形态必须线性-ish，禁止退化为 O(N²) 全配对。
  int get lastEvaluationCount => _lastEvaluationCount;

  List<RegionSegment> segment(List<FreedrawElement> strokes) {
    if (strokes.isEmpty) return const [];
    final sorted = [...strokes]
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    final boxes = <StrokeBox>[
      for (final stroke in sorted)
        StrokeBox(
          id: stroke.id.value,
          left: stroke.x,
          top: stroke.y,
          width: stroke.width,
          height: stroke.height,
        ),
    ];
    final idSet = <String>{};
    for (final box in boxes) {
      if (!idSet.add(box.id)) {
        throw ArgumentError.value(box.id, 'strokes', '笔画 id 重复');
      }
    }

    final medianHeight = _median([for (final box in boxes) box.height]);
    final cellSize = policy.gridCellFactor * medianHeight;
    final scaleIndex = SpatialGridIndex(cellSize: cellSize, boxes: boxes);
    final neighborRadius = policy.neighborRadiusFactor * medianHeight;

    // 1. 局部尺度：邻域（含自身）中位笔画高。
    final localScaleById = <String, double>{};
    for (final box in boxes) {
      final neighbors = scaleIndex.neighborsWithin(box, neighborRadius);
      localScaleById[box.id] = _median([
        box.height,
        for (final neighbor in neighbors) neighbor.height,
      ]);
    }

    // 2. deskew：右邻连线的主方向直方图。
    final skew = _estimateSkew(boxes, scaleIndex, neighborRadius);

    // 3. 旋转帧（绕全页中心）下的保守 AABB。
    final pivotX = _mean([for (final b in boxes) b.centerX]);
    final pivotY = _mean([for (final b in boxes) b.centerY]);
    final deskewedById = <String, StrokeBox>{};
    for (final box in boxes) {
      deskewedById[box.id] = _rotateBox(box, -skew, pivotX, pivotY);
    }
    final adjacencyIndex = SpatialGridIndex(
      cellSize: cellSize,
      boxes: [for (final box in boxes) deskewedById[box.id]!],
    );

    // 4. 邻接并查集：阈值 = gapFactor × 双方较大局部尺度。
    final byId = {for (final box in boxes) box.id: box};
    final unionFind = UnionFind(boxes.length);
    final indexOfId = <String, int>{
      for (var i = 0; i < boxes.length; i++) boxes[i].id: i,
    };
    for (final box in boxes) {
      final radius = policy.gapFactor * localScaleById[box.id]!;
      final candidates = adjacencyIndex.neighborsWithin(
        deskewedById[box.id]!,
        radius,
      );
      for (final candidate in candidates) {
        final other = byId[candidate.id]!;
        final pairThreshold =
            policy.gapFactor *
            math.max(localScaleById[box.id]!, localScaleById[other.id]!);
        final gap = deskewedById[box.id]!.gapTo(candidate);
        if (gap <= pairThreshold) {
          unionFind.union(indexOfId[box.id]!, indexOfId[other.id]!);
        }
      }
    }

    // 5. 连通分量 → 列聚类 → 区域。
    final components = <int, List<StrokeBox>>{};
    for (var i = 0; i < boxes.length; i++) {
      components.putIfAbsent(unionFind.find(i), () => []).add(boxes[i]);
    }
    final groups = components.values.toList()
      ..sort((a, b) {
        final wa = deskewedById[a.first.id]!;
        final wb = deskewedById[b.first.id]!;
        return wa.left.compareTo(wb.left);
      });

    final columnIntervalOf = <String, (double, double)>{};
    for (final group in groups) {
      var minLeft = double.infinity;
      var maxRight = double.negativeInfinity;
      for (final box in group) {
        final d = deskewedById[box.id]!;
        if (d.left < minLeft) minLeft = d.left;
        if (d.right > maxRight) maxRight = d.right;
      }
      columnIntervalOf[group.first.id] = (minLeft, maxRight);
    }

    final columnGap = policy.columnGapFactor * medianHeight;
    var columnIndex = 0;
    double? prevRight;
    final columnOfGroup = <List<StrokeBox>, int>{};
    final orderedGroups = [...groups]
      ..sort(
        (a, b) => columnIntervalOf[a.first.id]!.$1.compareTo(
          columnIntervalOf[b.first.id]!.$1,
        ),
      );
    for (final group in orderedGroups) {
      final (left, right) = columnIntervalOf[group.first.id]!;
      final previousRight = prevRight;
      if (previousRight != null && left - previousRight > columnGap) {
        columnIndex++;
      }
      columnOfGroup[group] = columnIndex;
      if (prevRight == null || right > prevRight) prevRight = right;
    }

    // 6. 区域输出：原始坐标系框 + reading geometry，按 (top, left) 定 id。
    final pending = <List<StrokeBox>>[...orderedGroups];
    pending.sort((a, b) {
      var c = _groupTop(a).compareTo(_groupTop(b));
      if (c == 0) c = _groupLeft(a).compareTo(_groupLeft(b));
      return c;
    });

    final segments = <RegionSegment>[];
    _lastEvaluationCount =
        scaleIndex.evaluationCount + adjacencyIndex.evaluationCount;

    for (var i = 0; i < pending.length; i++) {
      final group = pending[i];
      var left = double.infinity;
      var top = double.infinity;
      var right = double.negativeInfinity;
      var bottom = double.negativeInfinity;
      for (final box in group) {
        if (box.left < left) left = box.left;
        if (box.top < top) top = box.top;
        if (box.right > right) right = box.right;
        if (box.bottom > bottom) bottom = box.bottom;
      }
      final width = right - left;
      final height = bottom - top;
      final direction = height > width * policy.verticalAspectThreshold
          ? SegmentLineDirection.vertical
          : width > height * policy.horizontalAspectThreshold
          ? SegmentLineDirection.horizontal
          : SegmentLineDirection.mixed;
      final localScale = _median([
        for (final box in group) localScaleById[box.id]!,
      ]);
      final semantic = _classifier.semanticOf(
        group,
        direction: direction,
        localScale: localScale,
        pageScale: medianHeight,
      );
      segments.add(
        RegionSegment(
          id: 'seg-$i',
          strokeIds: List.unmodifiable(
            [for (final box in group) box.id]..sort(),
          ),
          left: left,
          top: top,
          width: width,
          height: height,
          lineDirection: direction,
          columnIndex: columnOfGroup[group] ?? 0,
          skewRadians: skew,
          localScale: localScale,
          regionClass: semantic.type,
          classificationConfidence: semantic.confidence,
          preservedReason: semantic.preservedReason,
        ),
      );
    }
    return List.unmodifiable(segments);
  }

  double _estimateSkew(
    List<StrokeBox> boxes,
    SpatialGridIndex index,
    double neighborRadius,
  ) {
    final votes = <double>[];
    for (final box in boxes) {
      final neighbors = index.neighborsWithin(box, neighborRadius);
      // 右半平面（dx>0 且 |角|≤45°）内按欧氏距离最近者投票；
      // 纯 dx 排序在倾斜时会被斜向邻居抢占（deskew 不变量测试覆盖）。
      StrokeBox? nearestRight;
      var nearestDistance = double.infinity;
      for (final candidate in neighbors) {
        final dx = candidate.centerX - box.centerX;
        final dy = candidate.centerY - box.centerY;
        if (dx <= 0 || dy.abs() > dx) continue;
        final distance = math.sqrt(dx * dx + dy * dy);
        if (distance < nearestDistance ||
            (distance == nearestDistance &&
                nearestRight != null &&
                candidate.id.compareTo(nearestRight.id) < 0)) {
          nearestDistance = distance;
          nearestRight = candidate;
        }
      }
      if (nearestRight != null) {
        final angle = math.atan2(
          nearestRight.centerY - box.centerY,
          nearestRight.centerX - box.centerX,
        );
        if (angle.abs() <= policy.maxDeskewRadians * 2) {
          votes.add(angle);
        }
      }
    }
    if (votes.length < policy.minNeighborVotesForDeskew) return 0;
    final bins = <int, int>{};
    for (final vote in votes) {
      final bin = (vote / policy.deskewBinRadians).floor();
      bins[bin] = (bins[bin] ?? 0) + 1;
    }
    var bestBin = bins.keys.reduce((a, b) {
      final ca = bins[a]!;
      final cb = bins[b]!;
      if (ca != cb) return ca > cb ? a : b;
      return a < b ? a : b;
    });
    final center = (bestBin + 0.5) * policy.deskewBinRadians;
    return math.max(
      -policy.maxDeskewRadians,
      math.min(policy.maxDeskewRadians, center),
    );
  }

  static StrokeBox _rotateBox(
    StrokeBox box,
    double radians,
    double pivotX,
    double pivotY,
  ) {
    if (radians == 0) return box;
    final cosR = math.cos(radians);
    final sinR = math.sin(radians);
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final (x, y) in [
      (box.left, box.top),
      (box.right, box.top),
      (box.right, box.bottom),
      (box.left, box.bottom),
    ]) {
      final dx = x - pivotX;
      final dy = y - pivotY;
      final rx = pivotX + dx * cosR - dy * sinR;
      final ry = pivotY + dx * sinR + dy * cosR;
      if (rx < minX) minX = rx;
      if (rx > maxX) maxX = rx;
      if (ry < minY) minY = ry;
      if (ry > maxY) maxY = ry;
    }
    return StrokeBox(
      id: box.id,
      left: minX,
      top: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  static double _groupTop(List<StrokeBox> group) {
    var top = double.infinity;
    for (final box in group) {
      if (box.top < top) top = box.top;
    }
    return top;
  }

  static double _groupLeft(List<StrokeBox> group) {
    var left = double.infinity;
    for (final box in group) {
      if (box.left < left) left = box.left;
    }
    return left;
  }

  /// 中位数（偶数个取下中位，保证确定性）。
  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }

  static double _mean(List<double> values) {
    var sum = 0.0;
    for (final value in values) {
      sum += value;
    }
    return sum / values.length;
  }
}
