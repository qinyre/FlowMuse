import 'dart:convert';
import 'dart:math' as math;

import 'package:rough_flutter/rough_flutter.dart';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../rough/rough.dart';
import 'svg_path_converter.dart';

/// Renders a single element to SVG markup.
///
/// Mirrors [ElementRenderer] + [RoughCanvasAdapter] dispatch but outputs
/// XML strings instead of canvas draw calls.
class SvgElementRenderer {
  /// Renders [element] to an SVG markup string.
  ///
  /// If [files] is provided, image elements embed their data as data URIs.
  static String render(Element element, {Map<String, ImageFile>? files}) {
    final buf = StringBuffer();
    final hasRotation = element.angle != 0.0;
    final hasOpacity = element.opacity < 1.0;

    // Open rotation group if needed
    if (hasRotation) {
      final cx = element.x + element.width / 2;
      final cy = element.y + element.height / 2;
      final deg = element.angle * 180 / math.pi;
      buf.write('<g transform="rotate(${_n(deg)},${_n(cx)},${_n(cy)})"');
      if (hasOpacity) {
        buf.write(' opacity="${_n(element.opacity)}"');
      }
      buf.write('>');
    } else if (hasOpacity) {
      buf.write('<g opacity="${_n(element.opacity)}">');
    }

    _dispatch(buf, element, files);

    // Close rotation/opacity group
    if (hasRotation || hasOpacity) {
      buf.write('</g>');
    }

    return buf.toString();
  }

  static void _dispatch(
    StringBuffer buf,
    Element element,
    Map<String, ImageFile>? files,
  ) {
    switch (element.type) {
      case 'rectangle':
        _renderShape(buf, element, _ShapeType.rectangle);
      case 'ellipse':
        _renderShape(buf, element, _ShapeType.ellipse);
      case 'diamond':
        _renderShape(buf, element, _ShapeType.diamond);
      case 'image':
        if (element is ImageElement) _renderImage(buf, element, files);
      case 'line':
        if (element is LineElement) _renderLine(buf, element);
      case 'arrow':
        if (element is ArrowElement) _renderArrow(buf, element);
      case 'freedraw':
        if (element is FreedrawElement) _renderFreedraw(buf, element);
      case 'text':
        if (element is TextElement) _renderText(buf, element);
      case 'frame':
        if (element is FrameElement) _renderFrame(buf, element);
    }
  }

  static void _renderShape(
    StringBuffer buf,
    Element element,
    _ShapeType shapeType,
  ) {
    final style = DrawStyle.fromElement(element);
    final generator = style.toGenerator();
    final bounds = Bounds.fromLTWH(
      element.x,
      element.y,
      element.width,
      element.height,
    );

    final Drawable drawable;
    switch (shapeType) {
      case _ShapeType.rectangle:
        if (element.roundness != null) {
          drawable = generator.polygon(
            _roundedRectPoints(bounds, element.roundness!),
          );
        } else {
          drawable = generator.rectangle(
            bounds.left,
            bounds.top,
            bounds.size.width,
            bounds.size.height,
          );
        }
      case _ShapeType.ellipse:
        drawable = generator.ellipse(
          bounds.center.x,
          bounds.center.y,
          bounds.size.width,
          bounds.size.height,
        );
      case _ShapeType.diamond:
        if (element.roundness != null) {
          drawable = generator.polygon(
            _roundedDiamondPoints(bounds, element.roundness!),
          );
        } else {
          final top = PointD(bounds.center.x, bounds.top);
          final right = PointD(bounds.right, bounds.center.y);
          final bottom = PointD(bounds.center.x, bounds.bottom);
          final left = PointD(bounds.left, bounds.center.y);
          drawable = generator.polygon([top, right, bottom, left]);
        }
    }

    _drawableToSvg(buf, drawable, style, element);
  }

