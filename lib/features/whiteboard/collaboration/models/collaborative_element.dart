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
    required this.data,
  });

  final String id;
  final WhiteboardElementType type;
  final int version;
  final int versionNonce;
  final int updatedAt;
  final String? fractionalIndex;
  final bool isDeleted;
  final Map<String, Object?> data;

  CollaborativeElement copyWith({
    int? version,
    int? versionNonce,
    int? updatedAt,
    String? fractionalIndex,
    bool? isDeleted,
    Map<String, Object?>? data,
  }) {
    return CollaborativeElement(
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
      'updated': updatedAt,
      'index': fractionalIndex,
      'isDeleted': isDeleted,
      'data': data,
    };
  }

  factory CollaborativeElement.fromJson(Map<String, Object?> json) {
    return CollaborativeElement(
      id: json['id']! as String,
      type: WhiteboardElementType.values.byName(json['type']! as String),
      version: (json['version']! as num).toInt(),
      versionNonce: (json['versionNonce']! as num).toInt(),
      updatedAt: ((json['updated'] ?? json['updatedAt'])! as num).toInt(),
      fractionalIndex: (json['index'] ?? json['fractionalIndex']) as String?,
      isDeleted: json['isDeleted']! as bool,
      data: Map<String, Object?>.from(json['data']! as Map),
    );
  }
}
