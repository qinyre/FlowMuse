import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../../core/scene/scene_exports.dart';
import '../bindings/binding_utils.dart';

/// Direction for flowchart node creation and navigation.
enum LinkDirection { up, down, left, right }

/// Gap between a source node edge and the new node edge (scene units).
const double _nodeGap = 100.0;

/// Bindable shape types that can serve as flowchart nodes.
const _flowchartNodeTypes = {'rectangle', 'ellipse', 'diamond'};

/// Stateless utility methods for flowchart creation and navigation.
class FlowchartUtils {
  FlowchartUtils._();

  /// Returns true for rectangle, ellipse, diamond.
  static bool isFlowchartNode(Element element) =>
      _flowchartNodeTypes.contains(element.type);

  /// Get connected nodes reachable from [node] in [direction].
  ///
  /// Examines all elbow arrows bound to [node] and filters by which edge
  /// the arrow connects to (using headingFromFixedPoint).
  static List<Element> getLinkedNodesInDirection(
    Scene scene,
    Element node,
    LinkDirection direction,
  ) {
    final arrows = BindingUtils.findBoundArrows(scene, node.id);
    final results = <Element>[];
    final heading = _directionToHeading(direction);

    for (final arrow in arrows) {
      // Check if this arrow leaves [node] on the correct edge
      if (arrow.startBinding?.elementId == node.id.value) {
        final fp = arrow.startBinding!.fixedPoint;
        if (ElbowRouting.headingFromFixedPoint(fp) == heading) {
          // The other end is the target
          if (arrow.endBinding != null) {
            final target = scene.getElementById(
              ElementId(arrow.endBinding!.elementId),
            );
            if (target != null && isFlowchartNode(target)) {
              results.add(target);
            }
          }
        }
      }
      // Also check arrows arriving at [node] from the opposite direction
      if (arrow.endBinding?.elementId == node.id.value) {
        final fp = arrow.endBinding!.fixedPoint;
        if (ElbowRouting.headingFromFixedPoint(fp) == heading) {
          if (arrow.startBinding != null) {
            final target = scene.getElementById(
              ElementId(arrow.startBinding!.elementId),
            );
            if (target != null && isFlowchartNode(target)) {
              results.add(target);
            }
          }
        }
      }
    }
    return results;
  }

  /// Compute offset for a single new node, accounting for collision avoidance.
  ///
  /// The returned offset is the top-left of the new node. If the direct
  /// position is occupied by an existing linked node, stagger alternating
  /// left/right (or up/down for horizontal directions).
  static Offset getOffset(
    Element startNode,
    List<Element> linkedNodes,
    LinkDirection direction,
  ) {
    final baseOffset = _directOffset(startNode, direction);
    if (linkedNodes.isEmpty) return baseOffset;

    // Check if the direct position collides with any linked node
    final newBounds = Rect.fromLTWH(
      baseOffset.dx,
      baseOffset.dy,
      startNode.width,
      startNode.height,
    );
    final hasCollision = linkedNodes.any((n) {
      final nb = Rect.fromLTWH(n.x, n.y, n.width, n.height);
      return newBounds.overlaps(nb);
    });

    if (!hasCollision) return baseOffset;

    // Stagger perpendicular to the flow direction
    final isHorizontal =
        direction == LinkDirection.left || direction == LinkDirection.right;
    final step = isHorizontal
        ? startNode.height + _nodeGap
        : startNode.width + _nodeGap;

    for (var i = 1; i <= linkedNodes.length + 1; i++) {
      // Try positive then negative offset
      for (final sign in [1.0, -1.0]) {
        final perp = sign * i * step;
        final candidate = isHorizontal
            ? Offset(baseOffset.dx, baseOffset.dy + perp)
            : Offset(baseOffset.dx + perp, baseOffset.dy);

        final candidateBounds = Rect.fromLTWH(
          candidate.dx,
          candidate.dy,
          startNode.width,
          startNode.height,
        );
        final collides = linkedNodes.any((n) {
          final nb = Rect.fromLTWH(n.x, n.y, n.width, n.height);
          return candidateBounds.overlaps(nb);
        });
        if (!collides) return candidate;
      }
    }
    return baseOffset; // fallback
  }

  /// Create a single new node + binding arrow. Returns list of 2 elements
  /// (node first, arrow second).
  static List<Element> createNodeAndArrow(
    Element startNode,
    LinkDirection direction,
    Scene scene,
  ) {
    final linked = getLinkedNodesInDirection(scene, startNode, direction);
    final offset = getOffset(startNode, linked, direction);
    final node = _cloneNode(startNode, offset);
    final arrow = createBindingArrow(startNode, node, direction);
    return [node, arrow];
  }

