import 'dart:convert';
import 'dart:typed_data';

import '../elements/elements.dart';
import '../math/math.dart';
import 'canvas_settings.dart';
import 'document_section.dart';
import 'markdraw_document.dart';
import 'parse_result.dart';

/// Codec for importing/exporting Excalidraw JSON (.excalidraw) files.
///
/// Provides lenient parsing that never throws — unsupported element types
/// and property values produce [ParseWarning]s and are skipped or mapped
/// to the closest equivalent.
class ExcalidrawJsonCodec {
  // Unsupported Excalidraw element types that we skip with a warning.
  static const _unsupportedTypes = {
    'magicframe',
    'iframe',
    'embeddable',
    'selection',
  };

  /// Font family number → name mapping (Excalidraw convention).
  static const fontFamilyFromNumber = <int, String>{
    1: 'Virgil',
    2: 'Helvetica',
    3: 'Cascadia',
    5: 'Excalifont',
    6: 'Nunito',
    7: 'Lilita One',
    8: 'Comic Shanns',
    9: 'Liberation Sans',
    10: 'Assistant',
  };

  /// Font family name → number mapping (reverse of [fontFamilyFromNumber]).
  static final fontFamilyToNumber = <String, int>{
    for (final entry in fontFamilyFromNumber.entries) entry.value: entry.key,
  };

  /// FillStyle string → enum mapping.
  static const _fillStyleFromString = <String, FillStyle>{
    'solid': FillStyle.solid,
    'hachure': FillStyle.hachure,
    'cross-hatch': FillStyle.crossHatch,
    'zigzag': FillStyle.zigzag,
  };

  /// StrokeStyle string → enum mapping.
  static const _strokeStyleFromString = <String, StrokeStyle>{
    'solid': StrokeStyle.solid,
    'dashed': StrokeStyle.dashed,
    'dotted': StrokeStyle.dotted,
  };

  /// FillStyle enum → string mapping (reverse).
  static const _fillStyleToString = <FillStyle, String>{
    FillStyle.solid: 'solid',
    FillStyle.hachure: 'hachure',
    FillStyle.crossHatch: 'cross-hatch',
    FillStyle.zigzag: 'zigzag',
  };

  /// StrokeStyle enum → string mapping (reverse).
  static const _strokeStyleToString = <StrokeStyle, String>{
    StrokeStyle.solid: 'solid',
    StrokeStyle.dashed: 'dashed',
    StrokeStyle.dotted: 'dotted',
  };

  /// Serializes a [MarkdrawDocument] to Excalidraw JSON format.
  static String serialize(MarkdrawDocument doc) {
    final elements = doc.allElements.map(elementToJson).toList();
    final filesJson = filesToJson(doc.files);
    final result = {
      'type': 'excalidraw',
      'version': 2,
      'source': 'markdraw',
      'elements': elements,
      'appState': <String, dynamic>{
        'viewBackgroundColor': doc.settings.background,
        if (doc.settings.name != null) 'name': doc.settings.name,
      },
      'files': filesJson,
    };
    return jsonEncode(result);
  }

