import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

import 'package:flow_muse/shared/widgets/app_spacing.dart';

/// 模板选择卡：识别完成后展示三张模板卡，每卡用本页真实内容按该模板
/// 预落位的结果渲染缩略图（所见即所得）；点选后进入既有草稿态，
/// 关闭即取消（零残留）。放不下的模板置灰并标注；三卡全放不下时给出
/// 分页提示。多页流程提供"跳过本页"（[allowSkip]），避免一页超容终止整单。
/// 窄屏（可用宽度 < 560）时三卡改纵向铺满列表，避免横排拥挤。
///
/// [onKeepHandwritingChanged] 非 null 时卡片区顶部展示"转写为印刷体 /
/// 保留手写笔迹"分段开关：保留手写模式下缩略图切换为
/// [SmartLayoutTemplatePreparation.layoutsKeepInk] 的预落位结果（缺项/
/// 为 null = 该模板该模式下放不下，置灰标注"该模式下放不下"）。
typedef SmartLayoutTemplateChoice = ({SmartLayoutTemplateKind? kind, bool skipped});

Future<SmartLayoutTemplateChoice?> showSmartLayoutTemplateSheet({
  required BuildContext context,
  required SmartLayoutTemplatePreparation preparation,
  bool allowSkip = false,
  bool keepHandwriting = false,
  ValueChanged<bool>? onKeepHandwritingChanged,
}) {
  return showModalBottomSheet<SmartLayoutTemplateChoice>(
    context: context,
    builder: (sheetContext) => SmartLayoutTemplateSheet(
      preparation: preparation,
      allowSkip: allowSkip,
      keepHandwriting: keepHandwriting,
      onKeepHandwritingChanged: onKeepHandwritingChanged,
    ),
  );
}

/// 模板适用场景说明（本地静态映射，不进引擎枚举）。
const Map<SmartLayoutTemplateKind, String> _templateDescriptions = {
  SmartLayoutTemplateKind.handout: '标题与图文成组编排，适合讲义式整理',
  SmartLayoutTemplateKind.outline: '条目式清单，配图随就近条目走',
  SmartLayoutTemplateKind.inplace: '仅转写文字，版式保持原样',
};

class SmartLayoutTemplateSheet extends StatefulWidget {
  const SmartLayoutTemplateSheet({
    super.key,
    required this.preparation,
    this.allowSkip = false,
    this.keepHandwriting = false,
    this.onKeepHandwritingChanged,
  });

  final SmartLayoutTemplatePreparation preparation;

  /// true = 多页流程：底栏提供"跳过本页"（本页不排版，继续下一页）。
  final bool allowSkip;

  /// 初始是否保留手写笔迹（开关仅在 [onKeepHandwritingChanged] 非 null 时展示）。
  final bool keepHandwriting;

  /// 保留手写开关回调；null = 隐藏开关（向后兼容既有调用点）。
  final ValueChanged<bool>? onKeepHandwritingChanged;

  @override
  State<SmartLayoutTemplateSheet> createState() =>
      _SmartLayoutTemplateSheetState();
}

class _SmartLayoutTemplateSheetState extends State<SmartLayoutTemplateSheet> {
  late bool _keepHandwriting = widget.keepHandwriting;

  /// 当前模式下的预落位结果：保留手写取 layoutsKeepInk，否则取 layouts。
  SmartLayoutTemplateLayoutResult? _layoutFor(SmartLayoutTemplateKind kind) =>
      _keepHandwriting
          ? widget.preparation.layoutsKeepInk[kind]
          : widget.preparation.layouts[kind];

