import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../view_models/whiteboard_view_model.dart';
import '../widgets/whiteboard_canvas.dart';
import '../widgets/whiteboard_toolbar.dart';
import '../widgets/zoom_controls.dart';

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
  @override
  void initState() {
    super.initState();
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

  Future<void> _openNotebook() async {
    await ref
        .read(whiteboardViewModelProvider.notifier)
        .openNotebook(notebookId: widget.notebookId, title: widget.title);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardViewModelProvider);
    final viewModel = ref.read(whiteboardViewModelProvider.notifier);

    return Scaffold(
      key: ValueKey(widget.notebookId),
      backgroundColor: const Color(0xFFFDFDFB),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: WhiteboardCanvas(
                state: state,
                onDragComplete: viewModel.addElementFromDrag,
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
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: WhiteboardToolbar(
                  activeTool: state.activeTool,
                  canUndo: state.canUndo,
                  canRedo: state.canRedo,
                  onToolSelected: viewModel.selectTool,
                  onUndo: viewModel.undo,
                  onRedo: viewModel.redo,
                ),
              ),
            ),
            Positioned(
              right: 24,
              top: 22,
              child: _CollaborationPanel(
                collaborating: state.collaborating,
                roomLink: state.roomLink,
                onStart: viewModel.startCollaboration,
                onStop: viewModel.stopCollaboration,
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
            Positioned(
              left: 24,
              bottom: 24,
              child: ZoomControls(
                zoom: state.zoom,
                onZoomIn: viewModel.zoomIn,
                onZoomOut: viewModel.zoomOut,
                onResetZoom: viewModel.resetZoom,
              ),
            ),
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
