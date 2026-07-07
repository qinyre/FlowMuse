import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide Element, SelectionOverlay, TextAlign;

import '../collaboration/models/collaboration_message.dart';
import '../collaboration/repositories/collaboration_repository.dart';
import '../view_models/whiteboard_view_model.dart';

class WhiteboardPage extends ConsumerStatefulWidget {
  const WhiteboardPage({
    super.key,
    required this.notebookId,
    required this.title,
  });

  final String notebookId;
  final String title;

  @override
  ConsumerState<WhiteboardPage> createState() => _WhiteboardPageState();
}

class _WhiteboardPageState extends ConsumerState<WhiteboardPage> {
  late final MarkdrawController _markdrawController;
  late final CollaborationRepository _collaborationRepository;
  StreamSubscription<CollaborationMessage>? _collaborationSubscription;
  bool _loadingScene = false;
  bool _applyingRemoteScene = false;

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
    if (oldWidget.notebookId != widget.notebookId ||
        oldWidget.title != widget.title) {
      Future.microtask(_openNotebook);
    }
  }

  @override
  void dispose() {
    unawaited(_collaborationSubscription?.cancel());
    unawaited(_collaborationRepository.stop());
    _markdrawController.dispose();
    super.dispose();
  }

  Future<void> _openNotebook() async {
    await ref
        .read(whiteboardViewModelProvider.notifier)
        .openNotebook(notebookId: widget.notebookId, title: widget.title);
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
    await _broadcastCurrentScene(content);
    if (!mounted) {
      return;
    }
    viewModel.markSaved();
  }

  Future<void> _startCollaboration() async {
    final initialElements = _currentSceneElements();
    await ref
        .read(whiteboardViewModelProvider.notifier)
        .startCollaboration(initialElements: initialElements);
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = _collaborationRepository
        .encryptedMessages(room)
        .listen(_handleCollaborationMessage);
  }

  Future<void> _stopCollaboration() async {
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = null;
    await ref.read(whiteboardViewModelProvider.notifier).stopCollaboration();
  }

  Future<void> _broadcastCurrentScene([String? serializedScene]) async {
    final room = ref.read(whiteboardViewModelProvider).activeRoom;
    if (room == null) {
      return;
    }
    final content =
        serializedScene ??
        _markdrawController.serializeScene(format: DocumentFormat.excalidraw);
    await _collaborationRepository.broadcastScene(
      room: room,
      elements: _extractElements(content),
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
    final decoded = jsonDecode(localContent) as Map<String, Object?>;
    final reconciled = _collaborationRepository.reconcileRemoteElements(
      localElements: _extractElements(localContent),
      remoteElements: remoteElements,
      protectedElementIds: _selectedElementIds(),
    );
    decoded['elements'] = reconciled;
    final nextContent = jsonEncode(decoded);

    _applyingRemoteScene = true;
    _markdrawController.applyRemoteContent(nextContent);
    _applyingRemoteScene = false;

    final repository = ref.read(whiteboardSceneRepositoryProvider);
    await repository.saveScene(widget.notebookId, nextContent);
    if (mounted) {
      ref.read(whiteboardViewModelProvider.notifier).markSaved();
    }
  }

  List<Map<String, Object?>> _currentSceneElements() {
    return _extractElements(
      _markdrawController.serializeScene(format: DocumentFormat.excalidraw),
    );
  }

  List<Map<String, Object?>> _extractElements(String content) {
    final decoded = jsonDecode(content) as Map<String, Object?>;
    final elements = decoded['elements'];
    if (elements is! List) {
      return const [];
    }
    return [
      for (final element in elements) Map<String, Object?>.from(element as Map),
    ];
  }

  Set<String> _selectedElementIds() {
    return _markdrawController.editorState.selectedIds
        .map((id) => id.value)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardViewModelProvider);

    return Scaffold(
      key: ValueKey(widget.notebookId),
      backgroundColor: const Color(0xFFFDFDFB),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: KeyedSubtree(
                key: const ValueKey('flowmuse-markdraw-editor'),
                child: MarkdrawEditor(
                  controller: _markdrawController,
                  config: const MarkdrawEditorConfig(
                    initialBackground: '#fdfdfb',
                  ),
                  onSceneChanged: (_) {
                    unawaited(_saveMarkdrawScene());
                  },
                ),
              ),
            ),
            Positioned(
              left: 24,
              top: 22,
              child: IconButton.filledTonal(
                tooltip: '返回',
                onPressed: () => context.pop(),
                icon: const Icon(LucideIcons.arrowLeft),
                style: IconButton.styleFrom(
                  fixedSize: const Size(56, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: const SizedBox.shrink(),
            ),
            Positioned(
              right: 24,
              top: 22,
              child: _CollaborationPanel(
                collaborating: state.collaborating,
                roomLink: state.roomLink,
                onStart: _startCollaboration,
                onStop: _stopCollaboration,
              ),
            ),
            Positioned(
              left: 92,
              top: 32,
              child: _BoardTitle(
                title: widget.title,
                saved: state.saveStatus == WhiteboardSaveStatus.saved,
              ),
            ),
            Positioned(left: 24, bottom: 24, child: const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class _BoardTitle extends StatelessWidget {
  const _BoardTitle({required this.title, required this.saved});

  final String title;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E8E5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.panelTop,
              color: Theme.of(context).colorScheme.primary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF2B302E),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              saved ? '已保存' : '保存中',
              style: const TextStyle(color: Color(0xFF8E9692), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollaborationPanel extends StatelessWidget {
  const _CollaborationPanel({
    required this.collaborating,
    required this.roomLink,
    required this.onStart,
    required this.onStop,
  });

  final bool collaborating;
  final String? roomLink;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E8E5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x145A625F),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    collaborating ? LucideIcons.radio : LucideIcons.radioTower,
                    color: collaborating
                        ? colorScheme.primary
                        : const Color(0xFF8E9692),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    collaborating ? '协作中' : '本地白板',
                    style: const TextStyle(
                      color: Color(0xFF2B302E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (roomLink != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  roomLink!,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Color(0xFF66706B),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: collaborating ? onStop : onStart,
                  icon: Icon(
                    collaborating ? LucideIcons.unlink : LucideIcons.link,
                    size: 18,
                  ),
                  label: Text(collaborating ? '停止协作' : '创建房间'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
