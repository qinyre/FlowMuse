library;

import 'package:flutter/material.dart' hide Element, SelectionOverlay;
import 'package:flutter/services.dart';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
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
    this.onBack,
    this.saveStatusLabel,
    this.collaborating = false,
    this.collaborationConnecting = false,
    this.collaborationError,
    this.collaborationStatusLabel,
    this.roomLink,
    this.roomValue,
    this.shareOriginConfigured = true,
    this.collaboratorCount = 0,
    this.collaborators = const [],
    this.isCollaborationOwner = false,
    this.onStartCollaboration,
    this.onLeaveCollaboration,
    this.onEndCollaboration,
    this.onPointerPresence,
    this.onVisibleSceneBoundsChanged,
    this.onDocumentRenamed,
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

  /// FlowMuse host chrome callbacks and state.
  final VoidCallback? onBack;
  final String? saveStatusLabel;
  final bool collaborating;
  final bool collaborationConnecting;
  final String? collaborationError;
  final String? collaborationStatusLabel;
  final String? roomLink;
  final String? roomValue;
  final bool shareOriginConfigured;
  final int collaboratorCount;
  final List<RemoteCollaboratorOverlay> collaborators;
  final bool isCollaborationOwner;
  final Future<void> Function()? onStartCollaboration;
  final Future<void> Function()? onLeaveCollaboration;
  final Future<void> Function()? onEndCollaboration;
  final void Function(Offset localPosition, bool pointerDown)?
  onPointerPresence;
  final void Function(Size canvasSize)? onVisibleSceneBoundsChanged;
  final VoidCallback? onDocumentRenamed;

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
    final topChromeOffset = isCompact ? 68.0 : 76.0;
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
                  return EditorCanvas(
                    controller: _controller,
                    collaborators: widget.collaborators,
                    onPointerPresence: widget.onPointerPresence,
                    onVisibleSceneBoundsChanged:
                        widget.onVisibleSceneBoundsChanged,
                  );
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
              left: 260,
              right: 300,
              child: Center(
                child: DesktopToolbar(
                  controller: _controller,
                  onImportImage: widget.onImportImage,
                  showMarkdownButton: widget.config.showMarkdownButton,
                ),
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
        if (showEditChrome)
          Positioned(
            top: 12,
            left: 12,
            child: _LeftChrome(
              controller: _controller,
              compact: isCompact,
              showMenu: widget.config.showMenu,
              onBack: widget.onBack,
              onOpen: widget.onOpen,
              onSave: widget.onSave,
              onSaveAs: widget.onSaveAs,
              onExportPng: widget.onExportPng,
              onExportSvg: widget.onExportSvg,
              onImportImage: widget.onImportImage,
              onImportLibrary: widget.onImportLibrary,
              onExportLibrary: widget.onExportLibrary,
              onThemeModeChanged: widget.onThemeModeChanged,
              currentThemeMode: widget.currentThemeMode,
              onDocumentRenamed: widget.onDocumentRenamed,
            ),
          ),
        if (showChrome)
          Positioned(
            top: 12,
            right: 12,
            child: _RightChrome(
              saveStatusLabel: widget.saveStatusLabel,
              collaborating: widget.collaborating,
              collaborationConnecting: widget.collaborationConnecting,
              collaborationError: widget.collaborationError,
              collaborationStatusLabel: widget.collaborationStatusLabel,
              roomLink: widget.roomLink,
              roomValue: widget.roomValue,
              shareOriginConfigured: widget.shareOriginConfigured,
              collaboratorCount: widget.collaboratorCount,
              isCollaborationOwner: widget.isCollaborationOwner,
              onStartCollaboration: widget.onStartCollaboration,
              onLeaveCollaboration: widget.onLeaveCollaboration,
              onEndCollaboration: widget.onEndCollaboration,
              viewMode: _controller.viewMode,
              zenMode: _controller.zenMode,
              onExitViewMode: _controller.toggleViewMode,
              onExitZenMode: _controller.toggleZenMode,
            ),
          ),
        // Floating property panel — desktop left side
        if (showEditChrome &&
            !isCompact &&
            widget.config.showPropertyPanel &&
            (_controller.selectedElements.isNotEmpty ||
                _controller.isCreationTool))
          Positioned(
            top: topChromeOffset,
            left: 12,
            bottom: 56,
            child: PropertyPanel(controller: _controller),
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
}

class _LeftChrome extends StatelessWidget {
  const _LeftChrome({
    required this.controller,
    required this.compact,
    required this.showMenu,
    required this.onBack,
    required this.onOpen,
    required this.onSave,
    required this.onSaveAs,
    required this.onExportPng,
    required this.onExportSvg,
    required this.onImportImage,
    required this.onImportLibrary,
    required this.onExportLibrary,
    required this.onThemeModeChanged,
    required this.currentThemeMode,
    required this.onDocumentRenamed,
  });

  final MarkdrawController controller;
  final bool compact;
  final bool showMenu;
  final VoidCallback? onBack;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;
  final VoidCallback? onSaveAs;
  final VoidCallback? onExportPng;
  final VoidCallback? onExportSvg;
  final VoidCallback? onImportImage;
  final VoidCallback? onImportLibrary;
  final VoidCallback? onExportLibrary;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ThemeMode? currentThemeMode;
  final VoidCallback? onDocumentRenamed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = controller.documentName?.trim().isNotEmpty == true
        ? controller.documentName!.trim()
        : '未命名白板';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onBack != null) ...[
          _ChromeIconButton(
            tooltip: '返回',
            icon: Icons.arrow_back,
            onPressed: onBack!,
          ),
          const SizedBox(width: 8),
        ],
        if (showMenu)
          compact
              ? CompactMenuButton(
                  controller: controller,
                  onOpen: onOpen,
                  onSave: onSave,
                  onSaveAs: onSaveAs,
                  onExportPng: onExportPng,
                  onExportSvg: onExportSvg,
                  onImportImage: onImportImage,
                  onShowLibrary: () => showCompactLibrary(
                    context,
                    controller,
                    onImportLibrary: onImportLibrary,
                    onExportLibrary: onExportLibrary,
                  ),
                  onThemeModeChanged: onThemeModeChanged,
                  currentThemeMode: currentThemeMode,
                  onDocumentRenamed: onDocumentRenamed,
                )
              : HamburgerMenu(
                  controller: controller,
                  onOpen: onOpen,
                  onSave: onSave,
                  onSaveAs: onSaveAs,
                  onExportPng: onExportPng,
                  onExportSvg: onExportSvg,
                  onImportImage: onImportImage,
                  onThemeModeChanged: onThemeModeChanged,
                  currentThemeMode: currentThemeMode,
                  onDocumentRenamed: onDocumentRenamed,
                ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Tooltip(
            message: '重命名',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => showRenameDocumentDialog(
                context,
                controller,
                onDocumentRenamed,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 168),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RightChrome extends StatelessWidget {
  const _RightChrome({
    required this.saveStatusLabel,
    required this.collaborating,
    required this.collaborationConnecting,
    required this.collaborationError,
    required this.collaborationStatusLabel,
    required this.roomLink,
    required this.roomValue,
    required this.shareOriginConfigured,
    required this.collaboratorCount,
    required this.isCollaborationOwner,
    required this.onStartCollaboration,
    required this.onLeaveCollaboration,
    required this.onEndCollaboration,
    required this.viewMode,
    required this.zenMode,
    required this.onExitViewMode,
    required this.onExitZenMode,
  });

  final String? saveStatusLabel;
  final bool collaborating;
  final bool collaborationConnecting;
  final String? collaborationError;
  final String? collaborationStatusLabel;
  final String? roomLink;
  final String? roomValue;
  final bool shareOriginConfigured;
  final int collaboratorCount;
  final bool isCollaborationOwner;
  final Future<void> Function()? onStartCollaboration;
  final Future<void> Function()? onLeaveCollaboration;
  final Future<void> Function()? onEndCollaboration;
  final bool viewMode;
  final bool zenMode;
  final VoidCallback onExitViewMode;
  final VoidCallback onExitZenMode;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final canCollaborate =
        onStartCollaboration != null && onLeaveCollaboration != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (viewMode)
          _StatusPill(label: '退出查看模式', onTap: onExitViewMode)
        else if (zenMode)
          _StatusPill(label: '退出专注模式', onTap: onExitZenMode)
        else ...[
          if (!compact && saveStatusLabel != null)
            _StatusPill(label: saveStatusLabel!),
          if (!compact && saveStatusLabel != null && canCollaborate)
            const SizedBox(width: 8),
          if (canCollaborate)
            _CollaborationChip(
              compact: compact,
              collaborating: collaborating,
              connecting: collaborationConnecting,
              error: collaborationError,
              statusLabel: collaborationStatusLabel,
              roomLink: roomLink,
              roomValue: roomValue,
              shareOriginConfigured: shareOriginConfigured,
              collaboratorCount: collaboratorCount,
              isOwner: isCollaborationOwner,
              onStart: onStartCollaboration!,
              onLeave: onLeaveCollaboration!,
              onEnd: onEndCollaboration,
            ),
        ],
      ],
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.17), blurRadius: 1),
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3),
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: onPressed,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (onTap == null) {
      return pill;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: pill,
    );
  }
}

