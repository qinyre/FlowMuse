import 'dart:math' as math;
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// Tool for creating freehand drawing elements by continuous path recording.
class FreedrawTool implements Tool {
  final List<Point> _points = [];
  bool _isDrawing = false;

  @override
  ToolType get type => ToolType.freedraw;

  @override
  ToolResult? onPointerDown(Point point, ToolContext context) {
    _isDrawing = true;
    _points.add(point);
    return null;
  }

  @override
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
  }) {
    if (!_isDrawing) return null;
    _points.add(point);
    return null;
  }

  @override
  ToolResult? onPointerUp(Point point, ToolContext context) {
    if (!_isDrawing || _points.isEmpty) {
      reset();
      return null;
    }

    final minX = _points.map((p) => p.x).reduce(math.min);
    final minY = _points.map((p) => p.y).reduce(math.min);
    final maxX = _points.map((p) => p.x).reduce(math.max);
    final maxY = _points.map((p) => p.y).reduce(math.max);

    final relativePoints = _points
        .map((p) => Point(p.x - minX, p.y - minY))
        .toList();

    final element = FreedrawElement(
      id: ElementId.generate(),
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      points: relativePoints,
      simulatePressure: true,
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
    if (_points.isEmpty) return null;
    return ToolOverlay(creationPoints: List.unmodifiable(_points));
  }

  @override
  void reset() {
    _points.clear();
    _isDrawing = false;
  }
}
