import 'dart:convert';

import 'collaborative_element.dart';

enum CollaborationMessageType {
  sceneInit,
  sceneUpdate,
  cursorUpdate,
  presenceUpdate,
  viewportUpdate,
  fileStatusUpdate,
}

class CollaborationMessage {
  const CollaborationMessage({required this.type, required this.payload});

  final CollaborationMessageType type;
  final Map<String, Object?> payload;

  List<int> toBytes() => utf8.encode(jsonEncode(toJson()));

  Map<String, Object?> toJson() {
    return {'type': type.name, 'payload': payload};
  }

  factory CollaborationMessage.sceneUpdate({
    required List<CollaborativeElement> elements,
  }) {
    return CollaborationMessage(
      type: CollaborationMessageType.sceneUpdate,
      payload: {
        'elements': [for (final element in elements) element.toJson()],
      },
    );
  }

  factory CollaborationMessage.fromBytes(List<int> bytes) {
    return CollaborationMessage.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, Object?>,
    );
  }

  factory CollaborationMessage.fromJson(Map<String, Object?> json) {
    return CollaborationMessage(
      type: CollaborationMessageType.values.byName(json['type']! as String),
      payload: Map<String, Object?>.from(json['payload']! as Map),
    );
  }

  List<CollaborativeElement> get elements {
    final rawElements = payload['elements'];
    if (rawElements is! List) {
      return const [];
    }
    return [
      for (final element in rawElements)
        CollaborativeElement.fromJson(
          Map<String, Object?>.from(element as Map),
        ),
    ];
  }
}
