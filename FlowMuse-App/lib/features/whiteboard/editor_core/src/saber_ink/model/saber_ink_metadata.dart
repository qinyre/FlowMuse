import '../../core/elements/element_id.dart';

/// Collaboration and product metadata attached to a Saber ink stroke.
class SaberInkMetadata {
  const SaberInkMetadata({
    required this.id,
    this.version = 1,
    this.versionNonce = 0,
    this.updated,
    this.index,
    this.isDeleted = false,
    this.customData,
  });

  final String id;
  final int version;
  final int versionNonce;
  final int? updated;
  final String? index;
  final bool isDeleted;
  final Map<String, Object?>? customData;

  factory SaberInkMetadata.create({
    String? id,
    String? index,
    Map<String, Object?>? customData,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return SaberInkMetadata(
      id: id ?? ElementId.generate().value,
      versionNonce: ElementId.generate().value.hashCode,
      updated: now,
      index: index,
      customData: customData,
    );
  }

  SaberInkMetadata copyWith({
    String? id,
    int? version,
    int? versionNonce,
    int? updated,
    bool clearUpdated = false,
    String? index,
    bool clearIndex = false,
    bool? isDeleted,
    Map<String, Object?>? customData,
    bool clearCustomData = false,
  }) {
    return SaberInkMetadata(
      id: id ?? this.id,
      version: version ?? this.version,
      versionNonce: versionNonce ?? this.versionNonce,
      updated: clearUpdated ? null : (updated ?? this.updated),
      index: clearIndex ? null : (index ?? this.index),
      isDeleted: isDeleted ?? this.isDeleted,
      customData: clearCustomData ? null : (customData ?? this.customData),
    );
  }

  SaberInkMetadata bumpVersion() {
    return copyWith(
      version: version + 1,
      versionNonce: ElementId.generate().value.hashCode,
      updated: DateTime.now().millisecondsSinceEpoch,
    );
  }

  SaberInkMetadata softDelete() {
    return copyWith(isDeleted: true).bumpVersion();
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'version': version,
      'versionNonce': versionNonce,
      if (updated != null) 'updated': updated,
      if (index != null) 'index': index,
      'isDeleted': isDeleted,
      if (customData != null) 'customData': customData,
    };
  }

  factory SaberInkMetadata.fromJson(Map<String, Object?> json) {
    final customData = json['customData'];
    return SaberInkMetadata(
      id: json['id'] as String,
      version: (json['version'] as num?)?.toInt() ?? 1,
      versionNonce: (json['versionNonce'] as num?)?.toInt() ?? 0,
      updated: (json['updated'] as num?)?.toInt(),
      index: json['index'] as String?,
      isDeleted: json['isDeleted'] as bool? ?? false,
      customData: customData is Map<String, Object?>
          ? customData
          : customData is Map
          ? {
              for (final entry in customData.entries)
                if (entry.key is String) entry.key as String: entry.value,
            }
          : null,
    );
  }
}
