import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide Element, SelectionOverlay, TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart'
    as editor_core;

import '../../../app/app_router.dart';
import '../../../app/app_theme_preset.dart';
import '../../../app/view_models/theme_view_model.dart';
import '../../account/models/collaboration_identity.dart';
import '../../account/view_models/account_view_model.dart';
import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';
import '../../../shared/storage/local_settings_repository.dart';
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
import '../ink_recognition/ink_recognition_repository.dart';
import '../pdf_note_import/pdf_note_consumer.dart';
import '../share/models/share_payload.dart';
import '../share/models/share_result.dart';
import '../share/services/share_export_coordinator.dart';
import '../share/services/share_service_selector.dart';
import '../view_models/whiteboard_view_model.dart';
import '../models/editor_preferences.dart';
import '../view_models/editor_preferences_view_model.dart';
import '../../../shared/utils/ui_lifecycle.dart';

class WhiteboardPage extends ConsumerStatefulWidget {
  const WhiteboardPage({
    super.key,
    required this.noteId,
    this.discardIfUnchanged = false,
  }) : temporaryCollaboration = false,
       initialRoom = null;

  const WhiteboardPage.collaboration({super.key})
    : noteId = 'collaboration-room',
      temporaryCollaboration = true,
      initialRoom = null,
      discardIfUnchanged = false;

  const WhiteboardPage.collaborationRoom({
    super.key,
    required CollaborationRoom this.initialRoom,
  }) : noteId = 'collaboration-room',
       temporaryCollaboration = true,
       discardIfUnchanged = false;

  final String noteId;
  final bool temporaryCollaboration;
  final CollaborationRoom? initialRoom;
  final bool discardIfUnchanged;

  @override
  ConsumerState<WhiteboardPage> createState() => _WhiteboardPageState();
}

enum _OwnerExitAction { cancel, leave, end }

enum _ShareSelection { png, markdraw, excalidraw, invitation }

