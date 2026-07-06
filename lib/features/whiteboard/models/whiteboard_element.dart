import 'dart:math';

enum WhiteboardElementType {
  rectangle,
  diamond,
  ellipse,
  arrow,
  line,
  freedraw,
  text,
  image,
  frame,
  magicFrame,
  embeddable,
  iframe,
}

enum WhiteboardFillStyle { hachure, crossHatch, solid, zigzag }

enum WhiteboardStrokeStyle { solid, dashed, dotted }

enum WhiteboardTextAlign { left, center, right }

enum WhiteboardVerticalAlign { top, middle, bottom }

class WhiteboardPoint {
  const WhiteboardPoint(this.x, this.y);

  final double x;
  final double y;

  List<double> toExcalidrawJson() => [x, y];

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  factory WhiteboardPoint.fromJson(Object? json) {
    if (json is List && json.length >= 2) {
      return WhiteboardPoint(
        (json[0] as num).toDouble(),
        (json[1] as num).toDouble(),
      );
    }
    throw const FormatException(
      'Whiteboard points must use Excalidraw point arrays.',
    );
  }
}

class WhiteboardElement {
  const WhiteboardElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.angle,
    required this.strokeColor,
    required this.backgroundColor,
    required this.fillStyle,
    required this.strokeWidth,
    required this.strokeStyle,
    required this.roughness,
    required this.opacity,
    required this.seed,
    required this.version,
    required this.versionNonce,
    required this.updatedAt,
    required this.fractionalIndex,
    required this.isDeleted,
    required this.groupIds,
    required this.frameId,
    required this.boundElements,
    required this.link,
    required this.locked,
    required this.points,
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.textAlign,
    required this.verticalAlign,
    required this.containerId,
    required this.originalText,
    required this.autoResize,
    required this.lineHeight,
    required this.fileId,
    required this.status,
    required this.scale,
    required this.crop,
    required this.startBinding,
    required this.endBinding,
    required this.startArrowhead,
    required this.endArrowhead,
    required this.elbowed,
    required this.pressures,
    required this.simulatePressure,
    required this.strokeOptions,
    required this.name,
    required this.customData,
  });

  static final Random _random = Random.secure();

  final String id;
  final WhiteboardElementType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double angle;
  final String strokeColor;
  final String backgroundColor;
  final WhiteboardFillStyle fillStyle;
  final double strokeWidth;
  final WhiteboardStrokeStyle strokeStyle;
  final double roughness;
  final int opacity;
  final int seed;
  final int version;
  final int versionNonce;
  final int updatedAt;
  final String? fractionalIndex;
  final bool isDeleted;
  final List<String> groupIds;
  final String? frameId;
  final List<Map<String, Object?>>? boundElements;
  final String? link;
  final bool locked;
  final List<WhiteboardPoint> points;
  final String? text;
  final double? fontSize;
  final int? fontFamily;
  final WhiteboardTextAlign? textAlign;
  final WhiteboardVerticalAlign? verticalAlign;
  final String? containerId;
  final String? originalText;
  final bool? autoResize;
  final double? lineHeight;
  final String? fileId;
  final String? status;
  final List<double>? scale;
  final Map<String, Object?>? crop;
  final Map<String, Object?>? startBinding;
  final Map<String, Object?>? endBinding;
  final String? startArrowhead;
  final String? endArrowhead;
  final bool? elbowed;
  final List<double>? pressures;
  final bool? simulatePressure;
  final Map<String, Object?>? strokeOptions;
  final String? name;
  final Map<String, Object?>? customData;

  factory WhiteboardElement.rectangle({
    required String id,
    required double x,
    required double y,
    required double width,
    required double height,
    required String fractionalIndex,
    int version = 1,
    int? versionNonce,
    int? updatedAt,
  }) {
    return WhiteboardElement._base(
      id: id,
      type: WhiteboardElementType.rectangle,
      x: x,
      y: y,
      width: width,
      height: height,
      fractionalIndex: fractionalIndex,
      version: version,
      versionNonce: versionNonce,
      updatedAt: updatedAt,
    );
  }

  factory WhiteboardElement.ellipse({
    required String id,
    required double x,
    required double y,
    required double width,
    required double height,
    required String fractionalIndex,
    int version = 1,
    int? versionNonce,
    int? updatedAt,
  }) {
    return WhiteboardElement._base(
      id: id,
      type: WhiteboardElementType.ellipse,
      x: x,
      y: y,
      width: width,
      height: height,
      fractionalIndex: fractionalIndex,
      version: version,
      versionNonce: versionNonce,
      updatedAt: updatedAt,
    );
  }

  factory WhiteboardElement.arrow({
    required String id,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required String fractionalIndex,
    int version = 1,
    int? versionNonce,
    int? updatedAt,
  }) {
    return WhiteboardElement._base(
      id: id,
      type: WhiteboardElementType.arrow,
      x: x1,
      y: y1,
      width: x2 - x1,
      height: y2 - y1,
      fractionalIndex: fractionalIndex,
      version: version,
      versionNonce: versionNonce,
      updatedAt: updatedAt,
      points: [const WhiteboardPoint(0, 0), WhiteboardPoint(x2 - x1, y2 - y1)],
    );
  }

  factory WhiteboardElement.path({
    required String id,
    required List<WhiteboardPoint> points,
    required String fractionalIndex,
    int version = 1,
    int? versionNonce,
    int? updatedAt,
  }) {
    final origin = points.isEmpty ? const WhiteboardPoint(0, 0) : points.first;
    final localPoints = [
      for (final point in points)
        WhiteboardPoint(point.x - origin.x, point.y - origin.y),
    ];
    final xs = localPoints.map((point) => point.x);
    final ys = localPoints.map((point) => point.y);
    final width = xs.isEmpty ? 0.0 : xs.reduce(max) - xs.reduce(min);
    final height = ys.isEmpty ? 0.0 : ys.reduce(max) - ys.reduce(min);
    return WhiteboardElement._base(
      id: id,
      type: WhiteboardElementType.freedraw,
      x: origin.x,
      y: origin.y,
      width: width,
      height: height,
      fractionalIndex: fractionalIndex,
      version: version,
      versionNonce: versionNonce,
      updatedAt: updatedAt,
      points: localPoints,
    );
  }

  factory WhiteboardElement.text({
    required String id,
    required double x,
    required double y,
    required String text,
    required String fractionalIndex,
    int version = 1,
    int? versionNonce,
    int? updatedAt,
  }) {
    return WhiteboardElement._base(
      id: id,
      type: WhiteboardElementType.text,
      x: x,
      y: y,
      width: text.isEmpty ? 20 : text.length * 20,
      height: 24,
      fractionalIndex: fractionalIndex,
      version: version,
      versionNonce: versionNonce,
      updatedAt: updatedAt,
      text: text,
      fontSize: 20,
      fontFamily: 1,
      textAlign: WhiteboardTextAlign.left,
      verticalAlign: WhiteboardVerticalAlign.top,
      originalText: text,
      autoResize: true,
      lineHeight: 1.25,
    );
  }

  factory WhiteboardElement._base({
    required String id,
    required WhiteboardElementType type,
    required double x,
    required double y,
    required double width,
    required double height,
    required String fractionalIndex,
    required int version,
    int? versionNonce,
    int? updatedAt,
    List<WhiteboardPoint> points = const [],
    String? text,
    double? fontSize,
    int? fontFamily,
    WhiteboardTextAlign? textAlign,
    WhiteboardVerticalAlign? verticalAlign,
    String? originalText,
    bool? autoResize,
    double? lineHeight,
  }) {
    return WhiteboardElement(
      id: id,
      type: type,
      x: x,
      y: y,
      width: width,
      height: height,
      angle: 0,
      strokeColor: '#1e1e1e',
      backgroundColor: 'transparent',
      fillStyle: WhiteboardFillStyle.solid,
      strokeWidth: 2,
      strokeStyle: WhiteboardStrokeStyle.solid,
      roughness: 0,
      opacity: 100,
      seed: _random.nextInt(1 << 31),
      version: version,
      versionNonce: versionNonce ?? _random.nextInt(1 << 31),
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      fractionalIndex: fractionalIndex,
      isDeleted: false,
      groupIds: const [],
      frameId: null,
      boundElements: null,
      link: null,
      locked: false,
      points: points,
      text: text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      verticalAlign: verticalAlign,
      containerId: null,
      originalText: originalText,
      autoResize: autoResize,
      lineHeight: lineHeight,
      fileId: null,
      status: null,
      scale: null,
      crop: null,
      startBinding: null,
      endBinding: null,
      startArrowhead: null,
      endArrowhead: type == WhiteboardElementType.arrow ? 'arrow' : null,
      elbowed: type == WhiteboardElementType.arrow ? false : null,
      pressures: type == WhiteboardElementType.freedraw
          ? List<double>.filled(points.length, 0.5, growable: false)
          : null,
      simulatePressure: type == WhiteboardElementType.freedraw ? true : null,
      strokeOptions: type == WhiteboardElementType.freedraw
          ? const {'variability': 'variable', 'streamline': 0.5}
          : null,
      name: null,
      customData: null,
    );
  }

  Map<String, Object?> get data {
    return switch (type) {
      WhiteboardElementType.arrow => {
        'x1': x,
        'y1': y,
        'x2': x + (points.length > 1 ? points[1].x : width),
        'y2': y + (points.length > 1 ? points[1].y : height),
      },
      WhiteboardElementType.freedraw || WhiteboardElementType.line => {
        'points': [for (final point in scenePoints) point.toJson()],
      },
      WhiteboardElementType.text => {'x': x, 'y': y, 'text': text ?? ''},
      _ => {'x': x, 'y': y, 'width': width, 'height': height},
    };
  }

  List<WhiteboardPoint> get scenePoints {
    return [
      for (final point in points) WhiteboardPoint(x + point.x, y + point.y),
    ];
  }

  WhiteboardElement copyWith({
    int? version,
    int? versionNonce,
    int? updatedAt,
    String? fractionalIndex,
    bool? isDeleted,
    Map<String, Object?>? data,
  }) {
    return WhiteboardElement(
      id: id,
      type: type,
      x: _numberFromData(data, 'x') ?? x,
      y: _numberFromData(data, 'y') ?? y,
      width: _numberFromData(data, 'width') ?? width,
      height: _numberFromData(data, 'height') ?? height,
      angle: angle,
      strokeColor: strokeColor,
      backgroundColor: backgroundColor,
      fillStyle: fillStyle,
      strokeWidth: strokeWidth,
      strokeStyle: strokeStyle,
      roughness: roughness,
      opacity: opacity,
      seed: seed,
      version: version ?? this.version,
      versionNonce: versionNonce ?? this.versionNonce,
      updatedAt: updatedAt ?? this.updatedAt,
      fractionalIndex: fractionalIndex ?? this.fractionalIndex,
      isDeleted: isDeleted ?? this.isDeleted,
      groupIds: groupIds,
      frameId: frameId,
      boundElements: boundElements,
      link: link,
      locked: locked,
      points: points,
      text: data?['text'] as String? ?? text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      verticalAlign: verticalAlign,
      containerId: containerId,
      originalText: originalText,
      autoResize: autoResize,
      lineHeight: lineHeight,
      fileId: fileId,
      status: status,
      scale: scale,
      crop: crop,
      startBinding: startBinding,
      endBinding: endBinding,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
      elbowed: elbowed,
      pressures: pressures,
      simulatePressure: simulatePressure,
      strokeOptions: strokeOptions,
      name: name,
      customData: customData,
    );
  }

  WhiteboardElement newWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? angle,
    String? strokeColor,
    String? backgroundColor,
    WhiteboardFillStyle? fillStyle,
    double? strokeWidth,
    WhiteboardStrokeStyle? strokeStyle,
    double? roughness,
    int? opacity,
    int? version,
    int? versionNonce,
    int? updatedAt,
    String? fractionalIndex,
    bool? isDeleted,
    List<String>? groupIds,
    String? frameId,
    List<Map<String, Object?>>? boundElements,
    String? link,
    bool? locked,
    List<WhiteboardPoint>? points,
    String? text,
    double? fontSize,
    int? fontFamily,
    WhiteboardTextAlign? textAlign,
    WhiteboardVerticalAlign? verticalAlign,
    String? containerId,
    String? originalText,
    bool? autoResize,
    double? lineHeight,
    String? fileId,
    String? status,
    List<double>? scale,
    Map<String, Object?>? crop,
    Map<String, Object?>? startBinding,
    Map<String, Object?>? endBinding,
    String? startArrowhead,
    String? endArrowhead,
    bool? elbowed,
    List<double>? pressures,
    bool? simulatePressure,
    Map<String, Object?>? strokeOptions,
    String? name,
    Map<String, Object?>? customData,
    bool force = false,
  }) {
    final nextX = x ?? this.x;
    final nextY = y ?? this.y;
    final nextWidth = width ?? this.width;
    final nextHeight = height ?? this.height;
    final nextAngle = angle ?? this.angle;
    final nextStrokeColor = strokeColor ?? this.strokeColor;
    final nextBackgroundColor = backgroundColor ?? this.backgroundColor;
    final nextFillStyle = fillStyle ?? this.fillStyle;
    final nextStrokeWidth = strokeWidth ?? this.strokeWidth;
    final nextStrokeStyle = strokeStyle ?? this.strokeStyle;
    final nextRoughness = roughness ?? this.roughness;
    final nextOpacity = opacity ?? this.opacity;
    final nextFractionalIndex = fractionalIndex ?? this.fractionalIndex;
    final nextIsDeleted = isDeleted ?? this.isDeleted;
    final nextGroupIds = groupIds ?? this.groupIds;
    final nextFrameId = frameId ?? this.frameId;
    final nextBoundElements = boundElements ?? this.boundElements;
    final nextLink = link ?? this.link;
    final nextLocked = locked ?? this.locked;
    final nextPoints = points ?? this.points;
    final nextText = text ?? this.text;
    final nextFontSize = fontSize ?? this.fontSize;
    final nextFontFamily = fontFamily ?? this.fontFamily;
    final nextTextAlign = textAlign ?? this.textAlign;
    final nextVerticalAlign = verticalAlign ?? this.verticalAlign;
    final nextContainerId = containerId ?? this.containerId;
    final nextOriginalText = originalText ?? this.originalText;
    final nextAutoResize = autoResize ?? this.autoResize;
    final nextLineHeight = lineHeight ?? this.lineHeight;
    final nextFileId = fileId ?? this.fileId;
    final nextStatus = status ?? this.status;
    final nextScale = scale ?? this.scale;
    final nextCrop = crop ?? this.crop;
    final nextStartBinding = startBinding ?? this.startBinding;
    final nextEndBinding = endBinding ?? this.endBinding;
    final nextStartArrowhead = startArrowhead ?? this.startArrowhead;
    final nextEndArrowhead = endArrowhead ?? this.endArrowhead;
    final nextElbowed = elbowed ?? this.elbowed;
    final nextPressures = pressures ?? this.pressures;
    final nextSimulatePressure = simulatePressure ?? this.simulatePressure;
    final nextStrokeOptions = strokeOptions ?? this.strokeOptions;
    final nextName = name ?? this.name;
    final nextCustomData = customData ?? this.customData;

    final didChange =
        force ||
        nextX != this.x ||
        nextY != this.y ||
        nextWidth != this.width ||
        nextHeight != this.height ||
        nextAngle != this.angle ||
        nextStrokeColor != this.strokeColor ||
        nextBackgroundColor != this.backgroundColor ||
        nextFillStyle != this.fillStyle ||
        nextStrokeWidth != this.strokeWidth ||
        nextStrokeStyle != this.strokeStyle ||
        nextRoughness != this.roughness ||
        nextOpacity != this.opacity ||
        nextFractionalIndex != this.fractionalIndex ||
        nextIsDeleted != this.isDeleted ||
        !_stringListsEqual(nextGroupIds, this.groupIds) ||
        nextFrameId != this.frameId ||
        !identical(nextBoundElements, this.boundElements) ||
        nextLink != this.link ||
        nextLocked != this.locked ||
        !_pointsEqual(nextPoints, this.points) ||
        nextText != this.text ||
        nextFontSize != this.fontSize ||
        nextFontFamily != this.fontFamily ||
        nextTextAlign != this.textAlign ||
        nextVerticalAlign != this.verticalAlign ||
        nextContainerId != this.containerId ||
        nextOriginalText != this.originalText ||
        nextAutoResize != this.autoResize ||
        nextLineHeight != this.lineHeight ||
        nextFileId != this.fileId ||
        nextStatus != this.status ||
        !_doubleListsEqual(nextScale, this.scale) ||
        !identical(nextCrop, this.crop) ||
        !identical(nextStartBinding, this.startBinding) ||
        !identical(nextEndBinding, this.endBinding) ||
        nextStartArrowhead != this.startArrowhead ||
        nextEndArrowhead != this.endArrowhead ||
        nextElbowed != this.elbowed ||
        !_doubleListsEqual(nextPressures, this.pressures) ||
        nextSimulatePressure != this.simulatePressure ||
        !identical(nextStrokeOptions, this.strokeOptions) ||
        nextName != this.name ||
        !identical(nextCustomData, this.customData);

    if (!didChange) {
      return this;
    }

    return WhiteboardElement(
      id: id,
      type: type,
      x: nextX,
      y: nextY,
      width: nextWidth,
      height: nextHeight,
      angle: nextAngle,
      strokeColor: nextStrokeColor,
      backgroundColor: nextBackgroundColor,
      fillStyle: nextFillStyle,
      strokeWidth: nextStrokeWidth,
      strokeStyle: nextStrokeStyle,
      roughness: nextRoughness,
      opacity: nextOpacity,
      seed: seed,
      version: version ?? this.version + 1,
      versionNonce: versionNonce ?? _random.nextInt(1 << 31),
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      fractionalIndex: nextFractionalIndex,
      isDeleted: nextIsDeleted,
      groupIds: nextGroupIds,
      frameId: nextFrameId,
      boundElements: nextBoundElements,
      link: nextLink,
      locked: nextLocked,
      points: nextPoints,
      text: nextText,
      fontSize: nextFontSize,
      fontFamily: nextFontFamily,
      textAlign: nextTextAlign,
      verticalAlign: nextVerticalAlign,
      containerId: nextContainerId,
      originalText: nextOriginalText,
      autoResize: nextAutoResize,
      lineHeight: nextLineHeight,
      fileId: nextFileId,
      status: nextStatus,
      scale: nextScale,
      crop: nextCrop,
      startBinding: nextStartBinding,
      endBinding: nextEndBinding,
      startArrowhead: nextStartArrowhead,
      endArrowhead: nextEndArrowhead,
      elbowed: nextElbowed,
      pressures: nextPressures,
      simulatePressure: nextSimulatePressure,
      strokeOptions: nextStrokeOptions,
      name: nextName,
      customData: nextCustomData,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': _typeToJson(type),
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'angle': angle,
      'strokeColor': strokeColor,
      'backgroundColor': backgroundColor,
      'fillStyle': _fillStyleToJson(fillStyle),
      'strokeWidth': strokeWidth,
      'strokeStyle': strokeStyle.name,
      'roughness': roughness,
      'opacity': opacity,
      'seed': seed,
      'version': version,
      'versionNonce': versionNonce,
      'index': fractionalIndex,
      'isDeleted': isDeleted,
      'groupIds': groupIds,
      'frameId': frameId,
      'boundElements': boundElements,
      'updated': updatedAt,
      'link': link,
      'locked': locked,
      if (points.isNotEmpty)
        'points': [for (final point in points) point.toExcalidrawJson()],
      if (text != null) 'text': text,
      if (fontSize != null) 'fontSize': fontSize,
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (textAlign != null) 'textAlign': textAlign!.name,
      if (verticalAlign != null) 'verticalAlign': verticalAlign!.name,
      if (containerId != null) 'containerId': containerId,
      if (originalText != null) 'originalText': originalText,
      if (autoResize != null) 'autoResize': autoResize,
      if (lineHeight != null) 'lineHeight': lineHeight,
      if (fileId != null) 'fileId': fileId,
      if (status != null) 'status': status,
      if (scale != null) 'scale': scale,
      if (crop != null) 'crop': crop,
      if (_isLinearElement) ...{
        'startBinding': startBinding,
        'endBinding': endBinding,
        'startArrowhead': startArrowhead,
        'endArrowhead': endArrowhead,
      },
      if (elbowed != null) 'elbowed': elbowed,
      if (pressures != null) 'pressures': pressures,
      if (simulatePressure != null) 'simulatePressure': simulatePressure,
      if (strokeOptions != null) 'strokeOptions': strokeOptions,
      if (name != null) 'name': name,
      if (customData != null) 'customData': customData,
    };
  }

  factory WhiteboardElement.fromJson(Map<String, Object?> json) {
    if (json.containsKey('data')) {
      throw const FormatException(
        'Whiteboard elements must use Excalidraw element JSON.',
      );
    }
    if (json.containsKey('updatedAt') || json.containsKey('fractionalIndex')) {
      throw const FormatException(
        'Whiteboard elements must use Excalidraw updated/index fields.',
      );
    }
    final type = _typeFromJson(json['type']! as String);
    final points = json['points'] is List
        ? [
            for (final point in json['points']! as List)
              WhiteboardPoint.fromJson(point),
          ]
        : const <WhiteboardPoint>[];
    return WhiteboardElement(
      id: json['id']! as String,
      type: type,
      x: _number(json['x']) ?? 0,
      y: _number(json['y']) ?? 0,
      width: _number(json['width']) ?? 0,
      height: _number(json['height']) ?? 0,
      angle: _number(json['angle']) ?? 0,
      strokeColor: json['strokeColor'] as String? ?? '#1e1e1e',
      backgroundColor: json['backgroundColor'] as String? ?? 'transparent',
      fillStyle: _fillStyleFromJson(json['fillStyle'] as String? ?? 'solid'),
      strokeWidth: _number(json['strokeWidth']) ?? 2,
      strokeStyle: WhiteboardStrokeStyle.values.byName(
        json['strokeStyle'] as String? ?? 'solid',
      ),
      roughness: _number(json['roughness']) ?? 0,
      opacity: (json['opacity'] as num?)?.toInt() ?? 100,
      seed: (json['seed'] as num?)?.toInt() ?? _random.nextInt(1 << 31),
      version: (json['version']! as num).toInt(),
      versionNonce: (json['versionNonce']! as num).toInt(),
      updatedAt: (json['updated']! as num).toInt(),
      fractionalIndex: json['index'] as String?,
      isDeleted: json['isDeleted']! as bool,
      groupIds: [
        for (final groupId in json['groupIds'] as List? ?? const [])
          groupId as String,
      ],
      frameId: json['frameId'] as String?,
      boundElements: json['boundElements'] is List
          ? [
              for (final item in json['boundElements']! as List)
                Map<String, Object?>.from(item as Map),
            ]
          : null,
      link: json['link'] as String?,
      locked: json['locked'] as bool? ?? false,
      points: points,
      text: json['text'] as String?,
      fontSize: _number(json['fontSize']),
      fontFamily: (json['fontFamily'] as num?)?.toInt(),
      textAlign: json['textAlign'] is String
          ? WhiteboardTextAlign.values.byName(json['textAlign']! as String)
          : null,
      verticalAlign: json['verticalAlign'] is String
          ? WhiteboardVerticalAlign.values.byName(
              json['verticalAlign']! as String,
            )
          : null,
      containerId: json['containerId'] as String?,
      originalText: json['originalText'] as String?,
      autoResize: json['autoResize'] as bool?,
      lineHeight: _number(json['lineHeight']),
      fileId: json['fileId'] as String?,
      status: json['status'] as String?,
      scale: json['scale'] is List
          ? [
              for (final item in json['scale']! as List)
                (item as num).toDouble(),
            ]
          : null,
      crop: json['crop'] is Map
          ? Map<String, Object?>.from(json['crop']! as Map)
          : null,
      startBinding: json['startBinding'] is Map
          ? Map<String, Object?>.from(json['startBinding']! as Map)
          : null,
      endBinding: json['endBinding'] is Map
          ? Map<String, Object?>.from(json['endBinding']! as Map)
          : null,
      startArrowhead: json['startArrowhead'] as String?,
      endArrowhead: json['endArrowhead'] as String?,
      elbowed: json['elbowed'] as bool?,
      pressures: json['pressures'] is List
          ? [
              for (final item in json['pressures']! as List)
                (item as num).toDouble(),
            ]
          : null,
      simulatePressure: json['simulatePressure'] as bool?,
      strokeOptions: json['strokeOptions'] is Map
          ? Map<String, Object?>.from(json['strokeOptions']! as Map)
          : null,
      name: json['name'] as String?,
      customData: json['customData'] is Map
          ? Map<String, Object?>.from(json['customData']! as Map)
          : null,
    );
  }

  bool get _isLinearElement {
    return type == WhiteboardElementType.arrow ||
        type == WhiteboardElementType.line;
  }

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;

  static double? _numberFromData(Map<String, Object?>? data, String key) {
    return data == null ? null : _number(data[key]);
  }

  static bool _stringListsEqual(List<String>? a, List<String>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _doubleListsEqual(List<double>? a, List<double>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _pointsEqual(List<WhiteboardPoint> a, List<WhiteboardPoint> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i].x != b[i].x || a[i].y != b[i].y) {
        return false;
      }
    }
    return true;
  }

  static String _typeToJson(WhiteboardElementType type) {
    return switch (type) {
      WhiteboardElementType.freedraw => 'freedraw',
      WhiteboardElementType.magicFrame => 'magicframe',
      _ => type.name,
    };
  }

  static WhiteboardElementType _typeFromJson(String type) {
    return switch (type) {
      'path' || 'freedraw' => WhiteboardElementType.freedraw,
      'magicframe' => WhiteboardElementType.magicFrame,
      _ => WhiteboardElementType.values.byName(type),
    };
  }

  static String _fillStyleToJson(WhiteboardFillStyle fillStyle) {
    return switch (fillStyle) {
      WhiteboardFillStyle.crossHatch => 'cross-hatch',
      _ => fillStyle.name,
    };
  }

  static WhiteboardFillStyle _fillStyleFromJson(String fillStyle) {
    return switch (fillStyle) {
      'cross-hatch' => WhiteboardFillStyle.crossHatch,
      _ => WhiteboardFillStyle.values.byName(fillStyle),
    };
  }
}
