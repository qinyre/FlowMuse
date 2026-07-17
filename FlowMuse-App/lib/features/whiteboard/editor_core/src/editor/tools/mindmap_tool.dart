import 'dart:ui' show Offset;

import '../../core/math/point.dart';
import '../mindmap/mindmap_layout.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// Tool for creating a mind-map root node.
///
/// Unlike shape tools (which drag to size), the mind-map tool creates a root
/// node **on tap** at the pointer location: a single click on empty canvas
/// drops a centred node and immediately switches back to the select tool so
/// the user can start typing. Adding children/siblings afterwards is done via
/// the floating + button, property panel, or keyboard shortcuts (Tab/Enter)
/// — all handled by [MarkdrawController], not this tool.
class MindmapTool implements Tool {
  Point? _downPoint;

  @override
  ToolType get type => ToolType.mindmap;

  @override
  ToolResult? onPointerDown(Point point, ToolContext context, {double? pressure}) {
    _downPoint = point;
    return null;
  }

  @override
  ToolResult? onPointerMove(Point point, ToolContext context, {Offset? screenDelta, double? pressure}) {
    return null;
  }

  @override
  ToolResult? onPointerUp(Point point, ToolContext context, {double? pressure}) {
    final down = _downPoint;
    _downPoint = null;
    if (down == null) return null;

    // Treat as a tap only if the pointer barely moved (no drag).
    if (down.distanceTo(point) > 5) return null;

    // Don't create if the user tapped on an existing element.
    final hit = context.scene.getElementAtPoint(point);
    if (hit != null) return null;

    // Create the root node at the tap location and switch to select tool.
    final elements = MindmapLayout.createRootAt(point);
    return CompoundResult([
      for (final e in elements) AddElementResult(e),
      SetSelectionResult({elements.first.id}),
      SwitchToolResult(ToolType.select),
    ]);
  }

  @override
  ToolResult? onKeyEvent(String key, {bool shift = false, bool ctrl = false, ToolContext? context}) {
    if (key == 'Escape') reset();
    return null;
  }

  @override
  ToolOverlay? get overlay => null;

  @override
  void reset() {
    _downPoint = null;
  }
}
