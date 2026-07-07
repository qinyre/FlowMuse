library;

import 'package:flutter/material.dart' hide Element, SelectionOverlay;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

/// A full-featured drawing editor widget.
///
/// Composes canvas, toolbar, property panel, zoom controls, help button,
/// library panel, and menus into a responsive layout.
///
/// File I/O is handled via callbacks, keeping platform code out of the library.
class MarkdrawEditor extends StatefulWidget {
  const MarkdrawEditor({
    super.key,
    this.controller,
    this.config = const MarkdrawEditorConfig(),
    this.onSave,
    this.onSaveAs,
    this.onOpen,
    this.onExportPng,
    this.onExportSvg,
    this.onImportImage,
    this.onImportLibrary,
    this.onExportLibrary,
    this.onThemeModeChanged,
    this.currentThemeMode,
    this.onSceneChanged,
  });

  /// Optional external controller. If null, one is created internally.
  final MarkdrawController? controller;

  /// Appearance and behavior configuration.
  final MarkdrawEditorConfig config;

  // File I/O callbacks — null = menu item hidden
  final VoidCallback? onSave;
  final VoidCallback? onSaveAs;
  final VoidCallback? onOpen;
  final VoidCallback? onExportPng;
  final VoidCallback? onExportSvg;
  final VoidCallback? onImportImage;
  final VoidCallback? onImportLibrary;
  final VoidCallback? onExportLibrary;

  /// Theme — widget doesn't own ThemeMode, just shows buttons + calls back.
  final void Function(ThemeMode)? onThemeModeChanged;
  final ThemeMode? currentThemeMode;

  /// Called when the scene changes (for auto-save, etc.).
  final void Function(Scene)? onSceneChanged;

  @override
  State<MarkdrawEditor> createState() => _MarkdrawEditorState();
}

class _MarkdrawEditorState extends State<MarkdrawEditor> {
  MarkdrawController? _ownController;

