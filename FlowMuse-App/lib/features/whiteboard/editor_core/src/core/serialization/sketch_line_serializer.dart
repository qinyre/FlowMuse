import 'dart:math' as math;

import '../elements/elements.dart';
import '../math/math.dart';
import 'color_names.dart';

/// Reverse mapping: font family → category alias for serialization.
const _fontToAlias = {
  'Excalifont': 'hand-drawn',
  'Nunito': 'normal',
  'Source Code Pro': 'code',
};

/// Returns the named size alias for a preset font size, or null.
String? _sizeAlias(double size) {
  // Use exact int comparison to avoid floating-point issues
  final i = size.toInt();
  if (size != i.toDouble()) return null;
  return switch (i) {
    16 => 's',
    20 => 'm',
    28 => 'l',
    36 => 'xl',
    _ => null,
  };
}

/// Serializes a single Element to a .markdraw sketch line string.
class SketchLineSerializer {
  /// Serialize an element to a single sketch line.
  ///
  /// [alias] is the short alias for this element's ID (if any).
  /// [aliasMap] maps element IDs to aliases (used for arrow binding references).
  String serialize(
    Element element, {
    String? alias,
    Map<String, String> aliasMap = const {},
    Map<String, Element> elementMap = const {},
  }) {
    return switch (element) {
      ArrowElement() => _serializeArrow(element, alias, aliasMap, elementMap),
      LineElement() => _serializeLine(element, alias),
      FrameElement() => _serializeFrame(element, alias),
      ImageElement() => _serializeImage(element, alias),
      RectangleElement() => _serializeShape('rect', element, alias),
      EllipseElement() => _serializeShape('ellipse', element, alias),
      DiamondElement() => _serializeShape('diamond', element, alias),
      TextElement() => _serializeText(element, alias),
      FreedrawElement() => _serializeFreedraw(element, alias),
      _ => _serializeShape(element.type, element, alias),
    };
  }

  /// Serialize a shape element with a bound text label inlined.
  String serializeWithLabel(
    Element element,
    TextElement labelElement, {
    String? alias,
    Map<String, String> aliasMap = const {},
    Map<String, Element> elementMap = const {},
  }) {
    if (element is ArrowElement) {
      return _serializeArrowWithLabel(
        element,
        alias,
        aliasMap,
        elementMap,
        labelElement,
      );
    }
    final keyword = switch (element) {
      RectangleElement() => 'rect',
      EllipseElement() => 'ellipse',
      DiamondElement() => 'diamond',
      _ => element.type,
    };
    return _serializeShapeWithLabel(keyword, element, alias, labelElement);
  }

  String _serializeShapeWithLabel(
    String keyword,
    Element element,
    String? alias,
    TextElement labelElement,
  ) {
    final parts = <String>[keyword];
    _addId(parts, alias);
    parts.add('"${labelElement.text}"');
    _addPosition(parts, element.x, element.y);
    _addSize(parts, element.width, element.height);
    _addTextProperties(parts, labelElement);
    _addCommonProperties(parts, element);
    return parts.join(' ');
  }

  String _serializeArrowWithLabel(
    ArrowElement element,
    String? alias,
    Map<String, String> aliasMap,
    Map<String, Element> elementMap,
    TextElement labelElement,
  ) {
    final parts = <String>['arrow'];
    _addId(parts, alias);
    parts.add('"${labelElement.text}"');

    _addArrowBody(parts, element, aliasMap, elementMap);
    _addTextProperties(parts, labelElement);
    _addCommonProperties(parts, element, isArrow: true);
    return parts.join(' ');
  }

