import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../elements/elements.dart';
import 'smart_layout_document.dart';

/// 版式单元种类。
enum LayoutUnitKind { text, image, shape, group }

/// 版式单元：参与排版的一个原子（文本块/图片/形状/成组）。
@immutable
class LayoutUnit {
  const LayoutUnit({
    required this.key,
    required this.sourceBounds,
    required this.size,
    required this.kind,
    this.textElement,
    this.element,
    this.vertical = false,
    this.memberIds = const [],
  });

  final String key;

  /// 原稿位置（配对与排序的唯一几何依据）。
  final Rect sourceBounds;

  /// 排版尺寸。
  final Size size;
  final LayoutUnitKind kind;

  /// kind == text 时的文本元素（含样式/字号/writingMode）。
  final TextElement? textElement;

  /// kind != text 时的场景元素。
  final Element? element;
  final bool vertical;

  /// 成组单元的成员元素 id（非组为空）。
  final List<String> memberIds;

  double get centerY => sourceBounds.center.dy;
}

/// 图文配对：结构层绑定后版式层不拆散（LaTeX float / HTML figure 的共同经验）。
class FigureTextPair {
  const FigureTextPair({
    required this.figure,
    required this.caption,
    required this.figureAbove,
  });

  final LayoutUnit figure;
  final LayoutUnit caption;

  /// 原稿中图在文的上方 → 排版顺序 [图, 文]，否则 [文, 图]。
  final bool figureAbove;
}

/// 一页排版的语义结构（结构层产物，版式模板只消费它）。
@immutable
class SmartLayoutContent {
  const SmartLayoutContent({
    required this.pageId,
    required this.contentArea,
    this.title,
    this.pairs = const [],
    this.looseTexts = const [],
    this.looseFigures = const [],
  });

  final String pageId;
  final Rect contentArea;
  final LayoutUnit? title;
  final List<FigureTextPair> pairs;
  final List<LayoutUnit> looseTexts;
  final List<LayoutUnit> looseFigures;
}

/// 结构层构建输入（控制器从场景与 compose 结果装配）。
@immutable
class SmartLayoutStructureInput {
  const SmartLayoutStructureInput({
    required this.groups,
    required this.textByKey,
    required this.textSourceBounds,
    required this.elementByKey,
    required this.elementSourceBounds,
    this.groupKeys = const {},
  });

  /// AI 分组（role + elementIds），按返回顺序。
  final List<SmartLayoutPptGroup> groups;

  /// 文本成员：block/unit key → 已创建的文本元素（含样式与 writingMode）。
  final Map<String, TextElement> textByKey;

  /// 文本成员原稿 bounds（key 同上）。
  final Map<String, Rect> textSourceBounds;

  /// 场景元素：元素 id → 元素（页内、可移动）。
  final Map<String, Element> elementByKey;

  /// 场景元素/组 key → 原稿 bounds。
  final Map<String, Rect> elementSourceBounds;

  /// 多成员组 key（整组移动单元）。
  final Set<String> groupKeys;
}

/// 结构层构建器：角色分类（title/body）、图文配对（垂直间距最小 + 水平重叠率，
/// pdfminer line_margin 思想）、松散项收集。纯函数、确定性。
class SmartLayoutStructureBuilder {
  const SmartLayoutStructureBuilder._();

  static const double minHorizontalOverlapRatio = 0.3;

