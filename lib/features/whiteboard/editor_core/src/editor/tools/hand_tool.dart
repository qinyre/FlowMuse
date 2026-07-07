import 'dart:ui';

import '../../core/math/math.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// Tool for panning the viewport by dragging.
/// Uses screen-space delta rather than scene coordinates.
class HandTool implements Tool {
  bool _isPanning = false;

  @override
  ToolType get type => ToolType.hand;

  @override
  ToolResult? onPointerDown(Point point, ToolContext context) {
    _isPanning = true;
    return null;
  }

  @override
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
  }) {
    if (!_isPanning || screenDelta == null) return null;
    final panned = context.viewport.pan(screenDelta);
    return UpdateViewportResult(panned);
  }

  @override
  ToolResult? onPointerUp(Point point, ToolContext context) {
    _isPanning = false;
    return null;
  }

  @override
  ToolResult? onKeyEvent(
    String key, {
    bool shift = false,
    bool ctrl = false,
    ToolContext? context,
  }) {
    return null;
  }

  @override
  ToolOverlay? get overlay => null;

  @override
  void reset() {
    _isPanning = false;
  }
}
