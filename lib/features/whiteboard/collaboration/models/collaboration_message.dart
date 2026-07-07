import 'dart:convert';

enum CollaborationMessageType {
  sceneInit('SCENE_INIT'),
  sceneUpdate('SCENE_UPDATE'),
  mouseLocation('MOUSE_LOCATION'),
  idleStatus('IDLE_STATUS'),
  userVisibleSceneBounds('USER_VISIBLE_SCENE_BOUNDS'),
  invalidResponse('INVALID_RESPONSE');

  const CollaborationMessageType(this.wireName);

  final String wireName;

  static CollaborationMessageType fromWireName(String name) {
    return values.firstWhere(
      (type) => type.wireName == name,
      orElse: () => invalidResponse,
    );
  }
}

class CollaborationMessage {
  const CollaborationMessage({required this.type, required this.payload});

  final CollaborationMessageType type;
  final Map<String, Object?> payload;

  List<int> toBytes() => utf8.encode(jsonEncode(toJson()));

  Map<String, Object?> toJson() {
    return {'type': type.wireName, 'payload': payload};
  }

  factory CollaborationMessage.sceneInit({
    required List<Map<String, Object?>> elements,
  }) {
    return CollaborationMessage(
      type: CollaborationMessageType.sceneInit,
      payload: {'elements': elements},
    );
  }

  factory CollaborationMessage.sceneUpdate({
    required List<Map<String, Object?>> elements,
  }) {
    return CollaborationMessage(
      type: CollaborationMessageType.sceneUpdate,
      payload: {'elements': elements},
    );
  }

  factory CollaborationMessage.mouseLocation({
    required String socketId,
    required Map<String, Object?> pointer,
    required String button,
    required Map<String, bool> selectedElementIds,
    required String username,
  }) {
    return CollaborationMessage(
      type: CollaborationMessageType.mouseLocation,
      payload: {
        'socketId': socketId,
        'pointer': pointer,
        'button': button,
        'selectedElementIds': selectedElementIds,
        'username': username,
      },
    );
  }

  factory CollaborationMessage.idleStatus({
    required String socketId,
    required String userState,
    required String username,
  }) {
    return CollaborationMessage(
      type: CollaborationMessageType.idleStatus,
      payload: {
        'socketId': socketId,
        'userState': userState,
        'username': username,
      },
    );
  }

  factory CollaborationMessage.userVisibleSceneBounds({
    required String socketId,
    required String username,
    required Map<String, Object?> sceneBounds,
  }) {
    return CollaborationMessage(
      type: CollaborationMessageType.userVisibleSceneBounds,
      payload: {
        'socketId': socketId,
        'username': username,
        'sceneBounds': sceneBounds,
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
      type: CollaborationMessageType.fromWireName(json['type']! as String),
      payload: Map<String, Object?>.from(json['payload']! as Map),
    );
  }

  List<Map<String, Object?>> get elements {
    final rawElements = payload['elements'];
    if (rawElements is! List) {
      return const [];
    }
    return [
      for (final element in rawElements)
        Map<String, Object?>.from(element as Map),
    ];
  }
}
