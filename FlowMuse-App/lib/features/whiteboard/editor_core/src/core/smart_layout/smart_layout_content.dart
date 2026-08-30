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
    bool? keepAsInk,
    List<String>? memberIds,
  }) => LayoutUnit(
    key: key ?? this.key,
    sourceBounds: sourceBounds ?? this.sourceBounds,
    size: size ?? this.size,
    kind: kind ?? this.kind,
    textElement: textElement ?? this.textElement,
    element: element ?? this.element,
    keepAsInk: keepAsInk ?? this.keepAsInk,
    memberIds: memberIds ?? this.memberIds,
  );
}

/// 图文配对：一图与其全部图旁标签（上方/下方/侧方）——结构层绑定后版式
/// 层不拆散（LaTeX float / HTML figure 的共同经验）。一图可收多个标签、
/// 一文本只归一图；侧方标签原稿 top 不小于图 top，归入下方栈。
class FigureTextPair {
  const FigureTextPair({
    required this.figure,
    this.topTexts = const [],
    this.bottomTexts = const [],
  });

  final LayoutUnit figure;

  /// 原稿位于图上方的标签（阅读序 top→left）。
  final List<LayoutUnit> topTexts;

  /// 其余标签（下方/侧方；阅读序 top→left）。
  final List<LayoutUnit> bottomTexts;

  /// 全部图旁标签（上栈在前）。
  List<LayoutUnit> get texts => [...topTexts, ...bottomTexts];

  /// 从图与若干标签构造：原稿 top 严格小于图 top 归 [topTexts]、其余归
  /// [bottomTexts]；各列表按原稿阅读序（top→left）排序（确定性）。
  factory FigureTextPair.bind({
    required LayoutUnit figure,
    required Iterable<LayoutUnit> texts,
  }) {
    final sorted = texts.toList()..sort((a, b) {
      final byTop = a.sourceBounds.top.compareTo(b.sourceBounds.top);
      return byTop != 0 ? byTop : a.sourceBounds.left.compareTo(b.sourceBounds.left);
    });
    return FigureTextPair(
      figure: figure,
      topTexts: [
        for (final unit in sorted)
          if (unit.sourceBounds.top < figure.sourceBounds.top) unit,
      ],
      bottomTexts: [
        for (final unit in sorted)
          if (unit.sourceBounds.top >= figure.sourceBounds.top) unit,
      ],
    );
  }
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

  /// 全部文本单元（标题 + 图旁标签 + 松散段落）——keepAsInk 变换、墨迹
  /// 笔迹 id 收集等按"文本单元"遍历的场景共用这一次枚举。
  Iterable<LayoutUnit> get textUnits => [
    ?title,
    for (final pair in pairs) ...pair.texts,
    ...looseTexts,
  ];

  /// 保留手写变体：全部文本单元改以原稿墨迹占位（keepAsInk），排版槽位
  /// 用原稿包围盒尺寸（印刷体测量尺寸不再参与版式计算）；图/形/组不变。
  /// 引擎据此用移动墨迹代替新增文本元素（"保留手写、仅重排位置"）。
  SmartLayoutContent withTextAsInk() {
    final inkUnits = <LayoutUnit, LayoutUnit>{
      for (final unit in textUnits)
        unit: unit.copyWith(
          keepAsInk: true,
          size: Size(unit.sourceBounds.width, unit.sourceBounds.height),
        ),
    };
    return SmartLayoutContent(
      pageId: pageId,
      contentArea: contentArea,
      title: title == null ? null : inkUnits[title!],
      pairs: [
        for (final pair in pairs)
          FigureTextPair(
            figure: pair.figure,
            topTexts: [for (final unit in pair.topTexts) inkUnits[unit]!],
            bottomTexts: [for (final unit in pair.bottomTexts) inkUnits[unit]!],
          ),
      ],
      looseTexts: [for (final unit in looseTexts) inkUnits[unit]!],
      looseFigures: looseFigures,
    );
  }
}