  void _addTextProperties(List<String> parts, TextElement labelElement) {
    if (labelElement.fontSize != 20.0) {
      final sizeAlias = _sizeAlias(labelElement.fontSize);
      parts.add(
        sizeAlias != null
            ? 'text-size=$sizeAlias'
            : 'text-size=${_formatNum(labelElement.fontSize)}',
      );
    }
    if (labelElement.fontFamily != 'Excalifont') {
      final fontAlias = _fontToAlias[labelElement.fontFamily];
      parts.add(
        fontAlias != null
            ? 'text-font=$fontAlias'
            : 'text-font=${_quoteIfNeeded(labelElement.fontFamily)}',
      );
    }
    if (labelElement.textAlign != TextAlign.center) {
      parts.add('text-align=${labelElement.textAlign.name}');
    }
    if (labelElement.verticalAlign != VerticalAlign.middle) {
      parts.add('text-valign=${labelElement.verticalAlign.name}');
    }
    if (labelElement.strokeColor != '#000000') {
      parts.add('text-color=${formatColor(labelElement.strokeColor)}');
    }
  }

  String _serializeFrame(FrameElement element, String? alias) {
    final parts = <String>['frame'];
    _addId(parts, alias);
    parts.add('"${element.label}"');
    _addPosition(parts, element.x, element.y);
    _addSize(parts, element.width, element.height);
    _addCommonProperties(parts, element);
    return parts.join(' ');
  }

  String _serializeImage(ImageElement element, String? alias) {
    final parts = <String>['image'];
    _addId(parts, alias);
    _addPosition(parts, element.x, element.y);
    _addSize(parts, element.width, element.height);
    parts.add('file=${element.fileId}');
    if (element.crop != null && !element.crop!.isFullImage) {
      final c = element.crop!;
      parts.add(
        'crop=${_formatNum(c.x)},${_formatNum(c.y)},${_formatNum(c.width)},${_formatNum(c.height)}',
      );
    }
    if (element.imageScale != 1.0) {
      parts.add('scale=${_formatNum(element.imageScale)}');
    }
    _addCommonProperties(parts, element);
    return parts.join(' ');
  }

  String _serializeShape(String keyword, Element element, String? alias) {
    final parts = <String>[keyword];
    _addId(parts, alias);
    _addPosition(parts, element.x, element.y);
    _addSize(parts, element.width, element.height);
    _addCommonProperties(parts, element);
    return parts.join(' ');
  }

  String _serializeText(TextElement element, String? alias) {
    final parts = <String>['text'];
    _addId(parts, alias);
    parts.add('"${element.text}"');
    _addPosition(parts, element.x, element.y);
    _addSize(parts, element.width, element.height);
    if (element.fontSize != 20.0) {
      final sizeAlias = _sizeAlias(element.fontSize);
      parts.add(
        sizeAlias != null
            ? 'size=$sizeAlias'
            : 'size=${_formatNum(element.fontSize)}',
      );
    }
    if (element.fontFamily != 'Excalifont') {
      final fontAlias = _fontToAlias[element.fontFamily];
      parts.add(
        fontAlias != null
            ? 'font=$fontAlias'
            : 'font=${_quoteIfNeeded(element.fontFamily)}',
      );
    }
    if (element.textAlign != TextAlign.left) {
      parts.add('align=${element.textAlign.name}');
    }
    if (element.verticalAlign != VerticalAlign.middle) {
      parts.add('valign=${element.verticalAlign.name}');
    }
    _addCommonProperties(parts, element);
    return parts.join(' ');
  }

  String _serializeLine(LineElement element, String? alias) {
    final parts = <String>['line'];
    _addId(parts, alias);
    _addPoints(parts, _absolutePoints(element));
    _addArrowheads(parts, element.startArrowhead, element.endArrowhead, false);
    if (element.closed) {
      parts.add('closed');
    }
    _addCommonProperties(parts, element);
    return parts.join(' ');
  }

  String _serializeArrow(
    ArrowElement element,
    String? alias,
    Map<String, String> aliasMap,
    Map<String, Element> elementMap,
  ) {
    final parts = <String>['arrow'];
    _addId(parts, alias);

    _addArrowBody(parts, element, aliasMap, elementMap);
    _addCommonProperties(parts, element, isArrow: true);
    return parts.join(' ');
  }

