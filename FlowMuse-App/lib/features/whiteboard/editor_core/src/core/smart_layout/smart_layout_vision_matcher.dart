import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'smart_layout_document.dart';

/// 视觉匹配结果：把 VLM 输出映射回场景原稿（纯函数、确定性）。
@immutable
class SmartLayoutVisionMatch {
  const SmartLayoutVisionMatch({
    required this.textClaims,
    required this.figureClaims,
    required this.unclaimedClusterKeys,
  });

  /// 文本项（vision elements 下标）→ 认领的笔迹簇 key 列表。
  final Map<int, List<String>> textClaims;

  /// 图形项下标 → 场景元素/组单元 key（唯一）。
  final Map<int, String> figureClaims;

  /// 未被任何识别认领的笔迹簇 key（失败红区）。
  final Set<String> unclaimedClusterKeys;

  int get matchedItemCount => textClaims.length + figureClaims.length;
}

/// 视觉匹配器：0-1000 坐标 → 页面坐标后，
/// - 文本项认领"簇中心落在其框内（含容差）"或"簇在框内覆盖率 ≥ minClusterCoverage"
///   的所有笔迹簇（一个段落框可合并多个小簇，见计划 2026-08-26）；
/// - 二次合并扫描：主认领后仍未认领的簇，若与某已认领文本项的并集框重叠
///   ≥ secondPassMergeRatio（治逐字拆簇导致的"半认半红"），并入该项；
/// - 图形项按 interArea/min(面积) 最大且唯一者匹配场景元素/组单元；
/// - 平局以更小的下标/key 破解，保证同输入同输出。
abstract class SmartLayoutVisionMatcher {
  /// 簇面积的覆盖率阈值：簇在文本框内面积达到该比例即被该文本项认领。
  static const double minClusterCoverage = 0.35;

  /// 簇中心点认领容差：中心点落在框外扩该像素数内也认领（治框略偏移）。
  static const double centerClaimTolerance = 8.0;

  /// 二次合并阈值：未认领簇与已认领文本项并集框的交叠 ≥ 簇面积该比例时并入。
  static const double secondPassMergeRatio = 0.5;

  /// 图形与场景单元的交叠阈值：interArea / min(两者面积)。
  static const double minFigureOverlapRatio = 0.4;

  /// 单个文本项最多认领的簇数（防失控）。
  static const int maxClustersPerTextItem = 12;

  static SmartLayoutVisionMatch match({
    required List<SmartLayoutVisionElement> elements,
    required Rect pageBounds,
    required Map<String, Rect> inkClusters,
    required Map<String, Rect> figureUnits,
  }) {
    final textClaims = <int, List<String>>{};
    final claimedClusters = <String>{};
    final figureClaims = <int, String>{};
    final claimedUnits = <String>{};

    bool centerInside(Rect cluster, Rect rect) {
      final center = cluster.center;
      final outer = rect.inflate(centerClaimTolerance);
      return outer.contains(center);
    }

    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (element.isFigure) continue;
      final rect = element.sceneRectAsRect(pageBounds);
      final scored = <(String, double)>[];
      for (final entry in inkClusters.entries) {
        if (claimedClusters.contains(entry.key)) continue;
        final cluster = entry.value;
        final coverage = _intersectionArea(cluster, rect) / _area(cluster);
        if (coverage >= minClusterCoverage || centerInside(cluster, rect)) {
          scored.add((entry.key, coverage));
        }
      }
      scored.sort((a, b) {
        final byCoverage = b.$2.compareTo(a.$2);
        return byCoverage != 0 ? byCoverage : a.$1.compareTo(b.$1);
      });
      final claimKeys = [
        for (final (key, _) in scored.take(maxClustersPerTextItem)) key,
      ];
      claimedClusters.addAll(claimKeys);
      if (claimKeys.isNotEmpty) {
        textClaims[i] = claimKeys;
      }
    }

    // 二次合并：未认领簇若大半落在某已认领文本项的并集框内，并入该项
    // （模型框往往只罩住拆簇后的一部分，另一半会误入红区）。
    for (var i = 0; i < elements.length; i++) {
      final claimKeys = textClaims[i];
      if (claimKeys == null || claimKeys.length >= maxClustersPerTextItem) {
        continue;
      }
      var union = elementRect(i, elements, pageBounds);
      for (final key in claimKeys) {
        union = union.expandToInclude(inkClusters[key]!);
      }
      final merged = <String>[];
      for (final entry in inkClusters.entries) {
        if (claimedClusters.contains(entry.key)) continue;
        final overlap = _intersectionArea(entry.value, union);
        if (overlap / _area(entry.value) >= secondPassMergeRatio) {
          merged.add(entry.key);
        }
      }
      if (merged.isEmpty) continue;
      merged.sort();
      claimKeys.addAll(merged);
      claimedClusters.addAll(merged);
    }

    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (!element.isFigure) continue;
      final rect = element.sceneRectAsRect(pageBounds);
      String? bestKey;
      var bestScore = 0.0;
      for (final entry in figureUnits.entries) {
        if (claimedUnits.contains(entry.key)) continue;
        // interArea / min(unitArea, figArea)：任一方远小于另一方时惩罚误配。
        final overlap = _intersectionArea(entry.value, rect);
        final denominator = _minArea(entry.value, rect);
        final ratio = denominator > 0 ? overlap / denominator : 0.0;
        if (ratio >= minFigureOverlapRatio && ratio > bestScore + 1e-9) {
          bestScore = ratio;
          bestKey = entry.key;
        }
      }
      if (bestKey != null) {
        claimedUnits.add(bestKey);
        figureClaims[i] = bestKey;
      }
    }

    return SmartLayoutVisionMatch(
      textClaims: textClaims,
      figureClaims: figureClaims,
      unclaimedClusterKeys: {
        for (final key in inkClusters.keys)
          if (!claimedClusters.contains(key)) key,
      },
    );
  }

  static Rect elementRect(
    int index,
    List<SmartLayoutVisionElement> elements,
    Rect pageBounds,
  ) => elements[index].sceneRectAsRect(pageBounds);

  static double _intersectionArea(Rect a, Rect b) {
    final left = a.left > b.left ? a.left : b.left;
    final top = a.top > b.top ? a.top : b.top;
    final right = a.right < b.right ? a.right : b.right;
    final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    if (left >= right || top >= bottom) return 0;
    return (right - left) * (bottom - top);
  }

  static double _area(Rect rect) => rect.width * rect.height;

  static double _minArea(Rect a, Rect b) {
    final areaA = _area(a);
    final areaB = _area(b);
    return areaA <= areaB ? areaA : areaB;
  }
}

extension on SmartLayoutVisionElement {
  Rect sceneRectAsRect(Rect pageBounds) {
    return Rect.fromLTWH(
      pageBounds.left + x1 / 1000 * pageBounds.width,
      pageBounds.top + y1 / 1000 * pageBounds.height,
      (x2 - x1) / 1000 * pageBounds.width,
      (y2 - y1) / 1000 * pageBounds.height,
    );
  }
}
