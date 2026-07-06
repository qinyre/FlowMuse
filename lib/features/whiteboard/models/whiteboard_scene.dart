import 'whiteboard_element.dart';

class WhiteboardScene {
  const WhiteboardScene({
    this.elements = const [],
    this.zoom = 1,
    this.panX = 0,
    this.panY = 0,
  });

  final List<WhiteboardElement> elements;
  final double zoom;
  final double panX;
  final double panY;

  WhiteboardScene copyWith({
    List<WhiteboardElement>? elements,
    double? zoom,
    double? panX,
    double? panY,
  }) {
    return WhiteboardScene(
      elements: elements ?? this.elements,
      zoom: zoom ?? this.zoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'elements': [for (final element in elements) element.toJson()],
      'appState': {'zoom': zoom, 'panX': panX, 'panY': panY},
    };
  }

  factory WhiteboardScene.fromJson(Map<String, Object?> json) {
    final appState = Map<String, Object?>.from(
      json['appState'] as Map? ?? const {},
    );
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
      zoom: (appState['zoom'] as num?)?.toDouble() ?? 1,
      panX: (appState['panX'] as num?)?.toDouble() ?? 0,
      panY: (appState['panY'] as num?)?.toDouble() ?? 0,
    );
  }
}
