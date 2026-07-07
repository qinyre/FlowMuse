library;

import 'package:flutter/material.dart';

import 'color_picker.dart' as cp;
import 'color_utils.dart' show canvasBackgroundPresets;
import 'markdraw_controller.dart';

/// Canvas background color picker row.
class CanvasBackgroundPicker extends StatelessWidget {
  final MarkdrawController controller;
  final List<String>? presets;
  final bool dismissOnTap;

  const CanvasBackgroundPicker({
    super.key,
    required this.controller,
    this.presets,
    this.dismissOnTap = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgPresets = presets ?? canvasBackgroundPresets;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text('Background', style: TextStyle(color: cs.onSurface)),
          const Spacer(),
          for (final c in bgPresets)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: cp.ColorSwatch(
                color: c,
                isSelected: controller.canvasBackgroundColor == c,
                onTap: () {
                  controller.canvasBackgroundColor = c;
                  if (dismissOnTap) Navigator.of(context).pop();
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              color: Theme.of(context).dividerColor,
            ),
          ),
          cp.ColorPickerButton(
            color: controller.canvasBackgroundColor,
            isActive: !bgPresets.contains(controller.canvasBackgroundColor),
            onColorSelected: (c) {
              controller.canvasBackgroundColor = c;
            },
          ),
        ],
      ),
    );
  }
}