  MarkdrawController get _controller =>
      widget.controller ??
      (_ownController ??= MarkdrawController(config: widget.config));

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _controller.onSceneChanged = widget.onSceneChanged;
    _controller.keyboardFocusNode.requestFocus();
  }

  @override
  void didUpdateWidget(MarkdrawEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      _controller.addListener(_onControllerChanged);
      _controller.onSceneChanged = widget.onSceneChanged;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _ownController?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  Size _getCanvasSize() => context.size ?? const Size(800, 600);

  void _noop() {}

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: buildShortcutBindings(
        onSave: widget.onSave ?? _noop,
        onSaveAs: widget.onSaveAs ?? _noop,
        onOpen: widget.onOpen ?? _noop,
        onUndo: _controller.undo,
        onRedo: _controller.redo,
        onExportPng: widget.onExportPng ?? _noop,
        onZoomIn: () => _controller.zoomIn(_getCanvasSize()),
        onZoomOut: () => _controller.zoomOut(_getCanvasSize()),
        onResetZoom: _controller.resetZoom,
        onFind: _controller.openFind,
      ),
      child: Focus(
        focusNode: _controller.keyboardFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          // Don't intercept keys when a descendant (e.g. markdown text pane)
          // has focus — only handle when the editor itself has primary focus.
          if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
          final handled = handleKeyEvent(
            event: event,
            controller: _controller,
            getCanvasSize: _getCanvasSize,
            onSave: widget.onSave ?? _noop,
            onSaveAs: widget.onSaveAs ?? _noop,
            onOpen: widget.onOpen ?? _noop,
            onExportPng: widget.onExportPng ?? _noop,
            onImportImage: widget.onImportImage ?? _noop,
            onThemeToggle: widget.onThemeModeChanged ?? (_) {},
            getCurrentThemeMode: () =>
                widget.currentThemeMode ?? ThemeMode.system,
            context: context,
            onShowLinkDialog: (_) => _controller.openLinkEditor(),
          );
          return handled ? KeyEventResult.handled : KeyEventResult.ignored;
        },
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact =
                  constraints.maxWidth < widget.config.compactBreakpoint;
              _controller.lastCanvasSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              if (isCompact != _controller.isCompact) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _controller.isCompact = isCompact;
                });
              }
              return _buildBody();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final isCompact = _controller.isCompact;
    final showChrome = !_controller.zenMode;
    final showEditChrome = showChrome && !_controller.viewMode;
    Widget body = Stack(
      children: [
        // Full-bleed canvas + desktop library panel
        Row(
          children: [
            Expanded(
              child: DragTarget<LibraryItem>(
                onAcceptWithDetails: (details) {
                  // Convert global drop position to local canvas position
                  final renderBox = context.findRenderObject() as RenderBox?;
                  if (renderBox == null) return;
                  final localPos = renderBox.globalToLocal(details.offset);
                  _controller.placeLibraryItemAt(details.data, localPos);
                },
                builder: (context, candidateData, rejectedData) {
                  return EditorCanvas(controller: _controller);
                },
              ),
            ),
            if (showChrome &&
                !isCompact &&
                _controller.showLibraryPanel &&
                widget.config.showLibraryPanel)
              LibraryPanel(
                controller: _controller,
                onImportLibrary: widget.onImportLibrary,
                onExportLibrary: widget.onExportLibrary,
              ),
          ],
        ),
        // Toolbar
        if (showEditChrome && widget.config.showToolbar) ...[
          if (isCompact)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(child: CompactToolbar(controller: _controller)),
            )
          else ...[
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: DesktopToolbar(
                  controller: _controller,
                  onImportImage: widget.onImportImage,
                  showMarkdownButton: widget.config.showMarkdownButton,
                ),
              ),
            ),
            // Scene name label — right of hamburger menu, behind toolbar
            Positioned(
              top: 23,
              left: 60,
              child: GestureDetector(
                onTap: () => showRenameDocumentDialog(context, _controller),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Builder(
                    builder: (context) {
                      final canvasBg = parseColor(
                        _controller.canvasBackgroundColor,
                      );
                      final textColor = canvasBg.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white;
                      return Text(
                        _controller.documentName ?? '未命名',
                        style: TextStyle(
                          fontSize: 16,
                          color: _controller.documentName != null
                              ? textColor.withValues(alpha: 0.7)
                              : textColor.withValues(alpha: 0.3),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (widget.config.showMenu)
              Positioned(
                top: 12,
                left: 12,
                child: HamburgerMenu(
                  controller: _controller,
                  onOpen: widget.onOpen,
                  onSave: widget.onSave,
                  onSaveAs: widget.onSaveAs,
                  onExportPng: widget.onExportPng,
                  onExportSvg: widget.onExportSvg,
                  onImportImage: widget.onImportImage,
                  onThemeModeChanged: widget.onThemeModeChanged,
                  currentThemeMode: widget.currentThemeMode,
                ),
              ),
            if (widget.config.showZoomControls)
              Positioned(
                bottom: 12,
                left: 12,
                child: ZoomControls(
                  controller: _controller,
                  getCanvasSize: _getCanvasSize,
                ),
              ),
            if (widget.config.showHelpButton)
              const Positioned(bottom: 12, right: 12, child: HelpButton()),
          ],
        ],
        // Floating property panel — desktop left side
        if (showEditChrome &&
            !isCompact &&
            widget.config.showPropertyPanel &&
            (_controller.selectedElements.isNotEmpty ||
                _controller.isCreationTool))
          Positioned(
            top: 60,
            left: 12,
            bottom: 56,
            child: PropertyPanel(controller: _controller),
          ),
        // Compact menu button
        if (showEditChrome && isCompact && widget.config.showMenu)
          Positioned(
            top: 12,
            left: 12,
            child: CompactMenuButton(
              controller: _controller,
              onOpen: widget.onOpen,
              onSave: widget.onSave,
              onSaveAs: widget.onSaveAs,
              onExportPng: widget.onExportPng,
              onExportSvg: widget.onExportSvg,
              onImportImage: widget.onImportImage,
              onShowLibrary: widget.config.showLibraryPanel
                  ? () => showCompactLibrary(
                      context,
                      _controller,
                      onImportLibrary: widget.onImportLibrary,
                      onExportLibrary: widget.onExportLibrary,
                    )
                  : null,
              onThemeModeChanged: widget.onThemeModeChanged,
              currentThemeMode: widget.currentThemeMode,
            ),
          ),
        // Find overlay
        if (_controller.isFindOpen)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: FindOverlay(
                controller: _controller,
                getCanvasSize: _getCanvasSize,
              ),
            ),
          ),
        // Link overlay
        if (_controller.isLinkEditorOpen &&
            _controller.selectedElements.length == 1)
          _buildLinkOverlay(),
        // View mode indicator — click to exit
        if (_controller.viewMode)
          Positioned(
            top: 12,
            right: 12,
            child: _modePill(
              context,
              label: '退出查看模式',
              onTap: _controller.toggleViewMode,
            ),
          ),
        // Zen mode indicator — click to exit
        if (_controller.zenMode && !_controller.viewMode)
          Positioned(
            top: 12,
            right: 12,
            child: _modePill(
              context,
              label: '退出专注模式',
              onTap: _controller.toggleZenMode,
            ),
          ),
      ],
    );
    if (!isCompact && _controller.showMarkdownPanel) {
      body = MarkdrawSplitPane(controller: _controller, child: body);
    }
    return body;
  }

  Widget _buildLinkOverlay() {
    final elements = _controller.selectedElements;
    if (elements.isEmpty) return const SizedBox.shrink();
    final element = elements.first;
    final viewport = _controller.editorState.viewport;

    // Position the overlay above the selected element, centered horizontally
    final topLeft = viewport.sceneToScreen(Offset(element.x, element.y));
    final bottomRight = viewport.sceneToScreen(
      Offset(element.x + element.width, element.y + element.height),
    );
    final centerX = (topLeft.dx + bottomRight.dx) / 2;
    final top = topLeft.dy - 54; // above the element

    return Positioned(
      left: (centerX - 170).clamp(8.0, double.infinity),
      top: top.clamp(8.0, double.infinity),
      child: LinkOverlay(
        controller: _controller,
        getCanvasSize: _getCanvasSize,
      ),
    );
  }

  Widget _modePill(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
