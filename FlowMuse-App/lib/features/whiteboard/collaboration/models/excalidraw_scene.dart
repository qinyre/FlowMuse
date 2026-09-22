import 'dart:convert';

import 'package:crypto/crypto.dart';

const emptyExcalidrawSceneContent =
    '{"type":"excalidraw","version":2,"source":"https://excalidraw.com","elements":[],"appState":{},"files":{}}';

class ExcalidrawScene {
  ExcalidrawScene({
    required List<Map<String, Object?>> elements,
    required Map<String, Object?> appState,
    required Map<String, Object?> files,
    this.type = 'excalidraw',
    this.version = 2,
    this.source = 'https://excalidraw.com',
  }) : elements = List.unmodifiable(elements.map(_deepMap)),
       appState = _deepMap(appState),
       files = _deepMap(files);

  const ExcalidrawScene._({
    required this.elements,
    required this.appState,
    required this.files,
    this.type = 'excalidraw',
    this.version = 2,
    this.source = 'https://excalidraw.com',
  });

  factory ExcalidrawScene.empty() {
    return const ExcalidrawScene._(elements: [], appState: {}, files: {});
  }

  factory ExcalidrawScene.fromContent(String content) {
    return ExcalidrawScene.fromCollaborationPayload(jsonDecode(content));
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

  factory ExcalidrawScene.fromCollaborationPayload(Object? payload) {
    if (payload is List) {
      return ExcalidrawScene(
        elements: [
          for (final element in payload)
            Map<String, Object?>.from(element as Map),
        ],
        appState: const {},
        files: const {},
      );
    }
    if (payload is Map) {
      return ExcalidrawScene.fromJson(Map<String, Object?>.from(payload));
    }
    throw const FormatException('Invalid Excalidraw collaboration payload');
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
    // Only this scene's deeply immutable elements are safe to share. New
    // inputs are copied and frozen, including unknown nested extension keys.
    final reusable = elements == null
        ? null
        : (Set<Map<String, Object?>>.identity()..addAll(this.elements));
    return ExcalidrawScene._(
      type: type,
      version: version,
      source: source,
      elements: elements == null
          ? this.elements
          : List.unmodifiable([
              for (final element in elements)
                reusable!.contains(element) ? element : _deepMap(element),
            ]),
      appState: appState == null ? this.appState : _deepMap(appState),
      files: files == null ? this.files : _deepMap(files),
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

  Map<String, Object?> toCollaborationPayload() {
    return toJson();
  }

  String toCollaborationContent() => jsonEncode(toCollaborationPayload());

  String collaborationHash() {
    return sha256.convert(utf8.encode(toCollaborationContent())).toString();
  }
}

Map<String, Object?> _deepMap(Map source) {
  return Map<String, Object?>.unmodifiable({
    for (final entry in source.entries)
      entry.key as String: _deepValue(entry.value),
  });
}

Object? _deepValue(Object? value) {
  if (value is Map) {
    return _deepMap(value);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepValue));
  }
  return value;
}
