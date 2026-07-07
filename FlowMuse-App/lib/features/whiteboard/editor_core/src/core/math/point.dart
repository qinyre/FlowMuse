import 'dart:math' as math;

/// An immutable 2D point.
class Point {
  final double x;
  final double y;

  const Point(this.x, this.y);

  static const zero = Point(0.0, 0.0);

  Point operator +(Point other) => Point(x + other.x, y + other.y);

  Point operator -(Point other) => Point(x - other.x, y - other.y);

  Point operator *(double scalar) => Point(x * scalar, y * scalar);

  double distanceTo(Point other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Point && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point($x, $y)';
}
