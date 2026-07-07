import 'dart:ui';

import '../../core/elements/elements.dart';

/// Utility for converting paths into dashed or dotted patterns.
class PathDashUtility {
  /// Returns the dash pattern for a given [StrokeStyle], or null for solid.
  ///
  /// Pattern is `[dashLength, gapLength]` in logical pixels.
  static List<double>? patternFor(StrokeStyle style) {
    return switch (style) {
      StrokeStyle.solid => null,
      StrokeStyle.dashed => const [8.0, 6.0],
      StrokeStyle.dotted => const [1.5, 6.0],
    };
  }

  /// Returns a dashed version of [path] for the given [style].
  ///
  /// If [style] is [StrokeStyle.solid], returns the original path unchanged.
  static Path dashPath(Path path, StrokeStyle style) {
    final pattern = patternFor(style);
    if (pattern == null) return path;

    final result = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var drawDash = true;
      while (distance < metric.length) {
        final segLength = drawDash ? pattern[0] : pattern[1];
        final end = (distance + segLength).clamp(0.0, metric.length);
        if (drawDash) {
          final segment = metric.extractPath(distance, end);
          result.addPath(segment, Offset.zero);
        }
        distance = end;
        drawDash = !drawDash;
      }
    }
    return result;
  }
}
