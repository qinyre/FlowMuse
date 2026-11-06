import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../library/models/note_item.dart';
import '../editor_core/flow_muse_whiteboard_editor.dart' hide TextAlign;
import '../editor_core/src/rendering/page_reading_position.dart';
import '../editor_core/src/ui/page_navigation_controls.dart';
import '../editor_core/src/ui/page_overview.dart';
import '../models/local_note_layout.dart';
import '../pdf_note_import/pdf_note_consumer.dart';

class NoteSplitWorkspace extends StatefulWidget {
  const NoteSplitWorkspace({
    super.key,
    required this.reference,
    required this.loadScene,
    required this.onReplace,
    required this.onClose,
    required this.child,
  });

  final NoteItem? reference;
  final Future<String> Function(String noteId) loadScene;
  final VoidCallback onReplace;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<NoteSplitWorkspace> createState() => _NoteSplitWorkspaceState();
}

typedef _ReferencePosition = (PageReadingPosition?, ViewportState);

class _NoteSplitWorkspaceState extends State<NoteSplitWorkspace> {
  static const _splitMinWidth = 800.0;
  static const _paneMinWidth = 300.0;
  static const _dividerWidth = 20.0;
  final _positions = <String, _ReferencePosition>{};
  double _referenceShare = 0.44;
  bool _referenceOnLeft = true;
  bool _showReference = false;

  @override
  void didUpdateWidget(covariant NoteSplitWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference?.id != widget.reference?.id) {
      _showReference = widget.reference != null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = widget.reference;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final split = reference != null && width >= _splitMinWidth;
        final compact = reference != null && !split;
        final available = width - _dividerWidth;
        final referenceWidth = split
            ? (available * _referenceShare).clamp(
                _paneMinWidth,
                available - _paneMinWidth,
              )
            : width;
        final mainWidth = split ? available - referenceWidth : width;
        final dividerLeft = _referenceOnLeft ? referenceWidth : mainWidth;
        void resize(double delta) {
          final next = referenceWidth + (_referenceOnLeft ? delta : -delta);
          setState(() {
            _referenceShare =
                next.clamp(_paneMinWidth, available - _paneMinWidth) /
                available;
          });
        }

        return Column(
          children: [
            if (compact)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('主笔记')),
                    ButtonSegment(value: true, label: Text('参考笔记')),
                  ],
                  selected: {_showReference},
                  onSelectionChanged: (values) {
                    setState(() => _showReference = values.single);
                  },
                ),
              ),
            Expanded(
              key: const ValueKey('note-split-canvas'),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: split && _referenceOnLeft
                        ? referenceWidth + _dividerWidth
                        : 0,
                    width: mainWidth,
                    child: _pane(
                      hidden: compact && _showReference,
                      child: widget.child,
                    ),
                  ),
                  if (reference != null)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: split && !_referenceOnLeft
                          ? mainWidth + _dividerWidth
                          : 0,
                      width: referenceWidth,
                      child: _pane(
                        hidden: compact && !_showReference,
                        child: _ReferenceNotePane(
                          key: ValueKey(reference.id),
                          note: reference,
                          loadScene: widget.loadScene,
                          savedPosition: _positions[reference.id],
                          rememberPosition: (position) =>
                              _positions[reference.id] = position,
                          onReplace: widget.onReplace,
                          onSwap: split
                              ? () => setState(
                                  () => _referenceOnLeft = !_referenceOnLeft,
                                )
                              : null,
                          onClose: widget.onClose,
                        ),
                      ),
                    ),
                  if (split)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: dividerLeft,
                      width: _dividerWidth,
                      child: _SplitDivider(onResize: resize),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pane({required bool hidden, required Widget child}) => Offstage(
    offstage: hidden,
    child: TickerMode(
      enabled: !hidden,
      child: ExcludeFocus(
        excluding: hidden,
        child: ClipRect(child: child),
      ),
    ),
  );
}

class _SplitDivider extends StatefulWidget {
  const _SplitDivider({required this.onResize});

  final ValueChanged<double> onResize;

  @override
  State<_SplitDivider> createState() => _SplitDividerState();
}

