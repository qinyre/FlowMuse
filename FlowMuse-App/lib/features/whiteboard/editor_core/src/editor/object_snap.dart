import '../core/elements/elements.dart';
import '../core/math/math.dart';
import '../core/scene/scene_exports.dart';
import '../rendering/interactive/snap_line.dart';

/// Pre-computed reference positions from scene elements for object snapping.
class ObjectSnapCache {
  /// X-coordinates for vertical alignment (left, centerX, right of each element).
  final List<double> xPositions;

  /// Y-coordinates for horizontal alignment (top, centerY, bottom of each element).
  final List<double> yPositions;

  /// Source bounds for computing snap line extents.
  final List<Bounds> sourceBounds;

  const ObjectSnapCache({
    required this.xPositions,
    required this.yPositions,
    required this.sourceBounds,
  });

  static const empty = ObjectSnapCache(
    xPositions: [],
    yPositions: [],
    sourceBounds: [],
  );
}

/// Result of snapping moving bounds to reference positions.
class ObjectSnapResult {
  final double dx;
  final double dy;
  final List<SnapLine> snapLines;

  const ObjectSnapResult({
    required this.dx,
    required this.dy,
    required this.snapLines,
  });
}

/// Builds a snap cache from the scene, excluding [excludeIds] and bound text.
ObjectSnapCache buildObjectSnapCache(Scene scene, Set<ElementId> excludeIds) {
  final xPositions = <double>[];
  final yPositions = <double>[];
  final sourceBounds = <Bounds>[];

  for (final element in scene.activeElements) {
    if (excludeIds.contains(element.id)) continue;
    // Skip bound text — it moves with its parent
    if (element is TextElement && element.containerId != null) continue;

    final bounds = Bounds.fromLTWH(
      element.x,
      element.y,
      element.width,
      element.height,
    );

    xPositions.add(bounds.left);
    xPositions.add(bounds.center.x);
    xPositions.add(bounds.right);

    yPositions.add(bounds.top);
    yPositions.add(bounds.center.y);
    yPositions.add(bounds.bottom);

    sourceBounds.add(bounds);
  }

  return ObjectSnapCache(
    xPositions: xPositions,
    yPositions: yPositions,
    sourceBounds: sourceBounds,
  );
}

/// Snaps [movingBounds] to reference positions in [cache].
///
/// Returns adjusted dx/dy offsets and snap lines to render.
/// [threshold] is the maximum distance (in scene units) to snap.
ObjectSnapResult snapToObjects(
  Bounds movingBounds,
  ObjectSnapCache cache,
  double threshold,
) {
  // Moving bounds positions
  final movingXs = [
    movingBounds.left,
    movingBounds.center.x,
    movingBounds.right,
  ];
  final movingYs = [
    movingBounds.top,
    movingBounds.center.y,
    movingBounds.bottom,
  ];

  // Find best X snap
  double bestDx = double.infinity;
  double? snapX;
  for (final mx in movingXs) {
    for (final rx in cache.xPositions) {
      final dist = (mx - rx).abs();
      if (dist < bestDx.abs() && dist <= threshold) {
        bestDx = rx - mx;
        snapX = rx;
      }
    }
  }

  // Find best Y snap
  double bestDy = double.infinity;
  double? snapY;
  for (final my in movingYs) {
    for (final ry in cache.yPositions) {
      final dist = (my - ry).abs();
      if (dist < bestDy.abs() && dist <= threshold) {
        bestDy = ry - my;
        snapY = ry;
      }
    }
  }

  final dx = snapX != null ? bestDx : 0.0;
  final dy = snapY != null ? bestDy : 0.0;

  // Build snap lines
  final snapLines = <SnapLine>[];

  if (snapX != null) {
    // Compute vertical line extent: min/max Y across all matching bounds + moving
    final snappedMoving = Bounds.fromLTWH(
      movingBounds.left + dx,
      movingBounds.top + dy,
      movingBounds.size.width,
      movingBounds.size.height,
    );
    var minY = snappedMoving.top;
    var maxY = snappedMoving.bottom;

    for (final b in cache.sourceBounds) {
      if (_boundsMatchesX(b, snapX)) {
        if (b.top < minY) minY = b.top;
        if (b.bottom > maxY) maxY = b.bottom;
      }
    }

    snapLines.add(
      SnapLine(
        orientation: SnapLineOrientation.vertical,
        position: snapX,
        start: minY,
        end: maxY,
      ),
    );
  }

  if (snapY != null) {
    final snappedMoving = Bounds.fromLTWH(
      movingBounds.left + dx,
      movingBounds.top + dy,
      movingBounds.size.width,
      movingBounds.size.height,
    );
    var minX = snappedMoving.left;
    var maxX = snappedMoving.right;

    for (final b in cache.sourceBounds) {
      if (_boundsMatchesY(b, snapY)) {
        if (b.left < minX) minX = b.left;
        if (b.right > maxX) maxX = b.right;
      }
    }

    snapLines.add(
      SnapLine(
        orientation: SnapLineOrientation.horizontal,
        position: snapY,
        start: minX,
        end: maxX,
      ),
    );
  }

  return ObjectSnapResult(dx: dx, dy: dy, snapLines: snapLines);
}

/// Returns true if [bounds] has left, center.x, or right matching [x].
bool _boundsMatchesX(Bounds bounds, double x) {
  const epsilon = 0.5;
  return (bounds.left - x).abs() < epsilon ||
      (bounds.center.x - x).abs() < epsilon ||
      (bounds.right - x).abs() < epsilon;
}

/// Returns true if [bounds] has top, center.y, or bottom matching [y].
bool _boundsMatchesY(Bounds bounds, double y) {
  const epsilon = 0.5;
  return (bounds.top - y).abs() < epsilon ||
      (bounds.center.y - y).abs() < epsilon ||
      (bounds.bottom - y).abs() < epsilon;
}