  /// Converts a single [Element] to its Excalidraw JSON representation.
  static Map<String, dynamic> elementToJson(Element el) {
    final base = baseToJson(el);
    if (el is FrameElement) {
      return {...base, 'name': el.label};
    } else if (el is ImageElement) {
      return {
        ...base,
        'fileId': el.fileId,
        'status': 'saved',
        'scale': [el.imageScale, el.imageScale],
        if (el.crop != null && !el.crop!.isFullImage)
          'crop': {
            'x': el.crop!.x,
            'y': el.crop!.y,
            'width': el.crop!.width,
            'height': el.crop!.height,
          },
      };
    } else if (el is TextElement) {
      return {
        ...base,
        'text': el.text,
        'fontSize': el.fontSize,
        'fontFamily': fontFamilyToNumber[el.fontFamily] ?? 5,
        'textAlign': el.textAlign.name,
        'containerId': el.containerId,
        'lineHeight': el.lineHeight,
        'autoResize': el.autoResize,
        'originalText': el.text,
        'verticalAlign': el.verticalAlign.name,
      };
    } else if (el is ArrowElement) {
      return {
        ...base,
        'points': el.points.map((p) => [p.x, p.y]).toList(),
        'startArrowhead': _arrowheadName(el.startArrowhead),
        'endArrowhead': _arrowheadName(el.endArrowhead),
        'startBinding': _bindingToJson(el.startBinding),
        'endBinding': _bindingToJson(el.endBinding),
        if (el.arrowType.isElbow) 'elbowed': true,
      };
    } else if (el is LineElement) {
      return {
        ...base,
        'points': el.points.map((p) => [p.x, p.y]).toList(),
        'startArrowhead': _arrowheadName(el.startArrowhead),
        'endArrowhead': _arrowheadName(el.endArrowhead),
        if (el.closed) 'polygon': true,
      };
    } else if (el is FreedrawElement) {
      return {
        ...base,
        'points': el.points.map((p) => [p.x, p.y]).toList(),
        'pressures': el.pressures,
        'simulatePressure': el.simulatePressure,
      };
    }
    return base;
  }

  /// Converts the base properties of an [Element] to JSON.
  static Map<String, dynamic> baseToJson(Element el) {
    return {
      'id': el.id.value,
      'type': el.type,
      'x': el.x,
      'y': el.y,
      'width': el.width,
      'height': el.height,
      'angle': el.angle,
      'strokeColor': el.strokeColor,
      'backgroundColor': el.backgroundColor,
      'fillStyle': _fillStyleToString[el.fillStyle] ?? 'solid',
      'strokeWidth': el.strokeWidth,
      'strokeStyle': _strokeStyleToString[el.strokeStyle] ?? 'solid',
      'roughness': el.roughness,
      'opacity': (el.opacity * 100).round(),
      'roundness': _roundnessToJson(el.roundness),
      'seed': el.seed,
      'version': el.version,
      'versionNonce': el.versionNonce,
      'isDeleted': el.isDeleted,
      'groupIds': el.groupIds,
      'frameId': el.frameId,
      'boundElements': el.boundElements.isEmpty
          ? null
          : _boundElementsToJson(el),
      'updated': el.updated,
      'link': el.link,
      'locked': el.locked,
      if (el.index != null) 'index': el.index,
    };
  }

  static Map<String, dynamic>? _roundnessToJson(Roundness? roundness) {
    if (roundness == null) return null;
    return {
      'type': roundness.type == RoundnessType.proportional ? 2 : 3,
      'value': roundness.value,
    };
  }

  static List<Map<String, dynamic>> _boundElementsToJson(Element el) {
    return el.boundElements.map((b) => {'id': b.id, 'type': b.type}).toList();
  }

  static Map<String, dynamic>? _bindingToJson(PointBinding? binding) {
    if (binding == null) return null;
    return {
      'elementId': binding.elementId,
      'fixedPoint': [binding.fixedPoint.x, binding.fixedPoint.y],
      'mode': 'inside',
    };
  }

