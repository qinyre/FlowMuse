import 'dart:math' as math;

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../../core/scene/scene_exports.dart';

/// Snap radius for binding detection (in scene units).
const double bindingSnapRadius = 20.0;

/// Bindable element types.
const _bindableTypes = {'rectangle', 'ellipse', 'diamond'};

/// Stateless utility methods for arrow–shape binding geometry.
class BindingUtils {
  BindingUtils._();

  /// Returns true for element types that arrows can bind to.
  static bool isBindable(Element element) =>
      _bindableTypes.contains(element.type);

  /// Find the nearest bindable element within [snapRadius] of [scenePoint].
  ///
  /// Points inside a shape always qualify as bind targets (matching Excalidraw
  /// behavior). Points outside must be within [snapRadius] of the shape edge.
  /// Returns null if no bindable element qualifies. Optionally [excludeId] to
  /// skip a specific element (e.g., the arrow being created).
  static Element? findBindTarget(
    Scene scene,
    Point scenePoint, {
    double snapRadius = bindingSnapRadius,
    ElementId? excludeId,
  }) {
    Element? best;
    var bestDist = double.infinity;

    for (final element in scene.activeElements) {
      if (!isBindable(element)) continue;
      if (excludeId != null && element.id == excludeId) continue;

      final inside = _isInsideElement(element, scenePoint);
      final dist = _distanceToEdge(element, scenePoint);

      // Inside the shape → always a valid target.
      // Outside → must be within snapRadius of the edge.
      if (!inside && dist > snapRadius) continue;

      if (dist < bestDist) {
        bestDist = dist;
        best = element;
      }
    }
    return best;
  }

  /// Compute a normalized (0-1, 0-1) fixedPoint for [scenePoint] relative to
  /// [target].
  ///
  /// For points **inside** the target, the fixedPoint preserves the actual
  /// interior position (matching Excalidraw's "inside" binding mode). For
  /// points **outside**, the point is projected onto the nearest bounding-box
  /// edge.
  ///
  /// Accounts for the target's rotation by transforming [scenePoint] into the
  /// element's local coordinate space.
  static Point computeFixedPoint(Element target, Point scenePoint) {
    // Transform into local (unrotated) space
    final local = _toLocal(target, scenePoint);

    final left = target.x;
    final top = target.y;
    final right = target.x + target.width;
    final bottom = target.y + target.height;
    final w = target.width;
    final h = target.height;

    final isInside =
        local.x >= left &&
        local.x <= right &&
        local.y >= top &&
        local.y <= bottom;

    if (isInside) {
      // Preserve the actual interior position as a normalized coordinate.
      final xFrac = w > 0 ? (local.x - left) / w : 0.5;
      final yFrac = h > 0 ? (local.y - top) / h : 0.5;
      return Point(xFrac, yFrac);
    }

    // Outside: project onto nearest edge.
    final cx = local.x.clamp(left, right);
    final cy = local.y.clamp(top, bottom);

    final distLeft = (local.x - left).abs() + (cy - local.y).abs();
    final distRight = (local.x - right).abs() + (cy - local.y).abs();
    final distTop = (local.y - top).abs() + (cx - local.x).abs();
    final distBottom = (local.y - bottom).abs() + (cx - local.x).abs();

    final minDist = [distLeft, distRight, distTop, distBottom].reduce(math.min);

    if (minDist == distLeft) {
      final yFrac = h > 0 ? (cy - top) / h : 0.5;
      return Point(0.0, yFrac);
    } else if (minDist == distRight) {
      final yFrac = h > 0 ? (cy - top) / h : 0.5;
      return Point(1.0, yFrac);
    } else if (minDist == distTop) {
      final xFrac = w > 0 ? (cx - left) / w : 0.5;
      return Point(xFrac, 0.0);
    } else {
      final xFrac = w > 0 ? (cx - left) / w : 0.5;
      return Point(xFrac, 1.0);
    }
  }

  /// Convert a fixedPoint binding back to a scene-space coordinate.
  ///
  /// The fixedPoint is in the element's local (unrotated) space. This method
  /// maps it to world space, accounting for the target's rotation.
  static Point resolveBindingPoint(Element target, PointBinding binding) {
    final fx = binding.fixedPoint.x;
    final fy = binding.fixedPoint.y;
    final localPoint = Point(
      target.x + fx * target.width,
      target.y + fy * target.height,
    );
    return _toWorld(target, localPoint);
  }

