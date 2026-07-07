import 'dart:math' as math;
import 'dart:ui';

import '../../core/alignment/alignment_utils.dart';
import '../../core/alignment/flip_utils.dart';
import '../../core/elements/elements.dart';
import '../../core/groups/groups.dart';
import '../../core/layer/layer_utils.dart';
import '../../core/math/math.dart';
import '../../core/scene/scene_exports.dart';
import '../../rendering/interactive/interactive.dart';
import '../bindings/bindings.dart';
import '../grid_snap.dart';
import '../object_snap.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// Minimum drag distance to distinguish a drag from a click.
const double _clickThreshold = 3.0;

/// Hit-test radius for handles (in scene units), scaled for interaction mode.
double _handleHitRadius(InteractionMode mode) =>
    mode == InteractionMode.touch ? 22.0 : 8.0;

/// Minimum element size enforced during resize.
const double _minSize = 10.0;

/// Drag mode for the select tool.
enum _DragMode { none, move, resize, rotate, dragPoint, dragSegment, marquee }

/// Tool for selecting, moving, resizing, rotating, and point-editing elements.
class SelectTool implements Tool {
  Point? _downPoint;
  Point? _current;
  Element? _hitElement;
  bool _isDragging = false;
  bool _shiftDown = false;
  _DragMode _dragMode = _DragMode.none;

  // Starting state for transforms
  Bounds? _startBounds;
  double _startAngle = 0.0;
  List<Point>? _startPoints;
  HandleType? _activeHandle;
  int? _activePointIndex;
  int? _activeSegmentIndex;

  // For multi-element transforms
  List<Element>? _startElements;
  Bounds? _startUnionBounds;

  // Binding indicator during point drag
  Element? _bindTarget;

  // Snap-to-close indicator during point drag
  Point? _closeIndicatorCenter;

  // Object snap state
  ObjectSnapCache? _objectSnapCache;
  List<SnapLine> _activeSnapLines = const [];

  // Snap-to-close constants for non-arrow line endpoints
  static const _closeThreshold = 10.0; // matching LineTool
  static const _defaultPolygonFill = '#a5d8ff'; // Excalidraw default

  @override
  ToolType get type => ToolType.select;

  /// True when the user is actively dragging a point or segment handle.
  /// UI should hide the selection bounding box during these drags.
  bool get isDraggingPoint =>
      _isDragging &&
      (_dragMode == _DragMode.dragPoint || _dragMode == _DragMode.dragSegment);

  /// Extended onPointerDown that accepts shift modifier.
  @override
  ToolResult? onPointerDown(
    Point point,
    ToolContext context, {
    bool shift = false,
  }) {
    _downPoint = point;
    _current = point;
    _isDragging = false;
    _shiftDown = shift;
    _dragMode = _DragMode.none;

    final selectedElements = _getSelectedElements(context);

    // Skip handle hit-tests if all selected elements are locked
    final allLocked =
        selectedElements.isNotEmpty && selectedElements.every((e) => e.locked);

    // 1. Point/segment handle hit-test (line/arrow only, single selection)
    //    For simple 2-point lines/arrows, handles are always visible so
    //    hit-test without requiring linear editing mode.
    if (selectedElements.length == 1 && !allLocked) {
      final elem = selectedElements.first;
      final isLinearEditable =
          elem is LineElement &&
          (elem.points.length <= 2 || context.isEditingLinear);

      // Point handle check first — always takes priority over segment drag
      // so that endpoint handles support binding on elbowed arrows.
      final pointIndex = isLinearEditable
          ? _hitTestPointHandle(point, elem, context.interactionMode)
          : null;
      if (pointIndex != null) {
        _dragMode = _DragMode.dragPoint;
        _activePointIndex = pointIndex;
        _hitElement = elem;
        _startBounds = Bounds.fromLTWH(elem.x, elem.y, elem.width, elem.height);
        if (elem is LineElement) {
          _startPoints = List.of(elem.points);
        }
        return null;
      }

      // For elbowed arrows, check segment hit after point handles
      if (context.isEditingLinear && elem is ArrowElement && elem.elbowed) {
        final segIndex = _hitTestSegment(point, elem, context.interactionMode);
        if (segIndex != null) {
          _dragMode = _DragMode.dragSegment;
          _activeSegmentIndex = segIndex;
          _hitElement = elem;
          _startBounds = Bounds.fromLTWH(
            elem.x,
            elem.y,
            elem.width,
            elem.height,
          );
          _startPoints = List.of(elem.points);
          return null;
        }
      }

      // Midpoint handle hit-test: insert a new point at the midpoint
      final midIdx = context.isEditingLinear
          ? _hitTestMidpointHandle(point, elem, context.interactionMode)
          : null;
      if (midIdx != null) {
        final line = elem as LineElement;
        final a = line.points[midIdx];
        final b = line.points[midIdx + 1];
        final mid = Point((a.x + b.x) / 2, (a.y + b.y) / 2);
        final newPoints = List<Point>.of(line.points)..insert(midIdx + 1, mid);
        final updated = _normalizeLineElement(line, newPoints);

        _dragMode = _DragMode.dragPoint;
        _activePointIndex = midIdx + 1;
        _hitElement = updated;
        _startBounds = Bounds.fromLTWH(
          updated.x,
          updated.y,
          updated.width,
          updated.height,
        );
        _startPoints = List.of((updated as LineElement).points);
        return UpdateElementResult(updated);
      }
    }

    // 2. Resize/rotation handle hit-test
    if (selectedElements.isNotEmpty && !allLocked) {
      final handleType = _hitTestHandle(
        point,
        selectedElements,
        context.interactionMode,
      );
      if (handleType != null) {
        if (handleType == HandleType.rotation) {
          _dragMode = _DragMode.rotate;
        } else {
          _dragMode = _DragMode.resize;
        }
        _activeHandle = handleType;
        _hitElement = selectedElements.length == 1
            ? selectedElements.first
            : null;
        _captureStartState(selectedElements, context: context);
        return null;
      }
    }

    // 3. Element body hit-test
    _hitElement = context.scene.getElementAtPoint(point);
    return null;
  }

