library;

import 'package:flutter/material.dart' hide Element, SelectionOverlay;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart' hide TextAlign;

/// Shows compact property panel as a bottom sheet.
void showCompactPropertyPanel(
  BuildContext context,
  MarkdrawController controller,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.15,
      maxChildSize: 0.7,
      expand: false,
      builder: (ctx, scrollController) {
        final elements = controller.selectedElements;
        if (elements.isEmpty) return const SizedBox.shrink();

        final isEditingText = controller.editingTextElementId != null;

        final boundText = <TextElement>[];
        for (final e in elements) {
          final bt = controller.editorState.scene.findBoundText(e.id);
          if (bt != null) boundText.add(bt);
        }
        var style = PropertyPanelState.fromElements(
          elements,
          boundTextElements: boundText,
        );
        // When editing bound text, show the text's strokeColor instead of the
        // parent shape's so the color picker reflects the text color.
        if (isEditingText && boundText.length == 1) {
          style = style.copyWith(strokeColor: boundText.first.strokeColor);
        }
        final isLocked = style.locked == true;
        final showFullTextProps =
            style.hasText &&
            (!style.hasArrowBoundText ||
                style.hasShapeBoundText ||
                elements.whereType<TextElement>().isNotEmpty);
        final textOnly = elements.every((e) => e is TextElement);

        final cs = Theme.of(ctx).colorScheme;
        return TextFieldTapRegion(
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).dividerColor,
                      borderRadius: BorderRadius.circular(2),
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
        );
      },
    ),
  );
}