  /// Recompute arrow start/end points from current target positions.
  ///
  /// If a binding's target is not found in the scene, that endpoint is left
  /// unchanged.
  static ArrowElement updateBoundArrowEndpoints(
    ArrowElement arrow,
    Scene scene,
  ) {
    if (arrow.startBinding == null && arrow.endBinding == null) return arrow;

    final absPoints = arrow.points
        .map((p) => Point(arrow.x + p.x, arrow.y + p.y))
        .toList();

    var changed = false;

    // Update start point
    if (arrow.startBinding != null) {
      final target = scene.getElementById(
        ElementId(arrow.startBinding!.elementId),
      );
      if (target != null) {
        absPoints[0] = resolveBindingPoint(target, arrow.startBinding!);
        changed = true;
      }
    }

    // Update end point
    if (arrow.endBinding != null) {
      final target = scene.getElementById(
        ElementId(arrow.endBinding!.elementId),
      );
      if (target != null) {
        absPoints[absPoints.length - 1] = resolveBindingPoint(
          target,
          arrow.endBinding!,
        );
        changed = true;
      }
    }

    if (!changed) return arrow;

    // For elbowed arrows, try terminal-only update to preserve middle segments
    var routedPoints = absPoints;
    if (arrow.elbowed) {
      // Build the original absolute points (before endpoint updates)
      final origAbsPoints = arrow.points
          .map((p) => Point(arrow.x + p.x, arrow.y + p.y))
          .toList();

      // Determine which sides changed
      final newStart =
          (arrow.startBinding != null && absPoints.first != origAbsPoints.first)
          ? absPoints.first
          : null;
      final newEnd =
          (arrow.endBinding != null && absPoints.last != origAbsPoints.last)
          ? absPoints.last
          : null;

      // Try terminal-only adjustment first
      final terminalResult = ElbowRouting.updateTerminals(
        origAbsPoints,
        newStart: newStart,
        newEnd: newEnd,
      );

      if (terminalResult != null) {
        routedPoints = terminalResult;
      } else {
        // Fall back to full re-route for short paths
        final startHeading = arrow.startBinding != null
            ? ElbowRouting.headingFromFixedPoint(arrow.startBinding!.fixedPoint)
            : null;
        final endHeading = arrow.endBinding != null
            ? ElbowRouting.headingFromFixedPoint(arrow.endBinding!.fixedPoint)
            : null;
        routedPoints = ElbowRouting.route(
          start: absPoints.first,
          end: absPoints.last,
          startHeading: startHeading,
          endHeading: endHeading,
        );
      }
    }

    // Recalculate bounding box and relative points
    var minX = routedPoints.first.x;
    var minY = routedPoints.first.y;
    var maxX = routedPoints.first.x;
    var maxY = routedPoints.first.y;
    for (final p in routedPoints) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }

    final relPoints = routedPoints
        .map((p) => Point(p.x - minX, p.y - minY))
        .toList();

    return arrow
        .copyWithLine(points: relPoints)
        .copyWith(x: minX, y: minY, width: maxX - minX, height: maxY - minY);
  }

  /// Find all arrows in [scene] that are bound to [elementId].
  static List<ArrowElement> findBoundArrows(Scene scene, ElementId elementId) {
    final result = <ArrowElement>[];
    for (final e in scene.activeElements) {
      if (e is ArrowElement) {
        if (e.startBinding?.elementId == elementId.value ||
            e.endBinding?.elementId == elementId.value) {
          result.add(e);
        }
      }
    }
    return result;
  }

  /// Whether [point] lies inside [element]'s bounding box, accounting for
  /// the element's rotation.
  static bool _isInsideElement(Element element, Point point) {
    final local = _toLocal(element, point);
    return local.x >= element.x &&
        local.x <= element.x + element.width &&
        local.y >= element.y &&
        local.y <= element.y + element.height;
  }

  /// Minimum distance from [point] to the bounding-box edges of [element],
  /// accounting for the element's rotation.
  static double _distanceToEdge(Element element, Point point) {
    // Transform point into element's local (unrotated) coordinate space
    final local = _toLocal(element, point);

    final left = element.x;
    final top = element.y;
    final right = element.x + element.width;
    final bottom = element.y + element.height;

    // Clamp to find nearest point on boundary
    final cx = local.x.clamp(left, right);
    final cy = local.y.clamp(top, bottom);

    // If inside, distance is to nearest edge
    if (local.x >= left &&
        local.x <= right &&
        local.y >= top &&
        local.y <= bottom) {
      return [
        (local.x - left),
        (right - local.x),
        (local.y - top),
        (bottom - local.y),
      ].reduce(math.min);
    }

    // Outside: distance to nearest point on boundary
    return local.distanceTo(Point(cx, cy));
  }

  /// Transform a world-space [point] into the element's local (unrotated)
  /// coordinate space by rotating around the element's center by -angle.
  static Point _toLocal(Element element, Point point) {
    if (element.angle == 0) return point;
    final cx = element.x + element.width / 2;
    final cy = element.y + element.height / 2;
    return _rotatePoint(point, cx, cy, -element.angle);
  }

  /// Transform a local-space [point] back to world space by rotating
  /// around the element's center by +angle.
  static Point _toWorld(Element element, Point point) {
    if (element.angle == 0) return point;
    final cx = element.x + element.width / 2;
    final cy = element.y + element.height / 2;
    return _rotatePoint(point, cx, cy, element.angle);
  }

  /// Rotate [point] around ([cx], [cy]) by [angle] radians.
  static Point _rotatePoint(Point point, double cx, double cy, double angle) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final dx = point.x - cx;
    final dy = point.y - cy;
    return Point(cx + dx * cosA - dy * sinA, cy + dx * sinA + dy * cosA);
  }
}
