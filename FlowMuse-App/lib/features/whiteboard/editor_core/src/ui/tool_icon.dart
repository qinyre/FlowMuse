library;

import 'package:flutter/material.dart';

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
  if (type == ToolType.eraser) {
    return CustomPaint(
      size: Size(s, s),
      painter: EraserIconPainter(color: color ?? Colors.grey.shade800),
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
    // 橡皮由 [iconWidgetFor] 自绘（EraserIconPainter），此处仅兜底编译，
    // 不会展示。不用 material_symbols_icons：该字体家族在本构建管线
    // 不可靠——release tree-shaking 曾静默丢字形（ink_highlighter 包内
    // 图标表与字体版本错位；ink_eraser 在增量构建中丢字形），真机渲染
    // 为 .notdef 实心块。
    ToolType.eraser => Icons.cleaning_services,
    ToolType.laser => Icons.flashlight_on,
    ToolType.mindmap => Icons.account_tree,
  };
}
