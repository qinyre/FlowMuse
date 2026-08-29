import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../elements/elements.dart';
import '../../rendering/text_renderer.dart';
import 'smart_layout_content.dart';
import 'smart_layout_document.dart';
import 'smart_layout_plan.dart';

/// v2 模板卡片制的三种模板（用户点选，AI 不判版式）。
enum SmartLayoutTemplateKind {
  handout('图文讲义'),
  outline('要点清单'),
  inplace('原文整理');

  const SmartLayoutTemplateKind(this.displayName);

  final String displayName;
}

/// 模板选择准备：识别（认字/图文配对/裁剪重问）完成后的全部产物——
/// 结构层 content、三张模板的预落位结果与成功/失败账本。
/// 模板选择卡消费 layouts 画真实内容缩略图；点选后控制器装配成计划。
@immutable
class SmartLayoutTemplatePreparation {
  const SmartLayoutTemplatePreparation({
    required this.pageId,
    required this.content,
    required this.layouts,
    this.layoutsKeepInk = const {},
    required this.removeIds,
    required this.failedStrokeIds,
    required this.removalRects,
    required this.failureRects,
    required this.failures,
    required this.confidence,
    required this.confidenceByBlockId,
    this.textClusterRects = const [],
  });

  final String pageId;
  final SmartLayoutContent content;

  /// 每种模板的预落位结果；null = 该模板放不下（选择卡置灰）。
  final Map<SmartLayoutTemplateKind, SmartLayoutTemplateLayoutResult?> layouts;

  /// 保留手写变体的预落位结果：同一 content 把文本单元置 keepAsInk 后的
  /// 二次引擎调用（无额外 VLM 成本）；"保留手写笔迹"开关消费这份结果。
  /// 缺项时调用方可用 content.withTextAsInk() 现算。
  final Map<SmartLayoutTemplateKind, SmartLayoutTemplateLayoutResult?>
  layoutsKeepInk;

  /// 识别成功的笔迹 + 旧智能排版文本（应用时删除）。
  final List<ElementId> removeIds;

  /// 识别失败块的笔迹（用户选择"删除未识别笔迹"时删除）。
  final List<ElementId> failedStrokeIds;
  final List<Rect> removalRects;
  final List<Rect> failureRects;
  final List<SmartLayoutFailureInfo> failures;

  /// 识别成功文本块的来源簇矩形（与 removalRects 同值域）。
  /// "保留手写"装配时从灰区/删除清单排除这些矩形对应的墨迹。
  final List<Rect> textClusterRects;

  /// 文本项平均把握（重问后有效值；确认条展示用）。
  final double confidence;

  /// 低置信校对直查表：blockId（== VLM 元素 id）→ 有效把握。
  final Map<String, double> confidenceByBlockId;
}

/// 模板引擎落位结果：几何已定（新增元素坐标/移动增量/预览框），
/// 由控制器装配成 SmartLayoutPlan（账本字段在调用方一侧）。
@immutable
class SmartLayoutTemplateLayoutResult {
  const SmartLayoutTemplateLayoutResult({
    required this.kind,
    required this.addElements,
    required this.moveDeltas,
    required this.previewRects,
    this.inkSlotRects = const [],
    required this.description,
    required this.document,
  });

  final SmartLayoutTemplateKind kind;

  /// 新增元素（已含最终坐标；尚未合并 pageId，apply 时统一合并）。
  final List<Element> addElements;

  /// 既有元素 → 左上角平移量（图/形/组，组内成员同 delta）。
  final Map<ElementId, Offset> moveDeltas;

  /// 场景坐标：新增/移动后的包围盒（蓝色幽灵预览与模板卡缩略图共用）。
  final List<Rect> previewRects;

  /// 保留手写模式的墨迹占位矩形（转写模式为空列表，与 previewRects 同
  /// 值域）：模板卡缩略图按它区分墨迹占位与图/形/组，不做尺寸匹配猜测。
  final List<Rect> inkSlotRects;

  final String description;
  final SmartLayoutDocument document;
}

/// v2 三模板落位引擎：固定区域填充，确定性（同输入同输出）。
/// 空间不足时 handout 先压间距再缩字号（下限 12pt），仍放不下返回 null
/// （控制器提示"内容过多，请分页"）；all-or-nothing，不做部分落位。
abstract final class SmartLayoutTemplateEngine {
  /// 小图判定：图宽不超过内容区该比例时，outline 允许其附于条目行右侧。
  static const double outlineSideFigureMaxWidthRatio = 0.4;

