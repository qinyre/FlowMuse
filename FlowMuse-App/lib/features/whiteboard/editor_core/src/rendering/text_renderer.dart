import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/elements/elements.dart'
    as core
    show TextAlign, TextElement, VerticalAlign;
import 'font_resolver.dart';

/// Renders text elements using Flutter's [TextPainter].
///
/// Text is not drawn with rough_flutter — it uses standard Flutter text
/// layout for readability. This mirrors how Excalidraw renders text
/// (clean, not hand-drawn).
class TextRenderer {
  /// Measures the text in [element] and returns `(width, height)`.
  ///
  /// If [maxWidth] is provided, the text wraps within that width.
  /// Returns `(0, 0)` for empty text.
  static (double, double) measure(
    core.TextElement element, {
    double? maxWidth,
  }) {
    if (element.text.isEmpty) return (0.0, 0.0);

    final painter = buildTextPainter(element);
    painter.layout(maxWidth: maxWidth ?? double.infinity);
    final result = (painter.width, painter.height);
    painter.dispose();
    return result;
  }

  /// Draws a [TextElement] onto [canvas] at the element's position.
  ///
  /// For elements with a fixed height (non-auto-resize), applies
  /// [VerticalAlign] to position text within the element bounds.
  static void draw(ui.Canvas canvas, core.TextElement element) {
    if (element.text.isEmpty) return;
    if (_isVerticalText(element)) {
      _drawVertical(canvas, element);
      return;
    }

    final painter = buildTextPainter(element);
    painter.layout(maxWidth: element.width);

    final dy = switch (element.verticalAlign) {
      core.VerticalAlign.top => 0.0,
      core.VerticalAlign.middle =>
        element.height > 0 ? (element.height - painter.height) / 2 : 0.0,
      core.VerticalAlign.bottom =>
        element.height > 0 ? element.height - painter.height : 0.0,
    };

    painter.paint(canvas, Offset(element.x, element.y + dy));
    painter.dispose();
  }

  static void _drawVertical(ui.Canvas canvas, core.TextElement element) {
    final chars = element.text.runes
        .map((rune) => String.fromCharCode(rune))
        .where((char) => char.trim().isNotEmpty)
        .toList();
    if (chars.isEmpty) return;
    final step = element.fontSize * element.lineHeight;
    var y = element.y;
    for (final char in chars) {
      final painter = buildTextPainter(element.copyWithText(text: char));
      painter.layout(maxWidth: element.width);
      painter.paint(
        canvas,
        Offset(element.x + (element.width - painter.width) / 2, y),
      );
      y += step;
      painter.dispose();
    }
  }

  /// Builds a [TextPainter] configured from the given [element].
  ///
  /// Callers must call [TextPainter.layout] before painting, and
  /// [TextPainter.dispose] when done.
  static TextPainter buildTextPainter(core.TextElement element) {
    final color = _parseColor(
      element.strokeColor,
    ).withValues(alpha: element.opacity);

    final style = FontResolver.resolve(
      element.fontFamily,
      baseStyle: TextStyle(
        color: color,
        fontSize: element.fontSize,
        height: element.lineHeight,
      ),
    );

    return TextPainter(
      text: TextSpan(text: element.text, style: style),
      textAlign: _mapTextAlign(element.textAlign),
      textDirection: ui.TextDirection.ltr,
    );
  }

  /// Draws a frame label above its top-left corner.
  static void drawFrameLabel(
    ui.Canvas canvas,
    String label,
    double x,
    double y,
    String colorStr,
  ) {
    if (label.isEmpty) return;

    final color = _parseColor(colorStr);
    final style = TextStyle(
      color: color,
      fontSize: 14,
      fontFamily: 'Helvetica',
    );

    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: ui.TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, Offset(x, y - painter.height));
    painter.dispose();
  }

  static TextAlign _mapTextAlign(core.TextAlign align) {
    return switch (align) {
      core.TextAlign.left => TextAlign.left,
      core.TextAlign.center => TextAlign.center,
      core.TextAlign.right => TextAlign.right,
    };
  }

  static bool _isVerticalText(core.TextElement element) {
    final flowMuse = element.customData?['flowMuse'];
    if (flowMuse is Map<String, Object?>) {
      return flowMuse['writingMode'] == 'vertical';
    }
    if (flowMuse is Map) {
      return flowMuse['writingMode'] == 'vertical';
    }
    return false;
  }

  static Color _parseColor(String colorStr) {
    if (colorStr == 'transparent') {
      return const Color(0x00000000);
    }
    final hex = colorStr.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('ff$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return const Color(0xFF000000);
  }
}
