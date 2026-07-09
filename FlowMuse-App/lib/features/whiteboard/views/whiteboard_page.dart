import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide Element, SelectionOverlay, TextAlign;

import '../../../app/app_router.dart';
import '../../account/models/collaboration_identity.dart';
import '../../account/view_models/account_view_model.dart';
import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';
import '../collaboration/models/collaboration_message.dart';
import '../collaboration/models/collaboration_room.dart';
import '../collaboration/models/collaborator_presence.dart';
import '../collaboration/models/excalidraw_scene.dart';
import '../collaboration/models/room_collaborator.dart';
import '../collaboration/repositories/collaboration_repository.dart';
import '../collaboration/services/collaboration_debug_log.dart';
import '../collaboration/services/realtime_transport.dart';
import '../collaboration/services/whiteboard_collaboration_adapter.dart';
import '../collaboration/widgets/join_room_dialog.dart';
import '../pdf_note_import/pdf_note_consumer.dart';
import '../view_models/whiteboard_view_model.dart';
import '../../../shared/utils/ui_lifecycle.dart';

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

enum _OwnerExitAction { cancel, leave, end }

class _WhiteboardPageState extends ConsumerState<WhiteboardPage> {
  late final MarkdrawController _markdrawController;
  late final MarkdrawFileHandler _fileHandler;
  late final WhiteboardCollaborationAdapter _collaborationAdapter;
  late final CollaborationRepository _collaborationRepository;
  StreamSubscription<CollaborationMessage>? _collaborationSubscription;
  StreamSubscription<ExcalidrawScene>? _fileStatusSceneSubscription;
  StreamSubscription<List<RoomCollaborator>>? _roomUsersSubscription;
  StreamSubscription<CollaborationRoomMetadata>? _roomEndedSubscription;
  StreamSubscription<String>? _roomErrorSubscription;
  StreamSubscription<RealtimeConnectionStatus>? _connectionStatusSubscription;
  Timer? _idleTimer;
  Timer? _awayTimer;
  Timer? _loadImagesTimer;
  bool _loadingScene = false;
  bool _applyingRemoteScene = false;
  bool _collaborationOpening = false;
  String? _lastIdleState;
  bool _temporarySaved = false;
  int _openGeneration = 0;
  RealtimeConnectionStatus? _lastRealtimeStatus;
  bool _disposingOrLeaving = false;
  Future<void> _remoteSceneQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _markdrawController = MarkdrawController();
    _fileHandler = MarkdrawFileHandler(controller: _markdrawController);
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
    _disposingOrLeaving = true;
    unawaited(_collaborationSubscription?.cancel());
    unawaited(_fileStatusSceneSubscription?.cancel());
    unawaited(_roomUsersSubscription?.cancel());
    unawaited(_roomEndedSubscription?.cancel());
    unawaited(_roomErrorSubscription?.cancel());
    unawaited(_connectionStatusSubscription?.cancel());
    _idleTimer?.cancel();
    _awayTimer?.cancel();
    _loadImagesTimer?.cancel();
    unawaited(_collaborationRepository.stop());
    _markdrawController.dispose();
    super.dispose();
  }

  Future<void> _openNote() async {
    final generation = ++_openGeneration;
    _disposingOrLeaving = false;
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardPage.openNote start '
      'noteId=${widget.noteId} temporary=${widget.temporaryCollaboration} '
      'generation=$generation',
    );
    if (widget.temporaryCollaboration) {
      _loadingScene = true;
      _markdrawController.closeTransientUiForSceneReplace();
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
    debugPrint('[FlowMuseCreateNote] WhiteboardPage.openNote ensured $noteId');
    final libraryIndex = await ref.read(libraryIndexProvider.future);
    final note = _noteById(libraryIndex.notes, noteId);
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardPage.openNote note '
      'found=${note != null} noteType=${note?.noteType.name} '
      'pageTemplate=${note?.pageTemplate.name}',
    );
    _markdrawController.setLayout(_layoutForNote(note));
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardPage.openNote layout '
      'type=${_markdrawController.layout.type.name} '
      'pages=${_markdrawController.layout.pages.length}',
    );
    if (!mounted || generation != _openGeneration || noteId != widget.noteId) {
      debugPrint(
        '[FlowMuseCreateNote] WhiteboardPage.openNote aborted before VM open',
      );
      return;
    }
    await ref
        .read(whiteboardViewModelProvider.notifier)
        .openNote(noteId: noteId);
    debugPrint('[FlowMuseCreateNote] WhiteboardPage.openNote viewModel opened');
    if (!mounted || generation != _openGeneration || noteId != widget.noteId) {
      debugPrint(
        '[FlowMuseCreateNote] WhiteboardPage.openNote aborted before scene load',
      );
      return;
    }
    final repository = ref.read(whiteboardSceneRepositoryProvider);
    final content = await repository.loadScene(noteId);
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardPage.openNote scene loaded '
      'length=${content.length}',
    );
    if (!mounted || generation != _openGeneration || noteId != widget.noteId) {
      debugPrint(
        '[FlowMuseCreateNote] WhiteboardPage.openNote aborted before controller load',
      );
      return;
    }
    _loadingScene = true;
    _markdrawController.closeTransientUiForSceneReplace();
    _markdrawController.loadFromContent(content, '$noteId.excalidraw');
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardPage.openNote controller loaded '
      'layout=${_markdrawController.layout.type.name} '
      'pages=${_markdrawController.layout.pages.length}',
    );
    final consumedPdf = await ref
        .read(pdfNoteConsumerProvider)
        .consume(
          ref,
          controller: _markdrawController,
          fileHandler: _fileHandler,
          noteId: noteId,
          canvasSize: const Size(1000, 800),
        );
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardPage.openNote pdfConsumed=$consumedPdf',
    );
    if (consumedPdf) {
      final updatedContent = _markdrawController.serializeScene(
        format: DocumentFormat.excalidraw,
      );
      await repository.saveScene(noteId, updatedContent);
      await _broadcastCurrentScene(serializedScene: updatedContent);
    }
    _loadingScene = false;
    debugPrint('[FlowMuseCreateNote] WhiteboardPage.openNote done $noteId');
    final room = widget.initialRoom;
    if (room != null) {
      unawaited(_joinCollaboration(room));
    }
  }

  Future<void> _saveMarkdrawScene() async {
    if (_loadingScene || _applyingRemoteScene) {
      CollaborationDebugLog.write('scene', 'local_change_skipped', {
        'loading': _loadingScene,
        'applyingRemote': _applyingRemoteScene,
      });
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
    await _broadcastCurrentScene();
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
    if (currentStatus == WhiteboardCollaborationStatus.connecting ||
        ref.read(whiteboardViewModelProvider).collaborating) {
      return;
    }
    final confirmed = await _confirmCreateCollaborationRoom();
    if (confirmed != true || !mounted) {
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
    if (mounted) {
      await _showCreatedCollaborationRoom(room);
    }
  }

  Future<void> _promptJoinCollaboration() async {
    final currentState = ref.read(whiteboardViewModelProvider);
    if (currentState.collaborating ||
        currentState.collaborationStatus ==
            WhiteboardCollaborationStatus.connecting) {
      return;
    }
    final room = await showDialog<CollaborationRoom>(
      context: context,
      builder: (context) => const JoinRoomDialog(),
    );
    if (room == null || !mounted) {
      return;
    }
    await _joinCollaboration(room);
  }

  Future<bool?> _confirmCreateCollaborationRoom() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建协作房间'),
        content: const Text('将当前笔记白板同步到协作房间。拥有房间信息的人可以加入并一起编辑。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('创建房间'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreatedCollaborationRoom(CollaborationRoom room) {
    final state = ref.read(whiteboardViewModelProvider);
    final roomLink = state.roomLink;
    final roomValue = state.roomValue ?? room.toRoomValue();
    final shareText = roomLink ?? roomValue;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('协作房间已创建'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('把下面的信息发给协作者，对方即可加入当前白板。'),
              const SizedBox(height: 16),
              _RoomInfoBlock(label: '房间号', value: roomValue),
              if (roomLink != null) ...[
                const SizedBox(height: 12),
                _RoomInfoBlock(label: '房间链接', value: roomLink),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  '分享地址未配置，当前请复制房间码加入。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '加入指引：在笔记库首页或白板右上协作菜单选择“加入房间”，粘贴完整链接、#room=房间号,密钥 或 房间号,密钥。',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: shareText));
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(roomLink == null ? '房间码已复制' : '房间链接已复制'),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: Text(roomLink == null ? '复制房间码' : '复制链接'),
          ),
        ],
      ),
    );
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
      if (!_canMutateWhiteboard) {
        return;
      }
      await _listenToRoom(room);
      if (!_canMutateWhiteboard) {
        return;
      }
      if (reconciledScene.elements.isNotEmpty) {
        await _enqueueRemoteScene(reconciledScene, reconcile: false);
      }
      if (_canMutateWhiteboard) {
        ref
            .read(whiteboardViewModelProvider.notifier)
            .applyCollaborationInitialized();
      }
    } finally {
      _collaborationOpening = false;
    }
  }

  Future<void> _leaveCollaboration() async {
    final state = ref.read(whiteboardViewModelProvider);
    if (state.isRoomOwner && state.collaborating) {
      final action = await _confirmOwnerCollaborationExit();
      if (action == _OwnerExitAction.cancel || !mounted) {
        return;
      }
      if (action == _OwnerExitAction.end) {
        await _endCollaboration();
        return;
      }
    } else if (widget.temporaryCollaboration && mounted && !_temporarySaved) {
      final save = await _confirmMemberRoomExit();
      if (save == null) {
        return;
      }
      if (save) {
        await _saveTemporaryRoomAsLocalNote();
      }
    }
    _disposingOrLeaving = true;
    _markdrawController.closeTransientUiForSceneReplace();
    await _disconnectCollaboration();
    if (widget.temporaryCollaboration && mounted) {
      _popWhenStable();
    }
  }

  Future<void> _handleBack() async {
    final state = ref.read(whiteboardViewModelProvider);
    if (state.collaborating) {
      await _leaveCollaboration();
      if (!widget.temporaryCollaboration && mounted) {
        _popWhenStable();
      }
      return;
    }
    _disposingOrLeaving = true;
    _markdrawController.closeTransientUiForSceneReplace();
    _popWhenStable();
  }

  Future<void> _endCollaboration() async {
    final confirmed = await _confirmEndCollaborationRoom();
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(whiteboardViewModelProvider.notifier).endCollaboration();
    } catch (error) {
      if (mounted) {
        ref
            .read(whiteboardViewModelProvider.notifier)
            .applyCollaborationError(error.toString());
      }
      return;
    }
    _disposingOrLeaving = true;
    _markdrawController.closeTransientUiForSceneReplace();
    await _cancelCollaborationStreams();
    if (widget.temporaryCollaboration && mounted) {
      _popWhenStable();
    }
  }

  Future<void> _disconnectCollaboration() async {
    _markdrawController.closeTransientUiForSceneReplace();
    await _cancelCollaborationStreams();
    await ref.read(whiteboardViewModelProvider.notifier).stopCollaboration();
  }

  Future<void> _cancelCollaborationStreams() async {
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = null;
    await _fileStatusSceneSubscription?.cancel();
    _fileStatusSceneSubscription = null;
    await _roomUsersSubscription?.cancel();
    _roomUsersSubscription = null;
    await _roomEndedSubscription?.cancel();
    _roomEndedSubscription = null;
    await _roomErrorSubscription?.cancel();
    _roomErrorSubscription = null;
    await _connectionStatusSubscription?.cancel();
    _connectionStatusSubscription = null;
    _idleTimer?.cancel();
    _awayTimer?.cancel();
    _loadImagesTimer?.cancel();
    _loadImagesTimer = null;
    _lastIdleState = null;
    _lastRealtimeStatus = null;
  }

  Future<_OwnerExitAction> _confirmOwnerCollaborationExit() async {
    return await showDialog<_OwnerExitAction>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('退出协作房间'),
            content: const Text('你是房主。可以只让自己离开，或结束整个协作房间。'),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_OwnerExitAction.cancel),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_OwnerExitAction.leave),
                child: const Text('仅自己退出'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_OwnerExitAction.end),
                child: const Text('结束协作'),
              ),
            ],
          ),
        ) ??
        _OwnerExitAction.cancel;
  }

  Future<bool?> _confirmEndCollaborationRoom() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束协作'),
        content: const Text('结束后，所有成员都会离开房间，已有链接不能再次加入。当前画布内容会保留在各自设备上。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('结束协作'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmMemberRoomExit() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出协作房间'),
        content: const Text('退出后将停止接收此房间的协作更新。是否保存当前白板为本地笔记？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('直接退出'),
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

  Future<void> _openExternalSceneAsLocalNote() async {
    await _fileHandler.open();
    if (!mounted) {
      return;
    }
    final note = await ref.read(libraryIndexProvider.notifier).createNote();
    final title = _markdrawController.documentName?.trim();
    if (title != null && title.isNotEmpty) {
      await ref.read(libraryIndexProvider.notifier).renameNote(note.id, title);
    }
    final content = _markdrawController.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    await ref
        .read(whiteboardSceneRepositoryProvider)
        .saveScene(note.id, content);
    await ref.read(libraryIndexProvider.notifier).touchNote(note.id);
    if (mounted) {
      runWhenUiStable(() {
        if (mounted) {
          context.go(AppRoutes.whiteboardPath(noteId: note.id));
        }
      });
    }
  }

  Future<void> _listenToRoom(CollaborationRoom room) async {
    _disposingOrLeaving = false;
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = _collaborationRepository
        .encryptedMessages(room)
        .listen(
          _handleCollaborationMessage,
          onError: (Object error) {
            _runAfterStableFrame(() {
              ref
                  .read(whiteboardViewModelProvider.notifier)
                  .applyCollaborationError(error.toString());
            });
          },
        );
    await _fileStatusSceneSubscription?.cancel();
    _fileStatusSceneSubscription = _collaborationRepository.fileStatusScenes
        .listen((scene) {
          _enqueueRemoteScene(scene, loadImages: false, reconcile: false);
        });
    await _roomUsersSubscription?.cancel();
    _roomUsersSubscription = _collaborationRepository.roomUsers.listen((users) {
      _runAfterStableFrame(() {
        ref.read(whiteboardViewModelProvider.notifier).applyRoomUsers(users);
      });
    });
    await _roomEndedSubscription?.cancel();
    _roomEndedSubscription = _collaborationRepository.roomEnded.listen((
      metadata,
    ) {
      unawaited(_handleRoomEnded(metadata));
    });
    await _roomErrorSubscription?.cancel();
    _roomErrorSubscription = _collaborationRepository.errors.listen((message) {
      _runAfterStableFrame(() {
        ref
            .read(whiteboardViewModelProvider.notifier)
            .applyCollaborationError(message);
      });
    });
    await _connectionStatusSubscription?.cancel();
    _connectionStatusSubscription = _collaborationRepository.connectionStatus
        .listen((status) {
          final previous = _lastRealtimeStatus;
          _lastRealtimeStatus = status;
          _runAfterStableFrame(() {
            ref
                .read(whiteboardViewModelProvider.notifier)
                .applyConnectionStatus(status);
          });
          if (status == RealtimeConnectionStatus.joined &&
              previous == RealtimeConnectionStatus.reconnecting) {
            unawaited(_refreshCollaborationSnapshot(room));
          }
        });
  }

  Future<void> _handleRoomEnded(CollaborationRoomMetadata metadata) async {
    _markdrawController.closeTransientUiForSceneReplace();
    await _cancelCollaborationStreams();
    if (!mounted) {
      return;
    }
    await _runAfterStableFrameAsync(() async {
      ref.read(whiteboardViewModelProvider.notifier).applyRoomEnded(metadata);
    });
    final save = await _showRoomEndedDialog();
    if (save == true) {
      await _saveTemporaryRoomAsLocalNote();
    }
    if (widget.temporaryCollaboration && mounted) {
      _disposingOrLeaving = true;
      _markdrawController.closeTransientUiForSceneReplace();
      _popWhenStable();
    }
  }

  Future<bool?> _showRoomEndedDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('协作已结束'),
        content: const Text('房主已结束协作。你可以把当前白板保存为本地笔记，或直接返回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('直接返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存到本地'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshCollaborationSnapshot(CollaborationRoom room) async {
    ref
        .read(whiteboardViewModelProvider.notifier)
        .applySnapshotRestoreStarted();
    try {
      final refreshed = await _collaborationRepository.refreshFromSnapshot(
        room: room,
        localScene: _currentScene(),
      );
      if (refreshed == null || !_canMutateWhiteboard) {
        if (_canMutateWhiteboard) {
          ref
              .read(whiteboardViewModelProvider.notifier)
              .applyCollaborationInitialized();
        }
        return;
      }
      await _enqueueRemoteScene(refreshed);
      await _broadcastCurrentScene(syncAll: true);
      if (_canMutateWhiteboard) {
        ref
            .read(whiteboardViewModelProvider.notifier)
            .applyCollaborationInitialized();
      }
    } catch (error) {
      if (_canMutateWhiteboard) {
        ref
            .read(whiteboardViewModelProvider.notifier)
            .applyCollaborationError('协作快照恢复失败：$error');
      }
    }
  }

  Future<void> _broadcastCurrentScene({
    String? serializedScene,
    bool syncAll = false,
    bool initial = false,
  }) async {
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      CollaborationDebugLog.write('scene', 'broadcast_skipped', {
        'reason': 'no_active_room',
      });
      return;
    }
    final scene = serializedScene == null
        ? _collaborationAdapter.currentScene()
        : ExcalidrawScene.fromContent(serializedScene);
    CollaborationDebugLog.write('scene', 'broadcast_current', {
      'room': _shortRoomId(room.roomId),
      'initial': initial,
      'syncAll': syncAll,
      'elements': scene.elements.length,
      'sceneVersion': CollaborationDebugLog.sceneVersion(scene.elements),
      'summary': CollaborationDebugLog.elementSummary(scene.elements),
    });
    await _collaborationRepository.broadcastScene(
      room: room,
      scene: scene,
      initial: initial,
      syncAll: syncAll,
    );
  }

  Future<void> _handleCollaborationMessage(CollaborationMessage message) async {
    if (!_canMutateWhiteboard) {
      CollaborationDebugLog.write('scene', 'message_skipped', {
        'type': message.type.wireName,
        'reason': 'cannot_mutate',
      });
      return;
    }
    CollaborationDebugLog.write('scene', 'message_received', {
      'type': message.type.wireName,
      'elements': message.elements.length,
      'summary': CollaborationDebugLog.elementSummary(message.elements),
    });
    switch (message.type) {
      case CollaborationMessageType.sceneInit:
      case CollaborationMessageType.sceneUpdate:
        _enqueueRemoteElements(message.elements);
      case CollaborationMessageType.mouseLocation:
      case CollaborationMessageType.idleStatus:
      case CollaborationMessageType.userVisibleSceneBounds:
        _runAfterStableFrame(() {
          ref
              .read(whiteboardViewModelProvider.notifier)
              .applyPresenceMessage(message);
        });
      case CollaborationMessageType.invalidResponse:
        break;
    }
  }

  void _enqueueRemoteElements(List<Map<String, Object?>> remoteElements) {
    CollaborationDebugLog.write('scene', 'remote_elements_queued', {
      'elements': remoteElements.length,
      'summary': CollaborationDebugLog.elementSummary(remoteElements),
    });
    final pending = _remoteSceneQueue.catchError(_ignoreRemoteSceneError);
    _remoteSceneQueue = pending
        .then<void>((_) async {
          await _runAfterStableFrameAsync(() async {
            await _applyRemoteElements(remoteElements);
          });
        })
        .catchError(_reportRemoteSceneFutureError);
    unawaited(_remoteSceneQueue);
  }

  Future<void> _enqueueRemoteScene(
    ExcalidrawScene remoteScene, {
    bool loadImages = true,
    bool reconcile = true,
  }) {
    CollaborationDebugLog.write('scene', 'remote_scene_queued', {
      'elements': remoteScene.elements.length,
      'sceneVersion': CollaborationDebugLog.sceneVersion(remoteScene.elements),
      'summary': CollaborationDebugLog.elementSummary(remoteScene.elements),
    });
    final pending = _remoteSceneQueue.catchError(_ignoreRemoteSceneError);
    _remoteSceneQueue = pending
        .then<void>((_) async {
          await _runAfterStableFrameAsync(() async {
            await _applyRemoteScene(remoteScene, reconcile: reconcile);
            if (loadImages) {
              _scheduleLoadImageFiles();
            }
          });
        })
        .catchError(_reportRemoteSceneFutureError);
    return _remoteSceneQueue;
  }

  Future<void> _ignoreRemoteSceneError(
    Object error,
    StackTrace stackTrace,
  ) async {}

  Future<void> _reportRemoteSceneFutureError(
    Object error,
    StackTrace stackTrace,
  ) async {
    _reportRemoteSceneError(error);
  }

  void _reportRemoteSceneError(Object error) {
    CollaborationDebugLog.write('scene', 'remote_apply_failed', {
      'error': error,
    });
    _runAfterStableFrame(() {
      ref
          .read(whiteboardViewModelProvider.notifier)
          .applyCollaborationError('协作场景同步失败：$error');
    });
  }

  Future<void> _applyRemoteElements(
    List<Map<String, Object?>> remoteElements,
  ) async {
    if (!_canMutateWhiteboard) {
      CollaborationDebugLog.write('scene', 'remote_elements_skipped', {
        'reason': 'cannot_mutate',
      });
      return;
    }
    final localScene = _collaborationAdapter.currentScene();
    final protectedElementIds = _collaborationAdapter.protectedElementIds();
    final reconciledScene = _collaborationRepository.reconcileRemoteScene(
      localScene: localScene,
      remoteElements: remoteElements,
      protectedElementIds: protectedElementIds,
    );
    CollaborationDebugLog.write('scene', 'remote_elements_reconciled', {
      'remote': remoteElements.length,
      'localBefore': localScene.elements.length,
      'localAfter': reconciledScene.elements.length,
      'protected': protectedElementIds.length,
      'summary': CollaborationDebugLog.elementSummary(reconciledScene.elements),
    });
    await _applyRemoteScene(reconciledScene);
    _scheduleLoadImageFiles();
  }

  Future<void> _applyRemoteScene(
    ExcalidrawScene remoteScene, {
    bool reconcile = true,
  }) async {
    if (!_canMutateWhiteboard) {
      CollaborationDebugLog.write('scene', 'remote_scene_skipped', {
        'reason': 'cannot_mutate',
      });
      return;
    }
    final localScene = _collaborationAdapter.currentScene();
    final protectedElementIds = _collaborationAdapter.protectedElementIds();
    final reconciledScene = reconcile
        ? _collaborationRepository
              .reconcileRemoteScene(
                localScene: localScene,
                remoteElements: remoteScene.elements,
                protectedElementIds: protectedElementIds,
              )
              .copyWith(
                appState: remoteScene.appState,
                files: remoteScene.files,
              )
        : remoteScene;
    if (!_canMutateWhiteboard) {
      CollaborationDebugLog.write('scene', 'remote_scene_skipped', {
        'reason': 'cannot_mutate_before_apply',
      });
      return;
    }
    final nextScene = reconciledScene.copyWith(
      files: reconcile
          ? {...localScene.files, ...reconciledScene.files}
          : reconciledScene.files,
    );
    final nextContent = nextScene.toContent();

    _applyingRemoteScene = true;
    try {
      _collaborationAdapter.applyRemoteScene(
        nextScene,
        closeTransientUi: false,
      );
      CollaborationDebugLog.write('scene', 'remote_scene_applied', {
        'remote': remoteScene.elements.length,
        'localBefore': localScene.elements.length,
        'localAfter': nextScene.elements.length,
        'protected': protectedElementIds.length,
        'filesLoaded': 0,
        'sceneVersion': CollaborationDebugLog.sceneVersion(nextScene.elements),
        'summary': CollaborationDebugLog.elementSummary(nextScene.elements),
      });
    } finally {
      _applyingRemoteScene = false;
    }

    if (widget.temporaryCollaboration) {
      if (_canMutateWhiteboard) {
        ref.read(whiteboardViewModelProvider.notifier).markSaved();
      }
      return;
    }

    final repository = ref.read(whiteboardSceneRepositoryProvider);
    await repository.saveScene(widget.noteId, nextContent);
    await ref.read(libraryIndexProvider.notifier).touchNote(widget.noteId);
    if (_canMutateWhiteboard) {
      ref.read(whiteboardViewModelProvider.notifier).markSaved();
    }
  }

  bool get _canMutateWhiteboard => mounted && !_disposingOrLeaving;

  String _shortRoomId(String roomId) =>
      roomId.length > 8 ? roomId.substring(0, 8) : roomId;

  void _runAfterStableFrame(VoidCallback action) {
    runWhenUiStable(() {
      if (_canMutateWhiteboard) {
        action();
      }
    });
  }

  Future<void> _runAfterStableFrameAsync(Future<void> Function() action) {
    final completer = Completer<void>();
    runWhenUiStable(() {
      if (!_canMutateWhiteboard) {
        completer.complete();
        return;
      }
      action().then(completer.complete, onError: completer.completeError);
    });
    return completer.future;
  }

  void _popWhenStable() {
    runWhenUiStable(() {
      if (mounted && Navigator.of(context).canPop()) {
        context.pop();
      }
    });
  }

  ExcalidrawScene _currentScene() {
    return _collaborationAdapter.currentScene();
  }

  void _scheduleLoadImageFiles() {
    if (_loadImagesTimer?.isActive ?? false) {
      return;
    }
    _loadImagesTimer = Timer(const Duration(milliseconds: 500), () {
      _loadImagesTimer = null;
      unawaited(_loadMissingImageFiles());
    });
  }

  Future<void> _loadMissingImageFiles() async {
    if (!_canMutateWhiteboard) {
      return;
    }
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    final scene = _collaborationAdapter.currentScene();
    final result = await _collaborationRepository.loadMissingFiles(
      room: room,
      fileIds: _savedImageFileIds(scene.elements),
      existingFileIds: scene.files.keys.toSet(),
    );
    if (!_canMutateWhiteboard ||
        (result.files.isEmpty && result.erroredFileIds.isEmpty)) {
      return;
    }
    final latestScene = _collaborationAdapter.currentScene();
    final nextScene = latestScene.copyWith(
      files: {...latestScene.files, ...result.files},
      elements: _markErroredImageFiles(
        latestScene.elements,
        result.erroredFileIds,
      ),
    );
    _applyingRemoteScene = true;
    try {
      _collaborationAdapter.applyRemoteScene(
        nextScene,
        closeTransientUi: false,
      );
      CollaborationDebugLog.write('file', 'remote_images_applied', {
        'filesLoaded': result.files.length,
        'filesErrored': result.erroredFileIds.length,
      });
    } finally {
      _applyingRemoteScene = false;
    }
  }

  Iterable<String> _savedImageFileIds(
    List<Map<String, Object?>> elements,
  ) sync* {
    for (final element in elements) {
      if (element['type'] == 'image' &&
          element['status'] == 'saved' &&
          element['fileId'] is String) {
        yield element['fileId']! as String;
      }
    }
  }

  List<Map<String, Object?>> _markErroredImageFiles(
    List<Map<String, Object?>> elements,
    Set<String> erroredFileIds,
  ) {
    if (erroredFileIds.isEmpty) {
      return elements;
    }
    return [
      for (final element in elements)
        if (element['type'] == 'image' &&
            element['fileId'] is String &&
            erroredFileIds.contains(element['fileId']))
          {
            ...element,
            'status': 'error',
            'version': ((element['version'] as num?)?.toInt() ?? 1) + 1,
            'updated': DateTime.now().millisecondsSinceEpoch,
          }
        else
          element,
    ];
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
        unawaited(_leaveCollaboration());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFDFDFB),
        body: SafeArea(
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
            isCollaborationOwner: state.isRoomOwner,
            onSave: () {
              unawaited(_saveMarkdrawScene());
            },
            onSaveAs: () {
              unawaited(_fileHandler.saveAs());
            },
            onOpen: widget.temporaryCollaboration
                ? null
                : () {
                    unawaited(_openExternalSceneAsLocalNote());
                  },
            onExportPng: () {
              unawaited(_fileHandler.exportPng());
            },
            onExportSvg: () {
              unawaited(_fileHandler.exportSvg());
            },
            onImportImage: () {
              unawaited(_fileHandler.importImage(context));
            },
            onImportLibrary: () {
              unawaited(_fileHandler.importLibrary());
            },
            onExportLibrary: () {
              unawaited(_fileHandler.exportLibrary());
            },
            onBack: widget.temporaryCollaboration
                ? () {
                    unawaited(_leaveCollaboration());
                  }
                : () {
                    unawaited(_handleBack());
                  },
            onStartCollaboration: _startCollaboration,
            onJoinCollaboration: _promptJoinCollaboration,
            onLeaveCollaboration: _leaveCollaboration,
            onEndCollaboration: _endCollaboration,
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
      WhiteboardCollaborationStatus.initializing => '初始化中',
      WhiteboardCollaborationStatus.reconnecting => '重连中',
      WhiteboardCollaborationStatus.restoringSnapshot => '快照恢复中',
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
    if (!_canMutateWhiteboard) {
      return;
    }
    _markUserActive();
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    final identity = _collaborationIdentity;
    unawaited(
      _collaborationRepository.broadcastMouseLocation(
        room: room,
        pointer: _collaborationAdapter.pointerPayload(localPosition),
        button: pointerDown ? 'down' : 'up',
        selectedElementIds: {
          for (final id in _collaborationAdapter.selectedElementIds()) id: true,
        },
        username: identity.username,
        userId: identity.userId,
        avatarUrl: identity.avatarUrl,
      ),
    );
  }

  void _broadcastVisibleSceneBounds(Size canvasSize) {
    if (!_canMutateWhiteboard) {
      return;
    }
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    final identity = _collaborationIdentity;
    unawaited(
      _collaborationRepository.broadcastVisibleSceneBounds(
        room: room,
        username: identity.username,
        userId: identity.userId,
        avatarUrl: identity.avatarUrl,
        sceneBounds: _collaborationAdapter.visibleSceneBounds(canvasSize),
      ),
    );
  }

  void _markUserActive() {
    if (!_canMutateWhiteboard) {
      return;
    }
    _idleTimer?.cancel();
    _awayTimer?.cancel();
    _broadcastIdleState('active');
    _idleTimer = Timer(const Duration(minutes: 1), () {
      if (_canMutateWhiteboard) {
        _broadcastIdleState('idle');
      }
    });
    _awayTimer = Timer(const Duration(minutes: 5), () {
      if (_canMutateWhiteboard) {
        _broadcastIdleState('away');
      }
    });
  }

  void _broadcastIdleState(String state) {
    if (!_canMutateWhiteboard) {
      return;
    }
    if (_lastIdleState == state) {
      return;
    }
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    _lastIdleState = state;
    final identity = _collaborationIdentity;
    unawaited(
      _collaborationRepository.broadcastIdleStatus(
        room: room,
        userState: state,
        username: identity.username,
        userId: identity.userId,
        avatarUrl: identity.avatarUrl,
      ),
    );
  }

  CollaborationIdentity get _collaborationIdentity {
    return ref.read(accountViewModelProvider).collaborationIdentity;
  }

  NoteItem? _noteById(List<NoteItem> notes, String noteId) {
    for (final note in notes) {
      if (note.id == noteId) {
        return note;
      }
    }
    return null;
  }

  CanvasLayout _layoutForNote(NoteItem? note) {
    final template = _templateForNote(note?.pageTemplate);
    return CanvasLayout(
      type: note?.noteType == NoteType.unbounded
          ? CanvasLayoutType.unbounded
          : CanvasLayoutType.paged,
      template: template,
    );
  }

  CanvasPageTemplate _templateForNote(PageTemplate? template) {
    return switch (template) {
      PageTemplate.narrowLine => CanvasPageTemplate.narrowLine,
      PageTemplate.wideLine => CanvasPageTemplate.wideLine,
      PageTemplate.grid => CanvasPageTemplate.grid,
      PageTemplate.dotGrid => CanvasPageTemplate.dotGrid,
      PageTemplate.blank || null => CanvasPageTemplate.blank,
    };
  }
}

class _RoomInfoBlock extends StatelessWidget {
  const _RoomInfoBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: SelectableText(
            value,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
