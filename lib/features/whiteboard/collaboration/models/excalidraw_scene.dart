import 'dart:convert';

const emptyExcalidrawSceneContent =
    '{"type":"excalidraw","version":2,"source":"https://excalidraw.com","elements":[],"appState":{},"files":{}}';

class ExcalidrawScene {
  const ExcalidrawScene({
    required this.elements,
    required this.appState,
    required this.files,
    this.type = 'excalidraw',
    this.version = 2,
    this.source = 'https://excalidraw.com',
  });

  factory ExcalidrawScene.empty() {
    return const ExcalidrawScene(
      elements: [],
      appState: {},
      files: {},
    );
  }

  factory ExcalidrawScene.fromContent(String content) {
    final decoded = jsonDecode(content) as Map<String, Object?>;
    return ExcalidrawScene.fromJson(decoded);
  }

  factory ExcalidrawScene.fromJson(Map<String, Object?> json) {
    final rawElements = json['elements'];
    final rawAppState = json['appState'];
    final rawFiles = json['files'];
    return ExcalidrawScene(
      type: json['type'] as String? ?? 'excalidraw',
      version: (json['version'] as num?)?.toInt() ?? 2,
      source: json['source'] as String? ?? 'https://excalidraw.com',
      elements: rawElements is List
          ? [
              for (final element in rawElements)
                Map<String, Object?>.from(element as Map),
            ]
          : const [],
      appState: rawAppState is Map
          ? Map<String, Object?>.from(rawAppState)
          : const {},
      files: rawFiles is Map ? Map<String, Object?>.from(rawFiles) : const {},
    );
  }

  final String type;
  final int version;
  final String source;
  final List<Map<String, Object?>> elements;
  final Map<String, Object?> appState;
  final Map<String, Object?> files;

  ExcalidrawScene copyWith({
    List<Map<String, Object?>>? elements,
    Map<String, Object?>? appState,
    Map<String, Object?>? files,
  }) {
    return ExcalidrawScene(
      type: type,
      version: version,
      source: source,
      elements: elements ?? this.elements,
      appState: appState ?? this.appState,
      files: files ?? this.files,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'type': type,
      'version': version,
      'source': source,
      'elements': elements,
      'appState': appState,
      'files': files,
    };
  }

  String toContent() => jsonEncode(toJson());
}
