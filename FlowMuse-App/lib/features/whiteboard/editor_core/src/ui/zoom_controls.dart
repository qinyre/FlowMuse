library;

import 'package:flutter/material.dart';

import 'markdraw_controller.dart';

/// Undo/redo controls used by the editor navigation.
class UndoRedoControls extends StatelessWidget {
  const UndoRedoControls({super.key, required this.controller});

  final MarkdrawController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.undo, size: 16),
          onPressed: controller.undo,
          tooltip: '撤销 (Ctrl+Z)',
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          iconSize: 16,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            hoverColor: cs.surfaceContainerHighest,
            focusColor: cs.surfaceContainerHighest,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.redo, size: 16),
          onPressed: controller.redo,
          tooltip: '重做 (Ctrl+Shift+Z)',
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          iconSize: 16,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            hoverColor: cs.surfaceContainerHighest,
            focusColor: cs.surfaceContainerHighest,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(
            height: 16,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: cs.outlineVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Zoom in/out/reset controls used by the editor navigation.
class ZoomControls extends StatelessWidget {
  final MarkdrawController controller;
  final Size Function() getCanvasSize;

  const ZoomControls({
    super.key,
    required this.controller,
    required this.getCanvasSize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zoomPercent = (controller.editorState.viewport.zoom * 100).round();
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => controller.zoomOut(getCanvasSize()),
            tooltip: '缩小 (Ctrl+\u2212)',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 16,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              hoverColor: cs.surfaceContainerHighest,
              focusColor: cs.surfaceContainerHighest,
            ),
          ),
          Semantics(
            label: '缩放 $zoomPercent%，点击重置',
            button: true,
            child: InkWell(
              onTap: () => controller.resetZoom(),
              borderRadius: BorderRadius.circular(12),
              hoverColor: cs.surfaceContainerHighest,
              focusColor: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '$zoomPercent%',
                  style: TextStyle(fontSize: 12, color: cs.onSurface),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => controller.zoomIn(getCanvasSize()),
            tooltip: '放大 (Ctrl++)',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 16,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              hoverColor: cs.surfaceContainerHighest,
              focusColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
