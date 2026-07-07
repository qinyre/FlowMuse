import '../core/math/math.dart';

/// Snaps a point to the nearest grid intersection.
/// Returns the point unchanged if gridSize is null.
Point snapToGrid(Point point, int? gridSize) {
  if (gridSize == null) return point;
  final g = gridSize.toDouble();
  return Point((point.x / g).round() * g, (point.y / g).round() * g);
}

/// Snaps a single coordinate value to the grid.
/// Returns the value unchanged if gridSize is null.
double snapValue(double value, int? gridSize) {
  if (gridSize == null) return value;
  final g = gridSize.toDouble();
  return (value / g).round() * g;
}
