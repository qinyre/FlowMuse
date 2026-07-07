import 'dart:math' as math;
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../grid_snap.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

const double _minDragDistance = 5.0;

/// Tool for creating ellipse elements by dragging.
class EllipseTool implements Tool {
  Point? _start;
  Point? _current;

  @override
  ToolType get type => ToolType.ellipse;

  @override
  ToolResult? onPointerDown(Point point, ToolContext context) {
    _start = snapToGrid(point, context.gridSize);
    _current = _start;
    return null;
  }

  @override
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
  }) {
    if (_start == null) return null;
    _current = snapToGrid(point, context.gridSize);
    return null;
  }

  @override
  ToolResult? onPointerUp(Point point, ToolContext context) {
    final start = _start;
    if (start == null) return null;

    final snapped = snapToGrid(point, context.gridSize);
    _current = snapped;
    if (start.distanceTo(snapped) < _minDragDistance) {
      reset();
      return null;
    }

    final x = math.min(start.x, snapped.x);
    final y = math.min(start.y, snapped.y);
    final w = (start.x - snapped.x).abs();
    final h = (start.y - snapped.y).abs();

    final element = EllipseElement(
      id: ElementId.generate(),
      x: x,
      y: y,
      width: w,
      height: h,
    );

    reset();
    return CompoundResult([
      AddElementResult(element),
      SetSelectionResult({element.id}),
      SwitchToolResult(ToolType.select),
    ]);
  }

  @override
  ToolResult? onKeyEvent(
    String key, {
    bool shift = false,
    bool ctrl = false,
    ToolContext? context,
  }) {
    if (key == 'Escape') reset();
    return null;
  }

  @override
  ToolOverlay? get overlay {
    final start = _start;
    final current = _current;
    if (start == null || current == null) return null;
    final x = math.min(start.x, current.x);
    final y = math.min(start.y, current.y);
    final w = (start.x - current.x).abs();
    final h = (start.y - current.y).abs();
    return ToolOverlay(creationBounds: Bounds.fromLTWH(x, y, w, h));
  }

  @override
  void reset() {
    _start = null;
    _current = null;
  }
}
