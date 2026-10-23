import 'package:flow_muse/features/whiteboard/collaboration/collaboration_config.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/view_models/whiteboard_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final sameNote in [false, true]) {
    test('被移出后${sameNote ? '重开原笔记' : '打开其他笔记'}恢复空闲状态并保留分享配置', () async {
      final repository = CollaborationRepository();
      final container = ProviderContainer(
        overrides: [
          collaborationRepositoryProvider.overrideWithValue(repository),
          collaborationConfigProvider.overrideWithValue(
            const CollaborationConfig(
              serverUrl: 'https://api.example.invalid',
              shareOrigin: 'https://app.example.invalid',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repository.stop);
      final notifier = container.read(whiteboardViewModelProvider.notifier);
      await notifier.openNote(noteId: 'note-a');
      notifier.applyRoomRemoved();
      await repository.stop();
      await notifier.openNote(noteId: sameNote ? 'note-a' : 'note-b');

      final state = container.read(whiteboardViewModelProvider);
      expect(state.noteId, sameNote ? 'note-a' : 'note-b');
      expect(state.collaborationStatus, WhiteboardCollaborationStatus.idle);
      expect(state.exitReason, WhiteboardCollaborationExitReason.none);
      expect(state.activeRoom, isNull);
      expect(state.collaborating, isFalse);
      expect(state.collaborators, isEmpty);
      expect(state.shareOrigin, 'https://app.example.invalid');
      expect(state.shareOriginConfigured, isTrue);
      expect(state.saveStatus, WhiteboardSaveStatus.saved);
    });
  }

  test('房主结束与协作失败的信息不会残留到新笔记', () async {
    final repository = CollaborationRepository();
    final container = ProviderContainer(
      overrides: [
        collaborationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(repository.stop);
    final notifier = container.read(whiteboardViewModelProvider.notifier);
    notifier.applyRoomEnded(
      CollaborationRoomMetadata(
        roomId: 'synthetic-room',
        role: CollaborationRoomRole.editor,
        ended: true,
      ),
    );
    notifier.applyCollaborationError('synthetic failure');
    await notifier.openNote(noteId: 'note-b');
    final state = container.read(whiteboardViewModelProvider);
    expect(state.collaborationStatus, WhiteboardCollaborationStatus.idle);
    expect(state.exitReason, WhiteboardCollaborationExitReason.none);
    expect(state.roomMetadata, isNull);
    expect(state.collaborationError, isNull);
  });
}
