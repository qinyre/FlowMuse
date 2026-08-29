import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../elements/elements.dart';

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
    this.keepAsInk = false,
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

  /// 保留手写：该文本单元以原稿墨迹整体占位（引擎用移动代替新增印刷体，
  /// 槽位用 [size]；生产方构造 keepAsInk 变体时 size 取原稿包围盒尺寸）。
  final bool keepAsInk;

  /// 成组单元的成员元素 id（非组为空）；keepAsInk 文本单元为该块笔迹
  /// 元素 id（随方案移动、从删除清单排除）。
  final List<String> memberIds;

  double get centerY => sourceBounds.center.dy;

  LayoutUnit copyWith({
    String? key,
    Rect? sourceBounds,
    Size? size,
    LayoutUnitKind? kind,
    TextElement? textElement,
    Element? element,
    bool? vertical,
    bool? keepAsInk,
    List<String>? memberIds,
  }) => LayoutUnit(
    key: key ?? this.key,
    sourceBounds: sourceBounds ?? this.sourceBounds,
    size: size ?? this.size,
    kind: kind ?? this.kind,
    textElement: textElement ?? this.textElement,
    element: element ?? this.element,
    vertical: vertical ?? this.vertical,
    keepAsInk: keepAsInk ?? this.keepAsInk,
    memberIds: memberIds ?? this.memberIds,
  );
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

  /// 保留手写变体：全部文本单元改以原稿墨迹占位（keepAsInk），排版槽位
  /// 用原稿包围盒尺寸（印刷体测量尺寸不再参与版式计算）；图/形/组不变。
  /// 引擎据此用移动墨迹代替新增文本元素（"保留手写、仅重排位置"）。
  SmartLayoutContent withTextAsInk() {
    LayoutUnit inkText(LayoutUnit unit) => unit.copyWith(
      keepAsInk: true,
      size: Size(unit.sourceBounds.width, unit.sourceBounds.height),
    );
    return SmartLayoutContent(
      pageId: pageId,
      contentArea: contentArea,
      title: title == null ? null : inkText(title!),
      pairs: [
        for (final pair in pairs)
          FigureTextPair(
            figure: pair.figure,
            caption: inkText(pair.caption),
            figureAbove: pair.figureAbove,
          ),
      ],
      looseTexts: [for (final unit in looseTexts) inkText(unit)],
      looseFigures: looseFigures,
    );
  }
}
