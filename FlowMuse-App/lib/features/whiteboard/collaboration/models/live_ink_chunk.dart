import 'dart:convert';

class LiveInkPoint {
  const LiveInkPoint({required this.x, required this.y, this.pressure});

  final double x;
  final double y;
  final double? pressure;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'pressure': pressure};

  factory LiveInkPoint.fromJson(Map<String, Object?> json) {
    final x = _finiteDouble(json['x'], 'x');
    final y = _finiteDouble(json['y'], 'y');
    final pressureValue = json['pressure'];
    final pressure = pressureValue == null
        ? null
        : _finiteDouble(pressureValue, 'pressure');
    if (x.abs() > LiveInkChunk.maxCoordinate ||
        y.abs() > LiveInkChunk.maxCoordinate) {
      throw const FormatException('Live ink coordinate is out of range');
    }
    if (pressure != null && (pressure < 0 || pressure > 1)) {
      throw const FormatException('Live ink pressure is out of range');
    }
    return LiveInkPoint(x: x, y: y, pressure: pressure);
  }
}

class LiveInkStyle {
  const LiveInkStyle({
    required this.brushType,
    required this.strokeColor,
    required this.strokeWidth,
    required this.opacity,
    this.renderVersion = 1,
  });

  /// 渲染版本（计划 §3.9）：1=v1（缺失即 1，旧客户端兼容），2=自然介质。
  /// 只影响预览渲染选择，不改 protocolVersion=2 的外层结构。
  final int renderVersion;

  static const allowedBrushTypes = {
    'pencil',
    'ballpoint',
    'fountainPen',
    'brushPen',
    'highlighter',
  };
  static final RegExp _colorPattern = RegExp(
    r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$',
  );

  final String brushType;
  final String strokeColor;
  final double strokeWidth;
  final double opacity;

  Map<String, Object?> toJson() => {
    'brushType': brushType,
    'strokeColor': strokeColor,
    'strokeWidth': strokeWidth,
    'opacity': opacity,
    // v1 省略字段：旧客户端按缺失=v1 处理（混合版本协作契约）。
    if (renderVersion == 2) 'renderVersion': 2,
  };

  factory LiveInkStyle.fromJson(Map<String, Object?> json) {
    final brushType = json['brushType'];
    final strokeColor = json['strokeColor'];
    final strokeWidth = _finiteDouble(json['strokeWidth'], 'strokeWidth');
    final opacity = _finiteDouble(json['opacity'], 'opacity');
    if (brushType is! String || !allowedBrushTypes.contains(brushType)) {
      throw const FormatException('Invalid live ink brushType');
    }
    if (strokeColor is! String || !_colorPattern.hasMatch(strokeColor)) {
      throw const FormatException('Invalid live ink strokeColor');
    }
    if (strokeWidth <= 0 || strokeWidth > 100) {
      throw const FormatException('Invalid live ink strokeWidth');
    }
    if (opacity < 0 || opacity > 100) {
      throw const FormatException('Invalid live ink opacity');
    }
    // renderVersion：缺失取 1；存在但不是 num == 1/2 时拒绝该 chunk
    //（禁止裸 is int——dart2js 下 1.0 不是 int）。v2 只对自然介质笔形
    // 有效，非法 brush/version 组合安全回退 1 而不是丢整段协作数据。
    var renderVersion = 1;
    final renderValue = json['renderVersion'];
    if (renderValue != null) {
      if (renderValue is num && renderValue == 2) {
        renderVersion = 2;
      } else if (!(renderValue is num && renderValue == 1)) {
        throw const FormatException('Invalid live ink renderVersion');
      }
    }
    if (renderVersion == 2 &&
        !(brushType == 'pencil' || brushType == 'brushPen')) {
      renderVersion = 1;
    }
    return LiveInkStyle(
      brushType: brushType,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      renderVersion: renderVersion,
    );
  }
}

class IndexedLiveInkPoint {
  const IndexedLiveInkPoint({required this.index, required this.point});

  final int index;
  final LiveInkPoint point;
}

class LiveInkChunk {
  const LiveInkChunk({
    required this.strokeId,
    required this.startIndex,
    required this.points,
    required this.style,
  });

  static const int protocolVersion = 2;
  static const int maxPoints = 64;
  static const double maxCoordinate = 10000000;

  final String strokeId;
  final int startIndex;
  final List<LiveInkPoint> points;
  final LiveInkStyle style;

  Iterable<IndexedLiveInkPoint> get indexedPoints sync* {
    for (var offset = 0; offset < points.length; offset++) {
      yield IndexedLiveInkPoint(
        index: startIndex + offset,
        point: points[offset],
      );
    }
  }

  int addMissingPointsTo(Map<int, LiveInkPoint> target) {
    var added = 0;
    for (final entry in indexedPoints) {
      if (target.containsKey(entry.index)) continue;
      target[entry.index] = entry.point;
      added++;
    }
    return added;
  }

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'strokeId': strokeId,
    'startIndex': startIndex,
    'points': [for (final point in points) point.toJson()],
    'style': style.toJson(),
  };

  factory LiveInkChunk.fromJson(Map<String, Object?> json) {
    if (json['protocolVersion'] != protocolVersion) {
      throw const FormatException('Unsupported live ink protocolVersion');
    }
    final strokeId = json['strokeId'];
    if (strokeId is! String ||
        strokeId.isEmpty ||
        utf8.encode(strokeId).length > 128) {
      throw const FormatException('Invalid live ink strokeId');
    }
    final startIndexValue = json['startIndex'];
    if (startIndexValue is! num ||
        startIndexValue.toInt() != startIndexValue ||
        startIndexValue.toInt() < 0) {
      throw const FormatException('Invalid live ink startIndex');
    }
    final rawPoints = json['points'];
    if (rawPoints is! List ||
        rawPoints.isEmpty ||
        rawPoints.length > maxPoints) {
      throw const FormatException('Invalid live ink points length');
    }
    final rawStyle = json['style'];
    if (rawStyle is! Map) {
      throw const FormatException('Missing live ink style');
    }
    return LiveInkChunk(
      strokeId: strokeId,
      startIndex: startIndexValue.toInt(),
      points: List.unmodifiable([
        for (final point in rawPoints)
          if (point is Map)
            LiveInkPoint.fromJson(Map<String, Object?>.from(point))
          else
            throw const FormatException('Invalid live ink point'),
      ]),
      style: LiveInkStyle.fromJson(Map<String, Object?>.from(rawStyle)),
    );
  }
}

double _finiteDouble(Object? value, String field) {
  if (value is! num) throw FormatException('Invalid live ink $field');
  final result = value.toDouble();
  if (!result.isFinite) throw FormatException('Invalid live ink $field');
  return result;
}