class _SplitDividerState extends State<_SplitDivider> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '调整两栏宽度',
      onIncrease: () => widget.onResize(24),
      onDecrease: () => widget.onResize(-24),
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onResize(-24);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onResize(24);
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (event) =>
                widget.onResize(event.primaryDelta ?? 0),
            child: ColoredBox(
              color: colors.surfaceContainerLow,
              child: Center(
                child: Container(
                  width: 4,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _focused ? colors.primary : colors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferenceNotePane extends StatefulWidget {
  const _ReferenceNotePane({
    super.key,
    required this.note,
    required this.loadScene,
    required this.savedPosition,
    required this.rememberPosition,
    required this.onReplace,
    required this.onSwap,
    required this.onClose,
  });

  final NoteItem note;
  final Future<String> Function(String) loadScene;
  final _ReferencePosition? savedPosition;
  final ValueChanged<_ReferencePosition> rememberPosition;
  final VoidCallback onReplace;
  final VoidCallback? onSwap;
  final VoidCallback onClose;

  @override
  State<_ReferenceNotePane> createState() => _ReferenceNotePaneState();
}

class _ReferenceNotePaneState extends State<_ReferenceNotePane> {
  final _focus = FocusNode(debugLabel: 'Reference note');
  final _controller = MarkdrawController()..toggleViewMode();
  bool _loaded = false;
  bool _failed = false;
  bool _initializedViewport = false;
  bool _showOverview = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final note = widget.note;
      final content = await widget.loadScene(note.id);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final surface = Theme.of(context).colorScheme.surface;
      _controller
        ..setThemeCanvasBackground(
          '#${surface.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
        )
        ..setLayout(layoutForLocalNote(note))
        ..loadFromContent(content, '${note.id}.excalidraw');
      if (note.kind == LibraryFilter.pdf) {
        _controller.contentBounds = PdfNoteConsumer.pdfBackgroundBounds(
          _controller.currentScene,
        );
      }
      setState(() => _loaded = true);
    } catch (error) {
      debugPrint('[ReferenceNote] load failed: ${error.runtimeType}');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _restoreViewport(Size size) {
    if (!mounted || _initializedViewport || size.isEmpty) return;
    _initializedViewport = true;
    _controller.canvasSize = size;
    final saved = widget.savedPosition;
    final pages = _controller.layout.pages;
    if (saved != null) {
      _controller.setViewport(
        saved.$1?.restore(_controller.layout, size) ?? saved.$2,
      );
    } else if (pages.isNotEmpty) {
      _controller.navigateToPage(pages.first.id, fit: true);
    } else if (_controller.contentBounds != null) {
      _controller.setViewport(
        PdfNoteConsumer.fitFirstPageViewport(_controller.currentScene, size),
      );
    } else {
      _controller.zoomToFit(size);
    }
  }

  @override
  void dispose() {
    if (_initializedViewport) {
      widget.rememberPosition((
        _controller.captureReadingPosition(),
        _controller.editorState.viewport,
      ));
    }
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Focus(
        focusNode: _focus,
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: widget.note.title,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('参考 · 只读', style: theme.textTheme.labelSmall),
                          Text(
                            widget.note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '查找参考笔记中的文本',
                    onPressed: _loaded
                        ? () => setState(() {
                            _showOverview = false;
                            _controller.openFind();
                          })
                        : null,
                    icon: const Icon(Icons.search),
                  ),
                  PopupMenuButton<VoidCallback>(
                    tooltip: '参考笔记选项',
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: widget.onReplace,
                        child: const Text('更换参考笔记'),
                      ),
                      if (widget.onSwap != null)
                        PopupMenuItem(
                          value: widget.onSwap,
                          child: const Text('交换左右'),
                        ),
                    ],
                  ),
                  IconButton(
                    tooltip: '关闭参考笔记',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loaded
                  ? _buildCanvas()
                  : Center(
                      child: _failed
                          ? TextButton(
                              onPressed: () {
                                setState(() => _failed = false);
                                _load();
                              },
                              child: const Text('参考笔记加载失败，点击重试'),
                            )
                          : const CircularProgressIndicator(),
                    ),
            ),
            if (_loaded) ...[
              const Divider(height: 1),
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Wrap(
                    alignment: _controller.layout.pages.isEmpty
                        ? WrapAlignment.end
                        : WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_controller.layout.pages.isNotEmpty)
                        PageNavigationControls(
                          controller: _controller,
                          onOverview: () => setState(() {
                            _controller.closeFind();
                            _showOverview = !_showOverview;
                          }),
                        ),
                      ZoomControls(
                        controller: _controller,
                        getCanvasSize: () => _controller.canvasSize,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas() => LayoutBuilder(
    builder: (context, constraints) {
      if (!_initializedViewport) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreViewport(constraints.biggest),
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          EditorCanvas(
            controller: _controller,
            onUserInteraction: () => _focus.requestFocus(),
          ),
          if (_showOverview)
            PageOverview(
              controller: _controller,
              onClose: () => setState(() => _showOverview = false),
              onNavigate: () => setState(() => _showOverview = false),
            ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.isFindOpen
                ? Align(
                    alignment: Alignment.topCenter,
                    child: FindOverlay(
                      controller: _controller,
                      getCanvasSize: () => _controller.canvasSize,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    },
  );
}