  /// Create N nodes fanned out from startNode. Returns list of 2*N elements.
  ///
  /// Evenly distributes nodes perpendicular to the flow direction.
  static List<Element> createFannedNodes(
    Element startNode,
    LinkDirection direction,
    Scene scene,
    int count,
  ) {
    final isHorizontal =
        direction == LinkDirection.left || direction == LinkDirection.right;
    final baseOffset = _directOffset(startNode, direction);

    // Compute perpendicular step
    final step = isHorizontal
        ? startNode.height + _nodeGap
        : startNode.width + _nodeGap;

    // Center the fan: offsets are -(count-1)/2 * step .. +(count-1)/2 * step
    final results = <Element>[];
    for (var i = 0; i < count; i++) {
      final perp = (i - (count - 1) / 2.0) * step;
      final offset = isHorizontal
          ? Offset(baseOffset.dx, baseOffset.dy + perp)
          : Offset(baseOffset.dx + perp, baseOffset.dy);

      final node = _cloneNode(startNode, offset);
      final arrow = createBindingArrow(startNode, node, direction);
      results.addAll([node, arrow]);
    }
    return results;
  }

  /// Create an elbow arrow between two nodes with proper bindings.
  static ArrowElement createBindingArrow(
    Element startNode,
    Element endNode,
    LinkDirection direction,
  ) {
    final arrowId = ElementId.generate();

    // Compute fixed points based on direction
    final startFP = _fixedPointForDirection(direction);
    final endFP = _fixedPointForDirection(_oppositeDirection(direction));

    // Resolve absolute start/end from fixed points
    final startPt = Point(
      startNode.x + startFP.x * startNode.width,
      startNode.y + startFP.y * startNode.height,
    );
    final endPt = Point(
      endNode.x + endFP.x * endNode.width,
      endNode.y + endFP.y * endNode.height,
    );

    // Route the elbow path
    final startHeading = ElbowRouting.headingFromFixedPoint(startFP);
    final endHeading = ElbowRouting.headingFromFixedPoint(endFP);
    final routedPoints = ElbowRouting.route(
      start: startPt,
      end: endPt,
      startHeading: startHeading,
      endHeading: endHeading,
    );

    // Compute bounding box
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

    return ArrowElement(
      id: arrowId,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      points: relPoints,
      endArrowhead: Arrowhead.arrow,
      arrowType: ArrowType.sharpElbow,
      startBinding: PointBinding(
        elementId: startNode.id.value,
        fixedPoint: startFP,
      ),
      endBinding: PointBinding(elementId: endNode.id.value, fixedPoint: endFP),
    );
  }

  // --- Private helpers ---

  /// Direct placement offset — node center aligned with parent center on the
  /// perpendicular axis, with [_nodeGap] between edges on the flow axis.
  static Offset _directOffset(Element startNode, LinkDirection direction) {
    switch (direction) {
      case LinkDirection.right:
        return Offset(startNode.x + startNode.width + _nodeGap, startNode.y);
      case LinkDirection.left:
        return Offset(startNode.x - startNode.width - _nodeGap, startNode.y);
      case LinkDirection.down:
        return Offset(startNode.x, startNode.y + startNode.height + _nodeGap);
      case LinkDirection.up:
        return Offset(startNode.x, startNode.y - startNode.height - _nodeGap);
    }
  }

  /// Clone a node with a new ID at the given offset, preserving visual style.
  static Element _cloneNode(Element startNode, Offset offset) {
    return startNode.copyWith(
      id: ElementId.generate(),
      x: offset.dx,
      y: offset.dy,
      boundElements: const [],
      frameId: startNode.frameId,
    );
  }

  /// Fixed point on the source node's edge for the given direction.
  static Point _fixedPointForDirection(LinkDirection direction) {
    switch (direction) {
      case LinkDirection.right:
        return const Point(1.0, 0.5);
      case LinkDirection.left:
        return const Point(0.0, 0.5);
      case LinkDirection.down:
        return const Point(0.5, 1.0);
      case LinkDirection.up:
        return const Point(0.5, 0.0);
    }
  }

  static Heading _directionToHeading(LinkDirection direction) {
    switch (direction) {
      case LinkDirection.up:
        return Heading.up;
      case LinkDirection.down:
        return Heading.down;
      case LinkDirection.left:
        return Heading.left;
      case LinkDirection.right:
        return Heading.right;
    }
  }

  static LinkDirection _oppositeDirection(LinkDirection direction) {
    switch (direction) {
      case LinkDirection.up:
        return LinkDirection.down;
      case LinkDirection.down:
        return LinkDirection.up;
      case LinkDirection.left:
        return LinkDirection.right;
      case LinkDirection.right:
        return LinkDirection.left;
    }
  }
}