  /// 宽图判定：图宽超过内容区该比例（或半栏宽）时 handout 走通栏单列。
  static const double handoutWideFigureRatio = 0.6;

  /// handout 空间压缩档位：(间距, 正文字号缩放)，先压间距再缩字号。
  static const List<(double, double)> handoutCompressionSteps = [
    (24, 1),
    (12, 1),
    (8, 1),
    (8, 0.9),
    (8, 0.8),
    (8, 0.7),
    (8, 0.6),
    (8, 0.5),
  ];

  /// outline 条目行距。
  static const double outlineRowGap = 16.0;

  static SmartLayoutTemplateLayoutResult? layout({
    required SmartLayoutTemplateKind kind,
    required SmartLayoutContent content,
  }) {
    switch (kind) {
      case SmartLayoutTemplateKind.handout:
        return _layoutHandout(content);
      case SmartLayoutTemplateKind.outline:
        return _layoutOutline(content);
      case SmartLayoutTemplateKind.inplace:
        return _layoutInPlace(content);
    }
  }

  // ---------- 公共小件 ----------

  /// 保留手写判定：文本单元以原稿墨迹整体占位——引擎用 _moveUnit 移动
  /// 墨迹（memberIds 为该块笔迹 id）而不是新增印刷体文本元素。
  static bool _isInkText(LayoutUnit unit) =>
      unit.kind == LayoutUnitKind.text && unit.keepAsInk;

  /// 文本单元排版槽高：墨迹用原稿包围盒高；印刷体用测量后的元素高；
  /// null 单元（无图注等）为 0。
  static double _textSlotHeight(LayoutUnit? unit, TextElement? measured) =>
      unit == null
      ? 0
      : _isInkText(unit)
      ? unit.size.height
      : (measured?.height ?? 0);

  /// 文本单元排版槽宽：墨迹用原稿包围盒宽；印刷体用测量后的元素宽。
  static double _textSlotWidth(LayoutUnit unit, TextElement? measured) =>
      _isInkText(unit) ? unit.size.width : (measured?.width ?? 0);

  /// 标题样式：字号不足 28 时放大到 28 并按测量值撑宽（与旧引擎规则一致）。
  static TextElement _styledTitle(TextElement element) {
    if (element.fontSize >= 28) return element;
    var candidate = element.copyWithText(fontSize: 28);
    final (mw, mh) = TextRenderer.measure(candidate);
    final width = math.max(candidate.width, mw);
    return candidate.copyWith(
      width: width,
      height: math.max(candidate.height, mh),
    );
  }

  /// 正文缩放：字号下限 12pt，缩放后重测尺寸。
  static TextElement _scaledBody(TextElement element, double scale) {
    if (scale >= 1) return element;
    final target = math.max(12.0, element.fontSize * scale);
    if (target >= element.fontSize) return element;
    final candidate = element.copyWithText(fontSize: target);
    final (mw, mh) = TextRenderer.measure(candidate);
    return candidate.copyWith(
      width: math.max(candidate.width, mw),
      height: math.max(candidate.height, mh),
    );
  }

  /// 移动单元到目标位置（memberIds 全员同 delta）；保留手写文本单元的
  /// 目标矩形顺手记入 [inkSlotRects]（缩略图区分墨迹占位与图/形用）。
  static void _moveUnit(
    LayoutUnit unit,
    double x,
    double y,
    Map<ElementId, Offset> moveDeltas,
    List<Rect> previewRects,
    List<Rect> inkSlotRects,
  ) {
    final delta = Offset(x - unit.sourceBounds.left, y - unit.sourceBounds.top);
    final ids = unit.memberIds.isNotEmpty ? unit.memberIds : [unit.key];
    for (final id in ids) {
      moveDeltas[ElementId(id)] = delta;
    }
    final target = Rect.fromLTWH(x, y, unit.size.width, unit.size.height);
    previewRects.add(target);
    if (_isInkText(unit)) inkSlotRects.add(target);
  }

  static SmartLayoutDocument _documentOf(
    String kindPrefix,
    List<Element> addElements,
    String pageId,
  ) {
    var order = 0;
    return SmartLayoutDocumentFactory.fromBlocks([
      for (var i = 0; i < addElements.length; i++)
        if (addElements[i] is TextElement)
          SmartLayoutBlock(
            id: 'export-$kindPrefix-$i',
            type: 'paragraph',
            text: (addElements[i] as TextElement).text,
            pageId: pageId,
            order: order++,
          ),
    ]);
  }

