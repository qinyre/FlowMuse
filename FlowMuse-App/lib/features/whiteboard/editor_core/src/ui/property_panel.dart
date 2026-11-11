library;

import 'package:flutter/material.dart' hide Element, SelectionOverlay;
import 'package:flow_muse/shared/widgets/app_spacing.dart';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

/// Desktop floating property panel (left side).
class PropertyPanel extends StatelessWidget {
  final MarkdrawController controller;
  final VoidCallback? onCollapse;
  final bool dockOnRight;
  final bool expand;
  final ({String attributionLabel, String actionLabel, VoidCallback onPressed})?
  Function(Element element)?
  attributionActionResolver;

  final Map<String, VoidCallback> selectionActions;

  const PropertyPanel({
    super.key,
    required this.controller,
    this.onCollapse,
    this.dockOnRight = false,
    this.expand = false,
    this.attributionActionResolver,
    this.selectionActions = const {},
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final elements = controller.selectedElements;
    final inkOnly =
        elements.isNotEmpty && elements.every((e) => e is FreedrawElement);
    final isEditingText = controller.editingTextElementId != null;
    final activeTool = controller.editorState.activeToolType;
    final title = switch (elements.length) {
      0 => activeTool == ToolType.freedraw ? '自由绘制' : '工具属性',
      1 => inkOnly ? '笔迹属性' : '选区属性',
      _ => inkOnly ? '笔迹属性' : '已选 ${elements.length} 项',
    };

    ElementStyle style;
    bool isLocked;
    bool showFullTextProps;
    bool textOnly = false;

    if (elements.isNotEmpty) {
      final boundText = <TextElement>[];
      for (final e in elements) {
        final bt = controller.editorState.scene.findBoundText(e.id);
        if (bt != null) boundText.add(bt);
      }
      style = PropertyPanelState.fromElements(
        elements,
        boundTextElements: boundText,
      );
      // When editing bound text, show the text's strokeColor instead of the
      // parent shape's so the color picker reflects the text color.
      if (isEditingText && boundText.length == 1) {
        style = style.copyWith(strokeColor: boundText.first.strokeColor);
      }
      isLocked = style.locked == true;
      showFullTextProps =
          style.hasText &&
          (!style.hasArrowBoundText ||
              style.hasShapeBoundText ||
              elements.whereType<TextElement>().isNotEmpty);
      textOnly = elements.every((e) => e is TextElement);
    } else if (controller.isCreationTool) {
      final ds = controller.defaultStyle;
      style = ElementStyle(
        strokeColor: ds.strokeColor,
        backgroundColor: ds.backgroundColor,
        strokeWidth: ds.strokeWidth,
        strokeStyle: ds.strokeStyle,
        fillStyle: ds.fillStyle,
        roughness: ds.roughness,
        opacity: ds.opacity,
        fontSize: ds.fontSize,
        fontFamily: ds.fontFamily,
        textAlign: ds.textAlign,
        verticalAlign: ds.verticalAlign,
        startArrowhead: ds.startArrowhead,
        endArrowhead: ds.endArrowhead,
        arrowType: ds.arrowType,
        roundness: ds.roundness,
        hasText: _toolHasText(controller.editorState.activeToolType),
        hasLines: _toolHasLines(controller.editorState.activeToolType),
        hasArrows: _toolHasArrows(controller.editorState.activeToolType),
        hasRoundness: _toolHasRoundness(controller.editorState.activeToolType),
      );
      isLocked = false;
      showFullTextProps = style.hasText;
      textOnly = style.hasText;
    } else {
      return const SizedBox.shrink();
    }

    return TextFieldTapRegion(
      child: Container(
        width: 232,
        constraints: BoxConstraints(minHeight: elements.isEmpty ? 360 : 480),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Column(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (onCollapse != null)
                Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    border: Border(
                      bottom: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      HoverTooltip(
                        message: '收起属性面板',
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            dockOnRight
                                ? Icons.keyboard_arrow_right
                                : Icons.keyboard_arrow_left,
                          ),
                          onPressed: onCollapse,
                        ),
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(AppSpacing.sidebarInset),
                  children: [
                    PropertyPanelContent(
                      controller: controller,
                      comfortable: true,
                      style: style,
                      elements: elements,
                      isLocked: isLocked,
                      showFullTextProps: showFullTextProps,
                      isEditingText: isEditingText,
                      textOnly: textOnly,
                      canvasSize: controller.canvasSize,
                      attributionActionResolver: attributionActionResolver,
                      selectionActions: selectionActions,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _toolHasText(ToolType type) => type == ToolType.text;

  static bool _toolHasLines(ToolType type) =>
      type == ToolType.line || type == ToolType.arrow;

  static bool _toolHasArrows(ToolType type) => type == ToolType.arrow;

  static bool _toolHasRoundness(ToolType type) =>
      type == ToolType.rectangle || type == ToolType.diamond;
}
