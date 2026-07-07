import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../collaboration/models/collaboration_message.dart';
import '../collaboration/models/collaboration_room.dart';
import '../collaboration/models/collaborator_presence.dart';
import '../collaboration/collaboration_config.dart';
import '../collaboration/repositories/collaboration_repository.dart';
import '../collaboration/services/collaboration_crypto.dart';
import '../collaboration/services/encrypted_scene_store.dart';
import '../collaboration/services/realtime_transport.dart';
import '../collaboration/services/scene_reconciler.dart';
import '../collaboration/services/socket_io_realtime_transport.dart';
import '../repositories/whiteboard_scene_repository.dart';

enum WhiteboardSaveStatus { idle, saving, saved }

class WhiteboardState {
  const WhiteboardState({
    this.notebookId = '',
    this.title = '未命名白板',
    this.saveStatus = WhiteboardSaveStatus.idle,
    this.activeRoom,
    this.collaborating = false,
    this.collaborators = const {},
  });

  final String notebookId;
  final String title;
  final WhiteboardSaveStatus saveStatus;
  final CollaborationRoom? activeRoom;
  final bool collaborating;
  final Map<String, CollaboratorPresence> collaborators;

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
    Map<String, CollaboratorPresence>? collaborators,
    bool clearRoom = false,
  }) {
    return WhiteboardState(
      notebookId: notebookId ?? this.notebookId,
      title: title ?? this.title,
      saveStatus: saveStatus ?? this.saveStatus,
      activeRoom: clearRoom ? null : activeRoom ?? this.activeRoom,
      collaborating: collaborating ?? this.collaborating,
      collaborators: clearRoom ? const {} : collaborators ?? this.collaborators,
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

  Future<void> startCollaboration({
    required List<Map<String, Object?>> initialElements,
  }) async {
    final room = await _repository.startNewRoom(
      initialElements: initialElements,
    );
    state = state.copyWith(activeRoom: room, collaborating: true);
  }

  Future<void> stopCollaboration() async {
    await _repository.stop();
    state = state.copyWith(collaborating: false, clearRoom: true);
  }

  void applyPresenceMessage(CollaborationMessage message) {
    final socketId = message.payload['socketId'];
    if (socketId is! String || socketId == _repository.socketId) {
      return;
    }
    final collaborators = Map<String, CollaboratorPresence>.from(
      state.collaborators,
    );
    final current =
        collaborators[socketId] ?? CollaboratorPresence(socketId: socketId);

    switch (message.type) {
      case CollaborationMessageType.mouseLocation:
        final pointer = message.payload['pointer'];
        final selectedElementIds = message.payload['selectedElementIds'];
        collaborators[socketId] = current.copyWith(
          username: message.payload['username'] as String?,
          pointer: pointer is Map ? Map<String, Object?>.from(pointer) : null,
          button: message.payload['button'] as String?,
          selectedElementIds: selectedElementIds is Map
              ? Map<String, bool>.from(selectedElementIds)
              : null,
          idleState: CollaboratorIdleState.active,
        );
      case CollaborationMessageType.idleStatus:
        collaborators[socketId] = current.copyWith(
          username: message.payload['username'] as String?,
          idleState: _idleStateFromWire(message.payload['userState']),
        );
      case CollaborationMessageType.userVisibleSceneBounds:
      case CollaborationMessageType.sceneInit:
      case CollaborationMessageType.sceneUpdate:
      case CollaborationMessageType.invalidResponse:
        return;
    }

    state = state.copyWith(collaborators: collaborators);
  }

  CollaboratorIdleState _idleStateFromWire(Object? value) {
    return switch (value) {
      'idle' => CollaboratorIdleState.idle,
      'away' => CollaboratorIdleState.away,
      _ => CollaboratorIdleState.active,
    };
  }
}

final collaborationRepositoryProvider = Provider<CollaborationRepository>((
  ref,
) {
  final config = ref.watch(collaborationConfigProvider);
  final crypto = CollaborationCrypto();
  final reconciler = SceneReconciler();
  return CollaborationRepository(
    transport: SocketIoRealtimeTransport(serverUrl: config.serverUrl),
    sceneStore: HttpEncryptedSceneStore(
      serverUrl: config.serverUrl,
      crypto: crypto,
      reconciler: reconciler,
    ),
    crypto: crypto,
    reconciler: reconciler,
  );
});

final memoryRealtimeRoomHubProvider = Provider<MemoryRealtimeRoomHub>((ref) {
  return MemoryRealtimeRoomHub();
});

final collaborationConfigProvider = Provider<CollaborationConfig>((ref) {
  return CollaborationConfig.fromEnvironment;
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
