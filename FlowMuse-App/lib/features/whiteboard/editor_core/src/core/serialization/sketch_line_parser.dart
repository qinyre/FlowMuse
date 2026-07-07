import 'dart:math' as math;

import '../elements/elements.dart';
import '../math/math.dart';
import 'color_names.dart';
import 'parse_result.dart';

/// Font category aliases for shorthand font names.
const _fontAliases = {
  'hand-drawn': 'Excalifont',
  'normal': 'Nunito',
  'code': 'Source Code Pro',
};

/// Resolves a font alias to its actual font name, or returns the value as-is.
String _resolveFontAlias(String value) => _fontAliases[value] ?? value;

/// Named font size aliases.
const _namedFontSizes = {
  'small': 16.0,
  's': 16.0,
  'medium': 20.0,
  'm': 20.0,
  'large': 28.0,
  'l': 28.0,
  'extra-large': 36.0,
  'xl': 36.0,
};

/// A pending arrow binding to be resolved after all elements are parsed.
class PendingBinding {
  final String arrowElementId;
  final String? fromAlias;
  final String? toAlias;
  final Point? fromFixedPoint;
  final Point? toFixedPoint;

  PendingBinding({
    required this.arrowElementId,
    this.fromAlias,
    this.toAlias,
    this.fromFixedPoint,
    this.toFixedPoint,
  });
}

/// Parses single .markdraw sketch lines into Elements.
class SketchLineParser {
  /// Map of alias → element ID, built during parsing.
  final Map<String, String> aliases = {};

  /// Pending arrow bindings to resolve after all lines are parsed.
  final List<PendingBinding> pendingBindings = [];