  /// Adds arrow-specific parts: bindings/points, arrow type, arrowheads.
  void _addArrowBody(
    List<String> parts,
    ArrowElement element,
    Map<String, String> aliasMap,
    Map<String, Element> elementMap,
  ) {
    final hasBindings =
        element.startBinding != null || element.endBinding != null;

    if (hasBindings) {
      // Start end
      if (element.startBinding != null) {
        final fromAlias =
            aliasMap[element.startBinding!.elementId] ??
            element.startBinding!.elementId;
        final fp = element.startBinding!.fixedPoint;
        if (fp.x == 1.0 && fp.y == 0.5) {
          parts.add('from $fromAlias');
        } else {
          final target = elementMap[element.startBinding!.elementId];
          final fpSuffix = _fixedPointToPixelSuffix(fp, target);
          parts.add('from $fromAlias$fpSuffix');
        }
      } else {
        // Unbound start — emit start coordinate
        final startPt = _absolutePoints(element).first;
        parts.add('from ${_formatNum(startPt.x)},${_formatNum(startPt.y)}');
      }

      // End end
      if (element.endBinding != null) {
        final toAlias =
            aliasMap[element.endBinding!.elementId] ??
            element.endBinding!.elementId;
        final fp = element.endBinding!.fixedPoint;
        if (fp.x == 0.0 && fp.y == 0.5) {
          parts.add('to $toAlias');
        } else {
          final target = elementMap[element.endBinding!.elementId];
          final fpSuffix = _fixedPointToPixelSuffix(fp, target);
          parts.add('to $toAlias$fpSuffix');
        }
      } else {
        // Unbound end — emit end coordinate
        final endPt = _absolutePoints(element).last;
        parts.add('to ${_formatNum(endPt.x)},${_formatNum(endPt.y)}');
      }
    } else {
      _addPoints(parts, _absolutePoints(element));
    }

    // Emit arrow type (omit for default 'sharp')
    switch (element.arrowType) {
      case ArrowType.sharp:
        break; // Default — omit
      case ArrowType.round:
        parts.add('arrow-type=round');
      case ArrowType.sharpElbow:
        parts.add('arrow-type=sharp-elbow');
      case ArrowType.roundElbow:
        parts.add('arrow-type=round-elbow');
    }

    // Arrow default endArrowhead is Arrowhead.arrow, so only emit non-defaults
    _addArrowheads(parts, element.startArrowhead, element.endArrowhead, true);
  }

  String _serializeFreedraw(FreedrawElement element, String? alias) {
    final parts = <String>['freedraw'];
    _addId(parts, alias);
    _addPoints(parts, _absolutePoints(element));
    if (element.pressures.isNotEmpty) {
      final pressureStr = element.pressures.map(_formatNum).join(',');
      parts.add('pressure=[$pressureStr]');
    }
    if (!element.simulatePressure) {
      parts.add('no-simulate-pressure');
    }
    _addCommonProperties(parts, element);
    return parts.join(' ');
  }

  void _addId(List<String> parts, String? alias) {
    if (alias != null) {
      parts.add('id=$alias');
    }
  }

  void _addPosition(List<String> parts, double x, double y) {
    parts.add('at ${_formatNum(x)},${_formatNum(y)}');
  }

  void _addSize(List<String> parts, double width, double height) {
    parts.add('${_formatNum(width)}x${_formatNum(height)}');
  }

  void _addPoints(List<String> parts, List<Point> points) {
    final pointsStr = points
        .map((p) => '${_formatNum(p.x)},${_formatNum(p.y)}')
        .join(' ');
    parts.add('points=[$pointsStr]');
  }