  // ---------- handout 图文讲义 ----------

  /// 标题通栏置顶居中；pairs 网格（宽图单列、窄图两两成行，图上图注下）；
  /// looseTexts 通栏段落流；looseFigures 依序附后。
  static SmartLayoutTemplateLayoutResult? _layoutHandout(
    SmartLayoutContent content,
  ) {
    for (final (gap, scale) in handoutCompressionSteps) {
      final result = _tryHandout(content, gap: gap, bodyScale: scale);
      if (result != null) return result;
    }
    return null;
  }

  static SmartLayoutTemplateLayoutResult? _tryHandout(
    SmartLayoutContent content, {
    required double gap,
    required double bodyScale,
  }) {
    final area = content.contentArea;
    final centerX = area.center.dx;
    final addElements = <Element>[];
    final moveDeltas = <ElementId, Offset>{};
    final previewRects = <Rect>[];
    final inkSlotRects = <Rect>[];
    TextElement? bodyTextOf(LayoutUnit unit) {
      final element = unit.textElement;
      return element == null ? null : _scaledBody(element, bodyScale);
    }

    void placeTextAt(TextElement element, double x, double y) {
      addElements.add(element.copyWith(x: x, y: y));
      previewRects.add(Rect.fromLTWH(x, y, element.width, element.height));
    }

    /// 墨迹占位移动或新增印刷体文本（保留手写分支走 _moveUnit）。
    void placeTextUnit(LayoutUnit unit, double x, double y) {
      if (_isInkText(unit)) {
        _moveUnit(unit, x, y, moveDeltas, previewRects, inkSlotRects);
        return;
      }
      final text = bodyTextOf(unit);
      if (text == null) return;
      placeTextAt(text, x, y);
    }

    bool textUnitPlaceable(LayoutUnit unit) =>
        _isInkText(unit) || bodyTextOf(unit) != null;

    var y = area.top;
    final titleUnit = content.title;
    if (titleUnit != null) {
      if (_isInkText(titleUnit)) {
        // 保留手写：标题墨迹居中置顶（不做 28pt 放大）。
        if (y + titleUnit.size.height > area.bottom) return null;
        _moveUnit(
          titleUnit,
          centerX - titleUnit.size.width / 2,
          y,
          moveDeltas,
          previewRects,
          inkSlotRects,
        );
        y += titleUnit.size.height + gap;
      } else {
        final title = _styledTitle(titleUnit.textElement!);
        placeTextAt(title, centerX - title.width / 2, y);
        y += title.height + gap;
      }
    }
    if (y > area.bottom) return null;

    // 行规划：宽图独占通栏行；窄图两两成行（行高取两格较大者）。
    // 行记录恰有一格语义：wide 非空 = 通栏行；否则 left 必非空。
    final halfWidth = (area.width - gap) / 2;
    final rows =
        <({FigureTextPair? wide, FigureTextPair? left, FigureTextPair? right})>[];
    FigureTextPair? pending;
    for (final pair in content.pairs) {
      if (!textUnitPlaceable(pair.caption)) continue;
      final wide =
          pair.figure.size.width > area.width * handoutWideFigureRatio ||
          pair.figure.size.width > halfWidth;
      if (wide) {
        rows.add((wide: pair, left: null, right: null));
      } else if (pending == null) {
        pending = pair;
      } else {
        rows.add((wide: null, left: pending, right: pair));
        pending = null;
      }
    }
    if (pending != null) {
      rows.add((wide: null, left: pending, right: null));
    }

    double cellHeight(FigureTextPair pair) {
      if (!textUnitPlaceable(pair.caption)) return pair.figure.size.height;
      return pair.figure.size.height + gap + _textSlotHeight(
        pair.caption,
        bodyTextOf(pair.caption),
      );
    }

    for (final row in rows) {
      final widePair = row.wide;
      if (widePair != null) {
        final rowHeight = cellHeight(widePair);
        if (y + rowHeight > area.bottom) return null;
        _moveUnit(
          widePair.figure,
          centerX - widePair.figure.size.width / 2,
          y,
          moveDeltas,
          previewRects,
          inkSlotRects,
        );
        placeTextUnit(
          widePair.caption,
          centerX - _textSlotWidth(widePair.caption, bodyTextOf(widePair.caption)) / 2,
          y + widePair.figure.size.height + gap,
        );
        y += rowHeight + gap;
      } else {
        final left = row.left!;
        final right = row.right;
        final leftCaption = bodyTextOf(left.caption);
        var rowHeight = cellHeight(left);
        final rightCaption = right == null ? null : bodyTextOf(right.caption);
        if (right != null && rightCaption != null) {
          rowHeight = math.max(rowHeight, cellHeight(right));
        }
        if (y + rowHeight > area.bottom) return null;
        final leftCenter = area.left + halfWidth / 2;
        final rightCenter = area.left + halfWidth + gap + halfWidth / 2;
        _moveUnit(
          left.figure,
          leftCenter - left.figure.size.width / 2,
          y,
          moveDeltas,
          previewRects,
          inkSlotRects,
        );
        placeTextUnit(
          left.caption,
          leftCenter - _textSlotWidth(left.caption, leftCaption) / 2,
          y + left.figure.size.height + gap,
        );
        if (right != null && rightCaption != null) {
          _moveUnit(
            right.figure,
            rightCenter - right.figure.size.width / 2,
            y,
            moveDeltas,
            previewRects,
            inkSlotRects,
          );
          placeTextUnit(
            right.caption,
            rightCenter - _textSlotWidth(right.caption, rightCaption) / 2,
            y + right.figure.size.height + gap,
          );
        }
        y += rowHeight + gap;
      }
    }

    // 通栏段落流：looseTexts 左对齐；looseFigures 居中附后。
    for (final unit in content.looseTexts) {
      if (!textUnitPlaceable(unit)) continue;
      final slotHeight = _textSlotHeight(unit, bodyTextOf(unit));
      if (y + slotHeight > area.bottom) return null;
      placeTextUnit(unit, area.left, y);
      y += slotHeight + gap;
    }
    for (final unit in content.looseFigures) {
      if (y + unit.size.height > area.bottom) return null;
      _moveUnit(
        unit,
        centerX - unit.size.width / 2,
        y,
        moveDeltas,
        previewRects,
        inkSlotRects,
      );
      y += unit.size.height + gap;
    }

    return SmartLayoutTemplateLayoutResult(
      kind: SmartLayoutTemplateKind.handout,
      addElements: addElements,
      moveDeltas: moveDeltas,
      previewRects: previewRects,
      inkSlotRects: inkSlotRects,
      description:
          '图文讲义：标题 ${content.title == null ? 0 : 1} 处、'
          '图文 ${content.pairs.length} 组、正文 ${content.looseTexts.length} 段、'
          '配图 ${content.looseFigures.length} 张',
      document: _documentOf('handout', addElements, content.pageId),
    );
  }

