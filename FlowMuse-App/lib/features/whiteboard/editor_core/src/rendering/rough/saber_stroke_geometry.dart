import 'dart:math' as math;
import 'dart:ui';

import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart' hide Point;

import '../../core/elements/brush_type.dart';
import '../../core/elements/freedraw_element.dart';
import '../../core/math/point.dart';
import '../../input/outline_render_mode.dart';

class SaberStrokeGeometry {
  const SaberStrokeGeometry._();

  static StrokeOptions optionsFor({
    required BrushType brushType,
    required double strokeWidth,
    required bool hasPressure,
    required bool isComplete,
    required double pressureSensitivity,
  }) {
    final config = SaberBrushConfig.forType(brushType);
    final sensitivity = pressureSensitivity.clamp(0.0, 1.0);
    return StrokeOptions(
      size: math.max(strokeWidth * config.sizeScale, 1.0),
      thinning: hasPressure
          ? config.realPressureThinning(sensitivity)
          : config.simulatedThinning,
      smoothing: config.smoothing,
      streamline: config.streamline,
      simulatePressure: !hasPressure || config.forceSimulatePressure,
      isComplete: isComplete,
      start: config.taperEnabled
          ? StrokeEndOptions.start(
              taperEnabled: true,
              customTaper: config.customTaper,
            )
          : null,
      end: config.taperEnabled
          ? StrokeEndOptions.end(
              taperEnabled: true,
              customTaper: config.customTaper,
            )
          : null,
    );
  }

  static List<PointVector> inputVectors(
    List<Point> points, {
    List<double>? pressures,
    required BrushType brushType,
  }) {
    final config = SaberBrushConfig.forType(brushType);
    final hasPressure =
        config.pressureEnabled &&
        pressures != null &&
        pressures.length == points.length;
    return [
      for (var i = 0; i < points.length; i++)
        PointVector(points[i].x, points[i].y, hasPressure ? pressures[i] : null),
    ];
  }

  static List<PointVector> skipPoints(List<PointVector> points, int n) {
    if (n <= 1) return points;
    final divided = points.length / n;
    const minDivided = 8;
    if (divided < minDivided) {
      n = (n * divided / minDivided).floor();
      if (n <= 1) return points;
    }
    return [
      for (var i = 0; i < points.length - 1; i += n) points[i],
      points.last,
    ];
  }

  static List<Offset> outline(
    List<Point> points, {
    required double strokeWidth,
    List<double>? pressures,
    required BrushType brushType,
    required double pressureSensitivity,
    required bool isComplete,
    SaberStrokeQuality quality = SaberStrokeQuality.high,
  }) {
    if (points.isEmpty) return const [];
    final config = SaberBrushConfig.forType(brushType);
    final hasPressure =
        config.pressureEnabled &&
        pressures != null &&
        pressures.length == points.length;
    final vectors = inputVectors(
      points,
      pressures: pressures,
      brushType: brushType,
    );
    final options = quality == SaberStrokeQuality.low
        ? optionsFor(
            brushType: brushType,
            strokeWidth: strokeWidth,
            hasPressure: false,
            isComplete: isComplete,
            pressureSensitivity: pressureSensitivity,
          ).copyWith(smoothing: 0, streamline: 0, simulatePressure: false)
        : optionsFor(
            brushType: brushType,
            strokeWidth: strokeWidth,
            hasPressure: hasPressure,
            isComplete: isComplete,
            pressureSensitivity: pressureSensitivity,
          );
    return getStroke(skipPoints(vectors, quality.skip), options: options);
  }

  static Path pathFromOutline(
    List<Offset> outline,
    OutlineRenderMode mode, {
    required bool isComplete,
  }) {
    if (outline.isEmpty) return Path();
    if (!isComplete || mode == OutlineRenderMode.polygon || outline.length < 3) {
      return Path()..addPolygon(outline, true);
    }
    return smoothPathFromPolygon(outline);
  }