  void _addArrowheads(
    List<String> parts,
    Arrowhead? start,
    Arrowhead? end,
    bool isArrow,
  ) {
    if (start != null) {
      parts.add('start-arrow=${start.name}');
    }
    if (isArrow) {
      // Arrow's default endArrowhead is Arrowhead.arrow — only emit if different
      if (end != null && end != Arrowhead.arrow) {
        parts.add('end-arrow=${end.name}');
      }
    } else {
      // Line has no default arrowhead — emit if present
      if (end != null) {
        parts.add('end-arrow=${end.name}');
      }
    }
  }

  void _addCommonProperties(
    List<String> parts,
    Element element, {
    bool isArrow = false,
  }) {
    if (element.backgroundColor != 'transparent') {
      parts.add('fill=${formatColor(element.backgroundColor)}');
    }
    if (element.strokeColor != '#000000') {
      parts.add('color=${formatColor(element.strokeColor)}');
    }
    if (element.strokeStyle != StrokeStyle.solid) {
      parts.add('stroke=${element.strokeStyle.name}');
    }
    if (element.fillStyle != FillStyle.solid) {
      parts.add('fill-style=${_fillStyleName(element.fillStyle)}');
    }
    if (element.strokeWidth != 2.0) {
      parts.add('stroke-width=${_formatNum(element.strokeWidth)}');
    }
    if (element.roughness != 1.0) {
      parts.add('roughness=${_formatNum(element.roughness)}');
    }
    if (element.opacity != 1.0) {
      parts.add('opacity=${_formatNum(element.opacity)}');
    }
    if (element.roundness != null && !isArrow) {
      parts.add('rounded=${_formatNum(element.roundness!.value)}');
    }
    if (element.angle != 0.0) {
      parts.add('angle=${(element.angle * 180 / math.pi).round()}');
    }
    if (element.locked) {
      parts.add('locked');
    }
    if (element.frameId != null) {
      parts.add('frame=${element.frameId}');
    }
    if (element.groupIds.isNotEmpty) {
      parts.add('group=${element.groupIds.join(',')}');
    }
    if (element.link != null && element.link!.isNotEmpty) {
      parts.add('link="${element.link}"');
    }
    // seed is intentionally omitted — it's auto-generated from a random value
    // and only affects rough-drawing wobble, not document semantics.
  }

  String _fillStyleName(FillStyle style) {
    return switch (style) {
      FillStyle.solid => 'solid',
      FillStyle.hachure => 'hachure',
      FillStyle.crossHatch => 'cross-hatch',
      FillStyle.zigzag => 'zigzag',
    };
  }

  /// Converts a normalized fixedPoint to a pixel @x,y suffix string.
  /// Falls back to normalized values if the target element is unavailable.
  String _fixedPointToPixelSuffix(Point fp, Element? target) {
    if (target != null) {
      final px = (fp.x * target.width).round();
      final py = (fp.y * target.height).round();
      return '@$px,$py';
    }
    return '@${_formatNum(fp.x)},${_formatNum(fp.y)}';
  }

  /// Converts relative points to absolute by adding the element's position.
  /// Rounds to integers for clean serialization.
  List<Point> _absolutePoints(Element element) {
    final pts = switch (element) {
      LineElement() => element.points,
      FreedrawElement() => element.points,
      _ => <Point>[],
    };
    return pts
        .map(
          (p) => Point(
            (p.x + element.x).roundToDouble(),
            (p.y + element.y).roundToDouble(),
          ),
        )
        .toList();
  }

  /// Wraps a value in quotes if it contains spaces.
  String _quoteIfNeeded(String value) =>
      value.contains(' ') ? '"$value"' : value;

  /// Formats a number: integers without decimal, doubles with decimals.
  String _formatNum(num value) {
    if (value is int) return value.toString();
    final d = value.toDouble();
    // Round near-integer values to avoid floating point noise from trig
    // (e.g., rotated resize producing 150.00000000000001 instead of 150).
    final rounded = d.roundToDouble();
    if ((d - rounded).abs() < 1e-10) {
      return rounded.toInt().toString();
    }
    return d.toString();
  }
}
