import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:rough_flutter/rough_flutter.dart';

import '../natural_media/directional_brush_envelope.dart';
import '../natural_media/natural_media_stroke_plan.dart';
import '../natural_media/natural_media_stroke_sampler.dart';
import '../natural_media/pencil_stroke_renderer_v2.dart';

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
    if (absPoints.isEmpty) return;
    final brushType = brushTypeFromCustomData(element.customData);
    // v2 自然介质（T9）：消费共享 primitive plan/多边形（与 Canvas 同
    // 真源，不复制 sampler/seed/方向滤波），输出真实 <path> 节点
    //（铅笔 ≤4：基底+密度桶；毛笔 ≤2：包络+毫丝）。缺 pressures 的
    // v2 元数据按 v1 导出（与 element_renderer 分发一致）。
    final family = element.pressures.isEmpty
        ? StrokeRendererFamily.classicV1
        : strokeRendererFamilyFor(element.customData);
    if (family == StrokeRendererFamily.pencilV2) {
      _renderPencilV2(buf, element, absPoints);
      return;
    }
    if (family == StrokeRendererFamily.brushPenV2) {
      _renderBrushV2(buf, element, absPoints);
      return;
    }
    // 单一真源：宽度/透明度/taper/端帽全部读 BrushRenderProfile，
    // 与画布渲染共用同一 outline（issue #5 T7）。
    final profile = BrushRenderProfile.forType(brushType);
    final opacity = element.opacity * profile.opacityScale;
    final size = profile.renderSize(element.strokeWidth);

    // 单点：显式圆点（中性压力半径）。画布端单点 drawCircle 同样套
    // profile 混合模式，darken（荧光笔）在此保持一致。
    if (absPoints.length == 1) {
      final p = absPoints[0];
      buf.write('<circle cx="${_n(p.x)}" cy="${_n(p.y)}" r="${_n(size / 2)}" ');
      buf.write('fill="${element.strokeColor}"');
      if (profile.compositeMode == BrushCompositeMode.darken) {
        buf.write(' style="mix-blend-mode:darken"');
      }
      if (opacity < 1.0) {
        buf.write(' opacity="${_n(opacity)}"');
      }
      buf.write('/>');
      return;
    }

    final outline = FreedrawRenderer.buildOutline(
      absPoints,
      strokeWidth: element.strokeWidth,
      pressures: element.simulatePressure ? null : element.pressures,
      pressureEncoded: pressureEncodingFromCustomData(element.customData),
      isComplete: element.isComplete,
      brushType: brushType,
    );
    if (outline.isEmpty) return;
    final d = _outlineToSvgPathData(outline);

    // 铅笔颗粒：小尺寸确定性 pattern（按元素 id 唯一，尺寸随笔宽），
    // 作为覆盖层叠加；查看器不支持 pattern 时主体轮廓仍可见。
    // tile 与画布 shader 频率同源：freq = 4/size（场景坐标）→ 间距 size/4。
    if (profile.usesPencilTexture) {
      final tile = math.max(1.5, size / 4);
      buf.write('<defs>');
      buf.write(
        '<pattern id="pencil-grain-${element.id.value}" '
        'patternUnits="userSpaceOnUse" '
        'width="${_n(tile)}" height="${_n(tile)}">',
      );
      buf.write(
        '<circle cx="${_n(tile * 0.25)}" cy="${_n(tile * 0.25)}" '
        'r="${_n(tile * 0.15)}" fill="${element.strokeColor}" '
        'opacity="0.5"/>',
      );
      buf.write('</pattern>');
      buf.write('</defs>');
    }

    buf.write('<path d="$d" ');
    buf.write('fill="${element.strokeColor}" ');
    if (profile.compositeMode == BrushCompositeMode.darken) {
      // 荧光笔叠加加深：与画布 BlendMode.darken 同义；不支持的查看器
      // 退化为普通半透明（语义降级，元素不消失）。
      buf.write('style="mix-blend-mode:darken" ');
    }
    if (profile.usesPencilTexture) {
      buf.write('stroke="none" ');
    }
    if (opacity < 1.0) {
      buf.write('opacity="${_n(opacity)}" ');
    }
    buf.write('/>');

    if (profile.usesPencilTexture) {
      // 纹理层透明度 = 基准 0.4 × 元素最终 opacity（与光栅路径一致：
      // 光栅颗粒 paint 的 alpha = 元素色 alpha × 0.5，元素透明时颗粒
      // 同步消失）。固定值会让透明铅笔元素导出后仍显示颗粒。
      buf.write(
        '<path d="$d" fill="url(#pencil-grain-${element.id.value})" '
        'opacity="${_n(0.4 * opacity)}" stroke="none"/>',
      );
    }
  }

  /// 铅笔 v2 SVG：基底多边形 + ≤3 密度桶复合 path（颗粒为旋转四边形，
  /// 1~3px 尺度下与椭圆不可分辨，字节量约为四段三次贝塞尔的 1/3）。
  static void _renderPencilV2(
    StringBuffer buf,
    FreedrawElement element,
    List<Point> absPoints,
  ) {
    final profile = BrushRenderProfile.forType(BrushType.pencil);
    final plan = _v2Plan(element, absPoints, BrushType.pencil);
    final polygon = PencilStrokeRendererV2.basePolygon(
      plan,
      element.strokeWidth,
    );
    if (polygon.isEmpty) return;
    _writeV2FillPath(
      buf,
      // SVG 抽稀（不要求逐像素相同，§T9）：顶点上限 8000，稳定等步长
      // 取样并保留末点，16k 点预算内字节量随点数线性。
      _polygonPathData(_decimate(polygon, 8000)),
      fill: element.strokeColor,
      opacity: profile.pencilV2BaseAlpha * element.opacity,
    );
    // 颗粒总上限 4000（跨桶均摊），等步长跳过、不重排。
    final grains = plan.primitives
        .where((p) => p.kind == NaturalMediaPrimitiveKind.pencilGrain)
        .toList();
    final grainStep = math.max(1, (grains.length / 4000).ceil());
    final bucketData = <int, StringBuffer>{};
    var grainKept = 0;
    for (final p in grains) {
      if (grainKept % grainStep != grainStep - 1 && grains.length > 4000) {
        continue;
      }
      grainKept++;
      final b = bucketData.putIfAbsent(p.channel, StringBuffer.new);
      final t = p.tangent!;
      final c = p.center!;
      final ux = t.x * p.halfLength!;
      final uy = t.y * p.halfLength!;
      final vx = -t.y * p.halfThickness!;
      final vy = t.x * p.halfThickness!;
      b.write('M${_n(c.x + ux + vx)},${_n(c.y + uy + vy)}');
      b.write('L${_n(c.x - ux + vx)},${_n(c.y - uy + vy)}');
      b.write('L${_n(c.x - ux - vx)},${_n(c.y - uy - vy)}');
      b.write('L${_n(c.x + ux - vx)},${_n(c.y + uy - vy)}Z');
    }
    final channels = bucketData.keys.toList()..sort();
    for (final channel in channels) {
      _writeV2FillPath(
        buf,
        bucketData[channel]!.toString(),
        fill: element.strokeColor,
        opacity: profile.pencilV2GrainAlpha(channel) * element.opacity,
      );
    }
  }

  /// 毛笔 v2 SVG：主体包络多边形 + 毫丝描边细线（与 Canvas stroke
  /// 口径一致：round cap、0.8px、brushV2StrandAlpha）。
  static void _renderBrushV2(
    StringBuffer buf,
    FreedrawElement element,
    List<Point> absPoints,
  ) {
    final profile = BrushRenderProfile.forType(BrushType.brushPen);
    final plan = _v2Plan(element, absPoints, BrushType.brushPen);
    final polygon = DirectionalBrushEnvelope.bodyPolygon(
      plan,
      element.strokeWidth,
      isComplete: element.isComplete,
    );
    if (polygon.isEmpty) return;
    _writeV2FillPath(
      buf,
      _polygonPathData(_decimate(polygon, 8000)),
      fill: element.strokeColor,
      opacity: element.opacity,
    );
    final strandList = plan.primitives
        .where((p) => p.kind == NaturalMediaPrimitiveKind.brushStrand)
        .toList();
    final strandStep = math.max(1, (strandList.length / 2000).ceil());
    final strands = StringBuffer();
    var hasStrands = false;
    for (var i = 0; i < strandList.length; i++) {
      if (i % strandStep != 0 && strandList.length > 2000) continue;
      final p = strandList[i];
      hasStrands = true;
      final t = p.tangent!;
      final c = p.center!;
      final hl = p.halfLength!;
      strands.write('M${_n(c.x - t.x * hl)},${_n(c.y - t.y * hl)}');
      strands.write('L${_n(c.x + t.x * hl)},${_n(c.y + t.y * hl)}');
    }
    if (hasStrands) {
      buf.write('<path d="${strands.toString()}" ');
      buf.write('fill="none" stroke="${element.strokeColor}" ');
      buf.write('stroke-width="0.8" stroke-linecap="round" ');
      buf.write(
        'opacity="${_n(profile.brushV2StrandAlpha * element.opacity)}"/>',
      );
    }
  }

  static NaturalMediaStrokePlan _v2Plan(
    FreedrawElement element,
    List<Point> absPoints,
    BrushType brushType,
  ) => NaturalMediaStrokeSampler.sample(
    strokeId: element.id.value,
    points: absPoints,
    pressures: element.pressures,
    strokeWidth: element.strokeWidth,
    brushType: brushType,
    isComplete: element.isComplete,
  );

  /// 确定性抽稀：等步长保留 [maxPoints] 内的点，末点必留（闭合不缺
  /// 角）。≤maxPoints 时原样返回。
  static List<Offset> _decimate(List<Offset> polygon, int maxPoints) {
    if (polygon.length <= maxPoints) return polygon;
    final step = (polygon.length / maxPoints).ceil();
    return [
      for (var i = 0; i < polygon.length; i += step) polygon[i],
      if ((polygon.length - 1) % step != 0) polygon.last,
    ];
  }

  static String _polygonPathData(List<Offset> polygon) {
    final b = StringBuffer('M${_n(polygon.first.dx)},${_n(polygon.first.dy)}');
    for (final o in polygon.skip(1)) {
      b.write('L${_n(o.dx)},${_n(o.dy)}');
    }
    return '${b.toString()}Z';
  }

  static void _writeV2FillPath(
    StringBuffer buf,
    String d, {
    required String fill,
    required double opacity,
  }) {
    buf.write('<path d="$d" fill="$fill" ');
    if (opacity < 1.0) {
      buf.write('opacity="${_n(opacity)}" ');
    }
    buf.write('/>');
  }

  /// 闭合轮廓 → SVG path d：与画布 quadratic 中点法逐段一致
  /// （buildOutlinePath 的 SVG 版本，无 Canvas 依赖）。
  static String _outlineToSvgPathData(List<Offset> outline) {
    if (outline.length < 3) {
      // 防御分支：不足三点无法构闭合贝塞尔，退化为合法的 M/L 折线。
      final buf = StringBuffer();
      for (var i = 0; i < outline.length; i++) {
        buf.write(i == 0 ? 'M' : ' L');
        buf.write('${_n(outline[i].dx)} ${_n(outline[i].dy)}');
      }
      return buf.toString();
    }
    final buf = StringBuffer();
    final n = outline.length;
    void mid(int a, int b) {
      buf.write('${_n((outline[a].dx + outline[b].dx) / 2)} ');
      buf.write('${_n((outline[a].dy + outline[b].dy) / 2)} ');
    }

    buf.write('M');
    mid(0, 1);
    for (var i = 1; i <= n; i++) {
      final cur = i % n;
      final next = (i + 1) % n;
      buf.write('Q${_n(outline[cur].dx)} ${_n(outline[cur].dy)} ');
      mid(cur, next);
    }
    buf.write('Z');
    return buf.toString();
  }

  static void _renderText(StringBuffer buf, TextElement element) {
    if (_isVerticalText(element)) {
      _renderVerticalText(buf, element);
      return;
    }
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

  static void _renderVerticalText(StringBuffer buf, TextElement element) {
    final x = element.x + element.width / 2;
    final step = element.fontSize * element.lineHeight;
    buf.write('<text ');
    buf.write('x="${_n(x)}" ');
    buf.write('y="${_n(element.y + element.fontSize)}" ');
    buf.write('font-size="${_n(element.fontSize)}" ');
    buf.write('font-family="${element.fontFamily}" ');
    buf.write('fill="${element.strokeColor}" ');
    buf.write('text-anchor="middle"');
    buf.write('>');
    var index = 0;
    for (final rune in element.text.runes) {
      final char = String.fromCharCode(rune);
      if (char.trim().isEmpty) continue;
      buf.write(
        '<tspan x="${_n(x)}" y="${_n(element.y + element.fontSize + index * step)}">${_escapeXml(char)}</tspan>',
      );
      index++;
    }
    buf.write('</text>');
  }

  static bool _isVerticalText(TextElement element) {
    final flowMuse = element.customData?['flowMuse'];
    if (flowMuse is Map<String, Object?>) {
      return flowMuse['writingMode'] == 'vertical';
    }
    if (flowMuse is Map) {
      return flowMuse['writingMode'] == 'vertical';
    }
    return false;
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
    buf.write('xlink:href="$dataUrl" href="$dataUrl"');
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
    if (v.isNaN || v.isInfinite) return '0';
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
