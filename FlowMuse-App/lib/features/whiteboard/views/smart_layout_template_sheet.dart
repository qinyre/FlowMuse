import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

/// 模板选择卡：识别完成后展示三张模板卡，每卡用本页真实内容按该模板
/// 预落位的结果渲染缩略图（所见即所得）；点选后进入既有草稿态，
/// 关闭即取消（零残留）。放不下的模板置灰并标注；三卡全放不下时给出
/// 分页提示。多页流程提供"跳过本页"（[allowSkip]），避免一页超容终止整单。
/// 窄屏（可用宽度 < 560）时三卡改纵向铺满列表，避免横排拥挤。
typedef SmartLayoutTemplateChoice = ({SmartLayoutTemplateKind? kind, bool skipped});

Future<SmartLayoutTemplateChoice?> showSmartLayoutTemplateSheet({
  required BuildContext context,
  required SmartLayoutTemplatePreparation preparation,
  bool allowSkip = false,
}) {
  return showModalBottomSheet<SmartLayoutTemplateChoice>(
    context: context,
    builder: (sheetContext) => SmartLayoutTemplateSheet(
      preparation: preparation,
      allowSkip: allowSkip,
    ),
  );
}

class SmartLayoutTemplateSheet extends StatelessWidget {
  const SmartLayoutTemplateSheet({
    super.key,
    required this.preparation,
    this.allowSkip = false,
  });

  final SmartLayoutTemplatePreparation preparation;

  /// true = 多页流程：底栏提供"跳过本页"（本页不排版，继续下一页）。
  final bool allowSkip;

  /// 横排三卡的最低可用宽度（每卡缩略图 + 间距 + 内边距）。
  static const double _wideLayoutBreakpoint = 560;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDisabled = SmartLayoutTemplateKind.values.every(
      (kind) => preparation.layouts[kind] == null,
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
                  '本页内容超出所有模板的容量，请分页后再试（可关闭后选择"跳过本页"继续）。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cards = [
                    for (final kind in SmartLayoutTemplateKind.values)
                      _TemplateCard(
                        kind: kind,
                        layout: preparation.layouts[kind],
                        content: preparation.content,
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
              if (allowSkip)
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
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.kind,
    required this.layout,
    required this.content,
  });

  final SmartLayoutTemplateKind kind;
  final SmartLayoutTemplateLayoutResult? layout;
  final SmartLayoutContent content;

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
                          '内容放不下',
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
          ],
        ),
      ),
    );
  }
}

/// 模板卡缩略图：按预落位结果画文本实貌与图形容器（场景坐标 → 卡片缩放）。
class _TemplateThumbnailPainter extends CustomPainter {
  _TemplateThumbnailPainter({
    required SmartLayoutTemplateLayoutResult layout,
    required this.content,
  }) : texts = [
         for (final element in layout.addElements)
           if (element is TextElement) element,
       ],
       previewRects = layout.previewRects;

  final List<TextElement> texts;
  final List<Rect> previewRects;
  final SmartLayoutContent content;

  @override
  void paint(Canvas canvas, Size size) {
    var bounds = content.contentArea;
    for (final rect in previewRects) {
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

    final fill = Paint()..color = const Color(0x143B82F6);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale
      ..color = const Color(0x663B82F6);
    for (final rect in previewRects) {
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(4 / scale),
      );
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
    }
    for (final text in texts) {
      final painter = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(
            fontSize: text.fontSize,
            height: text.lineHeight,
            color: const Color(0xFF1F2937),
            fontFamily: text.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 4,
        ellipsis: '…',
      )..layout(maxWidth: math.max(text.width, 24));
      painter.paint(canvas, Offset(text.x, text.y));
      painter.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TemplateThumbnailPainter oldDelegate) {
    return oldDelegate.texts.length != texts.length ||
        oldDelegate.previewRects.length != previewRects.length;
  }
}
