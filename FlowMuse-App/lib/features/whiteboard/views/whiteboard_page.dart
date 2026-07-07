import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide Element, SelectionOverlay, TextAlign;

import '../../library/repositories/library_repository.dart';
import '../collaboration/models/collaboration_message.dart';
import '../collaboration/models/collaboration_room.dart';
import '../collaboration/models/collaborator_presence.dart';
import '../collaboration/models/excalidraw_scene.dart';
import '../collaboration/repositories/collaboration_repository.dart';
import '../collaboration/services/realtime_transport.dart';
import '../collaboration/services/whiteboard_collaboration_adapter.dart';
import '../view_models/whiteboard_view_model.dart';

class WhiteboardPage extends ConsumerStatefulWidget {
  const WhiteboardPage({super.key, required this.noteId})
    : temporaryCollaboration = false,
      initialRoom = null;

  const WhiteboardPage.collaboration({super.key})
    : noteId = 'collaboration-room',
      temporaryCollaboration = true,
      initialRoom = null;

  const WhiteboardPage.collaborationRoom({
    super.key,
    required CollaborationRoom this.initialRoom,
  }) : noteId = 'collaboration-room',
       temporaryCollaboration = true;

  final String noteId;
  final bool temporaryCollaboration;
  final CollaborationRoom? initialRoom;

  @override
  ConsumerState<WhiteboardPage> createState() => _WhiteboardPageState();
}

class _WhiteboardPageState extends ConsumerState<WhiteboardPage> {
  late final MarkdrawController _markdrawController;
  late final WhiteboardCollaborationAdapter _collaborationAdapter;
  late final CollaborationRepository _collaborationRepository;
  StreamSubscription<CollaborationMessage>? _collaborationSubscription;
  StreamSubscription<String>? _newUserSubscription;
  StreamSubscription<List<String>>? _roomUsersSubscription;
  StreamSubscription<String>? _roomErrorSubscription;
  StreamSubscription<RealtimeConnectionStatus>? _connectionStatusSubscription;
  Timer? _idleTimer;
  Timer? _awayTimer;
  bool _loadingScene = false;
  bool _applyingRemoteScene = false;
  bool _collaborationOpening = false;
  String? _lastIdleState;
  bool _temporarySaved = false;
  int _openGeneration = 0;
  RealtimeConnectionStatus? _lastRealtimeStatus;

  @override
  void initState() {
    super.initState();
    _markdrawController = MarkdrawController();
    _collaborationAdapter = WhiteboardCollaborationAdapter(_markdrawController);
    _collaborationRepository = ref.read(collaborationRepositoryProvider);
    Future.microtask(_openNote);
  }

