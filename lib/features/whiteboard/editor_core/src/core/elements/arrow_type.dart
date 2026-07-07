/// The visual style of an arrow element.
///
/// Determines how the arrow path is rendered — straight segments, smooth
/// curves, orthogonal elbows, or rounded elbows.
enum ArrowType {
  /// Straight line segments between points.
  sharp,

  /// Smooth Bezier curve through points.
  round,

  /// Orthogonal (right-angle) segments with sharp corners.
  sharpElbow,

  /// Orthogonal segments with rounded corners at bends.
  roundElbow;

  /// Whether this arrow type uses elbow (orthogonal) routing.
  bool get isElbow => this == sharpElbow || this == roundElbow;
}
