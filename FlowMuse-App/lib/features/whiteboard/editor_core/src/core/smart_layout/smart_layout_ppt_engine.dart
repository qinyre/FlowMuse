import 'dart:ui';

/// 一个版式单元：key 为单元标识（普通元素 id / 识别块 id / 成组元素组 id），size 为外接矩形尺寸。
class PptUnit {
  const PptUnit({required this.key, required this.size});

  final String key;
  final Size size;
}

/// 一个版式组（按 AI groups 语义）：role 仅 title/heading/body/figure；key 为组标识。
/// 单个单元成组时：key 与单元 key 相同、memberKeys 长度 1。
/// 成组元素（组内相对位置不变）时：key 为组 id、memberKeys 为组内成员 key。
class PptGroupItem {
  const PptGroupItem({
    required this.key,
    required this.role,
    required this.memberKeys,
  });

  final String key;
  final String role;
  final List<String> memberKeys;
}

class PptLayoutResult {
  const PptLayoutResult({required this.targets});

  /// key → 目标左上角（场景坐标）。
  final Map<String, Offset> targets;
}

/// PPT 式排版引擎：确定性双列网格（有配图）或单列（无配图），整体下移避障。
/// 布局规则见 docs/研发记录/plans/2026-08-24-ai-smart-layout-optimization.md 3.3 节。
class PptLayoutEngine {
  const PptLayoutEngine._();

  static const double unitGap = 16.0;
  static const double columnGap = 24.0;
  static const double rowGap = 24.0;
  static const double figureColumnRatio = 0.62;
  static const double downShiftStep = 24.0;
  static const int maxDownShifts = 40;

  static PptLayoutResult? place({
    required Rect contentArea,
    required List<PptGroupItem> groups,
    required Map<String, PptUnit> units,
    required List<Rect> occupied,
  }) {
    if (groups.isEmpty) return null;
    final hasFigure = groups.any((group) => group.role == 'figure');
    final textGroups = [
      for (final group in groups)
        if (group.role != 'figure') group,
    ];
    final figureGroups = [
      for (final group in groups)
        if (group.role == 'figure') group,
    ];
    final placements = <String, Offset>{};

    bool placeColumn(
      List<PptGroupItem> columnGroups,
      double columnLeft,
      double columnWidth,
    ) {
      var y = contentArea.top;
      for (final group in columnGroups) {
        final unit = units[group.key];
        if (unit == null) continue;
        if (unit.size.width > columnWidth) return false;
        placements[group.key] = Offset(columnLeft, y);
        y += unit.size.height + rowGap;
        if (y - rowGap > contentArea.bottom) return false;
      }
      return true;
    }

    if (hasFigure) {
      // 自适应列宽：配图列按"最大配图宽"决定（默认 38%，回落时加大），
      // 文本列必须容纳最大文本单元；配图列被文本挤压放不下时回落单列全宽堆叠。
      double figureNeeded = 0;
      for (final group in figureGroups) {
        final unit = units[group.key];
        if (unit == null) continue;
        if (unit.size.width > figureNeeded) {
          figureNeeded = unit.size.width;
        }
      }
      double textNeeded = 0;
      for (final group in textGroups) {
        final unit = units[group.key];
        if (unit == null) continue;
        if (unit.size.width > textNeeded) {
          textNeeded = unit.size.width;
        }
      }
      final defaultTextWidth = contentArea.width * figureColumnRatio - 12;
      final defaultFigureWidth = contentArea.width - defaultTextWidth - columnGap;
      final bothFitDefault = figureNeeded <= defaultFigureWidth &&
          textNeeded <= defaultTextWidth;
      final adaptiveFigureWidth = contentArea.width - columnGap - textNeeded;
      final adaptiveFits = figureNeeded <= adaptiveFigureWidth &&
          textNeeded <= contentArea.width - columnGap - figureNeeded;
      if (bothFitDefault) {
        final textWidth = defaultTextWidth;
        final figureLeft = contentArea.left + textWidth + columnGap;
        final figureWidth = contentArea.right - figureLeft;
        if (!placeColumn(textGroups, contentArea.left, textWidth)) return null;
        if (!placeColumn(figureGroups, figureLeft, figureWidth)) return null;
      } else if (adaptiveFits) {
        final figureWidth = figureNeeded;
        final textWidth = contentArea.width - figureWidth - columnGap;
        if (!placeColumn(textGroups, contentArea.left, textWidth)) return null;
        if (!placeColumn(
          figureGroups,
          contentArea.left + textWidth + columnGap,
          figureWidth,
        )) {
          return null;
        }
      } else {
        // 单列全宽回落：所有组按原顺序堆叠
        if (!placeColumn(groups, contentArea.left, contentArea.width)) {
          return null;
        }
      }
    } else {
      if (!placeColumn(textGroups, contentArea.left, contentArea.width)) {
        return null;
      }
    }

    bool insideAndClear() {
      for (final entry in placements.entries) {
        final unit = units[entry.key];
        if (unit == null) continue;
        final rect = Rect.fromLTWH(
          entry.value.dx,
          entry.value.dy,
          unit.size.width,
          unit.size.height,
        );
        if (rect.left < contentArea.left ||
            rect.top < contentArea.top ||
            rect.right > contentArea.right ||
            rect.bottom > contentArea.bottom) {
          return false;
        }
        for (final obstacle in occupied) {
          if (rect.overlaps(obstacle)) return false;
        }
      }
      return true;
    }

    if (insideAndClear()) {
      return PptLayoutResult(targets: placements);
    }
    for (var i = 1; i <= maxDownShifts; i++) {
      for (final key in placements.keys.toList()) {
        placements[key] = placements[key]! + const Offset(0, downShiftStep);
      }
      if (insideAndClear()) {
        return PptLayoutResult(targets: placements);
      }
    }
    return null;
  }
}