  @override
  void didUpdateWidget(covariant WhiteboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      Future.microtask(_openNote);
    }
  }

  @override
  void dispose() {
    unawaited(_collaborationSubscription?.cancel());
    unawaited(_newUserSubscription?.cancel());
    unawaited(_roomUsersSubscription?.cancel());
    unawaited(_roomErrorSubscription?.cancel());
    unawaited(_connectionStatusSubscription?.cancel());
    _idleTimer?.cancel();
    _awayTimer?.cancel();
    unawaited(_collaborationRepository.stop());
    _markdrawController.dispose();
    super.dispose();
  }

  Future<void> _openNote() async {
    final generation = ++_openGeneration;
    if (widget.temporaryCollaboration) {
      _loadingScene = true;
      _markdrawController.loadFromContent(
        emptyExcalidrawSceneContent,
        'collaboration.excalidraw',
      );
      _loadingScene = false;
      final room = widget.initialRoom;
      if (room != null) {
        unawaited(_joinCollaboration(room));
      }
      return;
    }
    final noteId = widget.noteId;
    await ref.read(libraryIndexProvider.notifier).ensureNote(noteId);
    if (!mounted || generation != _openGeneration || noteId != widget.noteId) {
      return;
    }
    await ref
        .read(whiteboardViewModelProvider.notifier)
        .openNote(noteId: noteId);
    if (!mounted || generation != _openGeneration || noteId != widget.noteId) {
      return;
    }
    final repository = ref.read(whiteboardSceneRepositoryProvider);
    final content = await repository.loadScene(noteId);
    if (!mounted || generation != _openGeneration || noteId != widget.noteId) {
      return;
    }
    _loadingScene = true;
    _markdrawController.loadFromContent(content, '$noteId.excalidraw');
    _loadingScene = false;
    final room = widget.initialRoom;
    if (room != null) {
      unawaited(_joinCollaboration(room));
    }
  }

  Future<void> _saveMarkdrawScene() async {
    if (_loadingScene || _applyingRemoteScene) {
      return;
    }
    if (widget.temporaryCollaboration) {
      await _broadcastCurrentScene();
      if (mounted) {
        ref.read(whiteboardViewModelProvider.notifier).markSaved();
      }
      return;
    }
    final viewModel = ref.read(whiteboardViewModelProvider.notifier);
    viewModel.markSaving();
    final repository = ref.read(whiteboardSceneRepositoryProvider);
    final content = _markdrawController.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    await repository.saveScene(widget.noteId, content);
    await ref.read(libraryIndexProvider.notifier).touchNote(widget.noteId);
    await _broadcastCurrentScene(serializedScene: content);
    if (!mounted) {
      return;
    }
    viewModel.markSaved();
  }

  Future<void> _renameAndSaveDocument() async {
    if (widget.temporaryCollaboration) {
      await _broadcastCurrentScene();
      return;
    }
    final title = _markdrawController.documentName?.trim();
    if (title != null && title.isNotEmpty) {
      await ref
          .read(libraryIndexProvider.notifier)
          .renameNote(widget.noteId, title);
    }
    await _saveMarkdrawScene();
  }

  Future<void> _startCollaboration() async {
    final currentStatus = ref
        .read(whiteboardViewModelProvider)
        .collaborationStatus;
    if (currentStatus == WhiteboardCollaborationStatus.connecting) {
      return;
    }
    await ref
        .read(whiteboardViewModelProvider.notifier)
        .startCollaboration(initialScene: _collaborationAdapter.currentScene());
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    await _listenToRoom(room);
  }

  Future<void> _joinCollaboration(CollaborationRoom room) async {
    if (_collaborationOpening) {
      return;
    }
    _collaborationOpening = true;
    try {
      final scene = _currentScene();
      final reconciledScene = await ref
          .read(whiteboardViewModelProvider.notifier)
          .joinCollaboration(room: room, localScene: scene);
      await _listenToRoom(room);
      if (reconciledScene.elements.isNotEmpty) {
        await _applyRemoteScene(reconciledScene);
      }
    } finally {
      _collaborationOpening = false;
    }
  }

  Future<void> _stopCollaboration() async {
    if (widget.temporaryCollaboration && mounted && !_temporarySaved) {
      final save = await _confirmTemporaryRoomExit();
      if (save == null) {
        return;
      }
      if (save) {
        await _saveTemporaryRoomAsLocalNote();
      }
    }
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = null;
    await _newUserSubscription?.cancel();
    _newUserSubscription = null;
    await _roomUsersSubscription?.cancel();
    _roomUsersSubscription = null;
    await _roomErrorSubscription?.cancel();
    _roomErrorSubscription = null;
    await _connectionStatusSubscription?.cancel();
    _connectionStatusSubscription = null;
    _idleTimer?.cancel();
    _awayTimer?.cancel();
    _lastIdleState = null;
    _lastRealtimeStatus = null;
    await ref.read(whiteboardViewModelProvider.notifier).stopCollaboration();
    if (widget.temporaryCollaboration && mounted) {
      context.pop();
    }
  }

  Future<bool?> _confirmTemporaryRoomExit() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出协作房间'),
        content: const Text('是否把当前协作白板保存为本地笔记？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不保存退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存到本地'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTemporaryRoomAsLocalNote() async {
    final note = await ref.read(libraryIndexProvider.notifier).createNote();
    final content = _markdrawController.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    await ref
        .read(whiteboardSceneRepositoryProvider)
        .saveScene(note.id, content);
    await ref.read(libraryIndexProvider.notifier).touchNote(note.id);
    _temporarySaved = true;
  }

  Future<void> _listenToRoom(CollaborationRoom room) async {
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = _collaborationRepository
        .encryptedMessages(room)
        .listen(
          _handleCollaborationMessage,
          onError: (Object error) {
            ref
                .read(whiteboardViewModelProvider.notifier)
                .applyCollaborationError(error.toString());
          },
        );
    await _newUserSubscription?.cancel();
    _newUserSubscription = _collaborationRepository.newUsers.listen((_) {
      unawaited(_broadcastCurrentScene(syncAll: true, initial: true));
    });
    await _roomUsersSubscription?.cancel();
    _roomUsersSubscription = _collaborationRepository.roomUsers.listen((users) {
      ref.read(whiteboardViewModelProvider.notifier).applyRoomUsers(users);
    });
    await _roomErrorSubscription?.cancel();
    _roomErrorSubscription = _collaborationRepository.errors.listen((message) {
      ref
          .read(whiteboardViewModelProvider.notifier)
          .applyCollaborationError(message);
    });
    await _connectionStatusSubscription?.cancel();
    _connectionStatusSubscription = _collaborationRepository.connectionStatus
        .listen((status) {
          final previous = _lastRealtimeStatus;
          _lastRealtimeStatus = status;
          ref
              .read(whiteboardViewModelProvider.notifier)
              .applyConnectionStatus(status);
          if (status == RealtimeConnectionStatus.joined &&
              previous == RealtimeConnectionStatus.reconnecting) {
            unawaited(_refreshCollaborationSnapshot(room));
          }
        });
  }

  Future<void> _refreshCollaborationSnapshot(CollaborationRoom room) async {
    final refreshed = await _collaborationRepository.refreshFromSnapshot(
      room: room,
      localScene: _currentScene(),
    );
    if (refreshed == null || !mounted) {
      return;
    }
    await _applyRemoteScene(refreshed);
    await _broadcastCurrentScene(syncAll: true);
  }

  Future<void> _broadcastCurrentScene({
    String? serializedScene,
    bool syncAll = false,
    bool initial = false,
  }) async {
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    final scene = serializedScene == null
        ? _collaborationAdapter.currentScene()
        : ExcalidrawScene.fromContent(serializedScene);
    await _collaborationRepository.broadcastScene(
      room: room,
      scene: scene,
      initial: initial,
      syncAll: syncAll,
    );
  }

  Future<void> _handleCollaborationMessage(CollaborationMessage message) async {
    switch (message.type) {
      case CollaborationMessageType.sceneInit:
      case CollaborationMessageType.sceneUpdate:
        await _applyRemoteElements(message.elements);
      case CollaborationMessageType.mouseLocation:
      case CollaborationMessageType.idleStatus:
      case CollaborationMessageType.userVisibleSceneBounds:
        ref
            .read(whiteboardViewModelProvider.notifier)
            .applyPresenceMessage(message);
      case CollaborationMessageType.invalidResponse:
        break;
    }
  }

  Future<void> _applyRemoteElements(
    List<Map<String, Object?>> remoteElements,
  ) async {
    if (!mounted) {
      return;
    }
    final localScene = _collaborationAdapter.currentScene();
    final reconciledScene = _collaborationRepository.reconcileRemoteScene(
      localScene: localScene,
      remoteElements: remoteElements,
      protectedElementIds: _collaborationAdapter.protectedElementIds(),
    );
    await _applyRemoteScene(reconciledScene);
  }

  Future<void> _applyRemoteScene(ExcalidrawScene remoteScene) async {
    final localScene = _collaborationAdapter.currentScene();
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    final remoteFiles = room == null
        ? const <String, dynamic>{}
        : await _collaborationRepository.loadMissingFiles(
            room: room,
            fileIds: _imageFileIds(remoteScene.elements),
            existingFileIds: localScene.files.keys.toSet(),
          );
    final nextScene = remoteScene.copyWith(
      files: {...localScene.files, ...remoteScene.files, ...remoteFiles},
    );
    final nextContent = nextScene.toContent();

    _applyingRemoteScene = true;
    _collaborationAdapter.applyRemoteScene(nextScene);
    _applyingRemoteScene = false;

    if (widget.temporaryCollaboration) {
      if (mounted) {
        ref.read(whiteboardViewModelProvider.notifier).markSaved();
      }
      return;
    }

    final repository = ref.read(whiteboardSceneRepositoryProvider);
    await repository.saveScene(widget.noteId, nextContent);
    await ref.read(libraryIndexProvider.notifier).touchNote(widget.noteId);
    if (mounted) {
      ref.read(whiteboardViewModelProvider.notifier).markSaved();
    }
  }

  ExcalidrawScene _currentScene() {
    return _collaborationAdapter.currentScene();
  }

  Iterable<String> _imageFileIds(List<Map<String, Object?>> elements) sync* {
    for (final element in elements) {
      if (element['type'] == 'image' && element['fileId'] is String) {
        yield element['fileId']! as String;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardViewModelProvider);

    return PopScope(
      canPop: !widget.temporaryCollaboration || _temporarySaved,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !widget.temporaryCollaboration) {
          return;
        }
        unawaited(_stopCollaboration());
      },
      child: Scaffold(
        key: ValueKey(widget.noteId),
        backgroundColor: const Color(0xFFFDFDFB),
        body: SafeArea(
          child: KeyedSubtree(
            key: const ValueKey('flowmuse-markdraw-editor'),
            child: MarkdrawEditor(
              controller: _markdrawController,
              config: const MarkdrawEditorConfig(initialBackground: '#fdfdfb'),
              saveStatusLabel: _saveStatusLabel(state.saveStatus),
              collaborating: state.collaborating,
              collaborationConnecting:
                  state.collaborationStatus ==
                  WhiteboardCollaborationStatus.connecting,
              collaborationError: state.collaborationError,
              collaborationStatusLabel: _collaborationStatusLabel(state),
              roomLink: state.roomLink,
              roomValue: state.roomValue,
              shareOriginConfigured: state.shareOriginConfigured,
              collaboratorCount: state.collaborators.length,
              collaborators: _remoteCollaboratorOverlays(state),
              onBack: widget.temporaryCollaboration
                  ? () {
                      unawaited(_stopCollaboration());
                    }
                  : () => context.pop(),
              onStartCollaboration: _startCollaboration,
              onStopCollaboration: _stopCollaboration,
              onPointerPresence: _broadcastPointerPresence,
              onVisibleSceneBoundsChanged: _broadcastVisibleSceneBounds,
              onDocumentRenamed: () {
                unawaited(_renameAndSaveDocument());
              },
              onSceneChanged: (_) {
                unawaited(_saveMarkdrawScene());
              },
            ),
          ),
        ),
      ),
    );
  }

  String _saveStatusLabel(WhiteboardSaveStatus status) {
    return switch (status) {
      WhiteboardSaveStatus.idle => '未保存',
      WhiteboardSaveStatus.saving => '保存中',
      WhiteboardSaveStatus.saved => '已保存',
    };
  }

  String? _collaborationStatusLabel(WhiteboardState state) {
    return switch (state.collaborationStatus) {
      WhiteboardCollaborationStatus.connecting => '连接中',
      WhiteboardCollaborationStatus.reconnecting => '重连中',
      WhiteboardCollaborationStatus.disconnected => '已断开',
      WhiteboardCollaborationStatus.failed => '协作失败',
      WhiteboardCollaborationStatus.connected
          when state.collaborators.isNotEmpty =>
        '协作中 ${state.collaborators.length}',
      WhiteboardCollaborationStatus.connected => '协作中',
      WhiteboardCollaborationStatus.idle => null,
    };
  }

  List<RemoteCollaboratorOverlay> _remoteCollaboratorOverlays(
    WhiteboardState state,
  ) {
    return [
      for (final presence in state.collaborators.values)
        RemoteCollaboratorOverlay(
          socketId: presence.socketId,
          username: presence.username,
          pointer: _pointerFromPayload(presence.pointer),
          selectedElementIds: presence.selectedElementIds.entries
              .where((entry) => entry.value)
              .map((entry) => entry.key)
              .toSet(),
          idle: presence.idleState != CollaboratorIdleState.active,
        ),
    ];
  }

  Point? _pointerFromPayload(Map<String, Object?>? payload) {
    if (payload == null) {
      return null;
    }
    final x = payload['x'];
    final y = payload['y'];
    if (x is! num || y is! num) {
      return null;
    }
    return Point(x.toDouble(), y.toDouble());
  }

  void _broadcastPointerPresence(Offset localPosition, bool pointerDown) {
    _markUserActive();
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    unawaited(
      _collaborationRepository.broadcastMouseLocation(
        room: room,
        pointer: _collaborationAdapter.pointerPayload(localPosition),
        button: pointerDown ? 'down' : 'up',
        selectedElementIds: {
          for (final id in _collaborationAdapter.selectedElementIds()) id: true,
        },
        username: 'FlowMuse',
      ),
    );
  }

  void _broadcastVisibleSceneBounds(Size canvasSize) {
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    unawaited(
      _collaborationRepository.broadcastVisibleSceneBounds(
        room: room,
        username: 'FlowMuse',
        sceneBounds: _collaborationAdapter.visibleSceneBounds(canvasSize),
      ),
    );
  }

  void _markUserActive() {
    _idleTimer?.cancel();
    _awayTimer?.cancel();
    _broadcastIdleState('active');
    _idleTimer = Timer(const Duration(minutes: 1), () {
      _broadcastIdleState('idle');
    });
    _awayTimer = Timer(const Duration(minutes: 5), () {
      _broadcastIdleState('away');
    });
  }

  void _broadcastIdleState(String state) {
    if (_lastIdleState == state) {
      return;
    }
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    _lastIdleState = state;
    unawaited(
      _collaborationRepository.broadcastIdleStatus(
        room: room,
        userState: state,
        username: 'FlowMuse',
      ),
    );
  }
}
