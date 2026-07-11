import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/view_models/account_view_model.dart';
import '../collaboration/models/collaboration_message.dart';
import '../collaboration/models/collaboration_room.dart';
import '../collaboration/models/collaborator_presence.dart';
import '../collaboration/models/excalidraw_scene.dart';
import '../collaboration/models/room_collaborator.dart';
import '../collaboration/collaboration_config.dart';
import '../collaboration/repositories/collaboration_repository.dart';
import '../collaboration/services/collaboration_crypto.dart';
import '../collaboration/services/collaboration_file_store.dart';
import '../collaboration/services/encrypted_scene_store.dart';
import '../collaboration/services/realtime_transport.dart';
import '../collaboration/services/scene_reconciler.dart';
import '../collaboration/services/socket_io_realtime_transport.dart';
import '../repositories/whiteboard_scene_repository.dart';

enum WhiteboardSaveStatus { idle, saving, saved }

enum WhiteboardCollaborationStatus {
  idle,
  connecting,
  initializing,
  connected,
  reconnecting,
  restoringSnapshot,
  disconnected,
  failed,
}

enum WhiteboardCollaborationExitReason { none, leftBySelf, endedByHost }

class WhiteboardState {
  const WhiteboardState({
    this.noteId = '',
    this.saveStatus = WhiteboardSaveStatus.idle,
    this.activeRoom,
    this.collaborating = false,
    this.collaborators = const {},
    this.collaborationStatus = WhiteboardCollaborationStatus.idle,
    this.collaborationError,
    this.roomMetadata,
    this.exitReason = WhiteboardCollaborationExitReason.none,
    this.shareOrigin = 'https://flowmuse.local',
    this.shareOriginConfigured = false,
  });

  final String noteId;
  final WhiteboardSaveStatus saveStatus;
  final CollaborationRoom? activeRoom;
  final bool collaborating;
  final Map<String, CollaboratorPresence> collaborators;
  final WhiteboardCollaborationStatus collaborationStatus;
  final String? collaborationError;
  final CollaborationRoomMetadata? roomMetadata;
  final WhiteboardCollaborationExitReason exitReason;
  final String shareOrigin;
  final bool shareOriginConfigured;

  bool get isRoomOwner => roomMetadata?.isOwner ?? false;

  bool get roomEnded => roomMetadata?.ended ?? false;

  String? get roomLink {
    final room = activeRoom;
    if (room == null || !shareOriginConfigured) {
      return null;
    }
    return room.toLink(origin: shareOrigin, path: '/whiteboard/collaboration');
  }

  String? get roomValue => activeRoom?.toRoomValue();

  WhiteboardState copyWith({
    String? noteId,
    WhiteboardSaveStatus? saveStatus,
    CollaborationRoom? activeRoom,
    bool? collaborating,
    Map<String, CollaboratorPresence>? collaborators,
    WhiteboardCollaborationStatus? collaborationStatus,
    String? collaborationError,
    CollaborationRoomMetadata? roomMetadata,
    WhiteboardCollaborationExitReason? exitReason,
    String? shareOrigin,
    bool? shareOriginConfigured,
    bool clearRoom = false,
    bool clearError = false,
    bool clearMetadata = false,
  }) {
    return WhiteboardState(
      noteId: noteId ?? this.noteId,
      saveStatus: saveStatus ?? this.saveStatus,
      activeRoom: clearRoom ? null : activeRoom ?? this.activeRoom,
      collaborating: collaborating ?? this.collaborating,
      collaborators: clearRoom ? const {} : collaborators ?? this.collaborators,
      collaborationStatus: collaborationStatus ?? this.collaborationStatus,
      collaborationError: clearError
          ? null
          : collaborationError ?? this.collaborationError,
      roomMetadata: clearMetadata ? null : roomMetadata ?? this.roomMetadata,
      exitReason: exitReason ?? this.exitReason,
      shareOrigin: shareOrigin ?? this.shareOrigin,
      shareOriginConfigured:
          shareOriginConfigured ?? this.shareOriginConfigured,
    );
  }
}

class WhiteboardViewModel extends Notifier<WhiteboardState> {
  late CollaborationRepository _repository;

  @override
  WhiteboardState build() {
    _repository = ref.watch(collaborationRepositoryProvider);
    final config = ref.watch(collaborationConfigProvider);
    return WhiteboardState(
      shareOrigin: config.shareOrigin,
      shareOriginConfigured: config.hasConfiguredShareOrigin,
    );
  }

  Future<void> openNote({required String noteId}) async {
    state = state.copyWith(
      noteId: noteId,
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
    required ExcalidrawScene initialScene,
  }) async {
    state = state.copyWith(
      collaborationStatus: WhiteboardCollaborationStatus.connecting,
      clearError: true,
    );
    try {
      final room = await _repository.startNewRoom(initialScene: initialScene);
      state = state.copyWith(
        activeRoom: room,
        roomMetadata: CollaborationRoomMetadata.localOwner(room.roomId),
        exitReason: WhiteboardCollaborationExitReason.none,
        collaborating: true,
        collaborationStatus: WhiteboardCollaborationStatus.connected,
      );
    } catch (error) {
      state = state.copyWith(
        collaborating: false,
        collaborationStatus: WhiteboardCollaborationStatus.failed,
        collaborationError: error.toString(),
      );
      rethrow;
    }
  }

