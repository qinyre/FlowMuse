import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import 'draw_style.dart';

/// Abstracts rough-style drawing behind a clean API.
///
/// Implementations translate core element geometry into canvas draw calls,
/// typically using `rough_flutter` for the hand-drawn aesthetic.
abstract class RoughAdapter {
  /// Draws a rectangle with rough/hand-drawn styling.
  ///
  /// When [roundness] is non-null, corners are rounded using the Excalidraw
  /// adaptive/proportional radius algorithm.
  void drawRectangle(
    Canvas canvas,
    Bounds bounds,
    DrawStyle style, {
    Roundness? roundness,
  });

  /// Draws an ellipse with rough/hand-drawn styling.
  void drawEllipse(Canvas canvas, Bounds bounds, DrawStyle style);

  /// Draws a diamond (4 midpoints of bounding box) with rough/hand-drawn styling.
  ///
  /// When [roundness] is non-null, corners are rounded using the Excalidraw
  /// proportional radius algorithm.
  void drawDiamond(
    Canvas canvas,
    Bounds bounds,
    DrawStyle style, {
    Roundness? roundness,
  });

  /// Draws a line (open polyline) through the given points.
  void drawLine(Canvas canvas, List<Point> points, DrawStyle style);

  /// Draws a closed polygon line with fill through the given points.
  void drawPolygonLine(Canvas canvas, List<Point> points, DrawStyle style);

  /// Draws an arrow (line with arrowheads) through the given points.
  void drawArrow(
    Canvas canvas,
    List<Point> points,
    Arrowhead? startArrowhead,
    Arrowhead? endArrowhead,
    DrawStyle style,
  );

  /// Draws a closed curved polygon (smooth Bezier curve) through the given points.
  void drawCurvedPolygon(Canvas canvas, List<Point> points, DrawStyle style);

  /// Draws a curved line (smooth Bezier curve) through the given points.
  void drawCurvedLine(Canvas canvas, List<Point> points, DrawStyle style);

  /// Draws a curved arrow (smooth Bezier curve with arrowheads) through the given points.
  void drawCurvedArrow(
    Canvas canvas,
    List<Point> points,
    Arrowhead? startArrowhead,
    Arrowhead? endArrowhead,
    DrawStyle style,
  );

  /// Draws an elbow (orthogonal) arrow with clean straight lines.
  void drawElbowArrow(
    Canvas canvas,
    List<Point> points,
    Arrowhead? startArrowhead,
    Arrowhead? endArrowhead,
    DrawStyle style,
  );

  /// Draws an elbow (orthogonal) arrow with rounded corners at bends.
  void drawRoundElbowArrow(
    Canvas canvas,
    List<Point> points,
    Arrowhead? startArrowhead,
    Arrowhead? endArrowhead,
    DrawStyle style,
  );

  /// Draws a freehand path through the given points.
  void drawFreedraw(
    Canvas canvas,
    List<Point> points,
    List<double> pressures,
    bool simulatePressure,
    DrawStyle style,
  );
}
