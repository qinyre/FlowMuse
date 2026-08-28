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

/// Set-of-Mark 匹配器：VLM 只引用截图上的编号标记（markIds），客户端按编号
/// 映射表直查回场景对象——无坐标回归、无几何阈值。同一编号被多项引用时
/// 首占者赢；引用未知编号或已占用编号的项按剔除后的引用结算（服务端已做
/// 同样的过滤，这里兜底）。
abstract class SmartLayoutVisionMatcher {
  static SmartLayoutVisionMatch match({
    required List<SmartLayoutVisionElement> elements,
    required Map<String, String> textMarks,
    required Map<String, String> figureMarks,
    required Set<String> allClusterKeys,
  }) {
    final textClaims = <int, List<String>>{};
    final figureClaims = <int, String>{};
    final claimedMarks = <String>{};
    for (var i = 0; i < elements.length; i++) {
      for (final markId in elements[i].markIds) {
        if (!claimedMarks.add(markId)) continue;
        final clusterKey = textMarks[markId];
        if (clusterKey != null) {
          textClaims.putIfAbsent(i, () => <String>[]).add(clusterKey);
          continue;
        }
        final unitKey = figureMarks[markId];
        if (unitKey != null) {
          figureClaims[i] = unitKey;
        }
      }
    }
    final claimedClusters = {
      for (final keys in textClaims.values) ...keys,
    };
    return SmartLayoutVisionMatch(
      textClaims: textClaims,
      figureClaims: figureClaims,
      unclaimedClusterKeys: {
        for (final key in allClusterKeys)
          if (!claimedClusters.contains(key)) key,
      },
    );
  }
}
