import 'dart:ui';

import '../core/elements/elements.dart' as core show Element, TextElement;
import '../core/elements/elements.dart' hide Element, TextElement;
import '../core/math/math.dart';
import 'rough/draw_style.dart';
import 'rough/rough_adapter.dart';
import 'rough/rough_canvas_adapter.dart';
import 'text_renderer.dart';

/// Dispatches element rendering to the appropriate adapter method.
///
/// This utility maps element types to the correct [RoughAdapter] call,
/// handles canvas rotation for elements with a non-zero angle, and
/// delegates text to [TextRenderer] (not rough_flutter).
class ElementRenderer {
  /// Renders a single [element] onto [canvas] using [adapter].
  ///
  /// Applies rotation if [element.angle] is non-zero.
  /// If [resolvedImages] is provided, image elements use the decoded Image.
  static void render(
    Canvas canvas,
    core.Element element,
    RoughAdapter adapter, {
    Map<String, Image>? resolvedImages,
  }) {
    final hasRotation = element.angle != 0.0;

    if (hasRotation) {
      canvas.save();
      // Rotate around the element's center
      final cx = element.x + element.width / 2;
      final cy = element.y + element.height / 2;
      canvas.translate(cx, cy);
      canvas.rotate(element.angle);
      canvas.translate(-cx, -cy);
    }

    if (adapter is RoughCanvasAdapter) {
      adapter.setCurrentElement(element.id.value, element.hashCode);
    }

    _dispatch(canvas, element, adapter, resolvedImages);

    if (adapter is RoughCanvasAdapter) {
      adapter.setCurrentElement(null, null);
    }

    if (hasRotation) {
      canvas.restore();
    }
  }

  static void _dispatch(
    Canvas canvas,
    core.Element element,
    RoughAdapter adapter,
    Map<String, Image>? resolvedImages,
  ) {
    final style = DrawStyle.fromElement(element);
    final bounds = Bounds.fromLTWH(
      element.x,
      element.y,
      element.width,
      element.height,
    );

    switch (element.type) {
      case 'rectangle':
        adapter.drawRectangle(
          canvas,
          bounds,
          style,
          roundness: element.roundness,
        );
      case 'ellipse':
        adapter.drawEllipse(canvas, bounds, style);
      case 'diamond':
        adapter.drawDiamond(
          canvas,
          bounds,
          style,
          roundness: element.roundness,
        );
      case 'frame':
        _renderFrame(canvas, element, bounds);
      case 'image':
        if (element is ImageElement) {
          _renderImage(canvas, element, bounds, resolvedImages);
        }
      case 'line':
        if (element is LineElement) {
          final absPoints = _absolutePoints(
            element.points,
            element.x,
            element.y,
          );
          if (element.closed) {
            if (element.roundness != null) {
              adapter.drawCurvedPolygon(canvas, absPoints, style);
            } else {
              adapter.drawPolygonLine(canvas, absPoints, style);
            }
          } else if (element.roundness != null) {
            adapter.drawCurvedLine(canvas, absPoints, style);
          } else {
            adapter.drawLine(canvas, absPoints, style);
          }
        }
      case 'arrow':
        if (element is ArrowElement) {
          final absPoints = _absolutePoints(
            element.points,
            element.x,
            element.y,
          );
          switch (element.arrowType) {
            case ArrowType.sharp:
              adapter.drawArrow(
                canvas,
                absPoints,
                element.startArrowhead,
                element.endArrowhead,
                style,
              );
            case ArrowType.round:
              adapter.drawCurvedArrow(
                canvas,
                absPoints,
                element.startArrowhead,
                element.endArrowhead,
                style,
              );
            case ArrowType.sharpElbow:
              adapter.drawElbowArrow(
                canvas,
                absPoints,
                element.startArrowhead,
                element.endArrowhead,
                style,
              );
            case ArrowType.roundElbow:
              adapter.drawRoundElbowArrow(
                canvas,
                absPoints,
                element.startArrowhead,
                element.endArrowhead,
                style,
              );
          }
        }
      case 'freedraw':
        if (element is FreedrawElement) {
          final absPoints = _absolutePoints(
            element.points,
            element.x,
            element.y,
          );
          adapter.drawFreedraw(
            canvas,
            absPoints,
            element.pressures,
            element.simulatePressure,
            style,
          );
        }
      case 'text':
        if (element is core.TextElement) {
          TextRenderer.draw(canvas, element);
        }
      default:
        break; // Unknown type — silently skip
    }
  }

  /// Renders an image element, or a placeholder if the image isn't decoded yet.
  static void _renderImage(
    Canvas canvas,
    ImageElement element,
    Bounds bounds,
    Map<String, Image>? resolvedImages,
  ) {
    final image = resolvedImages?[element.fileId];
    final dst = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.size.width,
      bounds.size.height,
    );

    if (image != null) {
      // Compute source rect (with optional crop)
      Rect src;
      if (element.crop != null) {
        final c = element.crop!;
        src = Rect.fromLTWH(
          c.x * image.width,
          c.y * image.height,
          c.width * image.width,
          c.height * image.height,
        );
      } else {
        src = Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        );
      }

      final paint = Paint()..filterQuality = FilterQuality.medium;
      if (element.opacity < 1.0) {
        paint.color = Color.fromRGBO(0, 0, 0, element.opacity);
      }
      canvas.drawImageRect(image, src, dst, paint);
    } else {
      // Placeholder: grey rect with border
      final fillPaint = Paint()
        ..color = const Color(0xFFE0E0E0)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = const Color(0xFF999999)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRect(dst, fillPaint);
      canvas.drawRect(dst, strokePaint);

      // Draw a simple X to indicate image placeholder
      canvas.drawLine(dst.topLeft, dst.bottomRight, strokePaint);
      canvas.drawLine(dst.topRight, dst.bottomLeft, strokePaint);
    }
  }

  /// Renders a frame with clean (non-rough) lines and a label above the top.
  static void _renderFrame(Canvas canvas, core.Element element, Bounds bounds) {
    final strokePaint = Paint()
      ..color = Color(_parseColor(element.strokeColor))
      ..style = PaintingStyle.stroke
      ..strokeWidth = element.strokeWidth;

    canvas.drawRect(
      Rect.fromLTWH(
        bounds.left,
        bounds.top,
        bounds.size.width,
        bounds.size.height,
      ),
      strokePaint,
    );

    // Draw label above the top-left corner
    if (element is FrameElement) {
      TextRenderer.drawFrameLabel(
        canvas,
        element.label,
        bounds.left,
        bounds.top - 4,
        element.strokeColor,
      );
    }
  }

  /// Parses a hex color string to an int value.
  static int _parseColor(String color) {
    if (color.startsWith('#')) {
      final hex = color.substring(1);
      if (hex.length == 6) {
        return int.parse('FF$hex', radix: 16);
      } else if (hex.length == 8) {
        return int.parse(hex, radix: 16);
      }
    }
    return 0xFF000000; // Default to black
  }

  /// Converts relative points to absolute by adding the element's origin.
  static List<Point> _absolutePoints(List<Point> points, double x, double y) {
    return points.map((p) => Point(p.x + x, p.y + y)).toList();
  }
}
