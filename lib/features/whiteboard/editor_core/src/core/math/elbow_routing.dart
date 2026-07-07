import 'dart:math' as math;

import 'point.dart';

/// Direction an arrow exits or enters a shape.
enum Heading { up, down, left, right }

/// Stateless utility for computing orthogonal (elbow) arrow routes.
///
/// Follows the BindingUtils/GroupUtils pattern — private constructor,
/// all static methods.
class ElbowRouting {
  ElbowRouting._();

  /// Padding distance extended from bound shape edges.
  static const double padding = 20.0;

  /// Determine heading from a PointBinding's fixedPoint (normalized 0-1).
  ///
  /// - fx near 0 → left edge → heading left
  /// - fx near 1 → right edge → heading right
  /// - fy near 0 → top edge → heading up
  /// - fy near 1 → bottom edge → heading down
  /// - Center/ambiguous → use the edge that the point is closest to
  static Heading headingFromFixedPoint(Point fixedPoint) {
    final fx = fixedPoint.x;
    final fy = fixedPoint.y;

    // Distance to each edge
    final dLeft = fx;
    final dRight = 1.0 - fx;
    final dTop = fy;
    final dBottom = 1.0 - fy;

    final minDist = [dLeft, dRight, dTop, dBottom].reduce(math.min);

    if (minDist == dLeft) return Heading.left;
    if (minDist == dRight) return Heading.right;
    if (minDist == dTop) return Heading.up;
    return Heading.down;
  }

  /// Infer heading from relative position of [to] vs [from].
  ///
  /// Uses the dominant axis (larger delta) to pick cardinal direction.
  static Heading inferHeading(Point from, Point to) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;

