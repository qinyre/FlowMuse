import '../../core/elements/elements.dart';
import '../../core/math/math.dart';

/// Padding cleared around label text on the arrow line (matches Excalidraw).
const double boundTextPadding = 5.0;

/// Utilities for computing arrow label (bound text) positions.
class ArrowLabelUtils {
  ArrowLabelUtils._();

  /// Compute the midpoint of [arrow]'s polyline by walking half the total
  /// path length. Points are converted from relative to absolute coordinates.
  ///
  /// Falls back to bounding box center for single-point arrows.
  static Point computeArrowMidpoint(ArrowElement arrow) {
    final pts = arrow.points
        .map((p) => Point(p.x + arrow.x, p.y + arrow.y))
        .toList();

    if (pts.length < 2) {
      return Point(arrow.x + arrow.width / 2, arrow.y + arrow.height / 2);
    }

    var totalLength = 0.0;
    for (var i = 1; i < pts.length; i++) {
      totalLength += pts[i - 1].distanceTo(pts[i]);
    }

    final halfLength = totalLength / 2;
    var walked = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final segLen = pts[i - 1].distanceTo(pts[i]);
      if (walked + segLen >= halfLength) {
        final remaining = halfLength - walked;
        final t = segLen > 0 ? remaining / segLen : 0.0;
        return Point(
          pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
          pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t,
        );
      }
      walked += segLen;
    }
    return pts.last;
  }

  /// Compute the label position for [arrow] — centered on the midpoint
  /// (matching Excalidraw behavior).
  static Point computeLabelPosition(ArrowElement arrow) {
    return computeArrowMidpoint(arrow);
  }
}