class _WhiteboardPageState extends ConsumerState<WhiteboardPage>
    with WidgetsBindingObserver {
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
  bool _handlingBack = false;
  bool _editorPreferencesApplied = false;
  Future<void> _remoteSceneQueue = Future<void>.value();

  // LocalDraftScheduler — debounce duration comes from editor preferences.
  Timer? _localDraftTimer;
  bool _localDraftDirty = false;

  Scene? _previousEditorScene;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _markdrawController = MarkdrawController();
    _markdrawController.onBrushStateChanged = (type, state) {
      unawaited(
        ref
            .read(editorPreferencesProvider.notifier)
            .updateBrushState(type, state),
      );
    };
    ref.listenManual(editorPreferencesProvider, (_, next) {
      next.whenData(_applyEditorPreferences);
    }, fireImmediately: true);
    _markdrawController.onInkRecognitionModeChanged =
        _saveInkRecognitionPreference;
    _fileHandler = MarkdrawFileHandler(controller: _markdrawController);
    _collaborationAdapter = WhiteboardCollaborationAdapter(_markdrawController);
    _collaborationRepository = ref.read(collaborationRepositoryProvider);
    Future.microtask(_openNote);
  }

  void _applyEditorPreferences(EditorPreferences preferences) {
    final tool = _editorPreferencesApplied
        ? _markdrawController.editorState.activeToolType
        : preferences.defaultTool;
    final brush = _editorPreferencesApplied
        ? _markdrawController.activeBrushType
        : preferences.defaultBrush;
    _markdrawController.applyEditorPreferences(
      defaultTool: tool,
      defaultBrush: brush,
      brushStates: preferences.brushStates,
      pressureEnabled: preferences.pressureEnabled,
      pressureExponent: preferences.pressureCurve.exponent,
      palmRejectionEnabled: preferences.palmRejectionEnabled,
      twoFingerZoomEnabled: preferences.twoFingerZoomEnabled,
      singleFingerPanEnabled: preferences.singleFingerPanEnabled,
    );
    _editorPreferencesApplied = true;
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
    WidgetsBinding.instance.removeObserver(this);
    _flushLocalDraftOnExit();
    _remoteMergeTimer?.cancel();
    _remoteMergeBuffer.clear();
    _pointerTrailingTimer?.cancel();
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
      _markdrawController.inkRecognitionMode = false;
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
    await _restoreInkRecognitionPreference(noteId);
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
    if (note?.kind == LibraryFilter.pdf && !consumedPdf) {
      _restorePdfViewportBounds();
    } else if (note?.kind != LibraryFilter.pdf) {
      _markdrawController.contentBounds = null;
    }
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardPage.openNote pdfConsumed=$consumedPdf',
    );
    if (consumedPdf) {
      final updatedContent = _markdrawController.serializeScene(
        format: DocumentFormat.excalidraw,
      );
      await repository.saveScene(noteId, updatedContent);
      await _touchNoteWithCurrentCover(noteId);
      await _broadcastCurrentScene(serializedScene: updatedContent);
    }
    _loadingScene = false;
    debugPrint('[FlowMuseCreateNote] WhiteboardPage.openNote done $noteId');
    final room = widget.initialRoom;
    if (room != null) {
      unawaited(_joinCollaboration(room));
    }
  }

  String _inkRecognitionPreferenceKey(String noteId) {
    return 'whiteboard.inkRecognitionMode.$noteId';
  }

  Future<void> _restoreInkRecognitionPreference(String noteId) async {
    final enabled = await defaultLocalSettingsRepository.readBool(
      _inkRecognitionPreferenceKey(noteId),
    );
    if (!mounted || noteId != widget.noteId) {
      return;
    }
    _markdrawController.inkRecognitionMode = enabled ?? false;
  }

  void _saveInkRecognitionPreference(bool enabled) {
    if (widget.temporaryCollaboration) {
      return;
    }
    unawaited(
      defaultLocalSettingsRepository.writeBool(
        _inkRecognitionPreferenceKey(widget.noteId),
        enabled,
      ),
    );
  }

  void _restorePdfViewportBounds() {
    final controller = _markdrawController;
    final bounds = PdfNoteConsumer.pdfBackgroundBounds(controller.currentScene);
    controller.contentBounds = bounds;
    if (bounds == null) {
      return;
    }
    final canvasSize =
        controller.canvasSize.width > 0 && controller.canvasSize.height > 0
        ? controller.canvasSize
        : const Size(1000, 800);
    controller.canvasSize = canvasSize;
    controller.setViewport(
      PdfNoteConsumer.fitFirstPageViewport(controller.currentScene, canvasSize),
    );
  }

  void _scheduleLocalDraft() {
    _localDraftDirty = true;
    _localDraftTimer?.cancel();
    final interval = ref
        .read(editorPreferencesProvider)
        .value
        ?.autosaveInterval
        .duration;
    // null interval = auto-save disabled; the draft is still flushed on exit
    // and on lifecycle pause via _flushLocalDraftOnExit.
    if (interval == null) return;
    _localDraftTimer = Timer(interval, _flushLocalDraft);
  }

  Future<void> _flushLocalDraft() async {
    _localDraftTimer = null;
    if (!_localDraftDirty || !mounted) return;
    _localDraftDirty = false;

    if (widget.temporaryCollaboration) return;

    final viewModel = ref.read(whiteboardViewModelProvider.notifier);
    final repository = ref.read(whiteboardSceneRepositoryProvider);
    final content = _markdrawController.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    await repository.saveScene(widget.noteId, content);
    await _touchNoteWithCurrentCover(widget.noteId);
    if (mounted) {
      viewModel.markSaved();
    }
  }

  Future<void> _finalizeLocalDraftBeforeLeaving() async {
    if (widget.temporaryCollaboration) {
      return;
    }
    _localDraftTimer?.cancel();
    _localDraftTimer = null;

    if (widget.discardIfUnchanged && await _shouldDiscardUnchangedDraft()) {
      _localDraftDirty = false;
      await ref.read(libraryIndexProvider.notifier).deleteNotesForever([
        widget.noteId,
      ]);
      return;
    }

    if (_localDraftDirty) {
      await _flushLocalDraft();
    }
  }

  Future<bool> _shouldDiscardUnchangedDraft() async {
    final scene = _markdrawController.currentScene;
    final hasUserContent =
        scene.smartLayout != null ||
        scene.activeElements.any((element) => !element.isCanvasPage);
    if (hasUserContent) {
      return false;
    }

    final libraryIndex = await ref.read(libraryIndexProvider.future);
    final note = _noteById(libraryIndex.notes, widget.noteId);
    if (note == null || note.kind != LibraryFilter.notes) {
      return false;
    }
    return note.title == '未命名${note.pageTemplate.displayName}';
  }

  void _flushLocalDraftOnExit() {
    _localDraftTimer?.cancel();
    _localDraftTimer = null;
    if (_localDraftDirty) {
      _flushLocalDraft();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _flushLocalDraftOnExit();
    }
  }

  Future<void> _broadcastUndoRedoScene(
    Scene? previousEditorScene,
    ExcalidrawScene currentScene,
  ) async {
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) return;

    final rng = Random();
    final bumpedElements = <Map<String, Object?>>[];
    final previousElements = previousEditorScene == null
        ? null
        : _collaborationAdapter.serializeElements(previousEditorScene.elements);

    final previousById = <String, Map<String, Object?>>{};
    if (previousElements != null) {
      for (final e in previousElements) {
        previousById[e['id'] as String] = e;
      }
    }

    if (previousById.isEmpty) {
      for (final element in currentScene.elements) {
        bumpedElements.add({
          ...element,
          'version': ((element['version'] as num).toInt() + 1),
          'versionNonce': rng.nextInt(1 << 31),
          'updated': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } else {
      final currentIds = <String>{};
      for (final element in currentScene.elements) {
        final id = element['id'] as String;
        currentIds.add(id);
        final prev = previousById[id];
        if (prev == null ||
            (element['version'] as num).toInt() !=
                (prev['version'] as num).toInt() ||
            (element['versionNonce'] as num).toInt() !=
                (prev['versionNonce'] as num).toInt() ||
            element['isDeleted'] != prev['isDeleted']) {
          bumpedElements.add({
            ...element,
            'version':
                max(
                  (element['version'] as num).toInt(),
                  (prev?['version'] as num?)?.toInt() ?? 0,
                ) +
                1,
            'versionNonce': rng.nextInt(1 << 31),
            'updated': DateTime.now().millisecondsSinceEpoch,
          });
        } else {
          bumpedElements.add(element);
        }
      }

      for (final entry in previousById.entries) {
        if (currentIds.contains(entry.key)) continue;
        final prev = entry.value;
        if (prev['isDeleted'] == true) continue;
        bumpedElements.add({
          ...prev,
          'version': ((prev['version'] as num).toInt() + 1),
          'versionNonce': rng.nextInt(1 << 31),
          'isDeleted': true,
          'updated': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }

    if (bumpedElements.isEmpty) return;

    final bumpedScene = currentScene.copyWith(elements: bumpedElements);

    _applyingRemoteScene = true;
    try {
      _collaborationAdapter.applyRemoteScene(
        bumpedScene,
        closeTransientUi: false,
      );
    } finally {
      _applyingRemoteScene = false;
    }

    await _collaborationRepository.broadcastScene(
      room: room,
      scene: bumpedScene,
      syncAll: true,
    );
  }

  Future<void> _saveMarkdrawScene() async {
    if (_loadingScene || _applyingRemoteScene) {
      CollaborationDebugLog.write('scene', 'local_change_skipped', {
        'loading': _loadingScene,
        'applyingRemote': _applyingRemoteScene,
      });
      return;
    }

    // 协作增量 — accumulator（Task 2 已处理）
    await _broadcastCurrentScene();

    // 本地草稿 — 500ms debounce（封面由 _flushLocalDraft 处理）
    _scheduleLocalDraft();
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
              await _shareCollaborationInvitation();
            },
            icon: const Icon(Icons.ios_share),
            label: const Text('系统分享'),
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

  Future<void> _shareCollaborationInvitation() async {
    final state = ref.read(whiteboardViewModelProvider);
    final shareText = state.roomLink ?? state.roomValue;
    if (shareText == null) {
      return;
    }
    final result = await createShareService().share(
      ShareTextPayload(title: 'FlowMuse 协作邀请', text: shareText),
    );
    if (!mounted || result == ShareResult.dismissed) {
      return;
    }
    if (result == ShareResult.unavailable) {
      await Clipboard.setData(ClipboardData(text: shareText));
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == ShareResult.unavailable
              ? '系统分享不可用，邀请信息已复制'
              : result == ShareResult.completed
              ? '已打开系统分享面板'
              : '分享失败，请稍后重试',
        ),
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
    if (_handlingBack) {
      return;
    }
    _handlingBack = true;
    final state = ref.read(whiteboardViewModelProvider);
    try {
      if (state.collaborating) {
        await _leaveCollaboration();
        if (!widget.temporaryCollaboration && mounted) {
          _popWhenStable();
        }
        return;
      }
      await _finalizeLocalDraftBeforeLeaving();
      _disposingOrLeaving = true;
      _markdrawController.closeTransientUiForSceneReplace();
      _popWhenStable();
    } finally {
      if (mounted && !_disposingOrLeaving) {
        _handlingBack = false;
      }
    }
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
    await _touchNoteWithCurrentCover(note.id);
    _temporarySaved = true;
  }

  Future<void> _openExternalSceneAsLocalNote() async {
    await _fileHandler.open();
    if (!mounted) {
      return;
    }
    final note = await ref.read(libraryIndexProvider.notifier).createNote();
    final title = _markdrawController.documentName?.trim();
    final sourceName = _fileHandler.lastOpenedFileName;
    final fallbackTitle = sourceName?.replaceFirst(
      RegExp(r'\.(markdraw|excalidraw)$', caseSensitive: false),
      '',
    );
    final noteTitle = title?.isNotEmpty == true ? title : fallbackTitle;
    if (noteTitle != null && noteTitle.trim().isNotEmpty) {
      await ref
          .read(libraryIndexProvider.notifier)
          .renameNote(note.id, noteTitle.trim());
    }
    final content = _markdrawController.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    await ref
        .read(whiteboardSceneRepositoryProvider)
        .saveScene(note.id, content);
    await _touchNoteWithCurrentCover(note.id);
    if (mounted) {
      runWhenUiStable(() {
        if (mounted) {
          context.go(
            AppRoutes.whiteboardPath(
              noteId: note.id,
              discardIfUnchanged: false,
            ),
          );
        }
      });
    }
  }

  Future<void> _shareCurrentWhiteboard() async {
    final selection = await showModalBottomSheet<_ShareSelection>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('分享 PNG 图片'),
              onTap: () => Navigator.pop(sheetContext, _ShareSelection.png),
            ),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: const Text('分享 .markdraw 文件（仅手写和图形）'),
              onTap: () =>
                  Navigator.pop(sheetContext, _ShareSelection.markdraw),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('分享 .excalidraw 文件（完整保留分页模板）'),
              onTap: () =>
                  Navigator.pop(sheetContext, _ShareSelection.excalidraw),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('分享协作邀请链接'),
              onTap: () =>
                  Navigator.pop(sheetContext, _ShareSelection.invitation),
            ),
          ],
        ),
      ),
    );
    if (selection == null || !mounted) return;

    try {
      final payload = await _buildSharePayload(selection);
      if (payload == null || !mounted) return;
      final result = await createShareService().share(payload);
      if (!mounted || result == ShareResult.dismissed) return;
      final message = switch (result) {
        ShareResult.completed => '已打开系统分享面板',
        ShareResult.unavailable =>
          payload is ShareFilePayload ? '文件已导出' : '链接已复制',
        ShareResult.failed => '分享失败，请稍后重试',
        ShareResult.dismissed => '',
      };
      if (message.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分享失败，请稍后重试')));
      }
    }
  }

  Future<SharePayload?> _buildSharePayload(_ShareSelection selection) async {
    final exporter = ShareExportCoordinator();
    switch (selection) {
      case _ShareSelection.png:
        return exporter.preparePng(_markdrawController);
      case _ShareSelection.markdraw:
        return exporter.prepareDocument(
          _markdrawController,
          DocumentFormat.markdraw,
        );
      case _ShareSelection.excalidraw:
        return exporter.prepareDocument(
          _markdrawController,
          DocumentFormat.excalidraw,
        );
      case _ShareSelection.invitation:
        final link = ref.read(whiteboardViewModelProvider).roomLink;
        if (link == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('当前没有可分享的协作邀请链接')));
          return null;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('分享协作邀请'),
            content: const Text('持有该链接的人可以加入当前协作房间。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('继续分享'),
              ),
            ],
          ),
        );
        return confirmed == true
            ? ShareTextPayload(title: 'FlowMuse 协作邀请', text: link)
            : null;
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

  Future<void> _broadcastChangedElements(
    Iterable<editor_core.Element> elements, {
    bool latestOnly = false,
  }) async {
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) return;
    await _collaborationRepository.broadcastElements(
      room: room,
      elements: _collaborationAdapter.serializeElements(elements),
      latestOnly: latestOnly,
    );
  }

  void _broadcastLiveFreedraw(editor_core.FreedrawElement element) {
    if (!ref.read(whiteboardViewModelProvider).collaborating) return;
    unawaited(_broadcastChangedElements([element], latestOnly: true));
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

  final Map<String, Map<String, Object?>> _remoteMergeBuffer = {};
  Timer? _remoteMergeTimer;
  static const Duration _remoteMergeWindow = Duration(milliseconds: 16);

  void _enqueueRemoteElements(List<Map<String, Object?>> remoteElements) {
    CollaborationDebugLog.write('scene', 'remote_elements_queued', {
      'elements': remoteElements.length,
      'summary': CollaborationDebugLog.elementSummary(remoteElements),
    });

    for (final element in remoteElements) {
      final id = element['id'] as String;
      final existing = _remoteMergeBuffer[id];
      if (existing == null) {
        _remoteMergeBuffer[id] = Map<String, Object?>.from(element);
      } else {
        final existingVersion = (existing['version'] as num).toInt();
        final incomingVersion = (element['version'] as num).toInt();
        if (incomingVersion > existingVersion ||
            (incomingVersion == existingVersion &&
                (element['versionNonce'] as num).toInt() <
                    (existing['versionNonce'] as num).toInt())) {
          _remoteMergeBuffer[id] = Map<String, Object?>.from(element);
        }
      }
    }

    _remoteMergeTimer?.cancel();
    _remoteMergeTimer = Timer(_remoteMergeWindow, _flushRemoteMerge);
  }

  Future<void> _flushRemoteMerge() async {
    _remoteMergeTimer = null;
    if (_remoteMergeBuffer.isEmpty) return;

    final merged = _remoteMergeBuffer.values.toList();
    _remoteMergeBuffer.clear();

    final pending = _remoteSceneQueue.catchError(_ignoreRemoteSceneError);
    _remoteSceneQueue = pending
        .then<void>((_) async {
          await _runAfterStableFrameAsync(() async {
            await _applyRemoteElements(merged);
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
    final protectedElementIds = _collaborationAdapter.protectedElementIds();
    final changedElements = _collaborationRepository.reconcileRemoteElements(
      remoteElements: remoteElements,
      protectedElementIds: protectedElementIds,
    );
    CollaborationDebugLog.write('scene', 'remote_elements_reconciled', {
      'remote': remoteElements.length,
      'changed': changedElements.length,
      'protected': protectedElementIds.length,
      'summary': CollaborationDebugLog.elementSummary(changedElements),
    });
    if (!_canMutateWhiteboard) return;
    _applyingRemoteScene = true;
    final sw = Stopwatch()..start();
    try {
      _collaborationAdapter.applyRemoteElements(changedElements);
      sw.stop();
      CollaborationDebugLog.write('metrics', 'remote_apply_latency_ms', {
        'ms': sw.elapsedMilliseconds,
        'elements': changedElements.length,
      });
    } finally {
      _applyingRemoteScene = false;
    }
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
    final localScene = reconcile ? _collaborationAdapter.currentScene() : null;
    final protectedElementIds = reconcile
        ? _collaborationAdapter.protectedElementIds()
        : const <String>{};
    final reconciledScene = reconcile
        ? _collaborationRepository
              .reconcileRemoteScene(
                localScene: localScene!,
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
          ? {...localScene!.files, ...reconciledScene.files}
          : reconciledScene.files,
    );

    _applyingRemoteScene = true;
    final sw = Stopwatch()..start();
    try {
      _collaborationAdapter.applyRemoteScene(
        nextScene,
        closeTransientUi: false,
      );
      sw.stop();
      CollaborationDebugLog.write('metrics', 'remote_apply_latency_ms', {
        'ms': sw.elapsedMilliseconds,
        'elements': remoteScene.elements.length,
      });
      CollaborationDebugLog.write('scene', 'remote_scene_applied', {
        'remote': remoteScene.elements.length,
        'localBefore': localScene?.elements.length ?? 0,
        'localAfter': nextScene.elements.length,
        'protected': protectedElementIds.length,
        'filesLoaded': 0,
        'sceneVersion': CollaborationDebugLog.sceneVersion(nextScene.elements),
        'summary': CollaborationDebugLog.elementSummary(nextScene.elements),
      });
    } finally {
      _applyingRemoteScene = false;
    }

    // Phase 0: 远端应用不直接写 SQLite — 由 onSceneChanged remoteApply 分支的
    // _scheduleLocalDraft() 统一管理，500ms debounce 后通过 _flushLocalDraft 批量持久化。
    if (widget.temporaryCollaboration) {
      if (_canMutateWhiteboard) {
        ref.read(whiteboardViewModelProvider.notifier).markSaved();
      }
      return;
    }
  }

  Future<void> _touchNoteWithCurrentCover(String noteId) async {
    final coverThumbnailBytes = await _markdrawController
        .exportCoverThumbnail();
    await ref
        .read(libraryIndexProvider.notifier)
        .touchNote(
          noteId,
          coverThumbnailBytes: coverThumbnailBytes,
          clearCoverThumbnail: coverThumbnailBytes == null,
        );
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
    final themePreset = ref.watch(themeViewModelProvider);
    final effectivePreset = effectiveAppThemePreset(
      themePreset,
      MediaQuery.platformBrightnessOf(context),
    );
    final identity = ref.watch(accountViewModelProvider).collaborationIdentity;
    final participants = state.collaborating
        ? _collaborationParticipantBadges(state, identity)
        : const <CollaborationParticipantBadge>[];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        if (widget.temporaryCollaboration) {
          unawaited(_leaveCollaboration());
        } else {
          unawaited(_handleBack());
        }
      },
      child: Scaffold(
        backgroundColor: effectivePreset.backgroundEnd,
        body: SafeArea(
          child: MarkdrawEditor(
            controller: _markdrawController,
            config: const MarkdrawEditorConfig(),
            currentThemeMode: themePreset.themeMode,
            onThemeModeChanged: _changeThemeMode,
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
            collaboratorCount: participants.isEmpty
                ? state.collaborators.length
                : participants.length,
            collaborators: _remoteCollaboratorOverlays(state),
            collaborationParticipants: participants,
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
            onShare: () {
              unawaited(_shareCurrentWhiteboard());
            },
            onExportSvg: () {
              unawaited(_fileHandler.exportSvg());
            },
            onExportSmartMarkdown: () {
              unawaited(
                _fileHandler.exportSmartLayout(
                  SmartLayoutExportFormat.markdown,
                ),
              );
            },
            onExportSmartLatex: () {
              unawaited(
                _fileHandler.exportSmartLayout(SmartLayoutExportFormat.latex),
              );
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
            onShareCollaboration: _shareCollaborationInvitation,
            onPointerPresence: _broadcastPointerPresence,
            onVisibleSceneBoundsChanged: _broadcastVisibleSceneBounds,
            onDocumentRenamed: () {
              unawaited(_renameAndSaveDocument());
            },
            onRecognizeInk: (request) =>
                ref.read(inkRecognitionRepositoryProvider).recognize(request),
            onSmartLayoutInk: (request) =>
                ref.read(inkRecognitionRepositoryProvider).smartLayout(request),
            onLiveFreedrawChanged: state.collaborating
                ? _broadcastLiveFreedraw
                : null,
            onSceneChanged: (editorScene, SceneChangeSource source) {
              switch (source) {
                case SceneChangeSource.undo:
                case SceneChangeSource.redo:
                  unawaited(
                    _broadcastUndoRedoScene(
                      _previousEditorScene,
                      _collaborationAdapter.currentScene(),
                    ),
                  );
                  _scheduleLocalDraft();
                  _previousEditorScene = editorScene;
                  break;
                case SceneChangeSource.remoteApply:
                  _scheduleLocalDraft();
                  _previousEditorScene = editorScene;
                  break;
                case SceneChangeSource.userEdit:
                case SceneChangeSource.restore:
                  final changedElements =
                      _markdrawController.lastChangedElements;
                  if (changedElements == null) {
                    unawaited(_saveMarkdrawScene());
                  } else {
                    unawaited(_broadcastChangedElements(changedElements));
                    _scheduleLocalDraft();
                  }
                  _previousEditorScene = editorScene;
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _changeThemeMode(ThemeMode mode) {
    return ref
        .read(themeViewModelProvider.notifier)
        .changePreset(appThemePresetByThemeMode(mode));
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

  List<CollaborationParticipantBadge> _collaborationParticipantBadges(
    WhiteboardState state,
    CollaborationIdentity identity,
  ) {
    return [
      CollaborationParticipantBadge(
        username: identity.username,
        avatarUrl: identity.avatarUrl,
        isCurrentUser: true,
      ),
      for (final presence in state.collaborators.values)
        CollaborationParticipantBadge(
          username: presence.username,
          avatarUrl: presence.avatarUrl,
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

  DateTime _lastPointerBroadcast = DateTime.now();
  static const Duration _pointerThrottle = Duration(milliseconds: 33);
  Timer? _pointerTrailingTimer;
  Offset? _lastPointerPosition;
  bool _lastPointerDown = false;

  void _broadcastPointerPresence(Offset localPosition, bool pointerDown) {
    if (!_canMutateWhiteboard) {
      return;
    }
    _markUserActive();

    _lastPointerPosition = localPosition;
    _lastPointerDown = pointerDown;

    final sinceLast = DateTime.now().difference(_lastPointerBroadcast);
    if (sinceLast >= _pointerThrottle) {
      _doBroadcastPointerPresence(localPosition, pointerDown);
      _pointerTrailingTimer?.cancel();
      _pointerTrailingTimer = null;
    } else {
      _pointerTrailingTimer ??= Timer(
        _pointerThrottle - sinceLast,
        _flushTrailingPointer,
      );
    }
  }

  void _flushTrailingPointer() {
    _pointerTrailingTimer = null;
    if (_lastPointerPosition != null) {
      _doBroadcastPointerPresence(_lastPointerPosition!, _lastPointerDown);
    }
  }

  void _doBroadcastPointerPresence(Offset localPosition, bool pointerDown) {
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    _lastPointerBroadcast = DateTime.now();
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
      pageFlow: _pageFlowForNote(note?.pageFlow),
    );
  }

  CanvasPageTemplate _templateForNote(PageTemplate? template) {
    return switch (template) {
      PageTemplate.narrowLine => CanvasPageTemplate.narrowLine,
      PageTemplate.wideLine => CanvasPageTemplate.wideLine,
      PageTemplate.grid => CanvasPageTemplate.grid,
      PageTemplate.dotGrid => CanvasPageTemplate.dotGrid,
      PageTemplate.tianGrid => CanvasPageTemplate.tianGrid,
      PageTemplate.miGrid => CanvasPageTemplate.miGrid,
      PageTemplate.narrowVerticalLine => CanvasPageTemplate.narrowVerticalLine,
      PageTemplate.wideVerticalLine => CanvasPageTemplate.wideVerticalLine,
      PageTemplate.fourLineGrid => CanvasPageTemplate.fourLineGrid,
      PageTemplate.ancientBook => CanvasPageTemplate.ancientBook,
      PageTemplate.blank || null => CanvasPageTemplate.blank,
    };
  }

  CanvasPageFlow _pageFlowForNote(PageFlow? pageFlow) {
    return switch (pageFlow) {
      PageFlow.rightToLeft => CanvasPageFlow.rightToLeft,
      PageFlow.topToBottom || null => CanvasPageFlow.topToBottom,
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