    if (dx.abs() >= dy.abs()) {
      return dx >= 0 ? Heading.right : Heading.left;
    } else {
      return dy >= 0 ? Heading.down : Heading.up;
    }
  }

  /// Route an orthogonal path from [start] to [end].
  ///
  /// Returns a list of points forming a path with only 90-degree bends.
  /// If [startHeading] or [endHeading] are null, they are inferred from
  /// the relative positions of start and end.
  static List<Point> route({
    required Point start,
    required Point end,
    Heading? startHeading,
    Heading? endHeading,
  }) {
    final sh = startHeading ?? inferHeading(start, end);
    final eh = endHeading ?? _reverseHeading(inferHeading(end, start));

    // Extend from start in its heading direction
    final p1 = _extend(start, sh, padding);
    // Extend from end in reverse of its heading direction
    final p2 = _extend(end, _reverseHeading(eh), padding);

    // Connect p1 → p2 with orthogonal segments
    final middle = _connectOrthogonal(p1, p2, sh, eh);

    final result = [start, p1, ...middle, p2, end];
    return simplify(result);
  }

  /// Adjust only the terminal segments of an existing elbow path.
  ///
  /// When a bound shape moves, instead of re-routing the entire path
  /// (which destroys user's manual segment adjustments), this method
  /// only updates the first and/or last segments to connect to the new
  /// endpoint positions, preserving all middle segments.
  ///
  /// Returns null if the path has fewer than 3 points (caller should
  /// fall back to full [route]).
  ///
  /// Pass [newStart] and/or [newEnd] for whichever side changed.
  static List<Point>? updateTerminals(
    List<Point> absPoints, {
    Point? newStart,
    Point? newEnd,
  }) {
    if (absPoints.length < 3) return null;

    final pts = List<Point>.of(absPoints);

    if (pts.length == 3) {
      // Special case: 3 points means one middle point shared by both
      // terminal segments. Determine original first segment direction.
      final p0 = newStart ?? pts[0];
      final p2 = newEnd ?? pts[2];

      // Determine if the original first segment was horizontal or vertical
      final origHorizontal =
          (pts[0].y - pts[1].y).abs() <= (pts[0].x - pts[1].x).abs();

      Point newMid;
      if (origHorizontal) {
        // First segment horizontal → middle point takes end's x, start's y
        newMid = Point(p2.x, p0.y);
      } else {
        // First segment vertical → middle point takes start's x, end's y
        newMid = Point(p0.x, p2.y);
      }

      return simplify([p0, newMid, p2]);
    }

    // General case: ≥4 points
    // Update start side
    if (newStart != null) {
      pts[0] = newStart;

      // Look at direction of second segment (P1→P2)
      final p1 = pts[1];
      final p2 = pts[2];
      final secondSegHorizontal = (p1.y - p2.y).abs() <= (p1.x - p2.x).abs();

      if (secondSegHorizontal) {
        // Second segment is horizontal → adjust P1 to keep vertical
        // first segment connecting to it
        pts[1] = Point(newStart.x, p1.y);
      } else {
        // Second segment is vertical → adjust P1 to keep horizontal
        // first segment connecting to it
        pts[1] = Point(p1.x, newStart.y);
      }
    }

    // Update end side
    if (newEnd != null) {
      final lastIdx = pts.length - 1;
      pts[lastIdx] = newEnd;

      // Look at direction of second-to-last segment (PN-3→PN-2)
      final pn3 = pts[lastIdx - 2];
      final pn2 = pts[lastIdx - 1];
      final penultSegHorizontal =
          (pn3.y - pn2.y).abs() <= (pn3.x - pn2.x).abs();

      if (penultSegHorizontal) {
        // Second-to-last is horizontal → adjust PN-2 to keep vertical
        // last segment connecting to it
        pts[lastIdx - 1] = Point(newEnd.x, pn2.y);
      } else {
        // Second-to-last is vertical → adjust PN-2 to keep horizontal
        // last segment connecting to it
        pts[lastIdx - 1] = Point(pn2.x, newEnd.y);
      }
    }

    return simplify(pts);
  }

  /// Remove collinear points and merge segments shorter than [minLength].
  static List<Point> simplify(List<Point> points, {double minLength = 2.0}) {
    if (points.length <= 2) return List.of(points);

    // Remove collinear points
    final filtered = <Point>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final prev = filtered.last;
      final curr = points[i];
      final next = points[i + 1];

      // Check if prev→curr→next are collinear (same direction)
      if (!_isCollinear(prev, curr, next)) {
        filtered.add(curr);
      }
    }
    filtered.add(points.last);

    // Merge short segments by removing points that create tiny jogs
    if (filtered.length <= 2) return filtered;

    final merged = <Point>[filtered.first];
    for (var i = 1; i < filtered.length - 1; i++) {
      final prev = merged.last;
      final curr = filtered[i];
      if (prev.distanceTo(curr) >= minLength) {
        merged.add(curr);
      }
    }
    merged.add(filtered.last);

    return merged;
  }

  /// Reverse a heading direction.
  static Heading _reverseHeading(Heading h) {
    switch (h) {
      case Heading.up:
        return Heading.down;
      case Heading.down:
        return Heading.up;
      case Heading.left:
        return Heading.right;
      case Heading.right:
        return Heading.left;
    }
  }

  /// Extend a point in a heading direction by [distance].
  static Point _extend(Point p, Heading heading, double distance) {
    switch (heading) {
      case Heading.up:
        return Point(p.x, p.y - distance);
      case Heading.down:
        return Point(p.x, p.y + distance);
      case Heading.left:
        return Point(p.x - distance, p.y);
      case Heading.right:
        return Point(p.x + distance, p.y);
    }
  }

  /// Check if three points are collinear (all on same horizontal or vertical line).
  static bool _isCollinear(Point a, Point b, Point c) {
    // All on same horizontal line
    if (a.y == b.y && b.y == c.y) return true;
    // All on same vertical line
    if (a.x == b.x && b.x == c.x) return true;
    return false;
  }

  /// Returns whether a heading is horizontal.
  static bool _isHorizontal(Heading h) =>
      h == Heading.left || h == Heading.right;

  /// Connect two points with orthogonal segments.
  ///
  /// Returns intermediate points (not including p1 and p2 themselves).
  static List<Point> _connectOrthogonal(
    Point p1,
    Point p2,
    Heading startHeading,
    Heading endHeading,
  ) {
    final startH = _isHorizontal(startHeading);
    final endH = _isHorizontal(endHeading);

    if (startH && endH) {
      // Both horizontal: connect with vertical midline or Z/U shape
      return _connectHH(p1, p2, startHeading, endHeading);
    } else if (!startH && !endH) {
      // Both vertical: connect with horizontal midline or Z/U shape
      return _connectVV(p1, p2, startHeading, endHeading);
    } else if (startH && !endH) {
      // Start horizontal, end vertical: L-shape
      return _connectHV(p1, p2);
    } else {
      // Start vertical, end horizontal: L-shape
      return _connectVH(p1, p2);
    }
  }

  /// Both headings horizontal → connect via vertical segment.
  static List<Point> _connectHH(Point p1, Point p2, Heading sh, Heading eh) {
    // Simple case: use midpoint X
    final midX = (p1.x + p2.x) / 2;
    return [Point(midX, p1.y), Point(midX, p2.y)];
  }

  /// Both headings vertical → connect via horizontal segment.
  static List<Point> _connectVV(Point p1, Point p2, Heading sh, Heading eh) {
    final midY = (p1.y + p2.y) / 2;
    return [Point(p1.x, midY), Point(p2.x, midY)];
  }

  /// Start horizontal, end vertical → L-shape.
  static List<Point> _connectHV(Point p1, Point p2) {
    // One bend at (p2.x, p1.y)
    return [Point(p2.x, p1.y)];
  }

  /// Start vertical, end horizontal → L-shape.
  static List<Point> _connectVH(Point p1, Point p2) {
    // One bend at (p1.x, p2.y)
    return [Point(p1.x, p2.y)];
  }
}
