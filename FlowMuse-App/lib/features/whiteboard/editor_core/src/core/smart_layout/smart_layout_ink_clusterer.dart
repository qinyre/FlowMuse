import 'dart:math' as math;

import '../elements/elements.dart';

/// 全页纯几何行列聚类（v2 去会话化）：对页内全部墨迹一次聚类成识别块，
/// 会话维度不再参与智能排版——会话边界是碎簇帮凶（"先头小子"分四笔写即
/// 四个会话四个单字簇），跨会话的连续笔迹必须能合到一起。
///
/// 流程：
/// 1. 杂散过滤：单笔画且包围盒 < 8×8pt 视为噪点（勾、点、污渍），直接剔除
///    （不参与聚类，也不会进入方案的删除/红区清单，原样留在页面上）。
/// 2. 竖排窄高列检测：x 重叠且纵向紧邻的笔画先聚成候选列，整列 高/宽 > 1.5
///    判为竖排列、整列不拆（否则"先头小子"这类竖排短语每个字会被拆成
///    独立行带）；不满足高宽比的候选组交回行带划分。
/// 3. 行带划分：按中心 y 聚类，相邻中心距 ≤ max(min(h1,h2)*0.7, 12) 同带。
/// 4. 带内按 x 间距分块：相邻间隙 > max(min(h1,h2)*1.2, 28) 拆成两块。
///
/// 输出保证确定性（y 优先、x 次之、id 兜底）。
class SmartLayoutInkClusterer {
  const SmartLayoutInkClusterer._();

  /// 杂散笔画判定：单笔画包围盒宽高均小于该值视为噪点。
  static const double noiseStrokeMinSize = 8.0;

  /// 竖排列判定：整组包围盒 高/宽 > 1.5（x 窄 y 长，如竖排短语）。
  static bool isVerticalColumn(List<FreedrawElement> strokes) {
    if (strokes.isEmpty) return false;
    final bounds = unionBounds(strokes);
    if (bounds.width <= 0) return false;
    return bounds.height / bounds.width > 1.5;
  }

  /// 全页聚类入口：输入页内全部手写笔迹，输出识别块（每块若干笔画）。
  static List<List<FreedrawElement>> cluster(List<FreedrawElement> strokes) {
    final kept = [
      for (final stroke in strokes)
        if (!_isNoiseStroke(stroke)) stroke,
    ];
    if (kept.isEmpty) return const [];
    final sorted = sortedByReadingOrder(kept);
    final clusters = <List<FreedrawElement>>[];
    final remainder = <FreedrawElement>[];
    for (final group in _stackedCandidateGroups(sorted)) {
      if (group.length > 1 && isVerticalColumn(group)) {
        clusters.add(group);
      } else {
        remainder.addAll(group);
      }
    }
    for (final band in _rowBands(sortedByReadingOrder(remainder))) {
      clusters.addAll(_splitBandByGap(band));
    }
    return clusters;
  }

  static bool _isNoiseStroke(FreedrawElement stroke) =>
      stroke.width < noiseStrokeMinSize && stroke.height < noiseStrokeMinSize;

  /// 阅读序排序：中心 y 优先、x 次之、id 兜底（确定性）。
  static List<FreedrawElement> sortedByReadingOrder(
    List<FreedrawElement> strokes,
  ) {
    final sorted = List<FreedrawElement>.of(strokes)
      ..sort((a, b) {
        final ay = a.y + a.height / 2;
        final by = b.y + b.height / 2;
        if (ay != by) return ay.compareTo(by);
        if (a.x != b.x) return a.x.compareTo(b.x);
        return a.id.value.compareTo(b.id.value);
      });
    return sorted;
  }

  /// 竖排候选列：按阅读序扫描，与当前列 x 重叠过半且纵向紧邻的笔画并入，
  /// 否则开新列。候选只是"待定"，是否真竖排由高宽比闸门决定（横排同行
  /// 笔画也会链成候选组，但整组宽扁、过不了闸门，交回行带划分）。
  static List<List<FreedrawElement>> _stackedCandidateGroups(
    List<FreedrawElement> sorted,
  ) {
    final groups = <List<FreedrawElement>>[];
    List<FreedrawElement> current = [];
    var colLeft = 0.0;
    var colRight = 0.0;
    var colBottom = 0.0;
    void close() {
      if (current.isNotEmpty) groups.add(current);
      current = <FreedrawElement>[];
    }

    for (final stroke in sorted) {
      final overlap =
          math.min(colRight, stroke.x + stroke.width) - math.max(colLeft, stroke.x);
      final joinRatio = current.isEmpty
          ? 1.0
          : overlap / math.max(stroke.width, 1.0);
      final gap = current.isEmpty ? 0.0 : stroke.y - colBottom;
      final gapLimit = math.max(stroke.height * 0.7, 12.0);
      if (current.isEmpty || (joinRatio >= 0.5 && gap <= gapLimit)) {
        if (current.isEmpty) {
          colLeft = stroke.x;
          colRight = stroke.x + stroke.width;
          colBottom = stroke.y + stroke.height;
        } else {
          colLeft = math.min(colLeft, stroke.x);
          colRight = math.max(colRight, stroke.x + stroke.width);
          colBottom = math.max(colBottom, stroke.y + stroke.height);
        }
        current.add(stroke);
      } else {
        close();
        colLeft = stroke.x;
        colRight = stroke.x + stroke.width;
        colBottom = stroke.y + stroke.height;
        current = [stroke];
      }
    }
    close();
    return groups;
  }

  /// 行带划分：相邻笔迹中心距 ≤ max(min(h1,h2)*0.7, 12) 视为同一行
  /// （真机校准值，与 Go 侧 groupSmartLayoutStrokeBounds 一致）。
  static List<List<FreedrawElement>> _rowBands(
    List<FreedrawElement> sorted,
  ) {
    if (sorted.isEmpty) return const [];
    final bands = <List<FreedrawElement>>[];
    var current = [sorted.first];
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
        bands.add(current);
        current = [stroke];
      }
    }
    bands.add(current);
    return bands;
  }

  /// 带内分块：按左边缘排序，相邻间隙 > max(min(h1,h2)*1.2, 28) 拆开
  /// （间隙超过约一个字高 = 中间是刻意留白，属两个内容块）。
  static List<List<FreedrawElement>> _splitBandByGap(
    List<FreedrawElement> band,
  ) {
    final sorted = List<FreedrawElement>.of(band)
      ..sort((a, b) {
        if (a.x != b.x) return a.x.compareTo(b.x);
        return a.id.value.compareTo(b.id.value);
      });
    final blocks = <List<FreedrawElement>>[];
    var current = [sorted.first];
    var currentRight = sorted.first.x + sorted.first.width;
    for (final stroke in sorted.skip(1)) {
      final gap = stroke.x - currentRight;
      final threshold = math.max(
        math.min(current.last.height, stroke.height) * 1.2,
        28.0,
      );
      if (gap > threshold) {
        blocks.add(current);
        current = [stroke];
      } else {
        current.add(stroke);
      }
      currentRight = math.max(currentRight, stroke.x + stroke.width);
    }
    blocks.add(current);
    return blocks;
  }

  /// 笔画组并集包围盒。
  static ({
    double left,
    double top,
    double width,
    double height,
  }) unionBounds(List<FreedrawElement> strokes) {
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
    return (
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }
}
