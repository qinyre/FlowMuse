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
