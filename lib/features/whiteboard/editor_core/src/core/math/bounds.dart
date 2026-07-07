import 'dart:math' as math;

import 'point.dart';
import 'size.dart';

/// An immutable axis-aligned bounding box.
class Bounds {
  final Point origin;
  final DrawSize size;

  const Bounds(this.origin, this.size);

  factory Bounds.fromLTWH(
    double left,
    double top,
    double width,
    double height,
  ) => Bounds(Point(left, top), DrawSize(width, height));

  double get left => origin.x;
  double get top => origin.y;
  double get right => origin.x + size.width;
  double get bottom => origin.y + size.height;

  Point get center =>
      Point(origin.x + size.width / 2, origin.y + size.height / 2);

  bool containsPoint(Point point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  /// Returns true if this bounds overlaps (strictly) with [other].
  /// Adjacent bounds sharing only an edge do not intersect.
  bool intersects(Bounds other) =>
      left < other.right &&
      right > other.left &&
      top < other.bottom &&
      bottom > other.top;

  /// Returns the smallest bounds that contains both this and [other].
  Bounds union(Bounds other) {
    final minX = math.min(left, other.left);
    final minY = math.min(top, other.top);
    final maxX = math.max(right, other.right);
    final maxY = math.max(bottom, other.bottom);
    return Bounds.fromLTWH(minX, minY, maxX - minX, maxY - minY);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bounds && origin == other.origin && size == other.size;

  @override
  int get hashCode => Object.hash(origin, size);

  @override
  String toString() => 'Bounds($origin, $size)';
}