  // ---------- outline 要点清单 ----------

  /// 标题置顶；文本条目按阅读序排列表（"• "前缀 + 固定行距，v1 无层级缩进；
  /// 保留手写条目为墨迹左对齐、无前缀）；小图（≤ 条目宽 40%）附于最近邻
  /// 条目行右侧（caption 随图），大图独占通栏行。
  /// 图片不缩放（保持原尺寸，不扩 move 协议）。
  static SmartLayoutTemplateLayoutResult? _layoutOutline(
    SmartLayoutContent content,
  ) {
    final area = content.contentArea;
    final addElements = <Element>[];
    final moveDeltas = <ElementId, Offset>{};
    final previewRects = <Rect>[];
    final inkSlotRects = <Rect>[];

    var y = area.top;
    if (content.title != null) {
      final titleUnit = content.title!;
      if (_isInkText(titleUnit)) {
        // 保留手写：标题墨迹左对齐置顶（不做字号放大）。
        if (y + titleUnit.size.height > area.bottom) return null;
        _moveUnit(
          titleUnit,
          area.left,
          y,
          moveDeltas,
          previewRects,
          inkSlotRects,
        );
        y += titleUnit.size.height + outlineRowGap;
      } else {
        final title = _styledTitle(content.title!.textElement!);
        addElements.add(title.copyWith(x: area.left, y: y));
        previewRects.add(Rect.fromLTWH(area.left, y, title.width, title.height));
        y += title.height + outlineRowGap;
      }
    }
    if (y > area.bottom) return null;

    // 阅读序条目流：文本条目与图文组按原稿 top 排序。
    final entries = <({LayoutUnit? text, LayoutUnit? figure, LayoutUnit? caption})>[
      for (final unit in content.looseTexts)
        (text: unit, figure: null, caption: null),
      for (final pair in content.pairs)
        (text: null, figure: pair.figure, caption: pair.caption),
      for (final unit in content.looseFigures)
        (text: null, figure: unit, caption: null),
    ]..sort((a, b) {
      final aBounds = (a.text ?? a.figure)!.sourceBounds;
      final bBounds = (b.text ?? b.figure)!.sourceBounds;
      final byTop = aBounds.top.compareTo(bBounds.top);
      return byTop != 0 ? byTop : aBounds.left.compareTo(bBounds.left);
    });

    // 小图挂靠：按原稿中心找最近文本条目（曼哈顿距离，确定性），一行至多一图。
    final sideFigureByText = <int, int>{};
    final attachedFigures = <int>{};
    for (var f = 0; f < entries.length; f++) {
      final figure = entries[f].figure;
      if (figure == null ||
          figure.size.width > area.width * outlineSideFigureMaxWidthRatio) {
        continue;
      }
      int? bestText;
      var bestDistance = double.infinity;
      for (var t = 0; t < entries.length; t++) {
        if (entries[t].text == null) continue;
        if (sideFigureByText.containsValue(t)) continue;
        final center = entries[t].text!.sourceBounds.center;
        final distance =
            (center.dy - figure.sourceBounds.center.dy).abs() +
            (center.dx - figure.sourceBounds.center.dx).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          bestText = t;
        }
      }
      if (bestText != null) {
        sideFigureByText[bestText] = f;
        attachedFigures.add(f);
      }
    }

