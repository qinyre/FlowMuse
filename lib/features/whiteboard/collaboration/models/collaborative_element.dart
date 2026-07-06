import '../../models/whiteboard_element.dart';

class CollaborativeElement {
  const CollaborativeElement({
    required this.id,
    required this.type,
    required this.version,
    required this.versionNonce,
    required this.updatedAt,
    required this.fractionalIndex,
    required this.isDeleted,
    required this.elementJson,
  });

  final String id;
  final WhiteboardElementType type;
  final int version;
  final int versionNonce;
  final int updatedAt;
  final String? fractionalIndex;
  final bool isDeleted;
  final Map<String, Object?> elementJson;

  factory CollaborativeElement.fromElement(WhiteboardElement element) {
    return CollaborativeElement(
      id: element.id,
      type: element.type,
      version: element.version,
      versionNonce: element.versionNonce,
      updatedAt: element.updatedAt,
      fractionalIndex: element.fractionalIndex,
      isDeleted: element.isDeleted,
      elementJson: element.toJson(),
    );
  }

  CollaborativeElement copyWith({
    int? version,
    int? versionNonce,
    int? updatedAt,
    String? fractionalIndex,
    bool? isDeleted,
    Map<String, Object?>? elementJson,
  }) {
    final nextVersion = version ?? this.version;
    final nextVersionNonce = versionNonce ?? this.versionNonce;
    final nextUpdatedAt = updatedAt ?? this.updatedAt;
    final nextFractionalIndex = fractionalIndex ?? this.fractionalIndex;
    final nextIsDeleted = isDeleted ?? this.isDeleted;
    final nextElementJson = Map<String, Object?>.from(
      elementJson ?? this.elementJson,
    );
    nextElementJson['version'] = nextVersion;
    nextElementJson['versionNonce'] = nextVersionNonce;
    nextElementJson['updated'] = nextUpdatedAt;
    nextElementJson['index'] = nextFractionalIndex;
    nextElementJson['isDeleted'] = nextIsDeleted;
    return CollaborativeElement(
      id: id,
      type: type,
      version: nextVersion,
      versionNonce: nextVersionNonce,
      updatedAt: nextUpdatedAt,
      fractionalIndex: nextFractionalIndex,
      isDeleted: nextIsDeleted,
      elementJson: nextElementJson,
    );
  }

  Map<String, Object?> toJson() {
    return Map<String, Object?>.from(elementJson)
      ..['id'] = id
      ..['type'] = _typeToJson(type)
      ..['version'] = version
      ..['versionNonce'] = versionNonce
      ..['updated'] = updatedAt
      ..['index'] = fractionalIndex
      ..['isDeleted'] = isDeleted;
  }

  factory CollaborativeElement.fromJson(Map<String, Object?> json) {
    if (json.containsKey('data')) {
      throw const FormatException(
        'Collaborative elements must use full Excalidraw element JSON.',
      );
    }
    final element = WhiteboardElement.fromJson(json);
    return CollaborativeElement(
      id: json['id']! as String,
      type: element.type,
      version: (json['version']! as num).toInt(),
      versionNonce: (json['versionNonce']! as num).toInt(),
      updatedAt: ((json['updated'] ?? json['updatedAt'])! as num).toInt(),
      fractionalIndex: (json['index'] ?? json['fractionalIndex']) as String?,
      isDeleted: json['isDeleted']! as bool,
      elementJson: Map<String, Object?>.from(json),
    );
  }

  static String _typeToJson(WhiteboardElementType type) {
    return switch (type) {
      WhiteboardElementType.freedraw => 'freedraw',
      WhiteboardElementType.magicFrame => 'magicframe',
      _ => type.name,
    };
  }
}
