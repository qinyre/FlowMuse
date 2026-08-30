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
/// 4. 带内按 x 间距分块：相邻间隙 > max(min(h1,h2)*0.8, 20) 拆成两块。
///
/// 输出保证确定性（y 优先、x 次之、id 兜底）。
///
/// 注：本类是 v2 视觉管线的**独立客户端聚类**，与经典 Go 管线
/// `groupSmartLayoutStrokeBounds` 不再对齐（v2 去会话化后阈值按真机走查
/// 独立校准，头注释与实现以此为准）。
class SmartLayoutInkClusterer {
  const SmartLayoutInkClusterer._();

  /// 杂散笔画判定：单笔画包围盒宽高均小于该值视为噪点。
  static const double noiseStrokeMinSize = 8.0;

  /// 杂散笔画判定（公开供控制器收集噪点 id 并入方案删除清单——
  /// 噪点不参与聚类，应用时随方案静默删除，消除"没排干净"的残留墨点）。
  static bool isNoiseStroke(FreedrawElement stroke) =>
      stroke.width < noiseStrokeMinSize && stroke.height < noiseStrokeMinSize;

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
        if (!isNoiseStroke(stroke)) stroke,
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
  /// （真机校准值；v2 客户端聚类已独立于 Go 侧经典管线
  /// groupSmartLayoutStrokeBounds，参数不再对齐）。
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

  /// 带内分块：按左边缘排序，相邻间隙 > max(min(h1,h2)*0.8, 20) 拆开。
  /// 阈值依据（真机走查校准）：短语内字符间隙通常只有几个 pt，不会误拆；
  /// 同一行两个短语之间的刻意留白往往不足一个字高（0.8×h ~ 1.2×h），
  /// 旧阈值 max(1.2h, 28) 会把"第1句话""第3句话"并成一块、阅读序错乱
  /// （1+3/2+4），收紧到 max(0.8h, 20) 后同行分句可靠拆开。
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
        math.min(current.last.height, stroke.height) * 0.8,
        20.0,
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
