import 'package:flutter/painting.dart';
import 'package:rough_flutter/rough_flutter.dart';

import '../../core/elements/elements.dart'
    as core
    show Element, FillStyle, StrokeStyle;
import '../../core/elements/elements.dart' hide Element, FillStyle, StrokeStyle;

/// Maps core [Element] string-based properties to Flutter/rough_flutter types.
///
/// This is a value object that bridges the pure-Dart core layer with the
/// Flutter rendering layer.
class DrawStyle {
  final Color strokeColor;
  final Color backgroundColor;
  final core.FillStyle fillStyle;
  final double strokeWidth;
  final core.StrokeStyle strokeStyle;
  final double roughness;
  final double opacity;
  final int seed;
  final Roundness? roundness;

  const DrawStyle({
    required this.strokeColor,
    required this.backgroundColor,
    required this.fillStyle,
    required this.strokeWidth,
    required this.strokeStyle,
    required this.roughness,
    required this.opacity,
    required this.seed,
    this.roundness,
  });

  /// Creates a [DrawStyle] from a core [Element]'s properties.
  factory DrawStyle.fromElement(core.Element element) {
    return DrawStyle(
      strokeColor: _parseColor(element.strokeColor),
      backgroundColor: _parseColor(element.backgroundColor),
      fillStyle: element.fillStyle,
      strokeWidth: element.strokeWidth,
      strokeStyle: element.strokeStyle,
      roughness: element.roughness,
      opacity: element.opacity,
      seed: element.seed,
      roundness: element.roundness,
    );
  }

  /// Converts to a rough_flutter [DrawConfig].
  DrawConfig toDrawConfig() {
    return DrawConfig.build(roughness: roughness, seed: seed);
  }

  /// Returns the appropriate rough_flutter [Filler] for this style's fill.
  ///
  /// Sets [FillerConfig.hachureGap] and [FillerConfig.fillWeight] based on
  /// [strokeWidth] to match Excalidraw's fill density.
  Filler toFiller() {
    final drawConfig = toDrawConfig();
    final fw = strokeWidth / 2;
    return switch (fillStyle) {
      core.FillStyle.solid => SolidFiller(
        FillerConfig.build(
          drawConfig: drawConfig,
          hachureGap: strokeWidth * 2,
          fillWeight: fw,
        ),
      ),
      core.FillStyle.hachure => HachureFiller(
        FillerConfig.build(
          drawConfig: drawConfig,
          hachureGap: strokeWidth * 2,
          fillWeight: fw,
        ),
      ),
      core.FillStyle.crossHatch => CrossHatchFiller(
        FillerConfig.build(
          drawConfig: drawConfig,
          hachureGap: strokeWidth * 3,
          fillWeight: fw,
        ),
      ),
      core.FillStyle.zigzag => ZigZagFiller(
        FillerConfig.build(
          drawConfig: drawConfig,
          hachureGap: strokeWidth * 3,
          fillWeight: fw,
        ),
      ),
    };
  }

  /// Creates a [Paint] configured for stroke outlines.
  Paint toStrokePaint() {
    return Paint()
      ..color = _withOpacity(strokeColor, opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
  }

  /// Creates a [Paint] configured for fill rendering.
  ///
  /// Uses [PaintingStyle.stroke] because rough_flutter's sketch fillers
  /// (hachure, zigzag, etc.) draw lines internally. The stroke width is
  /// set to [strokeWidth] / 2 to match Excalidraw's fill weight.
  Paint toFillPaint() {
    return Paint()
      ..color = _withOpacity(backgroundColor, opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / 2;
  }

  /// Creates a configured rough_flutter [Generator].
  Generator toGenerator() {
    return Generator(toDrawConfig(), toFiller());
  }

  /// Parses a color string (hex or 'transparent') into a [Color].
  static Color _parseColor(String colorStr) {
    if (colorStr == 'transparent') {
      return const Color(0x00000000);
    }
    final hex = colorStr.replaceFirst('#', '');
    if (hex.length == 3) {
      // Expand 3-digit hex: #f00 → #ff0000
      final r = hex[0] * 2;
      final g = hex[1] * 2;
      final b = hex[2] * 2;
      return Color(int.parse('ff$r$g$b', radix: 16));
    }
    if (hex.length == 6) {
      return Color(int.parse('ff$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return const Color(0xFF000000);
  }

  /// Applies opacity to a color by scaling its alpha channel.
  static Color _withOpacity(Color color, double opacity) {
    return color.withValues(alpha: color.a * opacity);
  }
}
