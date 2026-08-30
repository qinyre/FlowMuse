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
/// 卡片区顶部展示"转写为印刷体 / 保留手写笔迹"分段开关（仅当本页存在
/// 手写转写文本 [SmartLayoutTemplatePreparation.hasInkTextUnits] 且有保留
/// 手写变体 [SmartLayoutTemplatePreparation.layoutsKeepInk] 时）：保留手写
/// 模式下缩略图切换为 layoutsKeepInk 的预落位结果
/// （缺项/为 null = 该模板该模式下放不下，置灰标注"该模式下放不下"）；
/// 开关是弹层内部状态，最终值随选卡经
/// [SmartLayoutTemplateChoice.keepHandwriting] 返回。
typedef SmartLayoutTemplateChoice =
    ({SmartLayoutTemplateKind? kind, bool skipped, bool keepHandwriting});

Future<SmartLayoutTemplateChoice?> showSmartLayoutTemplateSheet({
  required BuildContext context,
  required SmartLayoutTemplatePreparation preparation,
  bool allowSkip = false,
  bool keepHandwriting = false,
}) {
  return showModalBottomSheet<SmartLayoutTemplateChoice>(
    context: context,
    builder: (sheetContext) => SmartLayoutTemplateSheet(
      preparation: preparation,
      allowSkip: allowSkip,
      keepHandwriting: keepHandwriting,
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
  });

  final SmartLayoutTemplatePreparation preparation;

  /// true = 多页流程：底栏提供"跳过本页"（本页不排版，继续下一页）。
  final bool allowSkip;

  /// 初始是否保留手写笔迹（开关仅在本页存在手写转写文本时展示）。
  final bool keepHandwriting;

  @override
  State<SmartLayoutTemplateSheet> createState() =>
      _SmartLayoutTemplateSheetState();
}

class _SmartLayoutTemplateSheetState extends State<SmartLayoutTemplateSheet> {
  late bool _keepHandwriting = widget.keepHandwriting;

  /// 是否展示"转写为印刷体 / 保留手写笔迹"开关：本页存在手写转写文本且
  /// 有保留手写变体才可切换（纯打字/纯图形页没有手写可保留）。
  bool get _showKeepInkSwitch =>
      widget.preparation.hasInkTextUnits &&
      widget.preparation.layoutsKeepInk.isNotEmpty;

  /// 当前模式下的预落位结果：保留手写取 layoutsKeepInk，否则取 layouts。
  SmartLayoutTemplateLayoutResult? _layoutFor(SmartLayoutTemplateKind kind) =>
      _keepHandwriting
          ? widget.preparation.layoutsKeepInk[kind]
          : widget.preparation.layouts[kind];

  /// 返回值携带当前开关状态，选卡后由调用方读取。
  void _handleKeepHandwritingChanged(bool value) {
    if (value == _keepHandwriting) return;
    setState(() => _keepHandwriting = value);
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
              if (_showKeepInkSwitch) ...[
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
                        keepHandwriting: _keepHandwriting,
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
                    onPressed: () => Navigator.of(context).pop(
                      (
                        kind: null,
                        skipped: true,
                        keepHandwriting: _keepHandwriting,
                      ),
                    ),
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
    required this.keepHandwriting,
  });

  final SmartLayoutTemplateKind kind;
  final SmartLayoutTemplateLayoutResult? layout;
  final SmartLayoutContent content;

  /// 放不下时缩略图占位文案（保留手写模式下为"该模式下放不下"）。
  final String disabledHint;

  /// 选卡时随返回值带回的当前开关状态。
  final bool keepHandwriting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = this.layout;
    final enabled = layout != null;
    return InkWell(
      onTap: enabled
          ? () => Navigator.of(context).pop(
              (kind: kind, skipped: false, keepHandwriting: keepHandwriting),
            )
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

/// 缩略图内文本/角标的屏幕字号下限（逻辑像素）。
const double kSmartLayoutThumbMinOnScreenFontSize = 9;

/// 缩略图文本屏幕字号：落位字号换算到屏幕不足下限时放大到下限（纯函数，
/// 与 paint 同源，测试直测）。
double smartLayoutThumbFontSize(double layoutFontSize, double scale) =>
    math.max(layoutFontSize, kSmartLayoutThumbMinOnScreenFontSize / scale);

/// 缩略图文本行数上限：落位框高在当前字号行高下"放得下为准"，
/// 至少 1 行（纯函数，与 paint 同源，测试直测）。
int smartLayoutThumbMaxLines({
  required double slotHeight,
  required double fontSize,
  required double lineHeight,
}) => math.max(1, slotHeight ~/ (fontSize * lineHeight));

/// 模板卡缩略图：按预落位结果画文本实貌与图形容器（场景坐标 → 卡片缩放）。
///
/// 几何与预落位结果严格同源（不重算布局）：落位框直接取 previewRects，
/// 新增文本元素矩形为文本框、结果自带的墨迹占位矩形（inkSlotRects）查表
/// 得墨迹占位，其余为图/形/组。文本字号按 [smartLayoutThumbFontSize] 设
/// 屏幕下限，宽度超出落位框省略截断、行数按 [smartLayoutThumbMaxLines]
/// ——内容过多时宁少画不糊。
class _TemplateThumbnailPainter extends CustomPainter {
  _TemplateThumbnailPainter({
    required this.layout,
    required this.content,
  }) : texts = [
         for (final element in layout.addElements)
           if (element is TextElement) element,
       ],
       boxes = _classifyBoxes(layout);

  final SmartLayoutTemplateLayoutResult layout;
  final List<TextElement> texts;
  final SmartLayoutContent content;
  final List<(_ThumbnailBoxKind, Rect)> boxes;

  /// 落位框分类：新增文本元素矩形为文本框；结果自带的墨迹占位矩形
  /// （inkSlotRects）为墨迹占位；其余为图/形/组。不做任何尺寸匹配猜测。
  static List<(_ThumbnailBoxKind, Rect)> _classifyBoxes(
    SmartLayoutTemplateLayoutResult layout,
  ) {
    final textRects = {
      for (final element in layout.addElements)
        if (element is TextElement)
          Rect.fromLTWH(element.x, element.y, element.width, element.height),
    };
    final inkSlotRects = layout.inkSlotRects.toSet();
    return [
      for (final rect in layout.previewRects)
        if (textRects.contains(rect))
          (_ThumbnailBoxKind.text, rect)
        else if (inkSlotRects.contains(rect))
          (_ThumbnailBoxKind.inkText, rect)
        else
          (_ThumbnailBoxKind.figure, rect),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
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
      final fontSize = smartLayoutThumbFontSize(text.fontSize, scale);
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
        maxLines: smartLayoutThumbMaxLines(
          slotHeight: text.height,
          fontSize: fontSize,
          lineHeight: text.lineHeight,
        ),
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      painter.paint(canvas, Offset(text.x, text.y));
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
          fontSize: kSmartLayoutThumbMinOnScreenFontSize / scale,
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
