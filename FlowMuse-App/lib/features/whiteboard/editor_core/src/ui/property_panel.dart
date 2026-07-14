library;

import 'package:flutter/material.dart' hide Element, SelectionOverlay;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart' hide TextAlign;

/// Desktop floating property panel (left side).
class PropertyPanel extends StatelessWidget {
  final MarkdrawController controller;
  final VoidCallback? onCollapse;
  final bool dockOnRight;

  const PropertyPanel({
    super.key,
    required this.controller,
    this.onCollapse,
    this.dockOnRight = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final elements = controller.selectedElements;
    final isEditingText = controller.editingTextElementId != null;

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
        width: 200,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.17),
              blurRadius: 1,
            ),
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 3,
            ),
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (onCollapse != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        dockOnRight
                            ? Icons.keyboard_arrow_right
                            : Icons.keyboard_arrow_left,
                      ),
                      tooltip: '收起属性面板',
                      onPressed: onCollapse,
                    ),
                  ),
                ),
              PropertyPanelContent(
                controller: controller,
                style: style,
                elements: elements,
                isLocked: isLocked,
                showFullTextProps: showFullTextProps,
                isEditingText: isEditingText,
                textOnly: textOnly,
                canvasSize: MediaQuery.of(context).size,
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
