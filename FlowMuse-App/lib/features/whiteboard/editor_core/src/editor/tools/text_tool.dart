import 'dart:math' as math;
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../grid_snap.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// Minimum drag distance (in scene units) to create a fixed-width text box.
const double _minDragDistance = 5.0;

/// Tool for creating text elements by clicking or dragging.
///
/// - **Click** (drag < 5px): Creates a point text element with auto-resize
///   width (current behavior).
/// - **Drag** (drag >= 5px): Creates a text element with fixed width matching
///   the drag extent. Text wraps within that width during editing.
class TextTool implements Tool {
  Point? _start;
  Point? _current;

  @override
  ToolType get type => ToolType.text;

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
    final distance = start.distanceTo(snapped);

    final Element element;
    if (distance < _minDragDistance) {
      // Click mode: point text with auto-resize
      // Start with a minimum size so selection handles don't overlap
      const defaultFontSize = 20.0;
      const defaultLineHeight = 1.25;
      const minH = defaultFontSize * defaultLineHeight;
      element = TextElement(
        id: ElementId.generate(),
        x: start.x,
        y: start.y,
        width: minH, // ~one character width
        height: minH,
        text: '',
      );
    } else {
      // Drag mode: fixed-width text box
      final x = math.min(start.x, snapped.x);
      final y = math.min(start.y, snapped.y);
      final w = (start.x - snapped.x).abs();
      final h = (start.y - snapped.y).abs();

      element = TextElement(
        id: ElementId.generate(),
        x: x,
        y: y,
        width: w,
        height: h,
        text: '',
        autoResize: false,
      );
    }

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
    if (key == 'Escape') {
      reset();
    }
    return null;
  }

  @override
  ToolOverlay? get overlay {
    final start = _start;
    final current = _current;
    if (start == null || current == null) return null;
    final distance = start.distanceTo(current);
    if (distance < _minDragDistance) return null;
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
