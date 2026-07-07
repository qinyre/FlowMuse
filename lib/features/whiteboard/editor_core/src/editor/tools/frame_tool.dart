import 'dart:math' as math;
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/groups/frame_utils.dart';
import '../../core/math/math.dart';
import '../grid_snap.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

const double _minDragDistance = 5.0;

/// Tool for creating frame elements by dragging.
///
/// Frames are named containers that visually clip their children.
/// Default label is "Frame N" where N is incremented per creation.
class FrameTool implements Tool {
  Point? _start;
  Point? _current;
  int _frameCount = 0;

  @override
  ToolType get type => ToolType.frame;

  @override
  ToolResult? onPointerDown(Point point, ToolContext context) {
    _start = snapToGrid(point, context.gridSize);
    _current = _start;
    // Count existing frames to generate the label
    _frameCount = context.scene.activeElements
        .where((e) => e.type == 'frame')
        .length;
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

    final element = FrameElement(
      id: ElementId.generate(),
      x: x,
      y: y,
      width: w,
      height: h,
      label: 'Frame ${_frameCount + 1}',
    );

    // Auto-assign existing elements that are fully inside the new frame
    final assignResults = <ToolResult>[];
    for (final existing in context.scene.activeElements) {
      if (existing is FrameElement) continue;
      if (existing.frameId != null) continue; // already in a frame
      if (FrameUtils.isInsideFrame(existing, element)) {
        assignResults.add(
          UpdateElementResult(existing.copyWith(frameId: element.id.value)),
        );
      }
    }

    reset();
    return CompoundResult([
      AddElementResult(element),
      ...assignResults,
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