  static void _renderLine(StringBuffer buf, LineElement element) {
    final style = DrawStyle.fromElement(element);
    final generator = style.toGenerator();
    final absPoints = _absolutePoints(element.points, element.x, element.y);

    if (absPoints.length < 2) return;

    if (element.closed && absPoints.length >= 3) {
      if (element.roundness != null) {
        // Strip duplicate closing point if last ≈ first
        var pts = absPoints;
        if (pts.length > 3 && _pointsNear(pts.last, pts.first)) {
          pts = pts.sublist(0, pts.length - 1);
        }
        // Discretize Catmull-Rom into a dense polygon (same as canvas renderer)
        final curvePoints = _catmullRomPolygon(pts);
        final drawable = generator.polygon(curvePoints);
        _drawableToSvg(buf, drawable, style, element);
      } else {
        final roughPoints = absPoints.map((p) => PointD(p.x, p.y)).toList();
        final drawable = generator.polygon(roughPoints);
        _drawableToSvg(buf, drawable, style, element);
      }
    } else if (element.roundness != null) {
      final paddedPoints = [
        PointD(absPoints.first.x, absPoints.first.y),
        ...absPoints.map((p) => PointD(p.x, p.y)),
        PointD(absPoints.last.x, absPoints.last.y),
      ];
      final drawable = generator.curvePath(paddedPoints);
      _drawableToSvg(buf, drawable, style, element);
    } else {
      for (var i = 0; i < absPoints.length - 1; i++) {
        final drawable = generator.line(
          absPoints[i].x,
          absPoints[i].y,
          absPoints[i + 1].x,
          absPoints[i + 1].y,
        );
        _drawableToSvg(buf, drawable, style, element);
      }
    }
  }

  static void _renderArrow(StringBuffer buf, ArrowElement element) {
    final absPoints = _absolutePoints(element.points, element.x, element.y);

    if (absPoints.length < 2) return;

    switch (element.arrowType) {
      case ArrowType.sharp:
        _renderRoughArrow(buf, element, absPoints);
      case ArrowType.round:
        _renderCurvedArrow(buf, element, absPoints);
      case ArrowType.sharpElbow:
        _renderElbowArrow(buf, element, absPoints);
      case ArrowType.roundElbow:
        _renderRoundElbowArrow(buf, element, absPoints);
    }
  }

  static void _renderRoughArrow(
    StringBuffer buf,
    ArrowElement element,
    List<Point> absPoints,
  ) {
    final style = DrawStyle.fromElement(element);
    final generator = style.toGenerator();

    // Draw line segments
    for (var i = 0; i < absPoints.length - 1; i++) {
      final drawable = generator.line(
        absPoints[i].x,
        absPoints[i].y,
        absPoints[i + 1].x,
        absPoints[i + 1].y,
      );
      _drawableToSvg(buf, drawable, style, element);
    }

    _renderArrowheads(buf, element, absPoints);
  }

  static void _renderCurvedArrow(
    StringBuffer buf,
    ArrowElement element,
    List<Point> absPoints,
  ) {
    final style = DrawStyle.fromElement(element);
    final generator = style.toGenerator();

    // Pad points so curvePath passes through all user points
    final paddedPoints = [
      PointD(absPoints.first.x, absPoints.first.y),
      ...absPoints.map((p) => PointD(p.x, p.y)),
      PointD(absPoints.last.x, absPoints.last.y),
    ];
    final drawable = generator.curvePath(paddedPoints);
    _drawableToSvg(buf, drawable, style, element);

    _renderArrowheads(buf, element, absPoints);
  }

  static void _renderElbowArrow(
    StringBuffer buf,
    ArrowElement element,
    List<Point> absPoints,
  ) {
    // Build clean polyline path (M...L...L...)
    final d = StringBuffer();
    d.write('M${_n(absPoints.first.x)},${_n(absPoints.first.y)}');
    for (var i = 1; i < absPoints.length; i++) {
      d.write(' L${_n(absPoints[i].x)},${_n(absPoints[i].y)}');
    }

    buf.write('<path d="$d" ');
    buf.write('stroke="${element.strokeColor}" ');
    buf.write('stroke-width="${_n(element.strokeWidth)}" ');
    buf.write('fill="none"');
    final dashArray = _dashArrayFor(element.strokeStyle);
    if (dashArray != null) {
      buf.write(' stroke-dasharray="$dashArray"');
    }
    buf.write('/>');

    _renderArrowheads(buf, element, absPoints);
  }