    for (var e = 0; e < entries.length; e++) {
      final entry = entries[e];
      final text = entry.text;
      if (text != null) {
        // 印刷体条目加"• "前缀；保留手写条目为墨迹左对齐、无前缀。
        final bulletElement = _isInkText(text) ? null : _outlineBullet(text);
        if (!_isInkText(text) && bulletElement == null) continue;
        final rowTextHeight = bulletElement?.height ?? text.size.height;
        var rowHeight = rowTextHeight;
        final sideIndex = sideFigureByText[e];
        if (sideIndex != null) {
          final side = entries[sideIndex];
          rowHeight = math.max(
            rowHeight,
            side.figure!.size.height +
                8 +
                _textSlotHeight(side.caption, side.caption?.textElement),
          );
        }
        if (y + rowHeight > area.bottom) return null;
        if (bulletElement != null) {
          addElements.add(bulletElement.copyWith(x: area.left, y: y));
          previewRects.add(
            Rect.fromLTWH(area.left, y, bulletElement.width, bulletElement.height),
          );
        } else {
          _moveUnit(text, area.left, y, moveDeltas, previewRects, inkSlotRects);
        }
        var rowBottom = y + rowTextHeight;
        if (sideIndex != null) {
          rowBottom = math.max(
            rowBottom,
            _placeSideFigure(
              entries[sideIndex],
              y,
              area,
              addElements,
              moveDeltas,
              previewRects,
              inkSlotRects,
            ),
          );
        }
        y = rowBottom + outlineRowGap;
      } else {
        if (attachedFigures.contains(e)) continue; // 已挂靠条目行
        final figure = entry.figure!;
        if (y + figure.size.height > area.bottom) return null;
        _moveUnit(figure, area.left, y, moveDeltas, previewRects, inkSlotRects);
        var rowBottom = y + figure.size.height;
        final caption = entry.caption;
        if (caption != null) {
          final captionY = rowBottom + 8;
          if (_isInkText(caption)) {
            // 保留手写：图注墨迹随图下方。
            _moveUnit(
              caption,
              area.left,
              captionY,
              moveDeltas,
              previewRects,
              inkSlotRects,
            );
            rowBottom = captionY + caption.size.height;
          } else if (caption.textElement != null) {
            final captionElement = caption.textElement!;
            addElements.add(captionElement.copyWith(x: area.left, y: captionY));
            previewRects.add(
              Rect.fromLTWH(
                area.left,
                captionY,
                captionElement.width,
                captionElement.height,
              ),
            );
            rowBottom = captionY + captionElement.height;
          }
        }
        y = rowBottom + outlineRowGap;
      }
    }