  @override
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
  }) {
    final down = _downPoint;
    if (down == null) return null;

    _current = point;
    final distance = down.distanceTo(point);

    // Check if we've started dragging
    if (!_isDragging && distance >= _clickThreshold) {
      _isDragging = true;

      // If we haven't committed to a mode yet, determine it now
      if (_dragMode == _DragMode.none) {
        if (_hitElement == null) {
          _dragMode = _DragMode.marquee;
        } else if (_hitElement!.locked) {
          // Locked elements can be selected but not moved
          _dragMode = _DragMode.none;
          _isDragging = false;
        } else {
          _dragMode = _DragMode.move;
          _captureStartStateForMove(context);
        }
      }
    }

    if (!_isDragging) return null;

    // Dispatch based on mode
    return switch (_dragMode) {
      _DragMode.resize => _applyResize(point, context),
      _DragMode.rotate => _applyRotation(point, context),
      _DragMode.dragPoint => _applyPointDrag(point, context),
      _DragMode.dragSegment => _applySegmentDrag(point, context),
      _DragMode.move => _applyMove(point, context),
      _DragMode.marquee => null, // Marquee is overlay-only during drag
      _DragMode.none => null,
    };
  }

  @override
  ToolResult? onPointerUp(Point point, ToolContext context) {
    final down = _downPoint;
    if (down == null) return null;

    _current = point;

    try {
      // If we were in a transform mode and dragging, the final update
      // was already emitted by onPointerMove. Just reset.
      if (_isDragging && _dragMode == _DragMode.resize) {
        return _applyResize(point, context);
      }
      if (_isDragging && _dragMode == _DragMode.rotate) {
        return _applyRotation(point, context);
      }
      if (_isDragging && _dragMode == _DragMode.dragPoint) {
        return _applyPointDrag(point, context);
      }
      if (_isDragging && _dragMode == _DragMode.dragSegment) {
        return _applySegmentDrag(point, context);
      }
      if (_isDragging && _dragMode == _DragMode.move) {
        return _applyMove(point, context);
      }

      // Marquee selection
      if (_dragMode == _DragMode.marquee) {
        return _handleMarquee(down, point, context);
      }

      // Click on element
      final hit = _hitElement;
      if (hit != null) {
        return _handleClick(hit, context);
      }

      // Click on empty
      return SetSelectionResult({});
    } finally {
      reset();
    }
  }

  ToolResult _handleClick(Element hit, ToolContext context) {
    // Resolve group level for this click
    final groupId = GroupUtils.resolveGroupForClick(
      hit,
      context.selectedIds,
      context.scene,
    );

    if (_shiftDown) {
      // Toggle in/out of selection
      final ids = Set<ElementId>.from(context.selectedIds);
      if (groupId != null) {
        // Toggle entire group
        final members = GroupUtils.findGroupMembers(context.scene, groupId);
        final memberIds = members.map((e) => e.id).toSet();
        final allSelected = memberIds.every((id) => ids.contains(id));
        if (allSelected) {
          ids.removeAll(memberIds);
        } else {
          ids.addAll(memberIds);
        }
      } else {
        if (ids.contains(hit.id)) {
          ids.remove(hit.id);
        } else {
          ids.add(hit.id);
        }
      }
      return SetSelectionResult(ids);
    }

    if (groupId != null) {
      final members = GroupUtils.findGroupMembers(context.scene, groupId);
      return SetSelectionResult(members.map((e) => e.id).toSet());
    }
    return SetSelectionResult({hit.id});
  }

  ToolResult? _applyMove(Point current, ToolContext context) {
    final down = _downPoint;
    if (down == null) return null;
    final hit = _hitElement;
    if (hit == null) return null;

    var dx = current.x - down.x;
    var dy = current.y - down.y;

    // Snap element position to grid (Ctrl disables)
    if (context.gridSize != null && !_shiftDown) {
      final startElem =
          _startElements?.firstWhere(
            (e) => e.id == hit.id,
            orElse: () => hit,
          ) ??
          hit;
      final snappedX = snapValue(startElem.x + dx, context.gridSize);
      final snappedY = snapValue(startElem.y + dy, context.gridSize);
      dx = snappedX - startElem.x;
      dy = snappedY - startElem.y;
    }

    // Snap to other objects
    if (context.objectsSnapMode && _objectSnapCache != null) {
      // Compute union bounds of all moving elements with current offset
      final startElems = _startElements ?? [hit];
      Bounds union = Bounds.fromLTWH(
        startElems.first.x + dx,
        startElems.first.y + dy,
        startElems.first.width,
        startElems.first.height,
      );
      for (var i = 1; i < startElems.length; i++) {
        union = union.union(
          Bounds.fromLTWH(
            startElems[i].x + dx,
            startElems[i].y + dy,
            startElems[i].width,
            startElems[i].height,
          ),
        );
      }
      final threshold = 8.0 / context.viewport.zoom;
      final snapResult = snapToObjects(union, _objectSnapCache!, threshold);
      dx += snapResult.dx;
      dy += snapResult.dy;
      _activeSnapLines = snapResult.snapLines;
    } else {
      _activeSnapLines = const [];
    }

    final selectedElements = _getSelectedElements(context);
    final isSelected = context.selectedIds.contains(hit.id);

    // Multi-element move
    if (isSelected && selectedElements.length > 1) {
      final updates = <ToolResult>[];
      final movedElements = <Element>[];
      for (final elem in _startElements ?? selectedElements) {
        final moved = elem.copyWith(x: elem.x + dx, y: elem.y + dy);
        updates.add(UpdateElementResult(moved));
        movedElements.add(moved);
      }
      updates.addAll(
        _buildFrameChildMoveUpdates(
          context.scene,
          movedElements,
          context.selectedIds,
        ),
      );
      updates.addAll(
        _buildBoundArrowUpdates(
          context.scene,
          movedElements,
          context.selectedIds,
        ),
      );
      updates.addAll(
        BoundTextUtils.updateBoundTextPositions(context.scene, movedElements),
      );
      updates.addAll(
        _buildFrameAssignmentUpdates(
          context.scene,
          movedElements,
          context.selectedIds,
        ),
      );
      return CompoundResult(updates);
    }

    // Single element move
    final startElem =
        _startElements?.firstWhere((e) => e.id == hit.id, orElse: () => hit) ??
        hit;
    final moved = startElem.copyWith(x: startElem.x + dx, y: startElem.y + dy);

    if (isSelected) {
      final arrowUpdates = _buildBoundArrowUpdates(context.scene, [
        moved,
      ], context.selectedIds);
      final textUpdates = BoundTextUtils.updateBoundTextPositions(
        context.scene,
        [moved],
      );
      final frameChildUpdates = _buildFrameChildMoveUpdates(context.scene, [
        moved,
      ], context.selectedIds);
      final frameAssignUpdates = _buildFrameAssignmentUpdates(context.scene, [
        moved,
      ], context.selectedIds);
      if (arrowUpdates.isEmpty &&
          textUpdates.isEmpty &&
          frameChildUpdates.isEmpty &&
          frameAssignUpdates.isEmpty) {
        return UpdateElementResult(moved);
      }
      return CompoundResult([
        UpdateElementResult(moved),
        ...frameChildUpdates,
        ...arrowUpdates,
        ...textUpdates,
        ...frameAssignUpdates,
      ]);
    }

    // Dragging an unselected element: expand to outermost group if grouped
    final outermostGid = GroupUtils.outermostGroupId(hit);
    if (outermostGid != null) {
      final groupMembers = GroupUtils.findGroupMembers(
        context.scene,
        outermostGid,
      );
      final groupIds = groupMembers.map((e) => e.id).toSet();
      final startElems = _startElements ?? groupMembers;
      final updates = <ToolResult>[SetSelectionResult(groupIds)];
      final movedElements = <Element>[];
      for (final elem in startElems) {
        final m = elem.copyWith(x: elem.x + dx, y: elem.y + dy);
        updates.add(UpdateElementResult(m));
        movedElements.add(m);
      }
      updates.addAll(
        _buildBoundArrowUpdates(context.scene, movedElements, groupIds),
      );
      updates.addAll(
        BoundTextUtils.updateBoundTextPositions(context.scene, movedElements),
      );
      return CompoundResult(updates);
    }

    // Dragging an unselected ungrouped element: select then move
    final arrowUpdates = _buildBoundArrowUpdates(
      context.scene,
      [moved],
      {hit.id},
    );
    final textUpdates = BoundTextUtils.updateBoundTextPositions(context.scene, [
      moved,
    ]);
    final frameChildUpdates = _buildFrameChildMoveUpdates(
      context.scene,
      [moved],
      {hit.id},
    );
    final frameAssignUpdates = _buildFrameAssignmentUpdates(
      context.scene,
      [moved],
      {hit.id},
    );
    return CompoundResult([
      SetSelectionResult({hit.id}),
      UpdateElementResult(moved),
      ...frameChildUpdates,
      ...arrowUpdates,
      ...textUpdates,
      ...frameAssignUpdates,
    ]);
  }

  ToolResult _handleMarquee(Point down, Point up, ToolContext context) {
    final minX = math.min(down.x, up.x);
    final minY = math.min(down.y, up.y);
    final maxX = math.max(down.x, up.x);
    final maxY = math.max(down.y, up.y);
    final marquee = Bounds.fromLTWH(minX, minY, maxX - minX, maxY - minY);

    final selected = <ElementId>{};
    for (final e in context.scene.activeElements) {
      // Skip bound text — users interact with the parent shape
      if (e is TextElement && e.containerId != null) continue;
      final eBounds = Bounds.fromLTWH(e.x, e.y, e.width, e.height);
      if (marquee.containsPoint(eBounds.origin) &&
          marquee.containsPoint(Point(eBounds.right, eBounds.bottom))) {
        selected.add(e.id);
      }
    }

    // Expand to include all members of any group that has at least one hit
    final groupsToExpand = <String>{};
    for (final id in selected) {
      final element = context.scene.getElementById(id);
      if (element != null) {
        for (final gid in element.groupIds) {
          groupsToExpand.add(gid);
        }
      }
    }
    var expanded = Set<ElementId>.from(selected);
    for (final gid in groupsToExpand) {
      expanded = GroupUtils.expandToGroup(context.scene, expanded, gid);
    }
    return SetSelectionResult(expanded);
  }

  // --- Handle hit-testing ---

  /// Hit-test for point handles on a line/arrow element.
  int? _hitTestPointHandle(
    Point scenePoint,
    Element element,
    InteractionMode mode,
  ) {
    if (element is! LineElement) return null;
    // Transform scene point into the element's local (unrotated) space
    final center = Point(
      element.x + element.width / 2,
      element.y + element.height / 2,
    );
    final localPoint = _unrotatePoint(scenePoint, center, element.angle);
    final radius = _handleHitRadius(mode);
    for (var i = 0; i < element.points.length; i++) {
      final absPoint = Point(
        element.x + element.points[i].x,
        element.y + element.points[i].y,
      );
      if (absPoint.distanceTo(localPoint) <= radius) {
        return i;
      }
    }
    return null;
  }

  /// Hit-test for midpoint handles between adjacent vertices.
  ///
  /// Returns the segment index (i.e. the index of the first point of the
  /// segment) if the scene point is within hit radius of the midpoint.
  /// Skipped for elbow arrows (they don't support midpoint insertion).
  int? _hitTestMidpointHandle(
    Point scenePoint,
    Element element,
    InteractionMode mode,
  ) {
    if (element is! LineElement) return null;
    if (element is ArrowElement && element.elbowed) return null;
    if (element.points.length < 2) return null;

    final center = Point(
      element.x + element.width / 2,
      element.y + element.height / 2,
    );
    final localPoint = _unrotatePoint(scenePoint, center, element.angle);
    final radius = _handleHitRadius(mode);

    for (var i = 0; i < element.points.length - 1; i++) {
      final a = Point(
        element.x + element.points[i].x,
        element.y + element.points[i].y,
      );
      final b = Point(
        element.x + element.points[i + 1].x,
        element.y + element.points[i + 1].y,
      );
      final mid = Point((a.x + b.x) / 2, (a.y + b.y) / 2);
      if (mid.distanceTo(localPoint) <= radius) {
        return i;
      }
    }
    return null;
  }

  /// Hit-test for resize/rotation handles on selected elements.
  HandleType? _hitTestHandle(
    Point scenePoint,
    List<Element> elements,
    InteractionMode mode,
  ) {
    final overlay = SelectionOverlay.fromElements(elements, mode: mode);
    if (overlay == null || !overlay.showBoundingBox) return null;

    // Transform scene point into the selection's local space (undo rotation)
    final localPoint = _unrotatePoint(
      scenePoint,
      overlay.bounds.center,
      overlay.angle,
    );

    final radius = _handleHitRadius(mode);
    for (final handle in overlay.handles) {
      if (handle.position.distanceTo(localPoint) <= radius) {
        return handle.type;
      }
    }
    return null;
  }

  /// Rotates [point] around [center] by -[angle] (inverse rotation).
  static Point _unrotatePoint(Point point, Point center, double angle) {
    if (angle == 0) return point;
    final cos = math.cos(-angle);
    final sin = math.sin(-angle);
    final dx = point.x - center.x;
    final dy = point.y - center.y;
    return Point(
      center.x + dx * cos - dy * sin,
      center.y + dx * sin + dy * cos,
    );
  }

  /// Rotates [point] around [center] by [angle].
  static Point _rotatePoint(Point point, Point center, double angle) {
    if (angle == 0) return point;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final dx = point.x - center.x;
    final dy = point.y - center.y;
    return Point(
      center.x + dx * cos - dy * sin,
      center.y + dx * sin + dy * cos,
    );
  }

  // --- Resize ---

  ToolResult? _applyResize(Point current, ToolContext context) {
    final down = _downPoint;
    if (down == null || _startBounds == null || _activeHandle == null) {
      return null;
    }

    // Unrotate the drag delta into the element's local coordinate system
    // so that resize directions align with the element's axes.
    final angle = _startAngle;
    final center = _startBounds!.center;
    final localCurrent = _unrotatePoint(current, center, angle);
    final localDown = _unrotatePoint(down, center, angle);
    final dx = localCurrent.x - localDown.x;
    final dy = localCurrent.y - localDown.y;
    final b = _startBounds!;

    var newLeft = b.left;
    var newTop = b.top;
    var newRight = b.right;
    var newBottom = b.bottom;

    switch (_activeHandle!) {
      case HandleType.topLeft:
        newLeft += dx;
        newTop += dy;
      case HandleType.topCenter:
        newTop += dy;
      case HandleType.topRight:
        newRight += dx;
        newTop += dy;
      case HandleType.middleLeft:
        newLeft += dx;
      case HandleType.middleRight:
        newRight += dx;
      case HandleType.bottomLeft:
        newLeft += dx;
        newBottom += dy;
      case HandleType.bottomCenter:
        newBottom += dy;
      case HandleType.bottomRight:
        newRight += dx;
        newBottom += dy;
      case HandleType.rotation:
        return null;
    }

    // Snap resize edges to grid
    if (context.gridSize != null && angle == 0.0) {
      switch (_activeHandle!) {
        case HandleType.topLeft:
          newLeft = snapValue(newLeft, context.gridSize);
          newTop = snapValue(newTop, context.gridSize);
        case HandleType.topCenter:
          newTop = snapValue(newTop, context.gridSize);
        case HandleType.topRight:
          newRight = snapValue(newRight, context.gridSize);
          newTop = snapValue(newTop, context.gridSize);
        case HandleType.middleLeft:
          newLeft = snapValue(newLeft, context.gridSize);
        case HandleType.middleRight:
          newRight = snapValue(newRight, context.gridSize);
        case HandleType.bottomLeft:
          newLeft = snapValue(newLeft, context.gridSize);
          newBottom = snapValue(newBottom, context.gridSize);
        case HandleType.bottomCenter:
          newBottom = snapValue(newBottom, context.gridSize);
        case HandleType.bottomRight:
          newRight = snapValue(newRight, context.gridSize);
          newBottom = snapValue(newBottom, context.gridSize);
        case HandleType.rotation:
          break;
      }
    }

    // Snap resize edges to other objects
    if (context.objectsSnapMode && _objectSnapCache != null && angle == 0.0) {
      final threshold = 8.0 / context.viewport.zoom;
      final snapLines = <SnapLine>[];

      // Snap active X edges
      final activeXEdges = <double>[];
      switch (_activeHandle!) {
        case HandleType.topLeft:
        case HandleType.middleLeft:
        case HandleType.bottomLeft:
          activeXEdges.add(newLeft);
        case HandleType.topRight:
        case HandleType.middleRight:
        case HandleType.bottomRight:
          activeXEdges.add(newRight);
        default:
          break;
      }

      for (final edge in activeXEdges) {
        double bestDist = double.infinity;
        double? bestSnap;
        for (final rx in _objectSnapCache!.xPositions) {
          final dist = (edge - rx).abs();
          if (dist < bestDist && dist <= threshold) {
            bestDist = dist;
            bestSnap = rx;
          }
        }
        if (bestSnap != null) {
          final delta = bestSnap - edge;
          switch (_activeHandle!) {
            case HandleType.topLeft:
            case HandleType.middleLeft:
            case HandleType.bottomLeft:
              newLeft += delta;
            case HandleType.topRight:
            case HandleType.middleRight:
            case HandleType.bottomRight:
              newRight += delta;
            default:
              break;
          }
          // Build vertical snap line
          var minY = math.min(newTop, newBottom);
          var maxY = math.max(newTop, newBottom);
          for (final sb in _objectSnapCache!.sourceBounds) {
            if (_xMatches(sb, bestSnap)) {
              minY = math.min(minY, sb.top);
              maxY = math.max(maxY, sb.bottom);
            }
          }
          snapLines.add(
            SnapLine(
              orientation: SnapLineOrientation.vertical,
              position: bestSnap,
              start: minY,
              end: maxY,
            ),
          );
        }
      }

      // Snap active Y edges
      final activeYEdges = <double>[];
      switch (_activeHandle!) {
        case HandleType.topLeft:
        case HandleType.topCenter:
        case HandleType.topRight:
          activeYEdges.add(newTop);
        case HandleType.bottomLeft:
        case HandleType.bottomCenter:
        case HandleType.bottomRight:
          activeYEdges.add(newBottom);
        default:
          break;
      }

      for (final edge in activeYEdges) {
        double bestDist = double.infinity;
        double? bestSnap;
        for (final ry in _objectSnapCache!.yPositions) {
          final dist = (edge - ry).abs();
          if (dist < bestDist && dist <= threshold) {
            bestDist = dist;
            bestSnap = ry;
          }
        }
        if (bestSnap != null) {
          final delta = bestSnap - edge;
          switch (_activeHandle!) {
            case HandleType.topLeft:
            case HandleType.topCenter:
            case HandleType.topRight:
              newTop += delta;
            case HandleType.bottomLeft:
            case HandleType.bottomCenter:
            case HandleType.bottomRight:
              newBottom += delta;
            default:
              break;
          }
          // Build horizontal snap line
          var minX = math.min(newLeft, newRight);
          var maxX = math.max(newLeft, newRight);
          for (final sb in _objectSnapCache!.sourceBounds) {
            if (_yMatches(sb, bestSnap)) {
              minX = math.min(minX, sb.left);
              maxX = math.max(maxX, sb.right);
            }
          }
          snapLines.add(
            SnapLine(
              orientation: SnapLineOrientation.horizontal,
              position: bestSnap,
              start: minX,
              end: maxX,
            ),
          );
        }
      }

      _activeSnapLines = snapLines;
    }

    // Enforce minimum size
    if (newRight - newLeft < _minSize) {
      if (_activeHandle == HandleType.topLeft ||
          _activeHandle == HandleType.middleLeft ||
          _activeHandle == HandleType.bottomLeft) {
        newLeft = newRight - _minSize;
      } else {
        newRight = newLeft + _minSize;
      }
    }
    if (newBottom - newTop < _minSize) {
      if (_activeHandle == HandleType.topLeft ||
          _activeHandle == HandleType.topCenter ||
          _activeHandle == HandleType.topRight) {
        newTop = newBottom - _minSize;
      } else {
        newBottom = newTop + _minSize;
      }
    }

    // Aspect ratio lock: images default to locked (Shift unlocks),
    // other shapes default to unlocked (Shift locks).
    final isImage =
        _hitElement is ImageElement ||
        (_startElements != null &&
            _startElements!.length == 1 &&
            _startElements!.first is ImageElement);
    final lockAspect = isImage ? !_shiftDown : _shiftDown;
    if (lockAspect) {
      final origW = b.right - b.left;
      final origH = b.bottom - b.top;
      if (origW > 0 && origH > 0) {
        final aspect = origW / origH;
        final newW = newRight - newLeft;
        final newH = newBottom - newTop;
        final currentAspect = newW / newH;
        if (currentAspect > aspect) {
          // Width is too big, adjust width
          final adjustedW = newH * aspect;
          if (_activeHandle == HandleType.topLeft ||
              _activeHandle == HandleType.middleLeft ||
              _activeHandle == HandleType.bottomLeft) {
            newLeft = newRight - adjustedW;
          } else {
            newRight = newLeft + adjustedW;
          }
        } else {
          // Height is too big, adjust height
          final adjustedH = newW / aspect;
          if (_activeHandle == HandleType.topLeft ||
              _activeHandle == HandleType.topCenter ||
              _activeHandle == HandleType.topRight) {
            newTop = newBottom - adjustedH;
          } else {
            newBottom = newTop + adjustedH;
          }
        }
      }
    }

    var newW = newRight - newLeft;
    var newH = newBottom - newTop;

    // Round dimensions for rotated elements to avoid trig noise
    if (angle != 0.0) {
      newW = newW.roundToDouble();
      newH = newH.roundToDouble();
    }

    // For rotated elements, adjust x/y to keep the anchor point (opposite
    // the dragged handle) fixed in world space. Changing width/height shifts
    // the center of rotation, so we must compensate.
    if (angle != 0.0) {
      final oldW = b.right - b.left;
      final oldH = b.bottom - b.top;
      final (fx, fy) = _anchorFraction(_activeHandle!);
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      // Anchor offset from center in old bounds
      final oldAX = fx * oldW / 2;
      final oldAY = fy * oldH / 2;
      // Anchor world position = old center + rotated old offset
      final oldCx = b.left + oldW / 2;
      final oldCy = b.top + oldH / 2;
      final anchorWx = oldCx + oldAX * cosA - oldAY * sinA;
      final anchorWy = oldCy + oldAX * sinA + oldAY * cosA;

      // Anchor offset from center in new bounds
      final newAX = fx * newW / 2;
      final newAY = fy * newH / 2;
      // new center = anchor world - rotated new offset
      final newCx = anchorWx - (newAX * cosA - newAY * sinA);
      final newCy = anchorWy - (newAX * sinA + newAY * cosA);

      newLeft = (newCx - newW / 2).roundToDouble();
      newTop = (newCy - newH / 2).roundToDouble();
    }

    final newBounds = Bounds.fromLTWH(newLeft, newTop, newW, newH);

    // Multi-element resize: scale proportionally
    if (_startElements != null && _startElements!.length > 1) {
      return _applyMultiResize(newBounds, context);
    }

    // Single element resize
    final elem = _hitElement ?? _startElements?.first;
    if (elem == null) return null;

    final startElem =
        _startElements?.firstWhere(
          (e) => e.id == elem.id,
          orElse: () => elem,
        ) ??
        elem;

    Element resized;
    // For point-based elements, scale points proportionally to new bounds
    if (startElem is LineElement || startElem is FreedrawElement) {
      final oldW = _startBounds!.right - _startBounds!.left;
      final oldH = _startBounds!.bottom - _startBounds!.top;
      final scaleX = oldW > 0 ? newW / oldW : 1.0;
      final scaleY = oldH > 0 ? newH / oldH : 1.0;

      if (startElem is LineElement) {
        final scaledPoints = startElem.points
            .map((p) => Point(p.x * scaleX, p.y * scaleY))
            .toList();
        resized = startElem
            .copyWithLine(points: scaledPoints)
            .copyWith(x: newLeft, y: newTop, width: newW, height: newH);
      } else {
        final fd = startElem as FreedrawElement;
        final scaledPoints = fd.points
            .map((p) => Point(p.x * scaleX, p.y * scaleY))
            .toList();
        resized = fd
            .copyWithFreedraw(points: scaledPoints)
            .copyWith(x: newLeft, y: newTop, width: newW, height: newH);
      }
    } else {
      resized = startElem.copyWith(
        x: newLeft,
        y: newTop,
        width: newW,
        height: newH,
      );
    }

    final arrowUpdates = _buildBoundArrowUpdates(context.scene, [
      resized,
    ], context.selectedIds);
    final textUpdates = BoundTextUtils.updateBoundTextPositions(context.scene, [
      resized,
    ]);
    if (arrowUpdates.isEmpty && textUpdates.isEmpty) {
      return UpdateElementResult(resized);
    }
    return CompoundResult([
      UpdateElementResult(resized),
      ...arrowUpdates,
      ...textUpdates,
    ]);
  }

  /// Returns the anchor point's offset from center as fractions of half-size.
  /// The anchor is the fixed point opposite the handle being dragged.
  static (double, double) _anchorFraction(HandleType handle) {
    return switch (handle) {
      HandleType.topLeft => (1.0, 1.0),
      HandleType.topCenter => (0.0, 1.0),
      HandleType.topRight => (-1.0, 1.0),
      HandleType.middleLeft => (1.0, 0.0),
      HandleType.middleRight => (-1.0, 0.0),
      HandleType.bottomLeft => (1.0, -1.0),
      HandleType.bottomCenter => (0.0, -1.0),
      HandleType.bottomRight => (-1.0, -1.0),
      HandleType.rotation => (0.0, 0.0),
    };
  }

  ToolResult _applyMultiResize(Bounds newBounds, ToolContext context) {
    final oldBounds = _startUnionBounds ?? _startBounds!;
    final scaleX = oldBounds.size.width > 0
        ? newBounds.size.width / oldBounds.size.width
        : 1.0;
    final scaleY = oldBounds.size.height > 0
        ? newBounds.size.height / oldBounds.size.height
        : 1.0;

    final updates = <ToolResult>[];
    final movedElements = <Element>[];
    for (final elem in _startElements!) {
      final newX = newBounds.left + (elem.x - oldBounds.left) * scaleX;
      final newY = newBounds.top + (elem.y - oldBounds.top) * scaleY;
      final newW = elem.width * scaleX;
      final newH = elem.height * scaleY;
      Element resized;
      if (elem is LineElement) {
        final elemScaleX = elem.width > 0 ? newW / elem.width : 1.0;
        final elemScaleY = elem.height > 0 ? newH / elem.height : 1.0;
        final scaledPoints = elem.points
            .map((p) => Point(p.x * elemScaleX, p.y * elemScaleY))
            .toList();
        resized = elem
            .copyWithLine(points: scaledPoints)
            .copyWith(x: newX, y: newY, width: newW, height: newH);
      } else if (elem is FreedrawElement) {
        final elemScaleX = elem.width > 0 ? newW / elem.width : 1.0;
        final elemScaleY = elem.height > 0 ? newH / elem.height : 1.0;
        final scaledPoints = elem.points
            .map((p) => Point(p.x * elemScaleX, p.y * elemScaleY))
            .toList();
        resized = elem
            .copyWithFreedraw(points: scaledPoints)
            .copyWith(x: newX, y: newY, width: newW, height: newH);
      } else {
        resized = elem.copyWith(x: newX, y: newY, width: newW, height: newH);
      }
      updates.add(UpdateElementResult(resized));
      movedElements.add(resized);
    }
    updates.addAll(
      _buildBoundArrowUpdates(
        context.scene,
        movedElements,
        context.selectedIds,
      ),
    );
    updates.addAll(
      BoundTextUtils.updateBoundTextPositions(context.scene, movedElements),
    );
    return CompoundResult(updates);
  }

  // --- Rotation ---

  ToolResult? _applyRotation(Point current, ToolContext context) {
    final down = _downPoint;
    if (down == null || _startBounds == null) return null;

    final center = _startBounds!.center;
    final startAngle = math.atan2(down.y - center.y, down.x - center.x);
    final currentAngle = math.atan2(current.y - center.y, current.x - center.x);
    var delta = currentAngle - startAngle;

    // Shift snaps to 15° increments
    if (_shiftDown) {
      const snap = math.pi / 12; // 15°
      delta = (delta / snap).roundToDouble() * snap;
    }

    // Multi-element rotate
    if (_startElements != null && _startElements!.length > 1) {
      return _applyMultiRotation(delta, context);
    }

    // Single element rotate
    final elem = _hitElement ?? _startElements?.first;
    if (elem == null) return null;

    final startElem =
        _startElements?.firstWhere(
          (e) => e.id == elem.id,
          orElse: () => elem,
        ) ??
        elem;

    final rotated = startElem.copyWith(angle: _startAngle + delta);
    final arrowUpdates = _buildBoundArrowUpdates(context.scene, [
      rotated,
    ], context.selectedIds);
    final textUpdates = BoundTextUtils.updateBoundTextPositions(context.scene, [
      rotated,
    ]);
    if (arrowUpdates.isEmpty && textUpdates.isEmpty) {
      return UpdateElementResult(rotated);
    }
    return CompoundResult([
      UpdateElementResult(rotated),
      ...arrowUpdates,
      ...textUpdates,
    ]);
  }

  ToolResult _applyMultiRotation(double angleDelta, ToolContext context) {
    final unionCenter = _startUnionBounds!.center;
    final updates = <ToolResult>[];
    final movedElements = <Element>[];

    for (final elem in _startElements!) {
      final elemCenter = Point(
        elem.x + elem.width / 2,
        elem.y + elem.height / 2,
      );
      final rotated = _rotatePoint(elemCenter, unionCenter, angleDelta);
      final newX = (rotated.x - elem.width / 2).roundToDouble();
      final newY = (rotated.y - elem.height / 2).roundToDouble();

      final moved = elem.copyWith(
        x: newX,
        y: newY,
        angle: elem.angle + angleDelta,
      );
      updates.add(UpdateElementResult(moved));
      movedElements.add(moved);
    }
    updates.addAll(
      _buildBoundArrowUpdates(
        context.scene,
        movedElements,
        context.selectedIds,
      ),
    );
    updates.addAll(
      BoundTextUtils.updateBoundTextPositions(context.scene, movedElements),
    );
    return CompoundResult(updates);
  }

  // --- Point drag ---

  ToolResult? _applyPointDrag(Point current, ToolContext context) {
    final down = _downPoint;
    if (down == null ||
        _hitElement is! LineElement ||
        _activePointIndex == null) {
      return null;
    }

    // Scene-space delta — must be unrotated into element-local space
    var dx = current.x - down.x;
    var dy = current.y - down.y;
    final angle = _hitElement!.angle;
    if (angle != 0) {
      final cos = math.cos(-angle);
      final sin = math.sin(-angle);
      final rdx = dx * cos - dy * sin;
      final rdy = dx * sin + dy * cos;
      dx = rdx;
      dy = rdy;
    }

    final startPts = _startPoints!;
    final oldPt = startPts[_activePointIndex!];
    final newPoints = List<Point>.from(startPts);
    newPoints[_activePointIndex!] = Point(oldPt.x + dx, oldPt.y + dy);

    final line = _hitElement! as LineElement;
    var updated = _normalizeLineElement(line, newPoints);
    // Get the normalized points for binding calculations
    final normalizedPoints = (updated as LineElement).points;

    // Handle binding for arrow first/last point
    if (updated is ArrowElement) {
      final isFirst = _activePointIndex == 0;
      final isLast = _activePointIndex == normalizedPoints.length - 1;

      if (isFirst || isLast) {
        // Compute absolute position of the dragged point
        final absPoint = Point(
          updated.x + normalizedPoints[_activePointIndex!].x,
          updated.y + normalizedPoints[_activePointIndex!].y,
        );
        final target = BindingUtils.findBindTarget(context.scene, absPoint);
        _bindTarget = target;

        if (target != null) {
          final fixedPoint = BindingUtils.computeFixedPoint(target, absPoint);
          final binding = PointBinding(
            elementId: target.id.value,
            fixedPoint: fixedPoint,
          );

          // Snap the point to the edge
          final snapped = BindingUtils.resolveBindingPoint(target, binding);
          final snappedRel = Point(
            snapped.x - updated.x,
            snapped.y - updated.y,
          );
          final snappedPoints = List<Point>.of(normalizedPoints);
          snappedPoints[_activePointIndex!] = snappedRel;

          // Re-normalize with snapped point
          updated = _normalizeLineElement(updated, snappedPoints);

          if (isFirst) {
            updated = (updated as ArrowElement).copyWithArrow(
              startBinding: binding,
            );
          } else {
            updated = (updated as ArrowElement).copyWithArrow(
              endBinding: binding,
            );
          }
        } else {
          // No target — grid snap if enabled
          if (context.gridSize != null) {
            final snapped = snapToGrid(absPoint, context.gridSize);
            final snappedRel = Point(
              snapped.x - updated.x,
              snapped.y - updated.y,
            );
            final snappedPoints = List<Point>.of(normalizedPoints);
            snappedPoints[_activePointIndex!] = snappedRel;
            updated = _normalizeLineElement(updated, snappedPoints);
          }

          // Clear binding if was bound
          if (isFirst && (line as ArrowElement).startBinding != null) {
            updated = (updated as ArrowElement).copyWithArrow(
              clearStartBinding: true,
            );
          }
          if (isLast && (line as ArrowElement).endBinding != null) {
            updated = (updated as ArrowElement).copyWithArrow(
              clearEndBinding: true,
            );
          }
        }
      } else {
        _bindTarget = null;
      }
    }

    // Snap-to-close for non-arrow open lines
    if (updated is LineElement && updated is! ArrowElement) {
      final pts = updated.points;
      final isFirst = _activePointIndex == 0;
      final isLast = _activePointIndex == pts.length - 1;

      if ((isFirst || isLast) && pts.length >= 3) {
        final draggedAbs = Point(
          updated.x + (isFirst ? pts.first.x : pts.last.x),
          updated.y + (isFirst ? pts.first.y : pts.last.y),
        );
        final otherAbs = Point(
          updated.x + (isFirst ? pts.last.x : pts.first.x),
          updated.y + (isFirst ? pts.last.y : pts.first.y),
        );
        if (draggedAbs.distanceTo(otherAbs) <= _closeThreshold) {
          _closeIndicatorCenter = otherAbs;
          // Snap: set dragged point to match the other endpoint
          final snappedPts = List<Point>.of(pts);
          final otherRel = isFirst ? pts.last : pts.first;
          snappedPts[_activePointIndex!] = otherRel;
          updated = _normalizeLineElement(updated, snappedPts);
          updated = (updated as LineElement)
              .copyWithLine(closed: true)
              .copyWith(backgroundColor: _defaultPolygonFill);
        } else {
          _closeIndicatorCenter = null;
        }
      } else {
        _closeIndicatorCenter = null;
      }
    } else {
      _closeIndicatorCenter = null;
    }

    return UpdateElementResult(updated);
  }

  // --- Segment drag (elbow arrows) ---

  /// Hit-test for segment proximity on an elbowed arrow.
  /// Returns the segment index (0-based) or null.
  int? _hitTestSegment(
    Point scenePoint,
    ArrowElement arrow,
    InteractionMode mode,
  ) {
    final points = arrow.points;
    if (points.length < 2) return null;

    // Transform scene point into the element's local (unrotated) space
    final center = Point(arrow.x + arrow.width / 2, arrow.y + arrow.height / 2);
    final localPoint = _unrotatePoint(scenePoint, center, arrow.angle);

    final radius = _handleHitRadius(mode);
    for (var i = 0; i < points.length - 1; i++) {
      final a = Point(arrow.x + points[i].x, arrow.y + points[i].y);
      final b = Point(arrow.x + points[i + 1].x, arrow.y + points[i + 1].y);
      final dist = _distToSegment(localPoint, a, b);
      if (dist <= radius) {
        return i;
      }
    }
    return null;
  }

  /// Minimum distance from [p] to the line segment [a]-[b].
  static double _distToSegment(Point p, Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lengthSq = dx * dx + dy * dy;
    if (lengthSq == 0) return p.distanceTo(a);
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    final proj = Point(a.x + t * dx, a.y + t * dy);
    return p.distanceTo(proj);
  }

  ToolResult? _applySegmentDrag(Point current, ToolContext context) {
    final down = _downPoint;
    if (down == null ||
        _hitElement is! ArrowElement ||
        _activeSegmentIndex == null ||
        _startPoints == null) {
      return null;
    }

    final arrow = _hitElement! as ArrowElement;
    final segIdx = _activeSegmentIndex!;
    final startPts = _startPoints!;

    // Scene-space delta — must be unrotated into element-local space
    var dx = current.x - down.x;
    var dy = current.y - down.y;
    final angle = arrow.angle;
    if (angle != 0) {
      final cos = math.cos(-angle);
      final sin = math.sin(-angle);
      final rdx = dx * cos - dy * sin;
      final rdy = dx * sin + dy * cos;
      dx = rdx;
      dy = rdy;
    }

    final newPoints = List<Point>.from(startPts);
    final ptA = startPts[segIdx];
    final ptB = startPts[segIdx + 1];

    // Determine if segment is horizontal or vertical
    final isHorizontal = (ptA.y - ptB.y).abs() < 0.5;

    // Move both endpoints by full (dx, dy), then cascade one level to
    // adjacent points so all segments remain orthogonal.
    newPoints[segIdx] = Point(ptA.x + dx, ptA.y + dy);
    newPoints[segIdx + 1] = Point(ptB.x + dx, ptB.y + dy);

    if (isHorizontal) {
      // Adjacent segments are vertical — match their shared x coordinate.
      if (segIdx > 0) {
        final prev = startPts[segIdx - 1];
        newPoints[segIdx - 1] = Point(prev.x + dx, prev.y);
      }
      if (segIdx + 2 < startPts.length) {
        final next = startPts[segIdx + 2];
        newPoints[segIdx + 2] = Point(next.x + dx, next.y);
      }
    } else {
      // Adjacent segments are horizontal — match their shared y coordinate.
      if (segIdx > 0) {
        final prev = startPts[segIdx - 1];
        newPoints[segIdx - 1] = Point(prev.x, prev.y + dy);
      }
      if (segIdx + 2 < startPts.length) {
        final next = startPts[segIdx + 2];
        newPoints[segIdx + 2] = Point(next.x, next.y + dy);
      }
    }

    return UpdateElementResult(_normalizeLineElement(arrow, newPoints));
  }

  /// Normalize a line element's x/y/width/height to match its points.
  ///
  /// Re-relativizes [points] so the origin is at the min x/y, and updates
  /// x/y/width/height accordingly.
  static Element _normalizeLineElement(LineElement elem, List<Point> points) {
    var minX = points.first.x;
    var minY = points.first.y;
    var maxX = points.first.x;
    var maxY = points.first.y;
    for (final pt in points) {
      minX = math.min(minX, pt.x);
      minY = math.min(minY, pt.y);
      maxX = math.max(maxX, pt.x);
      maxY = math.max(maxY, pt.y);
    }
    final normalized = points
        .map((p) => Point(p.x - minX, p.y - minY))
        .toList();

    final newWidth = maxX - minX;
    final newHeight = maxY - minY;

    // For rotated elements, the local-space normalization offset (minX, minY)
    // must be transformed to scene space, accounting for the shifting rotation
    // center caused by bounding box changes.
    double dx = minX;
    double dy = minY;
    if (elem.angle != 0) {
      final c = math.cos(elem.angle);
      final s = math.sin(elem.angle);
      final dw = newWidth - elem.width;
      final dh = newHeight - elem.height;
      dx = minX * c - minY * s - (dw * (1 - c) + dh * s) / 2;
      dy = minX * s + minY * c + (dw * s - dh * (1 - c)) / 2;
    }

    return elem
        .copyWithLine(points: normalized)
        .copyWith(
          x: elem.x + dx,
          y: elem.y + dy,
          width: newWidth,
          height: newHeight,
        );
  }

  // --- Keyboard ---

  @override
  ToolResult? onKeyEvent(
    String key, {
    bool shift = false,
    bool ctrl = false,
    ToolContext? context,
  }) {
    if (key == 'Escape') {
      reset();
      return SetSelectionResult({});
    }

    if (context == null) return null;

    final selectedElements = _getSelectedElements(context);

    // Delete/Backspace
    if (key == 'Delete' || key == 'Backspace') {
      if (selectedElements.isEmpty) return null;
      final deletable = selectedElements.where((e) => !e.locked).toList();
      if (deletable.isEmpty) return null;
      final results = <ToolResult>[
        for (final e in deletable) RemoveElementResult(e.id),
        SetSelectionResult({}),
      ];
      final deletedIds = deletable.map((e) => e.id).toSet();

      // Cascade: delete bound text children, and clean parent boundElements
      for (final elem in deletable) {
        // If this is a container/arrow, delete its bound text
        final boundText = context.scene.findBoundText(elem.id);
        if (boundText != null && !deletedIds.contains(boundText.id)) {
          results.add(RemoveElementResult(boundText.id));
          deletedIds.add(boundText.id);
        }

        // If this is bound text, update parent's boundElements list
        if (elem is TextElement && elem.containerId != null) {
          final parentId = ElementId(elem.containerId!);
          if (!deletedIds.contains(parentId)) {
            final parent = context.scene.getElementById(parentId);
            if (parent != null) {
              final newBound = parent.boundElements
                  .where((b) => b.id != elem.id.value)
                  .toList();
              results.add(
                UpdateElementResult(parent.copyWith(boundElements: newBound)),
              );
            }
          }
        }
      }

      // Release children of deleted frames
      for (final elem in deletable) {
        if (elem is FrameElement) {
          final released = FrameUtils.releaseFrameChildren(
            context.scene,
            elem.id,
          );
          for (final child in released) {
            if (!deletedIds.contains(child.id)) {
              results.add(UpdateElementResult(child));
            }
          }
        }
      }

      // Clean up orphaned image files
      for (final elem in deletable) {
        if (elem is ImageElement) {
          final fileId = elem.fileId;
          // Check if any other active element still references this fileId
          final stillReferenced = context.scene.activeElements.any(
            (e) =>
                e is ImageElement &&
                e.fileId == fileId &&
                !deletedIds.contains(e.id),
          );
          if (!stillReferenced && context.scene.files.containsKey(fileId)) {
            results.add(RemoveFileResult(fileId));
          }
        }
      }

      // Clear bindings on arrows that were bound to deleted elements
      final seen = <ElementId>{};
      for (final elem in deletable) {
        final arrows = BindingUtils.findBoundArrows(context.scene, elem.id);
        for (final arrow in arrows) {
          if (deletedIds.contains(arrow.id)) continue;
          if (seen.contains(arrow.id)) continue;
          seen.add(arrow.id);
          var updated = arrow;
          if (arrow.startBinding != null &&
              deletedIds.contains(ElementId(arrow.startBinding!.elementId))) {
            updated = updated.copyWithArrow(clearStartBinding: true);
          }
          if (arrow.endBinding != null &&
              deletedIds.contains(ElementId(arrow.endBinding!.elementId))) {
            updated = updated.copyWithArrow(clearEndBinding: true);
          }
          if (!identical(updated, arrow)) {
            results.add(UpdateElementResult(updated));
          }
        }
      }
      return CompoundResult(results);
    }

    // Ctrl+D: Duplicate
    if (ctrl && (key == 'd' || key == 'D')) {
      if (selectedElements.isEmpty) return null;
      return _duplicateElements(selectedElements, context: context);
    }

    // Ctrl+G: Group selected elements
    if (ctrl && !shift && (key == 'g' || key == 'G')) {
      if (selectedElements.length < 2) return null;
      final newGroupId = ElementId.generate().value;
      final grouped = GroupUtils.groupElements(selectedElements, newGroupId);
      final results = <ToolResult>[
        for (final e in grouped) UpdateElementResult(e),
      ];
      return CompoundResult(results);
    }

    // Ctrl+Shift+G: Ungroup selected elements
    if (ctrl && shift && (key == 'g' || key == 'G')) {
      if (selectedElements.isEmpty) return null;
      // Only ungroup elements that actually have groupIds
      final groupedElements = selectedElements
          .where((e) => e.groupIds.isNotEmpty)
          .toList();
      if (groupedElements.isEmpty) return null;
      final ungrouped = GroupUtils.ungroupElements(groupedElements);
      final results = <ToolResult>[
        for (final e in ungrouped) UpdateElementResult(e),
      ];
      return CompoundResult(results);
    }

    // Ctrl+Shift+L: Toggle lock
    if (ctrl && shift && (key == 'l' || key == 'L')) {
      if (selectedElements.isEmpty) return null;
      final allLocked = selectedElements.every((e) => e.locked);
      final results = <ToolResult>[
        for (final e in selectedElements)
          UpdateElementResult(e.copyWith(locked: !allLocked)),
      ];
      return CompoundResult(results);
    }

    // Ctrl+A: Select all (skip bound text)
    if (ctrl && (key == 'a' || key == 'A')) {
      final allIds = context.scene.activeElements
          .where((e) => e is! TextElement || e.containerId == null)
          .map((e) => e.id)
          .toSet();
      return SetSelectionResult(allIds);
    }

    // Ctrl+C: Copy
    if (ctrl && (key == 'c' || key == 'C')) {
      if (selectedElements.isEmpty) return null;
      return SetClipboardResult(List.of(selectedElements));
    }

    // Ctrl+V: Paste
    if (ctrl && (key == 'v' || key == 'V')) {
      if (context.clipboard.isEmpty) return null;
      return _pasteElements(context.clipboard, context: context);
    }

    // Ctrl+X: Cut (copy all, remove only unlocked)
    if (ctrl && (key == 'x' || key == 'X')) {
      if (selectedElements.isEmpty) return null;
      final cuttable = selectedElements.where((e) => !e.locked).toList();
      if (cuttable.isEmpty) return null;
      final results = <ToolResult>[
        SetClipboardResult(List.of(cuttable)),
        for (final e in cuttable) RemoveElementResult(e.id),
        SetSelectionResult({}),
      ];
      return CompoundResult(results);
    }

    // Ctrl+]: Bring forward / Ctrl+Shift+]: Bring to front
    if (ctrl && key == ']') {
      if (selectedElements.isEmpty) return null;
      if (selectedElements.every((e) => e.locked)) return null;
      final ids = selectedElements.map((e) => e.id).toSet();
      final updated = shift
          ? LayerUtils.bringToFront(context.scene, ids)
          : LayerUtils.bringForward(context.scene, ids);
      if (updated.isEmpty) return null;
      return CompoundResult([for (final e in updated) UpdateElementResult(e)]);
    }

    // Ctrl+[: Send backward / Ctrl+Shift+[: Send to back
    if (ctrl && key == '[') {
      if (selectedElements.isEmpty) return null;
      if (selectedElements.every((e) => e.locked)) return null;
      final ids = selectedElements.map((e) => e.id).toSet();
      final updated = shift
          ? LayerUtils.sendToBack(context.scene, ids)
          : LayerUtils.sendBackward(context.scene, ids);
      if (updated.isEmpty) return null;
      return CompoundResult([for (final e in updated) UpdateElementResult(e)]);
    }

    // Shift+H: Flip horizontal
    if (shift && !ctrl && (key == 'h' || key == 'H')) {
      if (selectedElements.isEmpty) return null;
      if (selectedElements.every((e) => e.locked)) return null;
      final flipped = FlipUtils.flipHorizontal(selectedElements);
      if (flipped.isEmpty) return null;
      return CompoundResult([for (final e in flipped) UpdateElementResult(e)]);
    }

    // Shift+V: Flip vertical
    if (shift && !ctrl && (key == 'v' || key == 'V')) {
      if (selectedElements.isEmpty) return null;
      if (selectedElements.every((e) => e.locked)) return null;
      final flipped = FlipUtils.flipVertical(selectedElements);
      if (flipped.isEmpty) return null;
      return CompoundResult([for (final e in flipped) UpdateElementResult(e)]);
    }

    // Tab / Shift+Tab: Cycle shape type
    if (!ctrl && key == 'Tab') {
      if (selectedElements.isEmpty) return null;
      if (selectedElements.every((e) => e.locked)) return null;
      final results = <ToolResult>[];
      for (final e in selectedElements) {
        final converted = ShapeConverter.cycleShape(e, reverse: shift);
        if (converted != null) {
          results.add(UpdateElementResult(converted));
        }
      }
      if (results.isEmpty) return null;
      return results.length == 1 ? results.first : CompoundResult(results);
    }

    // Ctrl+Shift+Arrow: Alignment shortcuts
    if (ctrl &&
        shift &&
        (key == 'ArrowLeft' ||
            key == 'ArrowRight' ||
            key == 'ArrowUp' ||
            key == 'ArrowDown')) {
      if (selectedElements.length < 2) return null;
      if (selectedElements.every((e) => e.locked)) return null;
      final aligned = switch (key) {
        'ArrowLeft' => AlignmentUtils.alignLeft(selectedElements),
        'ArrowRight' => AlignmentUtils.alignRight(selectedElements),
        'ArrowUp' => AlignmentUtils.alignTop(selectedElements),
        'ArrowDown' => AlignmentUtils.alignBottom(selectedElements),
        _ => <Element>[],
      };
      if (aligned.isEmpty) return null;
      return CompoundResult([for (final e in aligned) UpdateElementResult(e)]);
    }

    // Arrow keys: Nudge
    final nudge = shift ? 10.0 : 1.0;
    if (key == 'ArrowLeft' ||
        key == 'ArrowRight' ||
        key == 'ArrowUp' ||
        key == 'ArrowDown') {
      if (selectedElements.isEmpty) return null;
      if (selectedElements.any((e) => e.locked)) return null;
      final dx = key == 'ArrowLeft'
          ? -nudge
          : key == 'ArrowRight'
          ? nudge
          : 0.0;
      final dy = key == 'ArrowUp'
          ? -nudge
          : key == 'ArrowDown'
          ? nudge
          : 0.0;
      return _nudgeElements(selectedElements, dx, dy, context);
    }

    return null;
  }

  ToolResult _duplicateElements(
    List<Element> elements, {
    ToolContext? context,
  }) {
    final results = <ToolResult>[];
    final newIds = <ElementId>{};
    // Map old ID → new ID for reconnecting bound text and frameId
    final idMap = <String, ElementId>{};
    // Map old groupId → new groupId for independent duplicate groups
    final groupIdMap = <String, String>{};
    for (final e in elements) {
      for (final gid in e.groupIds) {
        groupIdMap.putIfAbsent(gid, () => ElementId.generate().value);
      }
    }
    // First pass: generate new IDs for all elements
    for (final e in elements) {
      idMap[e.id.value] = ElementId.generate();
    }
    for (final e in elements) {
      final newId = idMap[e.id.value]!;
      newIds.add(newId);
      final remappedGroupIds = e.groupIds
          .map((gid) => groupIdMap[gid]!)
          .toList();
      // Remap frameId if the frame is also being duplicated
      String? remappedFrameId = e.frameId;
      if (e.frameId != null && idMap.containsKey(e.frameId)) {
        remappedFrameId = idMap[e.frameId]!.value;
      }
      results.add(
        AddElementResult(
          e.copyWith(
            id: newId,
            x: e.x + 10,
            y: e.y + 10,
            groupIds: remappedGroupIds,
            frameId: remappedFrameId,
          ),
        ),
      );
    }
    // Duplicate bound text for each element that has it
    if (context != null) {
      for (final e in elements) {
        final boundText = context.scene.findBoundText(e.id);
        if (boundText != null) {
          final newTextId = ElementId.generate();
          final newParentId = idMap[e.id.value]!;
          results.add(
            AddElementResult(
              boundText
                  .copyWithText(containerId: newParentId.value)
                  .copyWith(
                    id: newTextId,
                    x: boundText.x + 10,
                    y: boundText.y + 10,
                  ),
            ),
          );
          // Update the duplicated parent's boundElements
          final parentResult =
              results.firstWhere(
                    (r) => r is AddElementResult && r.element.id == newParentId,
                  )
                  as AddElementResult;
          final updatedBound = [
            ...parentResult.element.boundElements,
            BoundElement(id: newTextId.value, type: 'text'),
          ];
          results[results.indexOf(parentResult)] = AddElementResult(
            parentResult.element.copyWith(boundElements: updatedBound),
          );
        }
      }
    }
    results.add(SetSelectionResult(newIds));
    return CompoundResult(results);
  }

  ToolResult _pasteElements(List<Element> clipboard, {ToolContext? context}) {
    final results = <ToolResult>[];
    final newIds = <ElementId>{};
    final idMap = <String, ElementId>{};
    // Map old groupId → new groupId for independent pasted groups
    final groupIdMap = <String, String>{};
    for (final e in clipboard) {
      for (final gid in e.groupIds) {
        groupIdMap.putIfAbsent(gid, () => ElementId.generate().value);
      }
    }
    // First pass: generate new IDs for all elements
    for (final e in clipboard) {
      idMap[e.id.value] = ElementId.generate();
    }
    for (final e in clipboard) {
      final newId = idMap[e.id.value]!;
      newIds.add(newId);
      final remappedGroupIds = e.groupIds
          .map((gid) => groupIdMap[gid]!)
          .toList();
      // Remap frameId if the frame is also being pasted
      String? remappedFrameId = e.frameId;
      if (e.frameId != null && idMap.containsKey(e.frameId)) {
        remappedFrameId = idMap[e.frameId]!.value;
      }
      results.add(
        AddElementResult(
          e.copyWith(
            id: newId,
            x: e.x + 10,
            y: e.y + 10,
            groupIds: remappedGroupIds,
            frameId: remappedFrameId,
          ),
        ),
      );
    }
    // Also paste bound text for clipboard elements
    if (context != null) {
      for (final e in clipboard) {
        final boundText = context.scene.findBoundText(e.id);
        if (boundText != null) {
          final newTextId = ElementId.generate();
          final newParentId = idMap[e.id.value]!;
          results.add(
            AddElementResult(
              boundText
                  .copyWithText(containerId: newParentId.value)
                  .copyWith(
                    id: newTextId,
                    x: boundText.x + 10,
                    y: boundText.y + 10,
                  ),
            ),
          );
        }
      }
    }
    results.add(SetSelectionResult(newIds));
    return CompoundResult(results);
  }

  ToolResult _nudgeElements(
    List<Element> elements,
    double dx,
    double dy,
    ToolContext context,
  ) {
    final movedElements = <Element>[];
    final results = <ToolResult>[];
    for (final e in elements) {
      final moved = e.copyWith(x: e.x + dx, y: e.y + dy);
      results.add(UpdateElementResult(moved));
      movedElements.add(moved);
    }
    results.addAll(
      _buildFrameChildMoveUpdates(
        context.scene,
        movedElements,
        context.selectedIds,
      ),
    );
    results.addAll(
      _buildBoundArrowUpdates(
        context.scene,
        movedElements,
        context.selectedIds,
      ),
    );
    results.addAll(
      BoundTextUtils.updateBoundTextPositions(context.scene, movedElements),
    );
    if (results.length == 1) return results.first;
    return CompoundResult(results);
  }

  @override
  ToolOverlay? get overlay {
    // Binding / close indicator during point drag
    if (_dragMode == _DragMode.dragPoint && _isDragging) {
      Bounds? bindBounds;
      double bindAngle = 0.0;
      if (_bindTarget != null) {
        bindBounds = Bounds.fromLTWH(
          _bindTarget!.x,
          _bindTarget!.y,
          _bindTarget!.width,
          _bindTarget!.height,
        );
        bindAngle = _bindTarget!.angle;
      }
      if (bindBounds != null || _closeIndicatorCenter != null) {
        return ToolOverlay(
          bindTargetBounds: bindBounds,
          bindTargetAngle: bindAngle,
          closeIndicatorCenter: _closeIndicatorCenter,
        );
      }
    }

    // Snap lines during move or resize
    if (_isDragging &&
        (_dragMode == _DragMode.move || _dragMode == _DragMode.resize) &&
        _activeSnapLines.isNotEmpty) {
      if (_dragMode == _DragMode.move) {
        return ToolOverlay(snapLines: _activeSnapLines);
      }
      // Resize: return snap lines only
      return ToolOverlay(snapLines: _activeSnapLines);
    }

    if (_dragMode != _DragMode.marquee || !_isDragging) return null;
    final down = _downPoint;
    final current = _current;
    if (down == null || current == null) return null;
    final minX = math.min(down.x, current.x);
    final minY = math.min(down.y, current.y);
    final w = (down.x - current.x).abs();
    final h = (down.y - current.y).abs();
    return ToolOverlay(marqueeRect: Bounds.fromLTWH(minX, minY, w, h));
  }

  @override
  void reset() {
    _downPoint = null;
    _current = null;
    _hitElement = null;
    _isDragging = false;
    _shiftDown = false;
    _dragMode = _DragMode.none;
    _startBounds = null;
    _startAngle = 0.0;
    _startPoints = null;
    _activeHandle = null;
    _activePointIndex = null;
    _activeSegmentIndex = null;
    _startElements = null;
    _startUnionBounds = null;
    _bindTarget = null;
    _closeIndicatorCenter = null;
    _objectSnapCache = null;
    _activeSnapLines = const [];
  }

  // --- Helpers ---

  List<Element> _getSelectedElements(ToolContext context) {
    return context.scene.activeElements
        .where((e) => context.selectedIds.contains(e.id))
        .toList();
  }

  void _captureStartState(List<Element> elements, {ToolContext? context}) {
    _startElements = List.of(elements);
    if (elements.length == 1) {
      final e = elements.first;
      _startBounds = Bounds.fromLTWH(e.x, e.y, e.width, e.height);
      _startAngle = e.angle;
      if (e is LineElement) {
        _startPoints = List.of(e.points);
      }
    } else {
      // Multi-element: union bounds
      Bounds union = Bounds.fromLTWH(
        elements.first.x,
        elements.first.y,
        elements.first.width,
        elements.first.height,
      );
      for (var i = 1; i < elements.length; i++) {
        final e = elements[i];
        union = union.union(Bounds.fromLTWH(e.x, e.y, e.width, e.height));
      }
      _startBounds = union;
      _startUnionBounds = union;
      _startAngle = 0.0;
    }

    // Build object snap cache for resize if enabled
    if (context != null && context.objectsSnapMode) {
      final excludeIds = elements.map((e) => e.id).toSet();
      _objectSnapCache = buildObjectSnapCache(context.scene, excludeIds);
    }
  }

  void _captureStartStateForMove(ToolContext context) {
    final hit = _hitElement;
    if (hit == null) return;
    final isSelected = context.selectedIds.contains(hit.id);
    if (isSelected && context.selectedIds.length > 1) {
      _startElements = _getSelectedElements(context);
    } else if (!isSelected) {
      // Dragging an unselected element: capture group members if grouped
      final outermostGid = GroupUtils.outermostGroupId(hit);
      if (outermostGid != null) {
        _startElements = GroupUtils.findGroupMembers(
          context.scene,
          outermostGid,
        );
      } else {
        _startElements = [hit];
      }
    } else {
      _startElements = [hit];
    }

    // Build object snap cache if enabled
    if (context.objectsSnapMode) {
      final excludeIds = <ElementId>{};
      if (_startElements != null) {
        for (final e in _startElements!) {
          excludeIds.add(e.id);
        }
      }
      excludeIds.add(hit.id);
      _objectSnapCache = buildObjectSnapCache(context.scene, excludeIds);
    }
  }

  /// Build UpdateElementResults for arrows bound to any of [movedElements],
  /// excluding arrows already in [selectedIds] (to avoid double-move).
  List<ToolResult> _buildBoundArrowUpdates(
    Scene scene,
    List<Element> movedElements,
    Set<ElementId> selectedIds,
  ) {
    // Build a temporary scene with the moved elements applied
    var tempScene = scene;
    for (final elem in movedElements) {
      tempScene = tempScene.updateElement(elem);
    }

    // Collect all bound arrows, deduplicated
    final seen = <ElementId>{};
    final results = <ToolResult>[];

    for (final elem in movedElements) {
      final arrows = BindingUtils.findBoundArrows(scene, elem.id);
      for (final arrow in arrows) {
        if (selectedIds.contains(arrow.id)) continue;
        if (seen.contains(arrow.id)) continue;
        seen.add(arrow.id);
        final updated = BindingUtils.updateBoundArrowEndpoints(
          arrow,
          tempScene,
        );
        if (!identical(updated, arrow)) {
          results.add(UpdateElementResult(updated));
        }
      }
    }
    return results;
  }

  /// Build UpdateElementResults that auto-assign or clear frameId for
  /// [movedElements] based on whether they are inside a frame.
  ///
  /// Uses a temporary scene with the moved elements applied to check
  /// containment against current frame positions.
  List<ToolResult> _buildFrameAssignmentUpdates(
    Scene scene,
    List<Element> movedElements,
    Set<ElementId> selectedIds,
  ) {
    // Build a temporary scene with the moved elements applied
    var tempScene = scene;
    for (final elem in movedElements) {
      tempScene = tempScene.updateElement(elem);
    }

    final results = <ToolResult>[];
    final seen = <ElementId>{};

    for (final elem in movedElements) {
      // Skip frames themselves — frames don't get assigned to other frames
      if (elem is FrameElement) continue;
      if (seen.contains(elem.id)) continue;
      seen.add(elem.id);

      // Look up the element in the temp scene to get its current position
      final current = tempScene.getElementById(elem.id) ?? elem;
      final containingFrame = FrameUtils.findContainingFrame(
        tempScene,
        current,
      );

      if (containingFrame != null) {
        // Element is inside a frame
        if (current.frameId != containingFrame.id.value) {
          results.add(
            UpdateElementResult(
              current.copyWith(frameId: containingFrame.id.value),
            ),
          );
        }
      } else {
        // Element is not inside any frame — clear frameId if set
        if (current.frameId != null) {
          results.add(
            UpdateElementResult(current.copyWith(clearFrameId: true)),
          );
        }
      }
    }
    return results;
  }

  /// Build UpdateElementResults to move frame children along with the frame.
  List<ToolResult> _buildFrameChildMoveUpdates(
    Scene scene,
    List<Element> movedElements,
    Set<ElementId> selectedIds,
  ) {
    final results = <ToolResult>[];
    final seen = <ElementId>{};

    for (final elem in movedElements) {
      if (elem is! FrameElement) continue;

      // Find the original frame to compute delta
      final original = scene.getElementById(elem.id);
      if (original == null) continue;
      final dx = elem.x - original.x;
      final dy = elem.y - original.y;
      if (dx == 0 && dy == 0) continue;

      final children = FrameUtils.findFrameChildren(scene, elem.id);
      for (final child in children) {
        if (selectedIds.contains(child.id)) continue;
        if (seen.contains(child.id)) continue;
        seen.add(child.id);
        results.add(
          UpdateElementResult(child.copyWith(x: child.x + dx, y: child.y + dy)),
        );
      }
    }
    return results;
  }

  /// Returns true if [bounds] has left, center.x, or right matching [x].
  static bool _xMatches(Bounds bounds, double x) {
    const epsilon = 0.5;
    return (bounds.left - x).abs() < epsilon ||
        (bounds.center.x - x).abs() < epsilon ||
        (bounds.right - x).abs() < epsilon;
  }

  /// Returns true if [bounds] has top, center.y, or bottom matching [y].
  static bool _yMatches(Bounds bounds, double y) {
    const epsilon = 0.5;
    return (bounds.top - y).abs() < epsilon ||
        (bounds.center.y - y).abs() < epsilon ||
        (bounds.bottom - y).abs() < epsilon;
  }
}