  /// Parse a single sketch line into an Element.
  ///
  /// Returns null value for empty/comment lines. Returns warnings for
  /// unrecognized content. Never throws.
  ParseResult<Element?> parseLine(String line, int lineNumber) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      return ParseResult(value: null);
    }

    final keyword = trimmed.split(RegExp(r'\s+')).first.toLowerCase();

    try {
      return switch (keyword) {
        'rect' => _parseShape(keyword, trimmed, lineNumber),
        'ellipse' => _parseShape(keyword, trimmed, lineNumber),
        'diamond' => _parseShape(keyword, trimmed, lineNumber),
        'frame' => _parseFrame(trimmed, lineNumber),
        'image' => _parseImage(trimmed, lineNumber),
        'text' => _parseText(trimmed, lineNumber),
        'line' => _parseLine(trimmed, lineNumber),
        'arrow' => _parseArrow(trimmed, lineNumber),
        'freedraw' => _parseFreedraw(trimmed, lineNumber),
        _ => ParseResult(
          value: null,
          warnings: [
            ParseWarning(
              line: lineNumber,
              message: 'Unknown keyword: $keyword',
              context: trimmed,
            ),
          ],
        ),
      };
    } catch (e) {
      return ParseResult(
        value: null,
        warnings: [
          ParseWarning(
            line: lineNumber,
            message: 'Parse error: $e',
            context: trimmed,
          ),
        ],
      );
    }
  }

  /// Resolve pending arrow bindings after all elements have been parsed.
  ///
  /// Returns a list of updated ArrowElements with bindings set, plus
  /// any warnings for unresolved aliases.
  ParseResult<List<ArrowElement>> resolveBindings(List<Element> elements) {
    final warnings = <ParseWarning>[];
    final resolved = <ArrowElement>[];

    // Build element lookup for pixel→normalized conversion
    final elementMap = <String, Element>{
      for (final e in elements) e.id.value: e,
    };

    for (final binding in pendingBindings) {
      final arrowIdx = elements.indexWhere(
        (e) => e.id.value == binding.arrowElementId,
      );
      if (arrowIdx < 0) continue;

      final arrow = elements[arrowIdx] as ArrowElement;
      PointBinding? startBinding;
      PointBinding? endBinding;

      if (binding.fromAlias != null) {
        final fromId = aliases[binding.fromAlias!];
        if (fromId != null) {
          final fixedPoint = binding.fromFixedPoint != null
              ? _pixelToNormalized(binding.fromFixedPoint!, elementMap[fromId])
              : const Point(1, 0.5);
          startBinding = PointBinding(
            elementId: fromId,
            fixedPoint: fixedPoint,
          );
        } else {
          warnings.add(
            ParseWarning(
              line: 0,
              message: 'Unresolved alias: ${binding.fromAlias}',
            ),
          );
        }
      }

      if (binding.toAlias != null) {
        final toId = aliases[binding.toAlias!];
        if (toId != null) {
          final fixedPoint = binding.toFixedPoint != null
              ? _pixelToNormalized(binding.toFixedPoint!, elementMap[toId])
              : const Point(0, 0.5);
          endBinding = PointBinding(elementId: toId, fixedPoint: fixedPoint);
        } else {
          warnings.add(
            ParseWarning(
              line: 0,
              message: 'Unresolved alias: ${binding.toAlias}',
            ),
          );
        }
      }

      resolved.add(
        arrow.copyWithArrow(startBinding: startBinding, endBinding: endBinding),
      );
    }

    return ParseResult(value: resolved, warnings: warnings);
  }

  // ── Shape parsing (rect, ellipse, diamond) ──

  ParseResult<Element?> _parseShape(
    String keyword,
    String line,
    int lineNumber,
  ) {
    final props = _PropertyBag(line, keyword);
    final id = props.id;
    final pos = props.position;
    final size = props.size;
    final common = props.commonProperties;

    final elementId = ElementId(id ?? _generateId());
    _registerAlias(id, elementId.value);

    final element = switch (keyword) {
      'rect' => RectangleElement(
        id: elementId,
        x: pos.$1,
        y: pos.$2,
        width: size.$1,
        height: size.$2,
        strokeColor: common.strokeColor,
        backgroundColor: common.backgroundColor,
        fillStyle: common.fillStyle,
        strokeWidth: common.strokeWidth,
        strokeStyle: common.strokeStyle,
        roughness: common.roughness,
        opacity: common.opacity,
        roundness: common.roundness,
        angle: common.angle,
        locked: common.locked,
        frameId: common.frameId,
        groupIds: common.groupIds,
        link: common.link,
      ),
      'ellipse' => EllipseElement(
        id: elementId,
        x: pos.$1,
        y: pos.$2,
        width: size.$1,
        height: size.$2,
        strokeColor: common.strokeColor,
        backgroundColor: common.backgroundColor,
        fillStyle: common.fillStyle,
        strokeWidth: common.strokeWidth,
        strokeStyle: common.strokeStyle,
        roughness: common.roughness,
        opacity: common.opacity,
        roundness: common.roundness,
        angle: common.angle,
        locked: common.locked,
        frameId: common.frameId,
        groupIds: common.groupIds,
        link: common.link,
      ),
      'diamond' => DiamondElement(
        id: elementId,
        x: pos.$1,
        y: pos.$2,
        width: size.$1,
        height: size.$2,
        strokeColor: common.strokeColor,
        backgroundColor: common.backgroundColor,
        fillStyle: common.fillStyle,
        strokeWidth: common.strokeWidth,
        strokeStyle: common.strokeStyle,
        roughness: common.roughness,
        opacity: common.opacity,
        roundness: common.roundness,
        angle: common.angle,
        locked: common.locked,
        frameId: common.frameId,
        groupIds: common.groupIds,
        link: common.link,
      ),
      _ => null,
    };

    return ParseResult(value: element);
  }

  // ── Frame parsing ──

  ParseResult<Element?> _parseFrame(String line, int lineNumber) {
    final props = _PropertyBag(line, 'frame');
    final id = props.id;
    final pos = props.position;
    final size = props.size;
    final common = props.commonProperties;
    final label = props.quotedString ?? 'Frame';

    final elementId = ElementId(id ?? _generateId());
    _registerAlias(id, elementId.value);

    final element = FrameElement(
      id: elementId,
      x: pos.$1,
      y: pos.$2,
      width: size.$1,
      height: size.$2,
      label: label,
      strokeColor: common.strokeColor,
      backgroundColor: common.backgroundColor,
      fillStyle: common.fillStyle,
      strokeWidth: common.strokeWidth,
      strokeStyle: common.strokeStyle,
      roughness: common.roughness,
      opacity: common.opacity,
      roundness: common.roundness,
      angle: common.angle,
      locked: common.locked,
      frameId: common.frameId,
      groupIds: common.groupIds,
      link: common.link,
    );

    return ParseResult(value: element);
  }

  // ── Image parsing ──

  ParseResult<Element?> _parseImage(String line, int lineNumber) {
    final props = _PropertyBag(line, 'image');
    final id = props.id;
    final pos = props.position;
    final size = props.size;
    final common = props.commonProperties;
    final fileId = props.namedString('file') ?? '';
    final scaleVal = props.namedDouble('scale');
    final cropStr = props.namedString('crop');

    ImageCrop? crop;
    if (cropStr != null) {
      final parts = cropStr.split(',');
      if (parts.length == 4) {
        crop = ImageCrop(
          x: double.parse(parts[0]),
          y: double.parse(parts[1]),
          width: double.parse(parts[2]),
          height: double.parse(parts[3]),
        );
      }
    }

    final elementId = ElementId(id ?? _generateId());
    _registerAlias(id, elementId.value);

    final element = ImageElement(
      id: elementId,
      x: pos.$1,
      y: pos.$2,
      width: size.$1,
      height: size.$2,
      fileId: fileId,
      crop: crop,
      imageScale: scaleVal ?? 1.0,
      strokeColor: common.strokeColor,
      backgroundColor: common.backgroundColor,
      fillStyle: common.fillStyle,
      strokeWidth: common.strokeWidth,
      strokeStyle: common.strokeStyle,
      roughness: common.roughness,
      opacity: common.opacity,
      angle: common.angle,
      locked: common.locked,
      frameId: common.frameId,
      groupIds: common.groupIds,
      link: common.link,
    );

    return ParseResult(value: element);
  }

  // ── Text parsing ──

  ParseResult<Element?> _parseText(String line, int lineNumber) {
    final props = _PropertyBag(line, 'text');
    final id = props.id;
    final pos = props.position;
    final common = props.commonProperties;
    final text = props.quotedString;
    final fontSize =
        _namedFontSizes[props.namedString('font-size')] ??
        props.namedDouble('size') ??
        20.0;
    final fontFamily = _resolveFontAlias(
      props.namedString('font') ?? 'Excalifont',
    );
    final alignStr = props.namedString('align');
    final textAlign = _parseTextAlign(alignStr);
    final valignStr = props.namedString('valign');
    final verticalAlign = _parseVerticalAlign(valignStr);

    final dims = props.size;

    final elementId = ElementId(id ?? _generateId());
    _registerAlias(id, elementId.value);

    final element = TextElement(
      id: elementId,
      x: pos.$1,
      y: pos.$2,
      width: dims.$1,
      height: dims.$2,
      text: text ?? '',
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      verticalAlign: verticalAlign,
      strokeColor: common.strokeColor,
      backgroundColor: common.backgroundColor,
      fillStyle: common.fillStyle,
      strokeWidth: common.strokeWidth,
      strokeStyle: common.strokeStyle,
      roughness: common.roughness,
      opacity: common.opacity,
      angle: common.angle,
      locked: common.locked,
      frameId: common.frameId,
      groupIds: common.groupIds,
      link: common.link,
    );

    return ParseResult(value: element);
  }

  // ── Line parsing ──

  ParseResult<Element?> _parseLine(String line, int lineNumber) {
    final props = _PropertyBag(line, 'line');
    final id = props.id;
    final points = props.points;
    final common = props.commonProperties;
    final startArrow = _parseArrowhead(props.namedString('start-arrow'));
    final endArrow = _parseArrowhead(props.namedString('end-arrow'));
    final isClosed = props.hasFlag('closed');

    final elementId = ElementId(id ?? _generateId());
    _registerAlias(id, elementId.value);

    final bounds = _boundsFromPoints(points);
    final relPoints = _toRelativePoints(points, bounds.$1, bounds.$2);

    final element = LineElement(
      id: elementId,
      x: bounds.$1,
      y: bounds.$2,
      width: bounds.$3,
      height: bounds.$4,
      points: relPoints,
      startArrowhead: startArrow,
      endArrowhead: endArrow,
      closed: isClosed,
      strokeColor: common.strokeColor,
      backgroundColor: common.backgroundColor,
      fillStyle: common.fillStyle,
      strokeWidth: common.strokeWidth,
      strokeStyle: common.strokeStyle,
      roughness: common.roughness,
      opacity: common.opacity,
      angle: common.angle,
      locked: common.locked,
      frameId: common.frameId,
      groupIds: common.groupIds,
      link: common.link,
    );

    return ParseResult(value: element);
  }

  // ── Arrow parsing ──

  ParseResult<Element?> _parseArrow(String line, int lineNumber) {
    final props = _PropertyBag(line, 'arrow');
    final id = props.id;
    final common = props.commonProperties;
    final startArrow = _parseArrowhead(props.namedString('start-arrow'));
    final endArrowStr = props.namedString('end-arrow');
    final endArrow = endArrowStr != null
        ? _parseArrowhead(endArrowStr) ?? Arrowhead.arrow
        : Arrowhead.arrow;

    final fromRaw = props.namedPositional('from');
    final toRaw = props.namedPositional('to');

    // Distinguish coordinate endpoints (e.g. "500,300") from alias bindings
    String? fromAlias;
    Point? fromFixedPoint;
    Point? fromCoord;
    String? toAlias;
    Point? toFixedPoint;
    Point? toCoord;

    if (fromRaw != null && _isCoordinate(fromRaw)) {
      final parts = fromRaw.split(',');
      fromCoord = Point(double.parse(parts[0]), double.parse(parts[1]));
    } else {
      final result = _splitFixedPoint(fromRaw);
      fromAlias = result.$1;
      fromFixedPoint = result.$2;
    }

    if (toRaw != null && _isCoordinate(toRaw)) {
      final parts = toRaw.split(',');
      toCoord = Point(double.parse(parts[0]), double.parse(parts[1]));
    } else {
      final result = _splitFixedPoint(toRaw);
      toAlias = result.$1;
      toFixedPoint = result.$2;
    }

    final hasBindings = fromAlias != null || toAlias != null;

    List<Point> points;
    if (hasBindings) {
      // Use actual coordinates for unbound ends, placeholders for bound ends
      final startPt = fromCoord ?? const Point(0, 0);
      final endPt = toCoord ?? const Point(0, 0);
      points = [startPt, endPt];
    } else if (fromCoord != null || toCoord != null) {
      // Both ends are coordinates (no bindings)
      points = [fromCoord ?? const Point(0, 0), toCoord ?? const Point(0, 0)];
    } else {
      points = props.points;
    }

    final elementId = ElementId(id ?? _generateId());
    _registerAlias(id, elementId.value);

    final bounds = _boundsFromPoints(points);
    final relPoints = hasBindings
        ? points
        : _toRelativePoints(points, bounds.$1, bounds.$2);

    // Parse arrow type: new 'arrow-type=' property first, legacy fallback second
    final arrowTypeStr = props.namedString('arrow-type');
    ArrowType arrowType;
    if (arrowTypeStr != null) {
      arrowType = switch (arrowTypeStr) {
        'round' => ArrowType.round,
        'sharp-elbow' => ArrowType.sharpElbow,
        'round-elbow' => ArrowType.roundElbow,
        _ => ArrowType.sharp,
      };
    } else if (props.hasFlag('elbowed')) {
      // Legacy: 'elbowed' flag → sharpElbow
      arrowType = ArrowType.sharpElbow;
    } else if (common.roundness != null) {
      // Legacy: 'rounded=X' on arrow → round
      arrowType = ArrowType.round;
    } else {
      arrowType = ArrowType.sharp;
    }

    final arrow = ArrowElement(
      id: elementId,
      x: bounds.$1,
      y: bounds.$2,
      width: bounds.$3,
      height: bounds.$4,
      points: relPoints,
      startArrowhead: startArrow,
      endArrowhead: endArrow,
      arrowType: arrowType,
      strokeColor: common.strokeColor,
      backgroundColor: common.backgroundColor,
      fillStyle: common.fillStyle,
      strokeWidth: common.strokeWidth,
      strokeStyle: common.strokeStyle,
      roughness: common.roughness,
      opacity: common.opacity,
      angle: common.angle,
      locked: common.locked,
      frameId: common.frameId,
      groupIds: common.groupIds,
      link: common.link,
    );

    if (hasBindings) {
      pendingBindings.add(
        PendingBinding(
          arrowElementId: elementId.value,
          fromAlias: fromAlias,
          toAlias: toAlias,
          fromFixedPoint: fromFixedPoint,
          toFixedPoint: toFixedPoint,
        ),
      );
    }

    return ParseResult(value: arrow);
  }

  // ── Freedraw parsing ──

  ParseResult<Element?> _parseFreedraw(String line, int lineNumber) {
    final props = _PropertyBag(line, 'freedraw');
    final id = props.id;
    final points = props.points;
    final pressures = props.pressures;
    // Default true; legacy 'simulate-pressure' flag also accepted
    final simulatePressure = !props.hasFlag('no-simulate-pressure');
    final common = props.commonProperties;

    final elementId = ElementId(id ?? _generateId());
    _registerAlias(id, elementId.value);

    final bounds = _boundsFromPoints(points);
    final relPoints = _toRelativePoints(points, bounds.$1, bounds.$2);

    final element = FreedrawElement(
      id: elementId,
      x: bounds.$1,
      y: bounds.$2,
      width: bounds.$3,
      height: bounds.$4,
      points: relPoints,
      pressures: pressures,
      simulatePressure: simulatePressure,
      strokeColor: common.strokeColor,
      backgroundColor: common.backgroundColor,
      fillStyle: common.fillStyle,
      strokeWidth: common.strokeWidth,
      strokeStyle: common.strokeStyle,
      roughness: common.roughness,
      opacity: common.opacity,
      angle: common.angle,
      locked: common.locked,
      frameId: common.frameId,
      groupIds: common.groupIds,
      link: common.link,
    );

    return ParseResult(value: element);
  }

  // ── Helpers ──

  TextAlign _parseTextAlign(String? value) {
    return switch (value) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
  }

  VerticalAlign _parseVerticalAlign(String? value) {
    return switch (value) {
      'top' => VerticalAlign.top,
      'bottom' => VerticalAlign.bottom,
      _ => VerticalAlign.middle,
    };
  }

  Arrowhead? _parseArrowhead(String? value) {
    return switch (value) {
      'arrow' => Arrowhead.arrow,
      'bar' => Arrowhead.bar,
      'dot' => Arrowhead.dot,
      'triangle' => Arrowhead.triangle,
      'triangleOutline' => Arrowhead.triangleOutline,
      'circle' => Arrowhead.circle,
      'circleOutline' => Arrowhead.circleOutline,
      'diamond' => Arrowhead.diamond,
      'diamondOutline' => Arrowhead.diamondOutline,
      'crowfootOne' => Arrowhead.crowfootOne,
      'crowfootMany' => Arrowhead.crowfootMany,
      'crowfootOneOrMany' => Arrowhead.crowfootOneOrMany,
      _ => null,
    };
  }

  (double, double, double, double) _boundsFromPoints(List<Point> points) {
    if (points.isEmpty) return (0, 0, 0, 0);
    var minX = points.first.x;
    var minY = points.first.y;
    var maxX = points.first.x;
    var maxY = points.first.y;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return (minX, minY, maxX - minX, maxY - minY);
  }

  /// Registers an alias in the aliases map for binding resolution.
  void _registerAlias(String? id, String elementIdValue) {
    if (id != null) {
      aliases[id] = elementIdValue;
    }
  }

  /// Converts pixel coordinates back to normalized (0-1) using target dimensions.
  Point _pixelToNormalized(Point pixel, Element? target) {
    if (target != null && target.width != 0 && target.height != 0) {
      return Point(pixel.x / target.width, pixel.y / target.height);
    }
    return pixel;
  }

  /// Returns true if the value is a coordinate pair like "500,300" or "-10.5,20".
  static final _coordRegExp = RegExp(r'^-?[\d.]+,-?[\d.]+$');
  bool _isCoordinate(String value) => _coordRegExp.hasMatch(value);

  /// Splits 'alias@x,y' into (alias, Point(x,y)), or (alias, null) if no '@'.
  (String?, Point?) _splitFixedPoint(String? raw) {
    if (raw == null) return (null, null);
    final atIdx = raw.indexOf('@');
    if (atIdx < 0) return (raw, null);
    final alias = raw.substring(0, atIdx);
    final coords = raw.substring(atIdx + 1).split(',');
    if (coords.length == 2) {
      final x = double.tryParse(coords[0]);
      final y = double.tryParse(coords[1]);
      if (x != null && y != null) {
        return (alias, Point(x, y));
      }
    }
    return (alias, null);
  }

  /// Converts absolute points to relative by subtracting the origin offset.
  List<Point> _toRelativePoints(List<Point> points, double ox, double oy) {
    return points.map((p) => Point(p.x - ox, p.y - oy)).toList();
  }

  int _idCounter = 0;
  String _generateId() => 'gen_${_idCounter++}';
}

