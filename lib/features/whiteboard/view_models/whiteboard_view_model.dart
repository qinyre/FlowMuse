import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../collaboration/models/collaboration_room.dart';
import '../collaboration/repositories/collaboration_repository.dart';
import '../repositories/whiteboard_scene_repository.dart';

enum WhiteboardSaveStatus { idle, saving, saved }

class WhiteboardState {
  const WhiteboardState({
    this.notebookId = '',
    this.title = '未命名白板',
    this.saveStatus = WhiteboardSaveStatus.idle,
    this.activeRoom,
    this.collaborating = false,
  });

  final String notebookId;
  final String title;
  final WhiteboardSaveStatus saveStatus;
  final CollaborationRoom? activeRoom;
  final bool collaborating;

  String? get roomLink {
    final room = activeRoom;
    if (room == null) {
      return null;
    }
    return room.toLink(origin: 'https://flowmuse.local', path: '/whiteboard');
  }

  WhiteboardState copyWith({
    String? notebookId,
    String? title,
    WhiteboardSaveStatus? saveStatus,
    CollaborationRoom? activeRoom,
    bool? collaborating,
    bool clearRoom = false,
  }) {
    return WhiteboardState(
      notebookId: notebookId ?? this.notebookId,
      title: title ?? this.title,
      saveStatus: saveStatus ?? this.saveStatus,
      activeRoom: clearRoom ? null : activeRoom ?? this.activeRoom,
      collaborating: collaborating ?? this.collaborating,
    );
  }
}

class WhiteboardViewModel extends Notifier<WhiteboardState> {
  late final CollaborationRepository _repository;

  @override
  WhiteboardState build() {
    _repository = ref.watch(collaborationRepositoryProvider);
    return const WhiteboardState();
  }

  Future<void> openNotebook({
    required String notebookId,
    required String title,
  }) async {
    state = state.copyWith(
      notebookId: notebookId,
      title: title,
      saveStatus: WhiteboardSaveStatus.saved,
    );
  }

  void markSaving() {
    if (state.saveStatus == WhiteboardSaveStatus.saving) {
      return;
    }
    state = state.copyWith(saveStatus: WhiteboardSaveStatus.saving);
  }

  void markSaved() {
    if (state.saveStatus == WhiteboardSaveStatus.saved) {
      return;
    }
    state = state.copyWith(saveStatus: WhiteboardSaveStatus.saved);
  }

  Future<void> startCollaboration() async {
    final room = await _repository.startNewRoom(initialElements: const []);
    state = state.copyWith(activeRoom: room, collaborating: true);
  }

  Future<void> stopCollaboration() async {
    await _repository.stop();
    state = state.copyWith(collaborating: false, clearRoom: true);
  }
}

final collaborationRepositoryProvider = Provider<CollaborationRepository>((
  ref,
) {
  return CollaborationRepository();
});

final whiteboardSceneRepositoryProvider = Provider<WhiteboardSceneRepository>((
  ref,
) {
  return SharedPreferencesWhiteboardSceneRepository(
    SharedPreferences.getInstance,
  );
});

final whiteboardViewModelProvider =
    NotifierProvider<WhiteboardViewModel, WhiteboardState>(
      WhiteboardViewModel.new,
    );
