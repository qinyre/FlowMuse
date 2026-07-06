import 'whiteboard_element.dart';

class WhiteboardScene {
  const WhiteboardScene({
    this.elements = const [],
    this.zoom = 1,
    this.panX = 0,
    this.panY = 0,
    this.source = 'flowmuse',
    this.appState = const {},
    this.files = const {},
  });

  final List<WhiteboardElement> elements;
  final double zoom;
  final double panX;
  final double panY;
  final String source;
  final Map<String, Object?> appState;
  final Map<String, Object?> files;

  WhiteboardScene copyWith({
    List<WhiteboardElement>? elements,
    double? zoom,
    double? panX,
    double? panY,
    String? source,
    Map<String, Object?>? appState,
    Map<String, Object?>? files,
  }) {
    return WhiteboardScene(
      elements: elements ?? this.elements,
      zoom: zoom ?? this.zoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      source: source ?? this.source,
      appState: appState ?? this.appState,
      files: files ?? this.files,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'type': 'excalidraw',
      'version': 2,
      'source': source,
      'elements': [for (final element in elements) element.toJson()],
      'appState': {
        ...appState,
        'scrollX': -panX,
        'scrollY': -panY,
        'zoom': {'value': zoom},
      },
      'files': files,
    };
  }

  factory WhiteboardScene.fromJson(Map<String, Object?> json) {
    final appState = Map<String, Object?>.from(
      json['appState'] as Map? ?? const {},
    );
    final rawZoom = appState['zoom'];
    final rawElements = json['elements'];
    return WhiteboardScene(
      elements: rawElements is List
          ? [
              for (final element in rawElements)
                WhiteboardElement.fromJson(
                  Map<String, Object?>.from(element as Map),
                ),
            ]
          : const [],
      zoom: rawZoom is Map
          ? (rawZoom['value'] as num?)?.toDouble() ?? 1
          : (rawZoom as num?)?.toDouble() ?? 1,
      panX:
          (appState['panX'] as num?)?.toDouble() ??
          -((appState['scrollX'] as num?)?.toDouble() ?? 0),
      panY:
          (appState['panY'] as num?)?.toDouble() ??
          -((appState['scrollY'] as num?)?.toDouble() ?? 0),
      source: json['source'] as String? ?? 'flowmuse',
      appState: appState,
      files: Map<String, Object?>.from(json['files'] as Map? ?? const {}),
    );
  }
}
