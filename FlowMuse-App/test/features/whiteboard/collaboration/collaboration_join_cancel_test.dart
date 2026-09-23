import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';

class DelayedScene extends MemoryEncryptedSceneStore {
  final ready = Completer<ExcalidrawScene?>();
  var joins = 0;
  @override
  Future<ExcalidrawScene?> loadScene(CollaborationRoom room) => ready.future;
  @override
  Future<CollaborationRoomMetadata> joinRoom(CollaborationRoom room) {
    joins++;
    return super.joinRoom(room);
  }
}

void main() {
  test('加载房间期间退出或切换账号，不再领取成员资格或连接旧房间', () async {
    for (final stop in [true, false]) {
      final store = DelayedScene();
      final repo = CollaborationRepository(sceneStore: store);
      var current = true;
      final future = repo.joinRoom(
        room: CollaborationRoom.newRoom(),
        localScene: ExcalidrawScene.empty(),
        isCurrent: () => current,
      );
      if (stop) {
        await repo.stop();
      } else {
        current = false;
      }
      store.ready.complete(ExcalidrawScene.empty());
      await expectLater(future, throwsStateError);
      expect(store.joins, 0);
      await repo.stop();
    }
  });
}