  static Path smoothPathFromPolygon(List<Offset> polygon) {
    if (polygon.isEmpty) return Path();
    if (polygon.length < 3) return Path()..addPolygon(polygon, true);
    final path = Path();
    final first = polygon.first;
    final start = Offset(
      (first.dx + polygon[1].dx) / 2,
      (first.dy + polygon[1].dy) / 2,
    );
    path.moveTo(start.dx, start.dy);
    for (var i = 1; i <= polygon.length; i++) {
      final current = polygon[i % polygon.length];
      final next = polygon[(i + 1) % polygon.length];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    return path..close();
  }

  static Path freedrawPath(
    FreedrawElement element, {
    required double pressureSensitivity,
    required OutlineRenderMode mode,
    SaberStrokeQuality quality = SaberStrokeQuality.high,
  }) {
    final points = absolutePoints(element);
    final outlinePoints = outline(
      points,
      strokeWidth: element.strokeWidth,
      pressures: element.pressures.isEmpty ? null : element.pressures,
      brushType: brushTypeFromCustomData(element.customData),
      pressureSensitivity: pressureSensitivity,
      isComplete: element.isComplete,
      quality: quality,
    );
    return pathFromOutline(
      outlinePoints,
      mode,
      isComplete: element.isComplete,
    );
  }

  static List<Point> absolutePoints(FreedrawElement element) {
    return [
      for (final point in element.points)
        Point(point.x + element.x, point.y + element.y),
    ];
  }

  static bool hitTestFreedraw(
    Point point,
    FreedrawElement element, {
    required double pressureSensitivity,
    double eraserSize = 10,
  }) {
    final path = freedrawPath(
      element,
      pressureSensitivity: pressureSensitivity,
      mode: OutlineRenderMode.polygon,
      quality: SaberStrokeQuality.low,
    );
    final offset = Offset(point.x, point.y);
    if (element.points.length <= 3 && path.contains(offset)) return true;

    final outlinePoints = outline(
      absolutePoints(element),
      strokeWidth: element.strokeWidth,
      pressures: element.pressures.isEmpty ? null : element.pressures,
      brushType: brushTypeFromCustomData(element.customData),
      pressureSensitivity: pressureSensitivity,
      isComplete: true,
      quality: SaberStrokeQuality.low,
    );
    final sqrSize = eraserSize * eraserSize;
    final skip = switch (outlinePoints.length) {
      < 100 => 1,
      < 1000 => 2,
      _ => 3,
    };
    for (var i = 0; i < outlinePoints.length; i += skip) {
      final vertex = outlinePoints[i];
      final dx = vertex.dx - point.x;
      final dy = vertex.dy - point.y;
      if (dx * dx + dy * dy <= sqrSize) return true;
    }
    return false;
  }

  static double percentInsideSelection(
    Path selection,
    FreedrawElement element, {
    required double pressureSensitivity,
  }) {
    final outlinePoints = outline(
      absolutePoints(element),
      strokeWidth: element.strokeWidth,
      pressures: element.pressures.isEmpty ? null : element.pressures,
      brushType: brushTypeFromCustomData(element.customData),
      pressureSensitivity: pressureSensitivity,
      isComplete: true,
      quality: SaberStrokeQuality.low,
    );
    if (outlinePoints.isEmpty) return 0;
    var inside = 0;
    for (final point in outlinePoints) {
      if (selection.contains(point)) inside++;
    }
    return inside / outlinePoints.length;
  }

  static RecognizedUnistroke? recognizeShape(List<Point> points) {
    if (points.length < 3) return null;
    return recognizeUnistroke([
      for (final point in points) PointVector(point.x, point.y, 0.5),
    ]);
  }

  static bool isStraightLine(List<Point> points, double strokeWidth) {
    if (points.length < 3) return false;
    final recognized = recognizeUnistroke(
      [for (final point in points) PointVector(point.x, point.y, 0.5)],
      overrideReferenceUnistrokes: default$1Unistrokes
          .where((unistroke) => unistroke.name == DefaultUnistrokeNames.line)
          .toList(),
    );
    if (recognized == null || recognized.score < 0.7) return false;
    final dx = points.first.x - points.last.x;
    final dy = points.first.y - points.last.y;
    final minLength = 5 * strokeWidth;
    return dx * dx + dy * dy >= minLength * minLength;
  }
}

enum SaberStrokeQuality {
  low(4),
  high(1);

  const SaberStrokeQuality(this.skip);
  final int skip;
}

class SaberBrushConfig {
  const SaberBrushConfig({
    this.sizeScale = 1.0,
    this.opacityScale = 1.0,
    this.thinning = 0.5,
    this.simulatedThinning = 0.5,
    this.smoothing = 0,
    this.streamline = 0.5,
    this.forceSimulatePressure = false,
    this.pressureEnabled = true,
    this.taperEnabled = false,
    this.customTaper = 0.0,
  });

  final double sizeScale;
  final double opacityScale;
  final double thinning;
  final double simulatedThinning;
  final double smoothing;
  final double streamline;
  final bool forceSimulatePressure;
  final bool pressureEnabled;
  final bool taperEnabled;
  final double customTaper;

  double realPressureThinning(double sensitivity) => thinning * sensitivity;

  static SaberBrushConfig forType(BrushType brushType) {
    return switch (brushType) {
      BrushType.pencil => const SaberBrushConfig(
        sizeScale: 0.82,
        opacityScale: 0.68,
        thinning: 0.45,
        simulatedThinning: 0.32,
        smoothing: 0,
        streamline: 0.1,
        taperEnabled: true,
        customTaper: 1,
      ),
      BrushType.ballpoint => const SaberBrushConfig(
        sizeScale: 0.72,
        thinning: 0,
        simulatedThinning: 0,
        smoothing: 0,
        streamline: 0.5,
        pressureEnabled: false,
      ),
      BrushType.fountainPen => const _FountainPenBrushConfig(),
      BrushType.shapePen => const SaberBrushConfig(
        thinning: 0,
        simulatedThinning: 0,
        smoothing: 0,
        streamline: 0,
        pressureEnabled: false,
      ),
      BrushType.highlighter => const SaberBrushConfig(
        sizeScale: 4.2,
        opacityScale: 0.32,
        thinning: 0,
        simulatedThinning: 0,
        smoothing: 0,
        streamline: 0.5,
        forceSimulatePressure: true,
        pressureEnabled: false,
      ),
    };
  }
}

class _FountainPenBrushConfig extends SaberBrushConfig {
  const _FountainPenBrushConfig()
    : super(
        thinning: 0.9,
        simulatedThinning: 0.5,
        smoothing: 0,
        streamline: 0.5,
      );

  @override
  double realPressureThinning(double sensitivity) => 0.05 + sensitivity * 0.9;
}