// ── Property bag: extracts properties from a sketch line ──

class _CommonProperties {
  final String strokeColor;
  final String backgroundColor;
  final FillStyle fillStyle;
  final double strokeWidth;
  final StrokeStyle strokeStyle;
  final double roughness;
  final double opacity;
  final Roundness? roundness;
  final double angle;
  final bool locked;

  final String? frameId;
  final List<String> groupIds;
  final String? link;

  _CommonProperties({
    required this.strokeColor,
    required this.backgroundColor,
    required this.fillStyle,
    required this.strokeWidth,
    required this.strokeStyle,
    required this.roughness,
    required this.opacity,
    required this.roundness,
    required this.angle,
    required this.locked,
    required this.frameId,
    required this.groupIds,
    required this.link,
  });
}

class _PropertyBag {
  final String line;
  final String keyword;

  _PropertyBag(this.line, this.keyword);

  String? get id => namedString('id');

  (double, double) get position {
    final match = RegExp(r'at\s+([\d.+-]+),([\d.+-]+)').firstMatch(line);
    if (match == null) return (0, 0);
    return (double.parse(match.group(1)!), double.parse(match.group(2)!));
  }

  (double, double) get size {
    // Shape size: "WxH" (also accepts legacy "size WxH")
    final match = RegExp(
      r'(?:^|size\s+|\s)([\d.]+)x([\d.]+)(?:\s|$)',
    ).firstMatch(line);
    if (match == null) return (0, 0);
    return (double.parse(match.group(1)!), double.parse(match.group(2)!));
  }

