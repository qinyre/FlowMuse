import 'dart:math' as math;
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../bindings/bindings.dart';
import '../grid_snap.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// Tool for creating arrow elements by clicking to add points.
/// Double-click or Enter finalizes the arrow.
///
/// When [arrowType] is an elbow type, creates two-click elbow (orthogonal)
/// arrows that route via [ElbowRouting].
class ArrowTool implements Tool {
  final List<Point> _points = [];
  Point? _previewPoint;
  PointBinding? _startBinding;
  PointBinding? _endBinding;
  Element? _bindTarget;
  bool _isDragCreating = false;
  Point? _dragOrigin;

  /// The visual style of arrows created by this tool.
  ArrowType arrowType;

  ArrowTool({this.arrowType = ArrowType.sharp});

  @override
  ToolType get type => ToolType.arrow;

  @override
  ToolResult? onPointerDown(Point point, ToolContext context) {
    if (_points.isEmpty) {
      // Check for binding at start point
      final target = BindingUtils.findBindTarget(context.scene, point);
      Point snappedPoint = point;

      if (target != null) {
        final fixedPoint = BindingUtils.computeFixedPoint(target, point);
        final binding = PointBinding(
          elementId: target.id.value,
          fixedPoint: fixedPoint,
        );
        snappedPoint = BindingUtils.resolveBindingPoint(target, binding);
        _startBinding = binding;
      } else {
        snappedPoint = snapToGrid(point, context.gridSize);
        _startBinding = null;
      }

      _points.add(snappedPoint);
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
      _previewPoint = point;
      _bindTarget = BindingUtils.findBindTarget(context.scene, point);
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
        // Check for binding at end point
        final target = BindingUtils.findBindTarget(context.scene, point);
        Point snappedPoint = point;

        if (target != null) {
          final fixedPoint = BindingUtils.computeFixedPoint(target, point);
          final binding = PointBinding(
            elementId: target.id.value,
            fixedPoint: fixedPoint,
          );
          snappedPoint = BindingUtils.resolveBindingPoint(target, binding);
          _endBinding = binding;
        } else {
          snappedPoint = snapToGrid(point, context.gridSize);
          _endBinding = null;
        }

        _points.add(snappedPoint);
        _previewPoint = null;
        _bindTarget = null;
        return _finalize();
      }
      // Short drag — stay in multi-click mode (point already added on down)
      _previewPoint = null;
      _bindTarget = null;
      return null;
    }

    // Multi-click mode: check for binding at this point
    final target = BindingUtils.findBindTarget(context.scene, point);
    Point snappedPoint = point;

    if (target != null) {
      final fixedPoint = BindingUtils.computeFixedPoint(target, point);
      final binding = PointBinding(
        elementId: target.id.value,
        fixedPoint: fixedPoint,
      );
      snappedPoint = BindingUtils.resolveBindingPoint(target, binding);
      _endBinding = binding;
    } else {
      snappedPoint = snapToGrid(point, context.gridSize);
      _endBinding = null;
    }

    _points.add(snappedPoint);
    _previewPoint = null;
    _bindTarget = null;

    // Elbow arrows finalize immediately on second click
    if (arrowType.isElbow && _points.length >= 2) {
      return _finalize();
    }

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
    final element = _createArrow(_points);
    reset();
    return CompoundResult([
      AddElementResult(element),
      SetSelectionResult({element.id}),
      SwitchToolResult(ToolType.select),
    ]);
  }

  ArrowElement _createArrow(List<Point> points) {
    List<Point> routedPoints;
    if (arrowType.isElbow) {
      // Route through orthogonal path
      final startHeading = _startBinding != null
          ? ElbowRouting.headingFromFixedPoint(_startBinding!.fixedPoint)
          : null;
      final endHeading = _endBinding != null
          ? ElbowRouting.headingFromFixedPoint(_endBinding!.fixedPoint)
          : null;
      routedPoints = ElbowRouting.route(
        start: points.first,
        end: points.last,
        startHeading: startHeading,
        endHeading: endHeading,
      );
    } else {
      routedPoints = points;
    }

    final minX = routedPoints.map((p) => p.x).reduce(math.min);
    final minY = routedPoints.map((p) => p.y).reduce(math.min);
    final maxX = routedPoints.map((p) => p.x).reduce(math.max);
    final maxY = routedPoints.map((p) => p.y).reduce(math.max);

    final relativePoints = routedPoints
        .map((p) => Point(p.x - minX, p.y - minY))
        .toList();

    return ArrowElement(
      id: ElementId.generate(),
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      points: relativePoints,
      endArrowhead: Arrowhead.arrow,
      startBinding: _startBinding,
      endBinding: _endBinding,
      arrowType: arrowType,
    );
  }

  @override
  ToolOverlay? get overlay {
    if (_points.isEmpty) return null;
    final displayPoints = [..._points];
    if (_previewPoint != null) {
      displayPoints.add(_previewPoint!);
    }

    // For elbowed arrows, route the preview path
    List<Point> overlayPoints;
    if (arrowType.isElbow && displayPoints.length >= 2) {
      final startHeading = _startBinding != null
          ? ElbowRouting.headingFromFixedPoint(_startBinding!.fixedPoint)
          : null;
      // Infer end heading from preview position
      Heading? endHeading;
      if (_bindTarget != null && _previewPoint != null) {
        final fixedPoint = BindingUtils.computeFixedPoint(
          _bindTarget!,
          _previewPoint!,
        );
        endHeading = ElbowRouting.headingFromFixedPoint(fixedPoint);
      }
      overlayPoints = ElbowRouting.route(
        start: displayPoints.first,
        end: displayPoints.last,
        startHeading: startHeading,
        endHeading: endHeading,
      );
    } else {
      overlayPoints = displayPoints;
    }

    Bounds? targetBounds;
    double targetAngle = 0;
    if (_bindTarget != null) {
      targetBounds = Bounds.fromLTWH(
        _bindTarget!.x,
        _bindTarget!.y,
        _bindTarget!.width,
        _bindTarget!.height,
      );
      targetAngle = _bindTarget!.angle;
    }
    return ToolOverlay(
      creationPoints: overlayPoints,
      bindTargetBounds: targetBounds,
      bindTargetAngle: targetAngle,
    );
  }

  @override
  void reset() {
    _points.clear();
    _previewPoint = null;
    _startBinding = null;
    _endBinding = null;
    _bindTarget = null;
    _isDragCreating = false;
    _dragOrigin = null;
  }
}
