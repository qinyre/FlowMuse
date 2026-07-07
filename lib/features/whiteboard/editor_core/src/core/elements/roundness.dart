/// The type of corner rounding applied to a shape.
enum RoundnessType { adaptive, proportional }

/// Roundness configuration for shape corners.
class Roundness {
  final RoundnessType type;
  final double value;

  const Roundness._({required this.type, required this.value});

  const Roundness.adaptive({required double value})
    : this._(type: RoundnessType.adaptive, value: value);

  const Roundness.proportional({required double value})
    : this._(type: RoundnessType.proportional, value: value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Roundness && type == other.type && value == other.value;

  @override
  int get hashCode => Object.hash(type, value);

  /// Computes the corner radius for a given [dimension] following
  /// Excalidraw's algorithm.
  ///
  /// For [RoundnessType.proportional] (diamonds, lines): 25% of dimension.
  /// For [RoundnessType.adaptive] (rectangles): fixed radius (default 32px)
  /// with proportional fallback for small elements.
  static double cornerRadius(double dimension, Roundness roundness) {
    const proportionalFactor = 0.25;
    const defaultAdaptiveRadius = 32.0;

    switch (roundness.type) {
      case RoundnessType.proportional:
        return dimension * proportionalFactor;
      case RoundnessType.adaptive:
        final fixedRadius = roundness.value > 0
            ? roundness.value
            : defaultAdaptiveRadius;
        final cutoff = fixedRadius / proportionalFactor;
        if (dimension <= cutoff) {
          return dimension * proportionalFactor;
        }
        return fixedRadius;
    }
  }

  @override
  String toString() => 'Roundness(${type.name}, $value)';
}
