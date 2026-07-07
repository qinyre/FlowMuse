/// An immutable width/height pair.
///
/// Named `DrawSize` to avoid conflicts with Flutter's `Size`.
class DrawSize {
  final double width;
  final double height;

  const DrawSize(this.width, this.height);

  static const zero = DrawSize(0.0, 0.0);

  double get area => width * height;

  /// Returns true if the point (x, y) lies within this size
  /// (treating origin as 0,0).
  bool contains(double x, double y) =>
      x >= 0 && x <= width && y >= 0 && y <= height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawSize && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'DrawSize($width, $height)';
}
