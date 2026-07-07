import 'dart:math' as math;
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../grid_snap.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// Tool for creating line elements by clicking to add points.
/// Double-click or Enter finalizes the line.
/// Press-and-drag creates a 2-point line in one gesture.
/// When the cursor approaches the start point with ≥3 points, the line
/// snaps closed to form a filled polygon.
class LineTool implements Tool {
  static const _closeThreshold = 10.0;

  final List<Point> _points = [];
  Point? _previewPoint;
  bool _isDragCreating = false;
  Point? _dragOrigin;
  bool _isNearStart = false;

  @override
  ToolType get type => ToolType.line;

  @override
  ToolResult? onPointerDown(Point point, ToolContext context) {
    if (_points.isEmpty) {
      _points.add(snapToGrid(point, context.gridSize));
      _isDragCreating = true;
      _dragOrigin = point;
    }
    return null;
  }

  @override
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
  }) {
    if (_points.isNotEmpty) {
      // Check proximity to start point for close detection
      if (_points.length >= 3) {
        final start = _points.first;
        final dx = point.x - start.x;
        final dy = point.y - start.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= _closeThreshold) {
          _isNearStart = true;
          _previewPoint = start;
          return null;
        }
      }
      _isNearStart = false;
      _previewPoint = point;
    }
    return null;
  }

  /// Extended onPointerUp with double-click detection.
  @override
  ToolResult? onPointerUp(
    Point point,
    ToolContext context, {
    bool isDoubleClick = false,
  }) {
    if (_isDragCreating) {
      _isDragCreating = false;
      final origin = _dragOrigin!;
      _dragOrigin = null;
      final dx = point.x - origin.x;
      final dy = point.y - origin.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > 2.0) {
        _points.add(snapToGrid(point, context.gridSize));
        _previewPoint = null;
        return _finalize();
      }
      // Short drag — stay in multi-click mode (point already added on down)
      _previewPoint = null;
      return null;
    }

    // Close the polygon if near start with enough points
    if (_isNearStart && _points.length >= 3) {
      _points.add(_points.first);
      _previewPoint = null;
      return _finalizeAsClosed();
    }

    _points.add(snapToGrid(point, context.gridSize));
    _previewPoint = null;

    if (isDoubleClick && _points.length >= 2) {
      return _finalize();
    }
    return null;
  }

  @override
  ToolResult? onKeyEvent(
    String key, {
    bool shift = false,
    bool ctrl = false,
    ToolContext? context,
  }) {
    if ((key == 'Escape' || key == 'Enter') && _points.length >= 2) {
      return _finalize();
    }
    if (key == 'Escape') {
      reset();
      return null;
    }
    return null;
  }

  ToolResult _finalize() {
    final element = _createElement(_points);
    reset();
    return CompoundResult([
      AddElementResult(element),
      SetSelectionResult({element.id}),
      SwitchToolResult(ToolType.select),
    ]);
  }

  ToolResult _finalizeAsClosed() {
    final element = _createElement(_points, closed: true);
    reset();
    return CompoundResult([
      AddElementResult(element),
      SetSelectionResult({element.id}),
      SwitchToolResult(ToolType.select),
    ]);
  }

  /// Creates the line element. Override in subclasses for different element types.
  LineElement _createElement(List<Point> points, {bool closed = false}) {
    final line = _buildLineElement(points);
    return closed ? line.copyWithLine(closed: true) : line;
  }

  LineElement _buildLineElement(List<Point> points) {
    final minX = points.map((p) => p.x).reduce(math.min);
    final minY = points.map((p) => p.y).reduce(math.min);
    final maxX = points.map((p) => p.x).reduce(math.max);
    final maxY = points.map((p) => p.y).reduce(math.max);

    // Make points relative to origin
    final relativePoints = points
        .map((p) => Point(p.x - minX, p.y - minY))
        .toList();

    return LineElement(
      id: ElementId.generate(),
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      points: relativePoints,
    );
  }

  @override
  ToolOverlay? get overlay {
    if (_points.isEmpty) return null;
    final displayPoints = [..._points];
    if (_previewPoint != null) {
      displayPoints.add(_previewPoint!);
    }
    return ToolOverlay(
      creationPoints: displayPoints,
      creationClosed: _isNearStart && _points.length >= 3,
    );
  }

  @override
  void reset() {
    _points.clear();
    _previewPoint = null;
    _isDragCreating = false;
    _dragOrigin = null;
    _isNearStart = false;
  }
}