  static void _renderRoundElbowArrow(
    StringBuffer buf,
    ArrowElement element,
    List<Point> absPoints,
  ) {
    // Build polyline path with Q (quadratic bezier) at corners
    final d = StringBuffer();
    d.write('M${_n(absPoints.first.x)},${_n(absPoints.first.y)}');

    for (var i = 1; i < absPoints.length - 1; i++) {
      final prev = absPoints[i - 1];
      final curr = absPoints[i];
      final next = absPoints[i + 1];

      final segALen = _dist(prev, curr);
      final segBLen = _dist(curr, next);
      final radius = math.min(10.0, math.min(segALen, segBLen) / 2);

      if (radius < 0.5) {
        d.write(' L${_n(curr.x)},${_n(curr.y)}');
        continue;
      }

      final dxA = (curr.x - prev.x) / segALen;
      final dyA = (curr.y - prev.y) / segALen;
      final dxB = (next.x - curr.x) / segBLen;
      final dyB = (next.y - curr.y) / segBLen;

      final arcStartX = curr.x - dxA * radius;
      final arcStartY = curr.y - dyA * radius;
      final arcEndX = curr.x + dxB * radius;
      final arcEndY = curr.y + dyB * radius;

      d.write(' L${_n(arcStartX)},${_n(arcStartY)}');
      d.write(' Q${_n(curr.x)},${_n(curr.y)} ${_n(arcEndX)},${_n(arcEndY)}');
    }

    d.write(' L${_n(absPoints.last.x)},${_n(absPoints.last.y)}');

    buf.write('<path d="$d" ');
    buf.write('stroke="${element.strokeColor}" ');
    buf.write('stroke-width="${_n(element.strokeWidth)}" ');
    buf.write('fill="none"');
    final dashArray = _dashArrayFor(element.strokeStyle);
    if (dashArray != null) {
      buf.write(' stroke-dasharray="$dashArray"');
    }
    buf.write('/>');

    _renderArrowheads(buf, element, absPoints);
  }

