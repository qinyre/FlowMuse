import '../models/collaboration_room.dart';

abstract interface class EncryptedSceneStore {
  Future<List<Map<String, Object?>>?> loadScene(CollaborationRoom room);

  Future<void> saveScene({
    required CollaborationRoom room,
    required List<Map<String, Object?>> elements,
  });
}

class MemoryEncryptedSceneStore implements EncryptedSceneStore {
  final Map<String, List<Map<String, Object?>>> _scenes = {};

  @override
  Future<List<Map<String, Object?>>?> loadScene(CollaborationRoom room) async {
    final elements = _scenes[room.roomId];
    return elements == null ? null : List.unmodifiable(elements);
  }

  @override
  Future<void> saveScene({
    required CollaborationRoom room,
    required List<Map<String, Object?>> elements,
  }) async {
    _scenes[room.roomId] = List.unmodifiable([
      for (final element in elements) Map<String, Object?>.from(element),
    ]);
  }
}
