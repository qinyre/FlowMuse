import 'dart:math';

enum WhiteboardElementType { path, rectangle, ellipse, arrow, text, image }

class WhiteboardPoint {
  const WhiteboardPoint(this.x, this.y);

  final double x;
  final double y;

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  factory WhiteboardPoint.fromJson(Map<String, Object?> json) {
    return WhiteboardPoint(
      (json['x']! as num).toDouble(),
      (json['y']! as num).toDouble(),
    );
  }
}

class WhiteboardElement {
  const WhiteboardElement({
    required this.id,
    required this.type,
    required this.version,
    required this.versionNonce,
    required this.updatedAt,
    required this.fractionalIndex,
    required this.isDeleted,
    required this.data,
  });

  static final Random _random = Random.secure();

  final String id;
  final WhiteboardElementType type;
  final int version;
  final int versionNonce;
  final int updatedAt;
  final String fractionalIndex;
  final bool isDeleted;
  final Map<String, Object?> data;

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
    return WhiteboardElement._shape(
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
    return WhiteboardElement._shape(
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
    return WhiteboardElement(
      id: id,
      type: WhiteboardElementType.arrow,
      version: version,
      versionNonce: versionNonce ?? _random.nextInt(1 << 31),
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      fractionalIndex: fractionalIndex,
      isDeleted: false,
      data: {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2},
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
    return WhiteboardElement(
      id: id,
      type: WhiteboardElementType.path,
      version: version,
      versionNonce: versionNonce ?? _random.nextInt(1 << 31),
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      fractionalIndex: fractionalIndex,
      isDeleted: false,
      data: {
        'points': [for (final point in points) point.toJson()],
      },
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
    return WhiteboardElement(
      id: id,
      type: WhiteboardElementType.text,
      version: version,
      versionNonce: versionNonce ?? _random.nextInt(1 << 31),
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      fractionalIndex: fractionalIndex,
      isDeleted: false,
      data: {'x': x, 'y': y, 'text': text},
    );
  }

  factory WhiteboardElement._shape({
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
  }) {
    return WhiteboardElement(
      id: id,
      type: type,
      version: version,
      versionNonce: versionNonce ?? _random.nextInt(1 << 31),
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      fractionalIndex: fractionalIndex,
      isDeleted: false,
      data: {'x': x, 'y': y, 'width': width, 'height': height},
    );
  }

  List<WhiteboardPoint> get points {
    final raw = data['points'];
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        WhiteboardPoint.fromJson(Map<String, Object?>.from(item as Map)),
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
      version: version ?? this.version,
      versionNonce: versionNonce ?? this.versionNonce,
      updatedAt: updatedAt ?? this.updatedAt,
      fractionalIndex: fractionalIndex ?? this.fractionalIndex,
      isDeleted: isDeleted ?? this.isDeleted,
      data: data ?? this.data,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.name,
      'version': version,
      'versionNonce': versionNonce,
      'updatedAt': updatedAt,
      'fractionalIndex': fractionalIndex,
      'isDeleted': isDeleted,
      'data': data,
    };
  }

  factory WhiteboardElement.fromJson(Map<String, Object?> json) {
    return WhiteboardElement(
      id: json['id']! as String,
      type: WhiteboardElementType.values.byName(json['type']! as String),
      version: json['version']! as int,
      versionNonce: json['versionNonce']! as int,
      updatedAt: json['updatedAt']! as int,
      fractionalIndex: json['fractionalIndex']! as String,
      isDeleted: json['isDeleted']! as bool,
      data: Map<String, Object?>.from(json['data']! as Map),
    );
  }
}