  /// Parses an Excalidraw JSON string into a [MarkdrawDocument].
  ///
  /// Returns a [ParseResult] with warnings for unsupported elements or
  /// lossy property conversions. Never throws.
  static ParseResult<MarkdrawDocument> parse(String json) {
    final warnings = <ParseWarning>[];

    // Decode JSON
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (e) {
      warnings.add(ParseWarning(line: 0, message: 'Invalid JSON: $e'));
      return ParseResult(
        value: MarkdrawDocument(sections: [SketchSection(const [])]),
        warnings: warnings,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      warnings.add(
        const ParseWarning(line: 0, message: 'Expected JSON object at root'),
      );
      return ParseResult(
        value: MarkdrawDocument(sections: [SketchSection(const [])]),
        warnings: warnings,
      );
    }

    final elementsJson = decoded['elements'];
    if (elementsJson is! List) {
      warnings.add(
        const ParseWarning(
          line: 0,
          message: 'Missing or invalid "elements" array',
        ),
      );
      return ParseResult(
        value: MarkdrawDocument(sections: [SketchSection(const [])]),
        warnings: warnings,
      );
    }

    final elements = <Element>[];
    for (var i = 0; i < elementsJson.length; i++) {
      final raw = elementsJson[i];
      if (raw is! Map<String, dynamic>) {
        warnings.add(
          ParseWarning(line: i, message: 'Element $i is not a JSON object'),
        );
        continue;
      }

      final type = raw['type'] as String?;
      if (type == null) {
        warnings.add(ParseWarning(line: i, message: 'Element $i has no type'));
        continue;
      }

      if (_unsupportedTypes.contains(type)) {
        warnings.add(
          ParseWarning(
            line: i,
            message: 'Unsupported element type "$type" skipped',
          ),
        );
        continue;
      }

      final element = parseElement(raw, type, i, warnings);
      if (element != null) {
        elements.add(element);
      }
    }

    final files = parseFilesJson(decoded['files'], warnings);

    // Extract viewBackgroundColor and name from appState
    final appState = decoded['appState'];
    final viewBg = (appState is Map<String, dynamic>)
        ? (appState['viewBackgroundColor'] as String? ?? '#ffffff')
        : '#ffffff';
    final name = (appState is Map<String, dynamic>)
        ? appState['name'] as String?
        : null;

    return ParseResult(
      value: MarkdrawDocument(
        sections: [SketchSection(elements)],
        files: files,
        settings: CanvasSettings(background: viewBg, name: name),
      ),
      warnings: warnings,
    );
  }

  /// Parses an Excalidraw files JSON map into a [Map] of file ID to
  /// [ImageFile].
  static Map<String, ImageFile> parseFilesJson(
    Object? filesJson,
    List<ParseWarning> warnings,
  ) {
    final files = <String, ImageFile>{};
    if (filesJson is Map<String, dynamic>) {
      for (final entry in filesJson.entries) {
        final fileData = entry.value;
        if (fileData is Map<String, dynamic>) {
          final dataUrl = fileData['dataURL'] as String?;
          final mimeType = fileData['mimeType'] as String? ?? 'image/png';
          if (dataUrl != null) {
            try {
              final commaIdx = dataUrl.indexOf(',');
              if (commaIdx >= 0) {
                final b64 = dataUrl.substring(commaIdx + 1);
                final bytes = base64Decode(b64);
                files[entry.key] = ImageFile(
                  mimeType: mimeType,
                  bytes: Uint8List.fromList(bytes),
                );
              }
            } catch (_) {
              warnings.add(
                ParseWarning(
                  line: 0,
                  message: 'Failed to decode file data for "${entry.key}"',
                ),
              );
            }
          }
        }
      }
    }
    return files;
  }

  /// Converts a files map to Excalidraw JSON format.
  static Map<String, dynamic> filesToJson(Map<String, ImageFile> files) {
    final result = <String, dynamic>{};
    for (final entry in files.entries) {
      final dataUrl =
          'data:${entry.value.mimeType};base64,${base64Encode(entry.value.bytes)}';
      result[entry.key] = {
        'mimeType': entry.value.mimeType,
        'id': entry.key,
        'dataURL': dataUrl,
        'created': DateTime.now().millisecondsSinceEpoch,
      };
    }
    return result;
  }

  /// Parses a single element JSON object into an [Element].
  ///
  /// Returns null with a warning for unsupported types.
  static Element? parseElement(
    Map<String, dynamic> raw,
    String type,
    int index,
    List<ParseWarning> warnings,
  ) {
    switch (type) {
      case 'rectangle':
        return _parseRectangle(raw);
      case 'ellipse':
        return _parseEllipse(raw);
      case 'diamond':
        return _parseDiamond(raw);
      case 'text':
        return _parseText(raw, index, warnings);
      case 'line':
        return _parseLine(raw, index, warnings);
      case 'arrow':
        return _parseArrow(raw, index, warnings);
      case 'freedraw':
        return _parseFreedraw(raw);
      case 'frame':
        return _parseFrame(raw);
      case 'image':
        return _parseImage(raw);
      default:
        warnings.add(
          ParseWarning(
            line: index,
            message: 'Unsupported element type "$type" skipped',
          ),
        );
        return null;
    }
  }

  // -- Base property extraction --

  static ElementId _id(Map<String, dynamic> raw) =>
      ElementId(raw['id'] as String);

  static double _double(
    Map<String, dynamic> raw,
    String key, [
    double fallback = 0.0,
  ]) => (raw[key] as num?)?.toDouble() ?? fallback;

  static int _int(Map<String, dynamic> raw, String key, [int fallback = 0]) =>
      (raw[key] as num?)?.toInt() ?? fallback;

  static double _opacity(Map<String, dynamic> raw) =>
      ((raw['opacity'] as num?)?.toDouble() ?? 100.0) / 100.0;

  static FillStyle _fillStyle(Map<String, dynamic> raw) =>
      _fillStyleFromString[raw['fillStyle'] as String? ?? 'solid'] ??
      FillStyle.solid;

  static StrokeStyle _strokeStyle(Map<String, dynamic> raw) =>
      _strokeStyleFromString[raw['strokeStyle'] as String? ?? 'solid'] ??
      StrokeStyle.solid;

  static Roundness? _roundness(Map<String, dynamic> raw) {
    final r = raw['roundness'];
    if (r == null || r is! Map<String, dynamic>) return null;
    final type = (r['type'] as num?)?.toInt();
    final value = (r['value'] as num?)?.toDouble() ?? 0.0;
    switch (type) {
      case 1:
      case 3:
        return Roundness.adaptive(value: value);
      case 2:
        return Roundness.proportional(value: value);
      default:
        return null;
    }
  }

  static List<BoundElement> _boundElements(Map<String, dynamic> raw) {
    final list = raw['boundElements'];
    if (list == null || list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(
          (m) => BoundElement(id: m['id'] as String, type: m['type'] as String),
        )
        .toList();
  }

  static List<String> _groupIds(Map<String, dynamic> raw) {
    final list = raw['groupIds'];
    if (list == null || list is! List) return const [];
    return list.cast<String>();
  }

  static List<Point> _points(Map<String, dynamic> raw) {
    final list = raw['points'];
    if (list == null || list is! List) return const [];
    return list
        .whereType<List<dynamic>>()
        .map((p) => Point((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList();
  }

  static List<double> _pressures(Map<String, dynamic> raw) {
    final list = raw['pressures'];
    if (list == null || list is! List) return const [];
    return list.map((p) => (p as num).toDouble()).toList();
  }

  static TextAlign _textAlign(Map<String, dynamic> raw) {
    switch (raw['textAlign'] as String? ?? 'left') {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  static VerticalAlign _verticalAlign(Map<String, dynamic> raw) {
    switch (raw['verticalAlign'] as String? ?? 'middle') {
      case 'top':
        return VerticalAlign.top;
      case 'bottom':
        return VerticalAlign.bottom;
      default:
        return VerticalAlign.middle;
    }
  }

  static String _fontFamily(
    Map<String, dynamic> raw,
    int index,
    List<ParseWarning> warnings,
  ) {
    final num? familyNum = raw['fontFamily'] as num?;
    if (familyNum == null) return 'Excalifont';
    final name = fontFamilyFromNumber[familyNum.toInt()];
    if (name != null) return name;
    warnings.add(
      ParseWarning(
        line: index,
        message: 'Unknown font family ${familyNum.toInt()}, using Excalifont',
      ),
    );
    return 'Excalifont';
  }

  /// Converts an [Arrowhead] enum to its Excalidraw snake_case name.
  static String? _arrowheadName(Arrowhead? arrowhead) {
    if (arrowhead == null) return null;
    return switch (arrowhead) {
      Arrowhead.arrow => 'arrow',
      Arrowhead.bar => 'bar',
      Arrowhead.dot => 'dot',
      Arrowhead.triangle => 'triangle',
      Arrowhead.triangleOutline => 'triangle_outline',
      Arrowhead.circle => 'circle',
      Arrowhead.circleOutline => 'circle_outline',
      Arrowhead.diamond => 'diamond',
      Arrowhead.diamondOutline => 'diamond_outline',
      Arrowhead.crowfootOne => 'crowfoot_one',
      Arrowhead.crowfootMany => 'crowfoot_many',
      Arrowhead.crowfootOneOrMany => 'crowfoot_one_or_many',
    };
  }

  /// Maps an Excalidraw arrowhead string to our [Arrowhead] enum.
  static Arrowhead? _arrowhead(
    String? value,
    int index,
    List<ParseWarning> warnings,
  ) {
    if (value == null) return null;
    switch (value) {
      case 'arrow':
        return Arrowhead.arrow;
      case 'bar':
        return Arrowhead.bar;
      case 'dot':
        return Arrowhead.dot;
      case 'triangle':
        return Arrowhead.triangle;
      case 'triangle_outline':
        return Arrowhead.triangleOutline;
      case 'circle':
        return Arrowhead.circle;
      case 'circle_outline':
        return Arrowhead.circleOutline;
      case 'diamond':
        return Arrowhead.diamond;
      case 'diamond_outline':
        return Arrowhead.diamondOutline;
      case 'crowfoot_one':
        return Arrowhead.crowfootOne;
      case 'crowfoot_many':
        return Arrowhead.crowfootMany;
      case 'crowfoot_one_or_many':
        return Arrowhead.crowfootOneOrMany;
      default:
        warnings.add(
          ParseWarning(
            line: index,
            message: 'Unknown arrowhead "$value", using "arrow"',
          ),
        );
        return Arrowhead.arrow;
    }
  }

  static PointBinding? _binding(Map<String, dynamic> raw, String key) {
    final b = raw[key];
    if (b == null || b is! Map<String, dynamic>) return null;
    final elementId = b['elementId'] as String?;
    if (elementId == null) return null;
    final fp = b['fixedPoint'];
    final fixedPoint = (fp is List && fp.length >= 2)
        ? Point((fp[0] as num).toDouble(), (fp[1] as num).toDouble())
        : Point.zero;
    return PointBinding(elementId: elementId, fixedPoint: fixedPoint);
  }

  // -- Shape parsers --

  static RectangleElement _parseRectangle(Map<String, dynamic> raw) {
    return RectangleElement(
      id: _id(raw),
      x: _double(raw, 'x'),
      y: _double(raw, 'y'),
      width: _double(raw, 'width'),
      height: _double(raw, 'height'),
      angle: _double(raw, 'angle'),
      strokeColor: raw['strokeColor'] as String? ?? '#000000',
      backgroundColor: raw['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyle(raw),
      strokeWidth: _double(raw, 'strokeWidth', 2.0),
      strokeStyle: _strokeStyle(raw),
      roughness: _double(raw, 'roughness', 1.0),
      opacity: _opacity(raw),
      roundness: _roundness(raw),
      seed: _int(raw, 'seed'),
      version: _int(raw, 'version', 1),
      versionNonce: _int(raw, 'versionNonce'),
      isDeleted: raw['isDeleted'] as bool? ?? false,
      groupIds: _groupIds(raw),
      frameId: raw['frameId'] as String?,
      boundElements: _boundElements(raw),
      updated: _int(raw, 'updated'),
      link: raw['link'] as String?,
      locked: raw['locked'] as bool? ?? false,
      index: raw['index'] as String?,
    );
  }

  static EllipseElement _parseEllipse(Map<String, dynamic> raw) {
    return EllipseElement(
      id: _id(raw),
      x: _double(raw, 'x'),
      y: _double(raw, 'y'),
      width: _double(raw, 'width'),
      height: _double(raw, 'height'),
      angle: _double(raw, 'angle'),
      strokeColor: raw['strokeColor'] as String? ?? '#000000',
      backgroundColor: raw['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyle(raw),
      strokeWidth: _double(raw, 'strokeWidth', 2.0),
      strokeStyle: _strokeStyle(raw),
      roughness: _double(raw, 'roughness', 1.0),
      opacity: _opacity(raw),
      roundness: _roundness(raw),
      seed: _int(raw, 'seed'),
      version: _int(raw, 'version', 1),
      versionNonce: _int(raw, 'versionNonce'),
      isDeleted: raw['isDeleted'] as bool? ?? false,
      groupIds: _groupIds(raw),
      frameId: raw['frameId'] as String?,
      boundElements: _boundElements(raw),
      updated: _int(raw, 'updated'),
      link: raw['link'] as String?,
      locked: raw['locked'] as bool? ?? false,
      index: raw['index'] as String?,
    );
  }

  static DiamondElement _parseDiamond(Map<String, dynamic> raw) {
    return DiamondElement(
      id: _id(raw),
      x: _double(raw, 'x'),
      y: _double(raw, 'y'),
      width: _double(raw, 'width'),
      height: _double(raw, 'height'),
      angle: _double(raw, 'angle'),
      strokeColor: raw['strokeColor'] as String? ?? '#000000',
      backgroundColor: raw['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyle(raw),
      strokeWidth: _double(raw, 'strokeWidth', 2.0),
      strokeStyle: _strokeStyle(raw),
      roughness: _double(raw, 'roughness', 1.0),
      opacity: _opacity(raw),
      roundness: _roundness(raw),
      seed: _int(raw, 'seed'),
      version: _int(raw, 'version', 1),
      versionNonce: _int(raw, 'versionNonce'),
      isDeleted: raw['isDeleted'] as bool? ?? false,
      groupIds: _groupIds(raw),
      frameId: raw['frameId'] as String?,
      boundElements: _boundElements(raw),
      updated: _int(raw, 'updated'),
      link: raw['link'] as String?,
      locked: raw['locked'] as bool? ?? false,
      index: raw['index'] as String?,
    );
  }

  static FrameElement _parseFrame(Map<String, dynamic> raw) {
    return FrameElement(
      id: _id(raw),
      x: _double(raw, 'x'),
      y: _double(raw, 'y'),
      width: _double(raw, 'width'),
      height: _double(raw, 'height'),
      label: raw['name'] as String? ?? 'Frame',
      angle: _double(raw, 'angle'),
      strokeColor: raw['strokeColor'] as String? ?? '#000000',
      backgroundColor: raw['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyle(raw),
      strokeWidth: _double(raw, 'strokeWidth', 2.0),
      strokeStyle: _strokeStyle(raw),
      roughness: _double(raw, 'roughness', 1.0),
      opacity: _opacity(raw),
      roundness: _roundness(raw),
      seed: _int(raw, 'seed'),
      version: _int(raw, 'version', 1),
      versionNonce: _int(raw, 'versionNonce'),
      isDeleted: raw['isDeleted'] as bool? ?? false,
      groupIds: _groupIds(raw),
      frameId: raw['frameId'] as String?,
      boundElements: _boundElements(raw),
      updated: _int(raw, 'updated'),
      link: raw['link'] as String?,
      locked: raw['locked'] as bool? ?? false,
      index: raw['index'] as String?,
    );
  }

  static ImageElement _parseImage(Map<String, dynamic> raw) {
    final scaleList = raw['scale'];
    final imageScale = (scaleList is List && scaleList.isNotEmpty)
        ? (scaleList[0] as num).toDouble()
        : 1.0;

    ImageCrop? crop;
    final cropJson = raw['crop'];
    if (cropJson is Map<String, dynamic>) {
      crop = ImageCrop(
        x: (cropJson['x'] as num?)?.toDouble() ?? 0,
        y: (cropJson['y'] as num?)?.toDouble() ?? 0,
        width: (cropJson['width'] as num?)?.toDouble() ?? 1,
        height: (cropJson['height'] as num?)?.toDouble() ?? 1,
      );
    }

    return ImageElement(
      id: _id(raw),
      x: _double(raw, 'x'),
      y: _double(raw, 'y'),
      width: _double(raw, 'width'),
      height: _double(raw, 'height'),
      fileId: raw['fileId'] as String? ?? '',
      imageScale: imageScale,
      crop: crop,
      angle: _double(raw, 'angle'),
      strokeColor: raw['strokeColor'] as String? ?? '#000000',
      backgroundColor: raw['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyle(raw),
      strokeWidth: _double(raw, 'strokeWidth', 2.0),
      strokeStyle: _strokeStyle(raw),
      roughness: _double(raw, 'roughness', 1.0),
      opacity: _opacity(raw),
      roundness: _roundness(raw),
      seed: _int(raw, 'seed'),
      version: _int(raw, 'version', 1),
      versionNonce: _int(raw, 'versionNonce'),
      isDeleted: raw['isDeleted'] as bool? ?? false,
      groupIds: _groupIds(raw),
      frameId: raw['frameId'] as String?,
      boundElements: _boundElements(raw),
      updated: _int(raw, 'updated'),
      link: raw['link'] as String?,
      locked: raw['locked'] as bool? ?? false,
      index: raw['index'] as String?,
    );
  }

  // -- Text, Line, Arrow, Freedraw parsers --

  static TextElement _parseText(
    Map<String, dynamic> raw,
    int index,
    List<ParseWarning> warnings,
  ) {
    return TextElement(
      id: _id(raw),
      x: _double(raw, 'x'),
      y: _double(raw, 'y'),
      width: _double(raw, 'width'),
      height: _double(raw, 'height'),
      text: raw['text'] as String? ?? '',
      fontSize: _double(raw, 'fontSize', 20.0),
      fontFamily: _fontFamily(raw, index, warnings),
      textAlign: _textAlign(raw),
      verticalAlign: _verticalAlign(raw),
      containerId: raw['containerId'] as String?,
      lineHeight: _double(raw, 'lineHeight', 1.25),
      autoResize: raw['autoResize'] as bool? ?? true,
      angle: _double(raw, 'angle'),
      strokeColor: raw['strokeColor'] as String? ?? '#000000',
      backgroundColor: raw['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyle(raw),
      strokeWidth: _double(raw, 'strokeWidth', 2.0),
      strokeStyle: _strokeStyle(raw),
      roughness: _double(raw, 'roughness', 1.0),
      opacity: _opacity(raw),
      roundness: _roundness(raw),
      seed: _int(raw, 'seed'),
      version: _int(raw, 'version', 1),
      versionNonce: _int(raw, 'versionNonce'),
      isDeleted: raw['isDeleted'] as bool? ?? false,
      groupIds: _groupIds(raw),
      frameId: raw['frameId'] as String?,
      boundElements: _boundElements(raw),
      updated: _int(raw, 'updated'),
      link: raw['link'] as String?,
      locked: raw['locked'] as bool? ?? false,
      index: raw['index'] as String?,
    );
  }

  static LineElement _parseLine(
    Map<String, dynamic> raw,
    int index,
    List<ParseWarning> warnings,
  ) {
    return LineElement(
      id: _id(raw),
      x: _double(raw, 'x'),
      y: _double(raw, 'y'),
      width: _double(raw, 'width'),
      height: _double(raw, 'height'),
      points: _points(raw),
      startArrowhead: _arrowhead(
        raw['startArrowhead'] as String?,
        index,
        warnings,
      ),
      endArrowhead: _arrowhead(raw['endArrowhead'] as String?, index, warnings),
      closed: raw['polygon'] as bool? ?? false,
      angle: _double(raw, 'angle'),
      strokeColor: raw['strokeColor'] as String? ?? '#000000',
      backgroundColor: raw['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyle(raw),
      strokeWidth: _double(raw, 'strokeWidth', 2.0),
      strokeStyle: _strokeStyle(raw),
      roughness: _double(raw, 'roughness', 1.0),
      opacity: _opacity(raw),
      roundness: _roundness(raw),
      seed: _int(raw, 'seed'),
      version: _int(raw, 'version', 1),
      versionNonce: _int(raw, 'versionNonce'),
      isDeleted: raw['isDeleted'] as bool? ?? false,
      groupIds: _groupIds(raw),
      frameId: raw['frameId'] as String?,
      boundElements: _boundElements(raw),
      updated: _int(raw, 'updated'),
      link: raw['link'] as String?,
      locked: raw['locked'] as bool? ?? false,
      index: raw['index'] as String?,
    );
  }

  static ArrowElement _parseArrow(
    Map<String, dynamic> raw,
    int index,
    List<ParseWarning> warnings,
  ) {
    // Derive ArrowType from elbowed + roundness combination
    final isElbowed = raw['elbowed'] as bool? ?? false;
    final hasRoundness = _roundness(raw) != null;
    final ArrowType arrowType;
    if (isElbowed && hasRoundness) {
      arrowType = ArrowType.roundElbow;
    } else if (isElbowed) {
      arrowType = ArrowType.sharpElbow;
    } else if (hasRoundness) {
      arrowType = ArrowType.round;
    } else {
      arrowType = ArrowType.sharp;
    }

    return ArrowElement(
      id: _id(raw),
      x: _double(raw, 'x'),
      y: _double(raw, 'y'),
      width: _double(raw, 'width'),
      height: _double(raw, 'height'),
      points: _points(raw),
      startArrowhead: _arrowhead(
        raw['startArrowhead'] as String?,
        index,
        warnings,
      ),
      endArrowhead: _arrowhead(raw['endArrowhead'] as String?, index, warnings),
      startBinding: _binding(raw, 'startBinding'),
      endBinding: _binding(raw, 'endBinding'),
      arrowType: arrowType,
      angle: _double(raw, 'angle'),
      strokeColor: raw['strokeColor'] as String? ?? '#000000',
      backgroundColor: raw['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyle(raw),
      strokeWidth: _double(raw, 'strokeWidth', 2.0),
      strokeStyle: _strokeStyle(raw),
      roughness: _double(raw, 'roughness', 1.0),
      opacity: _opacity(raw),
      roundness: _roundness(raw),
      seed: _int(raw, 'seed'),
      version: _int(raw, 'version', 1),
      versionNonce: _int(raw, 'versionNonce'),
      isDeleted: raw['isDeleted'] as bool? ?? false,
      groupIds: _groupIds(raw),
      frameId: raw['frameId'] as String?,
      boundElements: _boundElements(raw),
      updated: _int(raw, 'updated'),
      link: raw['link'] as String?,
      locked: raw['locked'] as bool? ?? false,
      index: raw['index'] as String?,
    );
  }

  static FreedrawElement _parseFreedraw(Map<String, dynamic> raw) {
    return FreedrawElement(
      id: _id(raw),
      x: _double(raw, 'x'),
      y: _double(raw, 'y'),
      width: _double(raw, 'width'),
      height: _double(raw, 'height'),
      points: _points(raw),
      pressures: _pressures(raw),
      simulatePressure: raw['simulatePressure'] as bool? ?? false,
      angle: _double(raw, 'angle'),
      strokeColor: raw['strokeColor'] as String? ?? '#000000',
      backgroundColor: raw['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyle(raw),
      strokeWidth: _double(raw, 'strokeWidth', 2.0),
      strokeStyle: _strokeStyle(raw),
      roughness: _double(raw, 'roughness', 1.0),
      opacity: _opacity(raw),
      roundness: _roundness(raw),
      seed: _int(raw, 'seed'),
      version: _int(raw, 'version', 1),
      versionNonce: _int(raw, 'versionNonce'),
      isDeleted: raw['isDeleted'] as bool? ?? false,
      groupIds: _groupIds(raw),
      frameId: raw['frameId'] as String?,
      boundElements: _boundElements(raw),
      updated: _int(raw, 'updated'),
      link: raw['link'] as String?,
      locked: raw['locked'] as bool? ?? false,
      index: raw['index'] as String?,
    );
  }
}
