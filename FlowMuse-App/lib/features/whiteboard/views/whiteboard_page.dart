import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide Element, SelectionOverlay, TextAlign;

import '../../library/repositories/library_repository.dart';
import '../collaboration/models/collaboration_message.dart';
import '../collaboration/models/collaboration_room.dart';
import '../collaboration/models/excalidraw_scene.dart';
import '../collaboration/repositories/collaboration_repository.dart';
import '../view_models/whiteboard_view_model.dart';

class WhiteboardPage extends ConsumerStatefulWidget {
  const WhiteboardPage({super.key, required this.notebookId});

  final String notebookId;

  @override
  ConsumerState<WhiteboardPage> createState() => _WhiteboardPageState();
}

class _WhiteboardPageState extends ConsumerState<WhiteboardPage> {
  late final MarkdrawController _markdrawController;
  late final CollaborationRepository _collaborationRepository;
  StreamSubscription<CollaborationMessage>? _collaborationSubscription;
  StreamSubscription<String>? _newUserSubscription;
  bool _loadingScene = false;
  bool _applyingRemoteScene = false;
  bool _collaborationOpening = false;

  @override
  void initState() {
    super.initState();
    _markdrawController = MarkdrawController();
    _collaborationRepository = ref.read(collaborationRepositoryProvider);
    Future.microtask(_openNotebook);
  }

  @override
  void didUpdateWidget(covariant WhiteboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notebookId != widget.notebookId) {
      Future.microtask(_openNotebook);
    }
  }

  @override
  void dispose() {
    unawaited(_collaborationSubscription?.cancel());
    unawaited(_newUserSubscription?.cancel());
    unawaited(_collaborationRepository.stop());
    _markdrawController.dispose();
    super.dispose();
  }

  Future<void> _openNotebook() async {
    await ref
        .read(libraryIndexProvider.notifier)
        .ensureNotebook(widget.notebookId);
    await ref
        .read(whiteboardViewModelProvider.notifier)
        .openNotebook(notebookId: widget.notebookId);
    final repository = ref.read(whiteboardSceneRepositoryProvider);
    final content = await repository.loadScene(widget.notebookId);
    if (!mounted) {
      return;
    }
    _loadingScene = true;
    _markdrawController.loadFromContent(
      content,
      '${widget.notebookId}.excalidraw',
    );
    _loadingScene = false;
    final room = _roomFromCurrentUri();
    if (room != null) {
      unawaited(_joinCollaboration(room));
    }
  }

  Future<void> _saveMarkdrawScene() async {
    if (_loadingScene || _applyingRemoteScene) {
      return;
    }
    final viewModel = ref.read(whiteboardViewModelProvider.notifier);
    viewModel.markSaving();
    final repository = ref.read(whiteboardSceneRepositoryProvider);
    final content = _markdrawController.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    await repository.saveScene(widget.notebookId, content);
    await ref
        .read(libraryIndexProvider.notifier)
        .touchNotebook(widget.notebookId);
    await _broadcastCurrentScene(serializedScene: content);
    if (!mounted) {
      return;
    }
    viewModel.markSaved();
  }

  Future<void> _renameAndSaveDocument() async {
    final title = _markdrawController.documentName?.trim();
    if (title != null && title.isNotEmpty) {
      await ref
          .read(libraryIndexProvider.notifier)
          .renameNotebook(widget.notebookId, title);
    }
    await _saveMarkdrawScene();
  }

  Future<void> _startCollaboration() async {
    final scene = _currentScene();
    await ref
        .read(whiteboardViewModelProvider.notifier)
        .startCollaboration(
          initialElements: scene.elements,
          files: scene.files,
        );
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
      final reconciled = await ref
          .read(whiteboardViewModelProvider.notifier)
          .joinCollaboration(
            room: room,
            localElements: scene.elements,
            files: scene.files,
          );
      await _listenToRoom(room);
      if (reconciled.isNotEmpty) {
        await _applyRemoteElements(reconciled);
      }
    } finally {
      _collaborationOpening = false;
    }
  }

  Future<void> _stopCollaboration() async {
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = null;
    await _newUserSubscription?.cancel();
    _newUserSubscription = null;
    await ref.read(whiteboardViewModelProvider.notifier).stopCollaboration();
  }

  Future<void> _listenToRoom(CollaborationRoom room) async {
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = _collaborationRepository
        .encryptedMessages(room)
        .listen(_handleCollaborationMessage);
    await _newUserSubscription?.cancel();
    _newUserSubscription = _collaborationRepository.newUsers.listen((_) {
      unawaited(_broadcastCurrentScene(syncAll: true, initial: true));
    });
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
        ? _currentScene()
        : ExcalidrawScene.fromContent(serializedScene);
    await _collaborationRepository.broadcastScene(
      room: room,
      elements: scene.elements,
      files: scene.files,
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
    if (remoteElements.isEmpty || !mounted) {
      return;
    }
    final localContent = _markdrawController.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    final localScene = ExcalidrawScene.fromContent(localContent);
    final reconciled = _collaborationRepository.reconcileRemoteElements(
      localElements: localScene.elements,
      remoteElements: remoteElements,
      protectedElementIds: _selectedElementIds(),
    );
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    final remoteFiles = room == null
        ? const <String, dynamic>{}
        : await _collaborationRepository.loadMissingFiles(
            room: room,
            fileIds: _imageFileIds(reconciled),
            existingFileIds: localScene.files.keys.toSet(),
          );
    final nextScene = localScene.copyWith(
      elements: reconciled,
      files: {...localScene.files, ...remoteFiles},
    );
    final nextContent = nextScene.toContent();

    _applyingRemoteScene = true;
    _markdrawController.applyRemoteExcalidrawSceneJson(nextScene.toJson());
    _applyingRemoteScene = false;

    final repository = ref.read(whiteboardSceneRepositoryProvider);
    await repository.saveScene(widget.notebookId, nextContent);
    await ref
        .read(libraryIndexProvider.notifier)
        .touchNotebook(widget.notebookId);
    if (mounted) {
      ref.read(whiteboardViewModelProvider.notifier).markSaved();
    }
  }

  ExcalidrawScene _currentScene() {
    return ExcalidrawScene.fromJson(
      _markdrawController.serializeExcalidrawSceneJson(),
    );
  }

  Set<String> _selectedElementIds() {
    return _markdrawController.editorState.selectedIds
        .map((id) => id.value)
        .toSet();
  }

  Iterable<String> _imageFileIds(List<Map<String, Object?>> elements) sync* {
    for (final element in elements) {
      if (element['type'] == 'image' && element['fileId'] is String) {
        yield element['fileId']! as String;
      }
    }
  }

  CollaborationRoom? _roomFromCurrentUri() {
    final uri = Uri.base;
    final link = uri.toString();
    return CollaborationRoom.tryParseLink(link);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardViewModelProvider);

    return Scaffold(
      key: ValueKey(widget.notebookId),
      backgroundColor: const Color(0xFFFDFDFB),
      body: SafeArea(
        child: KeyedSubtree(
          key: const ValueKey('flowmuse-markdraw-editor'),
          child: MarkdrawEditor(
            controller: _markdrawController,
            config: const MarkdrawEditorConfig(initialBackground: '#fdfdfb'),
            saveStatusLabel: _saveStatusLabel(state.saveStatus),
            collaborating: state.collaborating,
            roomLink: state.roomLink,
            collaboratorCount: state.collaborators.length,
            onBack: () => context.pop(),
            onStartCollaboration: _startCollaboration,
            onStopCollaboration: _stopCollaboration,
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
}