  void _handleKeepHandwritingChanged(bool value) {
    if (value == _keepHandwriting) return;
    setState(() => _keepHandwriting = value);
    widget.onKeepHandwritingChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDisabled = SmartLayoutTemplateKind.values.every(
      (kind) => _layoutFor(kind) == null,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        // 窄屏下三卡纵向列表会超出弹层最大高度：整体可滚动，避免 RenderFlex 溢出。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择排版模板',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '取消',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                'AI 已识别本页内容，点选一个模板进入预览（可拖动微调后再确认）。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (allDisabled) ...[
                const SizedBox(height: 8),
                Text(
                  widget.allowSkip
                      ? '本页内容超出所有模板的容量，请分页后再试，或点下方"跳过本页"继续后续页。'
                      : '本页内容超出所有模板的容量，请分页后再试。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (widget.onKeepHandwritingChanged != null) ...[
                const SizedBox(height: AppSpacing.controlGap),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('转写为印刷体')),
                      ButtonSegment(value: true, label: Text('保留手写笔迹')),
                    ],
                    selected: {_keepHandwriting},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        _handleKeepHandwritingChanged(selection.first),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final disabledHint = _keepHandwriting ? '该模式下放不下' : '内容放不下';
                  final cards = [
                    for (final kind in SmartLayoutTemplateKind.values)
                      _TemplateCard(
                        kind: kind,
                        layout: _layoutFor(kind),
                        content: widget.preparation.content,
                        disabledHint: disabledHint,
                      ),
                  ];
                  // 窄屏断点：可用宽度放不下三卡横排时改纵向铺满列表，
                  // 点选/置灰逻辑不变（卡本身自适应宽度）。
                  if (constraints.maxWidth < _wideLayoutBreakpoint) {
                    return Column(
                      children: [
                        for (var i = 0; i < cards.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          SizedBox(width: double.infinity, child: cards[i]),
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: cards[i]),
                      ],
                    ],
                  );
                },
              ),
              if (widget.allowSkip)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop((kind: null, skipped: true)),
                    child: const Text('跳过本页'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 横排三卡的最低可用宽度（每卡缩略图 + 间距 + 内边距）。
  static const double _wideLayoutBreakpoint = 560;
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.kind,
    required this.layout,
    required this.content,
    required this.disabledHint,
  });

  final SmartLayoutTemplateKind kind;
  final SmartLayoutTemplateLayoutResult? layout;
  final SmartLayoutContent content;

  /// 放不下时缩略图占位文案（保留手写模式下为"该模式下放不下"）。
  final String disabledHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = this.layout;
    final enabled = layout != null;
    return InkWell(
      onTap: enabled
          ? () => Navigator.of(context).pop((kind: kind, skipped: false))
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surface,
              ),
              child: SizedBox(
                key: ValueKey('template-thumb-${kind.name}'),
                height: 168,
                width: double.infinity,
                child: layout == null
                    ? Center(
                        child: Text(
                          disabledHint,
                          style: theme.textTheme.labelSmall,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : CustomPaint(
                        painter: _TemplateThumbnailPainter(
                          layout: layout,
                          content: content,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              kind.displayName,
              style: theme.textTheme.labelLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              _templateDescriptions[kind] ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 缩略图落位框种类：印刷体文本框（蓝调）、图/形/组（灰调 + "图"角标）、
/// 保留手写模式的墨迹占位（灰调、无角标——它是文字不是图）。
enum _ThumbnailBoxKind { text, figure, inkText }

/// 模板卡缩略图：按预落位结果画文本实貌与图形容器（场景坐标 → 卡片缩放）。
///
/// 几何与预落位结果严格同源（不重算布局）：落位框直接取 previewRects，
/// 依"新增文本元素矩形（与 addElements 同几何）"差集区分文本框与移动类框。
/// 文本字号设 9 逻辑像素下限：不足时放大绘制，宽度超出落位框省略截断、
/// 行数以落位框放得下为准——内容过多时宁少画不糊。
class _TemplateThumbnailPainter extends CustomPainter {
  _TemplateThumbnailPainter({
    required this.layout,
    required this.content,
  }) : texts = [
         for (final element in layout.addElements)
           if (element is TextElement) element,
       ],
       boxes = _classifyBoxes(layout, content);

  /// 缩略图内文本/角标的屏幕字号下限（逻辑像素）。
  static const double _minOnScreenFontSize = 9;

  final SmartLayoutTemplateLayoutResult layout;
  final List<TextElement> texts;
  final SmartLayoutContent content;
  final List<(_ThumbnailBoxKind, Rect)> boxes;

  /// 最近一次 paint 的观测值（各行屏幕字号 / 触发省略的文本数），仅供测试
  /// 做几何断言，不参与渲染决策。
  final List<double> paintedOnScreenFontSizes = [];
  int paintedTruncatedTextCount = 0;

  /// 落位框分类：新增文本元素矩形为文本框；移动类框按尺寸匹配 content
  /// 文本单元原稿包围盒（保留手写变体的墨迹占位尺寸 == 原稿包围盒尺寸）
  /// 区分为墨迹占位与图/形/组。
  static List<(_ThumbnailBoxKind, Rect)> _classifyBoxes(
    SmartLayoutTemplateLayoutResult layout,
    SmartLayoutContent content,
  ) {
    final textRects = {
      for (final element in layout.addElements)
        if (element is TextElement)
          Rect.fromLTWH(element.x, element.y, element.width, element.height),
    };
    final inkSlotSizes = [
      for (final unit in _textUnitsOf(content))
        Size(unit.sourceBounds.width, unit.sourceBounds.height),
    ];
    bool isInkSlot(Rect rect) => inkSlotSizes.any(
      (size) =>
          (size.width - rect.width).abs() < 0.5 &&
          (size.height - rect.height).abs() < 0.5,
    );
    return [
      for (final rect in layout.previewRects)
        if (textRects.contains(rect))
          (_ThumbnailBoxKind.text, rect)
        else if (isInkSlot(rect))
          (_ThumbnailBoxKind.inkText, rect)
        else
          (_ThumbnailBoxKind.figure, rect),
    ];
  }

  static Iterable<LayoutUnit> _textUnitsOf(SmartLayoutContent content) sync* {
    final title = content.title;
    if (title != null) yield title;
    yield* content.looseTexts;
    for (final pair in content.pairs) {
      yield pair.caption;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    paintedOnScreenFontSizes.clear();
    paintedTruncatedTextCount = 0;
    var bounds = content.contentArea;
    for (final (_, rect) in boxes) {
      bounds = bounds.expandToInclude(rect);
    }
    bounds = bounds.inflate(8);
    if (bounds.width <= 0 || bounds.height <= 0) return;
    final scale = math.min(
      size.width / bounds.width,
      size.height / bounds.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - bounds.width * scale) / 2,
      (size.height - bounds.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);

    final textFill = Paint()..color = const Color(0x143B82F6);
    final textStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale
      ..color = const Color(0x663B82F6);
    final figureFill = Paint()..color = const Color(0x141F2937);
    final figureStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale
      ..color = const Color(0x3D1F2937);

    final figureRects = <Rect>[];
    for (final (kind, rect) in boxes) {
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(4 / scale));
      switch (kind) {
        case _ThumbnailBoxKind.text:
          canvas.drawRRect(rrect, textFill);
          canvas.drawRRect(rrect, textStroke);
        case _ThumbnailBoxKind.figure:
          canvas.drawRRect(rrect, figureFill);
          canvas.drawRRect(rrect, figureStroke);
          figureRects.add(rect);
        case _ThumbnailBoxKind.inkText:
          canvas.drawRRect(rrect, figureFill);
          canvas.drawRRect(rrect, figureStroke);
      }
    }
    for (final text in texts) {
      // 字号下限：落位字号换算到屏幕不足 9 逻辑像素时放大到 9；行数按
      // 落位框高"放得下为准"，宽度超出落位框省略截断（宁少画不糊）。
      final fontSize = math.max(text.fontSize, _minOnScreenFontSize / scale);
      final lineExtent = fontSize * text.lineHeight;
      final maxWidth = math.max(text.width, 24.0);
      final painter = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(
            fontSize: fontSize,
            height: text.lineHeight,
            color: const Color(0xFF1F2937),
            fontFamily: text.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: math.max(1, text.height ~/ lineExtent),
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      painter.paint(canvas, Offset(text.x, text.y));
      paintedOnScreenFontSizes.add(fontSize * scale);
      // 截断观测：行数上限截断，或布局宽度贴满约束（超宽省略）。
      if (painter.didExceedMaxLines || painter.width >= maxWidth - 0.001) {
        paintedTruncatedTextCount++;
      }
      painter.dispose();
    }
    for (final rect in figureRects) {
      _drawFigureBadge(canvas, rect, scale);
    }
    canvas.restore();
  }

  /// 图块左上角"图"角标：固定屏幕尺寸（按 scale 折算回场景坐标），保证
  /// 缩放后仍可读。
  void _drawFigureBadge(Canvas canvas, Rect rect, double scale) {
    final painter = TextPainter(
      text: TextSpan(
        text: '图',
        style: TextStyle(
          fontSize: _minOnScreenFontSize / scale,
          height: 1,
          color: const Color(0xFF374151),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final badge = Rect.fromLTWH(
      rect.left + 3 / scale,
      rect.top + 3 / scale,
      painter.width + 4 / scale,
      painter.height + 2 / scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badge, Radius.circular(3 / scale)),
      Paint()..color = const Color(0xFFE5E7EB),
    );
    painter.paint(canvas, Offset(badge.left + 2 / scale, badge.top + 1 / scale));
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _TemplateThumbnailPainter oldDelegate) {
    // 模式切换后 layout 是不同实例（layouts / layoutsKeepInk 两份缓存），
    // 同一实例内几何不变，按实例与数量比较即可。
    return oldDelegate.layout != layout ||
        oldDelegate.content != content ||
        oldDelegate.boxes.length != boxes.length ||
        oldDelegate.texts.length != texts.length;
  }
}
