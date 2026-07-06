import '../models/collaborative_element.dart';
import '../models/collaboration_room.dart';

abstract interface class EncryptedSceneStore {
  Future<List<CollaborativeElement>?> loadScene(CollaborationRoom room);

  Future<void> saveScene({
    required CollaborationRoom room,
    required List<CollaborativeElement> elements,
  });
}

class MemoryEncryptedSceneStore implements EncryptedSceneStore {
  final Map<String, List<CollaborativeElement>> _scenes = {};

  @override
  Future<List<CollaborativeElement>?> loadScene(CollaborationRoom room) async {
    final elements = _scenes[room.roomId];
    return elements == null ? null : List.unmodifiable(elements);
  }

  @override
  Future<void> saveScene({
    required CollaborationRoom room,
    required List<CollaborativeElement> elements,
  }) async {
    _scenes[room.roomId] = List.unmodifiable(elements);
  }
}