  static double _dist(Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static void _renderArrowheads(
    StringBuffer buf,
    ArrowElement element,
    List<Point> absPoints,
  ) {
    // Draw start arrowhead
    if (element.startArrowhead != null) {
      final angle = ArrowheadRenderer.directionAngle(absPoints, isStart: true);
      final d = SvgPathConverter.arrowheadToPathData(
        element.startArrowhead!,
        absPoints.first,
        angle,
        element.strokeWidth,
      );
      final isFilled = _isFilledArrowhead(element.startArrowhead!);
      _writeArrowheadPath(buf, d, element, isFilled);
    }

    // Draw end arrowhead
    if (element.endArrowhead != null) {
      final angle = ArrowheadRenderer.directionAngle(absPoints, isStart: false);
      final d = SvgPathConverter.arrowheadToPathData(
        element.endArrowhead!,
        absPoints.last,
        angle,
        element.strokeWidth,
      );
      final isFilled = _isFilledArrowhead(element.endArrowhead!);
      _writeArrowheadPath(buf, d, element, isFilled);
    }
  }

  static void _renderFreedraw(StringBuffer buf, FreedrawElement element) {
    final absPoints = _absolutePoints(element.points, element.x, element.y);
    final d = SvgPathConverter.freedrawToPathData(
      absPoints,
      element.strokeWidth,
    );
    if (d.isEmpty) return;

    buf.write('<path d="$d" ');
    buf.write('stroke="${element.strokeColor}" ');
    buf.write('stroke-width="${_n(element.strokeWidth)}" ');
    buf.write('fill="none" ');
    buf.write('stroke-linecap="round" ');
    buf.write('stroke-linejoin="round"');
    buf.write('/>');
  }

  static void _renderText(StringBuffer buf, TextElement element) {
    final textAnchor = switch (element.textAlign) {
      TextAlign.left => 'start',
      TextAlign.center => 'middle',
      TextAlign.right => 'end',
    };

    final x = switch (element.textAlign) {
      TextAlign.left => element.x,
      TextAlign.center => element.x + element.width / 2,
      TextAlign.right => element.x + element.width,
    };

    buf.write('<text ');
    buf.write('x="${_n(x)}" ');
    buf.write('y="${_n(element.y + element.fontSize)}" ');
    buf.write('font-size="${_n(element.fontSize)}" ');
    buf.write('font-family="${element.fontFamily}" ');
    buf.write('fill="${element.strokeColor}" ');
    buf.write('text-anchor="$textAnchor"');
    buf.write('>');
    buf.write(_escapeXml(element.text));
    buf.write('</text>');
  }

  static void _renderFrame(StringBuffer buf, FrameElement element) {
    // Clean rectangle border (not rough)
    buf.write('<rect ');
    buf.write('x="${_n(element.x)}" ');
    buf.write('y="${_n(element.y)}" ');
    buf.write('width="${_n(element.width)}" ');
    buf.write('height="${_n(element.height)}" ');
    buf.write('stroke="${element.strokeColor}" ');
    buf.write('stroke-width="${_n(element.strokeWidth)}" ');
    buf.write('fill="none"');
    buf.write('/>');

    // Label above top-left corner
    if (element.label.isNotEmpty) {
      buf.write('<text ');
      buf.write('x="${_n(element.x)}" ');
      buf.write('y="${_n(element.y - 4)}" ');
      buf.write('font-size="14" ');
      buf.write('font-family="Helvetica" ');
      buf.write('fill="${element.strokeColor}" ');
      buf.write('text-anchor="start"');
      buf.write('>');
      buf.write(_escapeXml(element.label));
      buf.write('</text>');
    }
  }

  static void _renderImage(
    StringBuffer buf,
    ImageElement element,
    Map<String, ImageFile>? files,
  ) {
    final file = files?[element.fileId];
    if (file == null) {
      // Placeholder rect for missing image
      buf.write('<rect ');
      buf.write('x="${_n(element.x)}" ');
      buf.write('y="${_n(element.y)}" ');
      buf.write('width="${_n(element.width)}" ');
      buf.write('height="${_n(element.height)}" ');
      buf.write('fill="#E0E0E0" stroke="#999999" stroke-width="1"');
      buf.write('/>');
      return;
    }

    final dataUrl = 'data:${file.mimeType};base64,${base64Encode(file.bytes)}';
    buf.write('<image ');
    buf.write('x="${_n(element.x)}" ');
    buf.write('y="${_n(element.y)}" ');
    buf.write('width="${_n(element.width)}" ');
    buf.write('height="${_n(element.height)}" ');
    buf.write('href="$dataUrl"');
    buf.write(' preserveAspectRatio="none"');
    buf.write('/>');
  }

  static void _drawableToSvg(
    StringBuffer buf,
    Drawable drawable,
    DrawStyle style,
    Element element,
  ) {
    final isTransparent = element.backgroundColor == 'transparent';

    for (final opSet in drawable.sets) {
      final d = SvgPathConverter.opSetToPathData(opSet);
      if (d.isEmpty) continue;

      switch (opSet.type) {
        case OpSetType.fillPath:
          if (!isTransparent) {
            buf.write('<path d="$d" ');
            buf.write('fill="${element.backgroundColor}" ');
            buf.write('stroke="none"');
            buf.write('/>');
          }
        case OpSetType.fillSketch:
          if (!isTransparent) {
            buf.write('<path d="$d" ');
            buf.write('stroke="${element.backgroundColor}" ');
            buf.write('stroke-width="1" ');
            buf.write('fill="none"');
            buf.write('/>');
          }
        case OpSetType.path:
          buf.write('<path d="$d" ');
          buf.write('stroke="${element.strokeColor}" ');
          buf.write('stroke-width="${_n(element.strokeWidth)}" ');
          buf.write('fill="none"');
          final dashArray = _dashArrayFor(element.strokeStyle);
          if (dashArray != null) {
            buf.write(' stroke-dasharray="$dashArray"');
          }
          buf.write('/>');
      }
    }
  }

  static bool _isFilledArrowhead(Arrowhead type) {
    return type == Arrowhead.triangle ||
        type == Arrowhead.dot ||
        type == Arrowhead.circle ||
        type == Arrowhead.diamond;
  }

  static void _writeArrowheadPath(
    StringBuffer buf,
    String d,
    Element element,
    bool isFilled,
  ) {
    if (isFilled) {
      buf.write('<path d="$d" ');
      buf.write('fill="${element.strokeColor}" ');
      buf.write('stroke="none"');
      buf.write('/>');
    } else {
      buf.write('<path d="$d" ');
      buf.write('stroke="${element.strokeColor}" ');
      buf.write('stroke-width="${_n(element.strokeWidth)}" ');
      buf.write('fill="none"');
      buf.write('/>');
    }
  }

  static String? _dashArrayFor(StrokeStyle style) {
    return switch (style) {
      StrokeStyle.solid => null,
      StrokeStyle.dashed => '8,6',
      StrokeStyle.dotted => '1.5,6',
    };
  }

  static bool _pointsNear(Point a, Point b) {
    const eps = 0.01;
    return (a.x - b.x).abs() < eps && (a.y - b.y).abs() < eps;
  }

  static List<Point> _absolutePoints(List<Point> points, double x, double y) {
    return points.map((p) => Point(p.x + x, p.y + y)).toList();
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _n(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    final s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      var end = s.length;
      while (end > 0 && s[end - 1] == '0') {
        end--;
      }
      if (end > 0 && s[end - 1] == '.') end--;
      return s.substring(0, end);
    }
    return s;
  }

  static const _cornerSegments = 10;

  /// Discretizes a closed polygon into smooth Catmull-Rom curve points.
  static List<PointD> _catmullRomPolygon(List<Point> pts) {
    final n = pts.length;
    final result = <PointD>[];
    for (var i = 0; i < n; i++) {
      final p0 = pts[(i - 1 + n) % n];
      final p1 = pts[i];
      final p2 = pts[(i + 1) % n];
      final p3 = pts[(i + 2) % n];
      for (var j = 0; j < _cornerSegments; j++) {
        final t = j / _cornerSegments;
        final tt = t * t;
        final ttt = tt * t;
        result.add(
          PointD(
            0.5 *
                ((-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * ttt +
                    (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * tt +
                    (-p0.x + p2.x) * t +
                    2 * p1.x),
            0.5 *
                ((-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * ttt +
                    (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * tt +
                    (-p0.y + p2.y) * t +
                    2 * p1.y),
          ),
        );
      }
    }
    return result;
  }

  /// Generates polygon points for a rounded rectangle (quadratic Bezier corners).
  static List<PointD> _roundedRectPoints(Bounds bounds, Roundness roundness) {
    final w = bounds.size.width;
    final h = bounds.size.height;
    final r = Roundness.cornerRadius(math.min(w, h), roundness);
    final x = bounds.left;
    final y = bounds.top;
    return [
      PointD(x + r, y),
      PointD(x + w - r, y),
      ..._quadBezier(x + w - r, y, x + w, y, x + w, y + r),
      PointD(x + w, y + h - r),
      ..._quadBezier(x + w, y + h - r, x + w, y + h, x + w - r, y + h),
      PointD(x + r, y + h),
      ..._quadBezier(x + r, y + h, x, y + h, x, y + h - r),
      PointD(x, y + r),
      ..._quadBezier(x, y + r, x, y, x + r, y),
    ];
  }

  /// Generates polygon points for a rounded diamond (cubic Bezier corners).
  static List<PointD> _roundedDiamondPoints(
    Bounds bounds,
    Roundness roundness,
  ) {
    final topX = bounds.center.x;
    final topY = bounds.top;
    final rightX = bounds.right;
    final rightY = bounds.center.y;
    final bottomX = bounds.center.x;
    final bottomY = bounds.bottom;
    final leftX = bounds.left;
    final leftY = bounds.center.y;

    final vr = Roundness.cornerRadius((topX - leftX).abs(), roundness);
    final hr = Roundness.cornerRadius((rightY - topY).abs(), roundness);
    return [
      PointD(topX + vr, topY + hr),
      PointD(rightX - vr, rightY - hr),
      ..._cubicBezier(
        rightX - vr,
        rightY - hr,
        rightX,
        rightY,
        rightX,
        rightY,
        rightX - vr,
        rightY + hr,
      ),
      PointD(bottomX + vr, bottomY - hr),
      ..._cubicBezier(
        bottomX + vr,
        bottomY - hr,
        bottomX,
        bottomY,
        bottomX,
        bottomY,
        bottomX - vr,
        bottomY - hr,
      ),
      PointD(leftX + vr, leftY + hr),
      ..._cubicBezier(
        leftX + vr,
        leftY + hr,
        leftX,
        leftY,
        leftX,
        leftY,
        leftX + vr,
        leftY - hr,
      ),
      PointD(topX - vr, topY + hr),
      ..._cubicBezier(
        topX - vr,
        topY + hr,
        topX,
        topY,
        topX,
        topY,
        topX + vr,
        topY + hr,
      ),
    ];
  }

  static List<PointD> _quadBezier(
    double x0,
    double y0,
    double cx,
    double cy,
    double x1,
    double y1,
  ) {
    final pts = <PointD>[];
    for (var i = 1; i <= _cornerSegments; i++) {
      final t = i / _cornerSegments;
      final mt = 1 - t;
      pts.add(
        PointD(
          mt * mt * x0 + 2 * mt * t * cx + t * t * x1,
          mt * mt * y0 + 2 * mt * t * cy + t * t * y1,
        ),
      );
    }
    return pts;
  }

  static List<PointD> _cubicBezier(
    double x0,
    double y0,
    double cx1,
    double cy1,
    double cx2,
    double cy2,
    double x1,
    double y1,
  ) {
    final pts = <PointD>[];
    for (var i = 1; i <= _cornerSegments; i++) {
      final t = i / _cornerSegments;
      final mt = 1 - t;
      pts.add(
        PointD(
          mt * mt * mt * x0 +
              3 * mt * mt * t * cx1 +
              3 * mt * t * t * cx2 +
              t * t * t * x1,
          mt * mt * mt * y0 +
              3 * mt * mt * t * cy1 +
              3 * mt * t * t * cy2 +
              t * t * t * y1,
        ),
      );
    }
    return pts;
  }
}

enum _ShapeType { rectangle, ellipse, diamond }