  Future<ExcalidrawScene> joinCollaboration({
    required CollaborationRoom room,
    required ExcalidrawScene localScene,
  }) async {
    state = state.copyWith(
      collaborationStatus: WhiteboardCollaborationStatus.connecting,
      clearError: true,
    );
    try {
      final result = await _repository.joinRoom(
        room: room,
        localScene: localScene,
      );
      state = state.copyWith(
        activeRoom: room,
        roomMetadata: result.metadata,
        exitReason: WhiteboardCollaborationExitReason.none,
        collaborating: true,
        collaborationStatus: WhiteboardCollaborationStatus.initializing,
      );
      return result.scene;
    } catch (error) {
      state = state.copyWith(
        collaborating: false,
        collaborationStatus: WhiteboardCollaborationStatus.failed,
        collaborationError: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> stopCollaboration() async {
    await _repository.stop();
    state = state.copyWith(
      collaborating: false,
      clearRoom: true,
      clearError: true,
      clearMetadata: true,
      exitReason: WhiteboardCollaborationExitReason.leftBySelf,
      collaborationStatus: WhiteboardCollaborationStatus.idle,
    );
  }

  Future<void> endCollaboration() async {
    final metadata = await _repository.endRoom();
    state = state.copyWith(
      collaborating: false,
      clearRoom: true,
      clearError: true,
      roomMetadata: metadata,
      exitReason: WhiteboardCollaborationExitReason.endedByHost,
      collaborationStatus: WhiteboardCollaborationStatus.idle,
    );
  }

  void applyRoomEnded(CollaborationRoomMetadata metadata) {
    state = state.copyWith(
      collaborating: false,
      clearRoom: true,
      clearError: true,
      roomMetadata: metadata,
      exitReason: WhiteboardCollaborationExitReason.endedByHost,
      collaborationStatus: WhiteboardCollaborationStatus.disconnected,
    );
  }

  void applyCollaborationError(String message) {
    state = state.copyWith(
      collaborationStatus: WhiteboardCollaborationStatus.failed,
      collaborationError: message,
    );
  }

  void applyCollaborationInitialized() {
    state = state.copyWith(
      collaborationStatus: WhiteboardCollaborationStatus.connected,
      clearError: true,
    );
  }

  void applySnapshotRestoreStarted() {
    state = state.copyWith(
      collaborationStatus: WhiteboardCollaborationStatus.restoringSnapshot,
      clearError: true,
    );
  }

  void applyConnectionStatus(RealtimeConnectionStatus status) {
    final nextStatus = switch (status) {
      RealtimeConnectionStatus.idle => WhiteboardCollaborationStatus.idle,
      RealtimeConnectionStatus.connecting =>
        WhiteboardCollaborationStatus.connecting,
      RealtimeConnectionStatus.joined =>
        state.collaborationStatus == WhiteboardCollaborationStatus.initializing
            ? WhiteboardCollaborationStatus.initializing
            : WhiteboardCollaborationStatus.connected,
      RealtimeConnectionStatus.reconnecting =>
        WhiteboardCollaborationStatus.reconnecting,
      RealtimeConnectionStatus.disconnected =>
        WhiteboardCollaborationStatus.disconnected,
      RealtimeConnectionStatus.failed => WhiteboardCollaborationStatus.failed,
    };
    state = state.copyWith(
      collaborationStatus: nextStatus,
      clearError: nextStatus != WhiteboardCollaborationStatus.failed,
    );
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
          userId: message.payload['userId'] as String?,
          avatarUrl: message.payload['avatarUrl'] as String?,
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
          userId: message.payload['userId'] as String?,
          avatarUrl: message.payload['avatarUrl'] as String?,
          idleState: _idleStateFromWire(message.payload['userState']),
        );
      case CollaborationMessageType.userVisibleSceneBounds:
        final sceneBounds = message.payload['sceneBounds'];
        collaborators[socketId] = current.copyWith(
          username: message.payload['username'] as String?,
          userId: message.payload['userId'] as String?,
          avatarUrl: message.payload['avatarUrl'] as String?,
          sceneBounds: sceneBounds is Map
              ? Map<String, Object?>.from(sceneBounds)
              : null,
        );
      case CollaborationMessageType.sceneInit:
      case CollaborationMessageType.sceneUpdate:
      case CollaborationMessageType.invalidResponse:
        return;
    }

    state = state.copyWith(collaborators: collaborators);
  }

  void applyRoomUsers(List<RoomCollaborator> roomUsers) {
    final collaboratorsBySocketId = {
      for (final user in roomUsers) user.socketId: user,
    }..remove(_repository.socketId);
    final allowed = collaboratorsBySocketId.keys.toSet();
    final collaborators = {
      for (final entry in state.collaborators.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
    for (final entry in collaboratorsBySocketId.entries) {
      final user = entry.value;
      collaborators[entry.key] =
          collaborators[entry.key]?.copyWith(
            username: user.username,
            userId: user.userId,
            avatarUrl: user.avatarUrl,
            isGuest: user.isGuest,
          ) ??
          CollaboratorPresence(
            socketId: entry.key,
            username: user.username,
            userId: user.userId,
            avatarUrl: user.avatarUrl,
            isGuest: user.isGuest,
          );
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
  final identity = ref.watch(accountViewModelProvider).collaborationIdentity;
  final crypto = CollaborationCrypto();
  final reconciler = SceneReconciler();
  return CollaborationRepository(
    transport: SocketIoRealtimeTransport(
      serverUrl: config.serverUrl,
      identity: identity,
    ),
    sceneStore: HttpEncryptedSceneStore(
      serverUrl: config.serverUrl,
      crypto: crypto,
      authToken: identity.token,
      reconciler: reconciler,
    ),
    fileStore: HttpCollaborationFileStore(
      serverUrl: config.serverUrl,
      authToken: identity.token,
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
  return defaultWhiteboardSceneRepository;
});

final whiteboardViewModelProvider =
    NotifierProvider<WhiteboardViewModel, WhiteboardState>(
      WhiteboardViewModel.new,
    );
