import 'dart:math' as math;

import '../elements/elements.dart';

/// 手写行簇聚类：把一个书写会话内的笔迹按行拆分成多个识别块，
/// 避免"同一会话的几句话被识别成一个整体、无法分别排版"。
/// 规则与 Go 侧 groupSmartLayoutStrokeBounds 一致：按中心 y 排序，
/// 相邻笔迹中心距不超过 max(min(h1,h2)*0.7, 12) 视为同一行。
/// 输出保证确定性（y 优先、x 次之、id 兜底）。
class SmartLayoutInkClusterer {
  const SmartLayoutInkClusterer._();

  /// 竖排列判定：会话整体包围盒 高/宽 > 1.5（x 窄 y 长，如竖排短语）。
  /// 竖排列不参与按行拆分（否则每个字会被拆成独立簇）。
  static bool isVerticalColumn(List<FreedrawElement> strokes) {
    if (strokes.isEmpty) return false;
    var left = strokes.first.x;
    var top = strokes.first.y;
    var right = left + strokes.first.width;
    var bottom = top + strokes.first.height;
    for (final stroke in strokes.skip(1)) {
      left = math.min(left, stroke.x);
      top = math.min(top, stroke.y);
      right = math.max(right, stroke.x + stroke.width);
      bottom = math.max(bottom, stroke.y + stroke.height);
    }
    final width = right - left;
    final height = bottom - top;
    if (width <= 0) return false;
    return height / width > 1.5;
  }

  static List<List<FreedrawElement>> cluster(List<FreedrawElement> strokes) {
    if (strokes.isEmpty) {
      return const [];
    }
    if (strokes.length == 1) {
      return [List.of(strokes)];
    }
    final sorted = List<FreedrawElement>.of(strokes)
      ..sort((a, b) {
        final ay = a.y + a.height / 2;
        final by = b.y + b.height / 2;
        if (ay != by) return ay.compareTo(by);
        if (a.x != b.x) return a.x.compareTo(b.x);
        return a.id.value.compareTo(b.id.value);
      });
    final clusters = <List<FreedrawElement>>[];
    List<FreedrawElement> current = [sorted.first];
    for (final stroke in sorted.skip(1)) {
      final last = current.last;
      final lastCenterY = last.y + last.height / 2;
      final centerY = stroke.y + stroke.height / 2;
      final threshold = math.max(
        math.min(last.height, stroke.height) * 0.7,
        12.0,
      );
      if ((centerY - lastCenterY).abs() <= threshold) {
        current.add(stroke);
      } else {
        clusters.add(current);
        current = [stroke];
      }
    }
    clusters.add(current);
    return clusters;
  }
}