  static SmartLayoutContent build(
    SmartLayoutStructureInput input, {
    required String pageId,
    required Rect contentArea,
  }) {
    LayoutUnit? titleUnit;
    final bodyTexts = <LayoutUnit>[];
    final figures = <LayoutUnit>[];

    LayoutUnit? textUnitOf(String key) {
      final text = input.textByKey[key];
      if (text == null) return null;
      final bounds =
          input.textSourceBounds[key] ??
          Rect.fromLTWH(text.x, text.y, text.width, text.height);
      final vertical = _isVerticalText(text);
      return LayoutUnit(
        key: key,
        sourceBounds: bounds,
        size: Size(text.width, text.height),
        kind: LayoutUnitKind.text,
        textElement: text,
        vertical: vertical,
      );
    }

    LayoutUnit? figureUnitOf(String key) {
      final element = input.elementByKey[key];
      final bounds = input.elementSourceBounds[key];
      if (element == null || bounds == null) return null;
      return LayoutUnit(
        key: key,
        sourceBounds: bounds,
        size: Size(element.width, element.height),
        kind: element is ImageElement
            ? LayoutUnitKind.image
            : LayoutUnitKind.shape,
        element: element,
      );
    }

    for (final group in input.groups) {
      final keys = <String>[
        for (final rawId in group.elementIds)
          if (input.textByKey.containsKey(rawId) ||
              input.elementByKey.containsKey(rawId))
            rawId,
      ];
      if (keys.isEmpty) continue;
      for (final key in keys) {
        final isText = input.textByKey.containsKey(key);
        if (group.role == 'title' && isText && titleUnit == null) {
          titleUnit = textUnitOf(key);
          continue;
        }
        if (isText) {
          final unit = textUnitOf(key);
          if (unit != null) bodyTexts.add(unit);
        } else {
          final unit = figureUnitOf(key);
          if (unit != null) figures.add(unit);
        }
      }
    }

    // 整组成员（未被 AI 引用的组）作为形状单元兜底收进 looseFigures？
    // 否——未引用即不参与排版，保持障碍语义，这里不收。

    final pairedTexts = <String>{};
    final usedFigures = <String>{};
    final pairs = <FigureTextPair>[];
    final looseTexts = <LayoutUnit>[];
    final looseFigures = <LayoutUnit>[];

    bool horizontalOverlapAtLeast(LayoutUnit a, LayoutUnit b, double ratio) {
      final overlap =
          (a.sourceBounds.left < b.sourceBounds.right &&
              b.sourceBounds.left < a.sourceBounds.right)
          ? math.min(a.sourceBounds.right, b.sourceBounds.right) -
                math.max(a.sourceBounds.left, b.sourceBounds.left)
          : 0.0;
      final narrower = math.min(a.size.width, b.size.width);
      return narrower > 0 && overlap / narrower >= ratio;
    }

    double verticalGap(LayoutUnit a, LayoutUnit b) {
      final top = math.max(a.sourceBounds.top, b.sourceBounds.top);
      final bottom = math.min(a.sourceBounds.bottom, b.sourceBounds.bottom);
      return top >= bottom ? top - bottom : 0.0;
    }

    // 配对：图按 y 序，题注取"垂直间距最小且水平重叠率达标"者；互为唯一。
    final orderedFigures = [...figures]
      ..sort((a, b) => a.sourceBounds.top.compareTo(b.sourceBounds.top));
    for (final figure in orderedFigures) {
      LayoutUnit? best;
      var bestGap = double.infinity;
      for (final caption in bodyTexts) {
        if (pairedTexts.contains(caption.key)) continue;
        if (!horizontalOverlapAtLeast(
          figure,
          caption,
          minHorizontalOverlapRatio,
        )) {
          continue;
        }
        final gap = verticalGap(figure, caption);
        if (gap < bestGap) {
          bestGap = gap;
          best = caption;
        }
      }
      if (best == null) continue;
      pairedTexts.add(best.key);
      usedFigures.add(figure.key);
      pairs.add(
        FigureTextPair(
          figure: figure,
          caption: best,
          figureAbove: figure.sourceBounds.top <= best.sourceBounds.top,
        ),
      );
    }
    for (final caption in bodyTexts) {
      if (!pairedTexts.contains(caption.key)) {
        looseTexts.add(caption);
      }
    }
    for (final figure in figures) {
      if (!usedFigures.contains(figure.key)) {
        looseFigures.add(figure);
      }
    }

    return SmartLayoutContent(
      pageId: pageId,
      contentArea: contentArea,
      title: titleUnit,
      pairs: pairs,
      looseTexts: looseTexts,
      looseFigures: looseFigures,
    );
  }

  static bool _isVerticalText(TextElement element) {
    final flowMuse = element.customData?['flowMuse'];
    if (flowMuse is Map<String, Object?>) {
      return flowMuse['writingMode'] == 'vertical';
    }
    return false;
  }
}

// 局部小工具（避免引入 dart:math 全量导入别名冲突）