  String? get quotedString {
    final match = RegExp(r'"([^"]*)"').firstMatch(line);
    return match?.group(1);
  }

  List<Point> get points {
    final match = RegExp(r'points=\[(.+?)\](?:\s|$)').firstMatch(line);
    if (match == null) return [];
    final inner = match.group(1)!;
    // Support both new "x,y x,y" and legacy "[[x,y],[x,y]]" formats
    final pointMatches = RegExp(r'([\d.+-]+),([\d.+-]+)').allMatches(inner);
    return pointMatches.map((m) {
      return Point(double.parse(m.group(1)!), double.parse(m.group(2)!));
    }).toList();
  }

  List<double> get pressures {
    final match = RegExp(r'pressure=\[([\d.,]+)\]').firstMatch(line);
    if (match == null) return [];
    return match.group(1)!.split(',').map(double.parse).toList();
  }

  String? namedString(String name) {
    // Try quoted value first: name="value with spaces"
    final quoted = RegExp('(?:^|\\s)$name="([^"]*)"').firstMatch(line);
    if (quoted != null) return quoted.group(1);
    // Fall back to unquoted: name=value
    final match = RegExp('(?:^|\\s)$name=(\\S+)').firstMatch(line);
    return match?.group(1);
  }

  double? namedDouble(String name) {
    final str = namedString(name);
    if (str == null) return null;
    return double.tryParse(str);
  }