    return SmartLayoutTemplateLayoutResult(
      kind: SmartLayoutTemplateKind.outline,
      addElements: addElements,
      moveDeltas: moveDeltas,
      previewRects: previewRects,
      inkSlotRects: inkSlotRects,
      description:
          '要点清单：标题 ${content.title == null ? 0 : 1} 处、'
          '条目 ${content.looseTexts.length} 条、配图 ${content.pairs.length + content.looseFigures.length} 张',
      document: _documentOf('outline', addElements, content.pageId),
    );
  }

  /// outline 印刷体条目的"• "前缀元素（按测量值撑宽）。
  static TextElement? _outlineBullet(LayoutUnit unit) {
    final element0 = unit.textElement;
    if (element0 == null) return null;
    final bullet = element0.copyWithText(text: '• ${element0.text}');
    final (mw, mh) = TextRenderer.measure(bullet);
    return bullet.copyWith(
      width: math.max(bullet.width, mw),
      height: math.max(bullet.height, mh),
    );
  }

  /// 条目行右侧放置小图（右对齐内容区），caption 随图在下；返回行底 y。
  static double _placeSideFigure(
    ({LayoutUnit? text, LayoutUnit? figure, LayoutUnit? caption}) entry,
    double rowY,
    Rect area,
    List<Element> addElements,
    Map<ElementId, Offset> moveDeltas,
    List<Rect> previewRects,
    List<Rect> inkSlotRects,
  ) {
    final figure = entry.figure!;
    final figureX = area.right - figure.size.width;
    _moveUnit(figure, figureX, rowY, moveDeltas, previewRects, inkSlotRects);
    var rowBottom = rowY + figure.size.height;
    final caption = entry.caption;
    if (caption != null) {
      final captionY = rowBottom + 8;
      if (_isInkText(caption)) {
        _moveUnit(
          caption,
          figureX,
          captionY,
          moveDeltas,
          previewRects,
          inkSlotRects,
        );
        rowBottom = captionY + caption.size.height;
      } else if (caption.textElement != null) {
        final captionElement = caption.textElement!;
        addElements.add(captionElement.copyWith(x: figureX, y: captionY));
        previewRects.add(
          Rect.fromLTWH(
            figureX,
            captionY,
            captionElement.width,
            captionElement.height,
          ),
        );
        rowBottom = captionY + captionElement.height;
      }
    }
    return rowBottom;
  }

  // ---------- inplace 原文整理 ----------

  /// 文本以原稿并集框中心原位替换（零风险兜底）；保留手写时文本墨迹完全
  /// 不动（仅预览占位）；图/形/组一律不动。
  static SmartLayoutTemplateLayoutResult? _layoutInPlace(
    SmartLayoutContent content,
  ) {
    final addElements = <Element>[];
    final previewRects = <Rect>[];
    final inkSlotRects = <Rect>[];
    final keepInk = content.textUnits.any(_isInkText);
    var placedTextCount = 0;
    void replaceInPlace(LayoutUnit unit) {
      if (_isInkText(unit)) {
        // 保留手写：文本墨迹完全不动，仅预览其占位。
        previewRects.add(unit.sourceBounds);
        inkSlotRects.add(unit.sourceBounds);
        placedTextCount++;
        return;
      }
      final text = unit.textElement;
      if (text == null) return;
      final x = unit.sourceBounds.center.dx - text.width / 2;
      final y = unit.sourceBounds.center.dy - text.height / 2;
      addElements.add(text.copyWith(x: x, y: y));
      previewRects.add(Rect.fromLTWH(x, y, text.width, text.height));
      placedTextCount++;
    }

    if (content.title != null) replaceInPlace(content.title!);
    for (final pair in content.pairs) {
      replaceInPlace(pair.caption);
    }
    for (final unit in content.looseTexts) {
      replaceInPlace(unit);
    }
    if (addElements.isEmpty && previewRects.isEmpty) return null;
    return SmartLayoutTemplateLayoutResult(
      kind: SmartLayoutTemplateKind.inplace,
      addElements: addElements,
      moveDeltas: const {},
      previewRects: previewRects,
      inkSlotRects: inkSlotRects,
      // 保留手写模式无转写：文字保持手写原样，仅整页说明。
      description: keepInk
          ? '原文整理：手写原样保留，图与形保持原位'
          : '原文整理：转写 $placedTextCount 处文字，图与形保持原位',
      document: _documentOf('inplace', addElements, content.pageId),
    );
  }
}
