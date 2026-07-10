library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../markdraw.dart' hide TextAlign;

/// Returns a widget for the given tool type.
Widget iconWidgetFor(
  ToolType type, {
  Color? color,
  double? size,
  bool isActive = false,
}) {
  final s = size ?? 24;
  if (type == ToolType.diamond) {
    return CustomPaint(
      size: Size(s, s),
      painter: DiamondIconPainter(
        color: color ?? Colors.grey.shade800,
        filled: isActive,
      ),
    );
  }
  return Icon(
    iconFor(type, isActive: isActive),
    color: color,
    size: s,
  );
}

/// Returns the [IconData] for a given [ToolType].
IconData iconFor(ToolType type, {bool isActive = false}) {
  return switch (type) {
    ToolType.select => Icons.near_me,
    ToolType.rectangle => isActive ? Icons.rectangle : Icons.rectangle_outlined,
    ToolType.ellipse => isActive ? Icons.circle : Icons.circle_outlined,
    ToolType.diamond => Icons.square_outlined,
    ToolType.line => Icons.show_chart,
    ToolType.arrow => Icons.arrow_forward,
    ToolType.freedraw => Icons.draw,
    ToolType.text => Icons.text_fields,
    ToolType.hand => Icons.pan_tool_outlined,
    ToolType.frame => Icons.crop_free,
    ToolType.eraser => Symbols.ink_eraser,
    ToolType.laser => Icons.flashlight_on,
  };
}