  int? namedInt(String name) {
    final str = namedString(name);
    if (str == null) return null;
    return int.tryParse(str);
  }

  /// Parses "from alias" or "to alias" style positional named params.
  String? namedPositional(String name) {
    final match = RegExp('(?:^|\\s)$name\\s+(\\S+)').firstMatch(line);
    if (match == null) return null;
    // Avoid matching named=value patterns
    final value = match.group(1)!;
    if (value.contains('=')) return null;
    return value;
  }

  bool hasFlag(String name) {
    // Match as whole word, not as part of name=value
    return RegExp('(?:^|\\s)$name(?:\\s|\$)').hasMatch(line);
  }

  _CommonProperties get commonProperties {
    final fillStr = namedString('fill');
    final colorStr = namedString('color');
    final strokeStr = namedString('stroke');
    final fillStyleStr = namedString('fill-style');
    final strokeWidthVal = namedDouble('stroke-width');
    final roughnessVal = namedDouble('roughness');
    final opacityVal = namedDouble('opacity');
    final roundedVal = namedDouble('rounded');
    final angleDeg = namedDouble('angle');
    final isLocked = hasFlag('locked');
    final frameIdStr = namedString('frame');
    final groupStr = namedString('group');
    final groupIds = groupStr != null && groupStr.isNotEmpty
        ? groupStr.split(',')
        : <String>[];
    final linkStr = namedString('link');

    return _CommonProperties(
      strokeColor: colorStr != null ? normalizeColor(colorStr) : '#000000',
      backgroundColor: fillStr != null
          ? normalizeColor(fillStr)
          : 'transparent',
      fillStyle: _parseFillStyle(fillStyleStr),
      strokeWidth: strokeWidthVal ?? 2.0,
      strokeStyle: _parseStrokeStyle(strokeStr),
      roughness: roughnessVal ?? 1.0,
      opacity: opacityVal ?? 1.0,
      roundness: roundedVal != null
          ? Roundness.adaptive(value: roundedVal)
          : null,
      angle: angleDeg != null ? angleDeg * math.pi / 180 : 0.0,
      locked: isLocked,
      frameId: frameIdStr,
      groupIds: groupIds,
      link: linkStr,
    );
  }

  FillStyle _parseFillStyle(String? value) {
    return switch (value) {
      'solid' => FillStyle.solid,
      'hachure' => FillStyle.hachure,
      'cross-hatch' => FillStyle.crossHatch,
      'zigzag' => FillStyle.zigzag,
      _ => FillStyle.solid,
    };
  }

  StrokeStyle _parseStrokeStyle(String? value) {
    return switch (value) {
      'solid' => StrokeStyle.solid,
      'dashed' => StrokeStyle.dashed,
      'dotted' => StrokeStyle.dotted,
      _ => StrokeStyle.solid,
    };
  }
}