class _CollaborationChip extends StatefulWidget {
  const _CollaborationChip({
    required this.compact,
    required this.collaborating,
    required this.connecting,
    required this.error,
    required this.statusLabel,
    required this.roomLink,
    required this.roomValue,
    required this.shareOriginConfigured,
    required this.collaboratorCount,
    required this.isOwner,
    required this.onStart,
    required this.onLeave,
    required this.onEnd,
  });

  final bool compact;
  final bool collaborating;
  final bool connecting;
  final String? error;
  final String? statusLabel;
  final String? roomLink;
  final String? roomValue;
  final bool shareOriginConfigured;
  final int collaboratorCount;
  final bool isOwner;
  final Future<void> Function() onStart;
  final Future<void> Function() onLeave;
  final Future<void> Function()? onEnd;

  @override
  State<_CollaborationChip> createState() => _CollaborationChipState();
}

class _CollaborationChipState extends State<_CollaborationChip> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label =
        widget.statusLabel ??
        (widget.connecting
            ? '连接中'
            : widget.error != null
            ? '协作失败'
            : widget.collaborating
            ? (widget.collaboratorCount > 0
                  ? '协作中 ${widget.collaboratorCount}'
                  : '协作中')
            : '创建房间');
    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            widget.connecting
                ? label
                : widget.error != null
                ? '协作失败'
                : widget.collaborating
                ? label
                : '本地白板',
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
          ),
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                widget.error!,
                style: TextStyle(color: cs.error, fontSize: 12, height: 1.25),
              ),
            ),
          ),
        if (widget.roomLink != null || widget.roomValue != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.shareOriginConfigured && widget.roomValue != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '分享地址未配置，请复制房间码加入',
                        style: TextStyle(
                          color: cs.error,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                  SelectableText(
                    widget.roomLink ?? widget.roomValue!,
                    maxLines: 3,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (widget.roomLink != null || widget.roomValue != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.roomLink ?? widget.roomValue!),
              );
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(widget.roomLink == null ? '房间码已复制' : '房间链接已复制'),
                ),
              );
            },
            child: Text(widget.roomLink == null ? '复制房间码' : '复制链接'),
          ),
        MenuItemButton(
          leadingIcon: Icon(widget.collaborating ? Icons.logout : Icons.link),
          onPressed: widget.connecting
              ? null
              : widget.collaborating
              ? () => runAfterUiFrame(widget.onLeave)
              : () => runAfterUiFrame(widget.onStart),
          child: Text(widget.collaborating ? '退出房间' : '创建房间'),
        ),
        if (widget.collaborating && widget.isOwner && widget.onEnd != null)
          MenuItemButton(
            leadingIcon: Icon(Icons.stop_circle, color: cs.error),
            onPressed: widget.connecting
                ? null
                : () => runAfterUiFrame(widget.onEnd!),
            child: Text('结束协作', style: TextStyle(color: cs.error)),
          ),
      ],
      builder: (context, controller, child) {
        return FilledButton.icon(
          onPressed: () {
            controller.isOpen ? controller.close() : controller.open();
          },
          icon: Icon(
            widget.collaborating ? Icons.sensors : Icons.add_link,
            size: 18,
          ),
          label: widget.compact ? const SizedBox.shrink() : Text(label),
          style: FilledButton.styleFrom(
            minimumSize: widget.compact
                ? const Size(44, 44)
                : const Size(0, 44),
            padding: widget.compact
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }
}
