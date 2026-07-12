library;

import 'package:flutter/material.dart' hide Element, SelectionOverlay;
import 'package:flutter/services.dart';

import 'package:flow_muse/features/account/widgets/account_avatar.dart';
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
    this.onShare,
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
    this.collaborationParticipants = const [],
    this.isCollaborationOwner = false,
    this.onStartCollaboration,
    this.onJoinCollaboration,
    this.onLeaveCollaboration,
    this.onEndCollaboration,
    this.onPointerPresence,
    this.onVisibleSceneBoundsChanged,
    this.onDocumentRenamed,
    this.onRecognizeInk,
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
  final VoidCallback? onShare;
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
  final List<CollaborationParticipantBadge> collaborationParticipants;
  final bool isCollaborationOwner;
  final Future<void> Function()? onStartCollaboration;
  final Future<void> Function()? onJoinCollaboration;
  final Future<void> Function()? onLeaveCollaboration;
  final Future<void> Function()? onEndCollaboration;
  final void Function(Offset localPosition, bool pointerDown)?
  onPointerPresence;
  final void Function(Size canvasSize)? onVisibleSceneBoundsChanged;
  final VoidCallback? onDocumentRenamed;
  final Future<InkRecognitionResult> Function(InkRecognitionRequest)?
  onRecognizeInk;

  @override
  State<MarkdrawEditor> createState() => _MarkdrawEditorState();
}

class CollaborationParticipantBadge {
  const CollaborationParticipantBadge({
    required this.username,
    this.avatarUrl = '',
    this.isCurrentUser = false,
    this.idle = false,
  });

  final String username;
  final String avatarUrl;
  final bool isCurrentUser;
  final bool idle;
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
    _controller.onRecognizeInk = widget.onRecognizeInk;
    _controller.restoreKeyboardFocusWhenStable();
  }

  @override
  void didUpdateWidget(MarkdrawEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      _controller.addListener(_onControllerChanged);
      _controller.onSceneChanged = widget.onSceneChanged;
      _controller.onRecognizeInk = widget.onRecognizeInk;
    } else if (widget.onRecognizeInk != oldWidget.onRecognizeInk) {
      _controller.onRecognizeInk = widget.onRecognizeInk;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _ownController?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
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
                runWhenUiStable(() {
                  if (mounted) {
                    _controller.isCompact = isCompact;
                  }
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
              onShare: widget.onShare,
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
              collaborationParticipants: widget.collaborationParticipants,
              isCollaborationOwner: widget.isCollaborationOwner,
              onStartCollaboration: widget.onStartCollaboration,
              onJoinCollaboration: widget.onJoinCollaboration,
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
    required this.onShare,
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
  final VoidCallback? onShare;
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
                  onShare: onShare,
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
                  onShare: onShare,
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
    required this.collaborationParticipants,
    required this.isCollaborationOwner,
    required this.onStartCollaboration,
    required this.onJoinCollaboration,
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
  final List<CollaborationParticipantBadge> collaborationParticipants;
  final bool isCollaborationOwner;
  final Future<void> Function()? onStartCollaboration;
  final Future<void> Function()? onJoinCollaboration;
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
          if (collaborating && collaborationParticipants.isNotEmpty) ...[
            _ParticipantAvatarStack(participants: collaborationParticipants),
            const SizedBox(width: 8),
          ],
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
              onJoin: onJoinCollaboration,
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

class _ParticipantAvatarStack extends StatelessWidget {
  const _ParticipantAvatarStack({required this.participants});

  static const _avatarSize = 26.0;
  static const _avatarRadius = 11.0;
  static const _overlapStep = 18.0;
  static const _maxVisible = 5;

  final List<CollaborationParticipantBadge> participants;

  @override
  Widget build(BuildContext context) {
    final visible = participants.take(_maxVisible).toList();
    final hiddenCount = participants.length - visible.length;
    final itemCount = visible.length + (hiddenCount > 0 ? 1 : 0);
    final width = itemCount <= 1
        ? _avatarSize
        : _avatarSize + (itemCount - 1) * _overlapStep;

    return Tooltip(
      message: participants
          .map((participant) {
            final name = participant.username.isEmpty
                ? '匿名协作者'
                : participant.username;
            return participant.isCurrentUser ? '$name（我）' : name;
          })
          .join('、'),
      child: SizedBox(
        width: width,
        height: 44,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            for (var index = 0; index < visible.length; index++)
              Positioned(
                left: index * _overlapStep,
                child: _ParticipantAvatar(participant: visible[index]),
              ),
            if (hiddenCount > 0)
              Positioned(
                left: visible.length * _overlapStep,
                child: _ParticipantOverflowAvatar(count: hiddenCount),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantAvatar extends StatelessWidget {
  const _ParticipantAvatar({required this.participant});

  final CollaborationParticipantBadge participant;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = participant.isCurrentUser
        ? cs.primary
        : cs.surfaceContainerHighest;
    final label = participant.username.isEmpty ? '协' : participant.username;

    return Opacity(
      opacity: participant.idle ? 0.56 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: AccountAvatar(
            label: label,
            avatarUrl: participant.avatarUrl,
            radius: _ParticipantAvatarStack._avatarRadius,
          ),
        ),
      ),
    );
  }
}

class _ParticipantOverflowAvatar extends StatelessWidget {
  const _ParticipantOverflowAvatar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: _ParticipantAvatarStack._avatarSize,
      height: _ParticipantAvatarStack._avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surface,
        border: Border.all(color: cs.surfaceContainerHighest, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        '+$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
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
    required this.onJoin,
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
  final Future<void> Function()? onJoin;
  final Future<void> Function() onLeave;
  final Future<void> Function()? onEnd;

  @override
  State<_CollaborationChip> createState() => _CollaborationChipState();
}

class _CollaborationChipState extends State<_CollaborationChip> {
  @override
  Widget build(BuildContext context) {
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
    return FilledButton.icon(
      onPressed: () => _showCollaborationMenu(context, label),
      icon: Icon(
        widget.collaborating ? Icons.sensors : Icons.add_link,
        size: 18,
      ),
      label: widget.compact ? const SizedBox.shrink() : Text(label),
      style: FilledButton.styleFrom(
        minimumSize: widget.compact ? const Size(44, 44) : const Size(0, 44),
        padding: widget.compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _showCollaborationMenu(
    BuildContext anchorContext,
    String label,
  ) async {
    final selected = await showAnchoredPopupMenu<_CollaborationAction>(
      context: anchorContext,
      items: [
        PopupMenuItem<_CollaborationAction>(
          enabled: false,
          child: _CollaborationMenuHeader(
            title: widget.connecting
                ? label
                : widget.error != null
                ? '协作失败'
                : widget.collaborating
                ? label
                : '本地白板',
            error: widget.error,
            roomText: widget.roomLink ?? widget.roomValue,
            shareOriginConfigured: widget.shareOriginConfigured,
            usesRoomCode: widget.roomLink == null,
          ),
        ),
        if (widget.roomLink != null || widget.roomValue != null)
          PopupMenuItem<_CollaborationAction>(
            value: _CollaborationAction.copy,
            child: ListTile(
              leading: const Icon(Icons.copy),
              title: Text(widget.roomLink == null ? '复制房间码' : '复制链接'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem<_CollaborationAction>(
          enabled: !widget.connecting,
          value: widget.collaborating
              ? _CollaborationAction.leave
              : _CollaborationAction.start,
          child: ListTile(
            leading: Icon(widget.collaborating ? Icons.logout : Icons.link),
            title: Text(widget.collaborating ? '退出房间' : '创建房间'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (!widget.collaborating && widget.onJoin != null)
          PopupMenuItem<_CollaborationAction>(
            enabled: !widget.connecting,
            value: _CollaborationAction.join,
            child: const ListTile(
              leading: Icon(Icons.login),
              title: Text('加入房间'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (widget.collaborating && widget.isOwner && widget.onEnd != null)
          PopupMenuItem<_CollaborationAction>(
            enabled: !widget.connecting,
            value: _CollaborationAction.end,
            child: ListTile(
              leading: Icon(
                Icons.stop_circle,
                color: Theme.of(anchorContext).colorScheme.error,
              ),
              title: Text(
                '结束协作',
                style: TextStyle(
                  color: Theme.of(anchorContext).colorScheme.error,
                ),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
    if (selected == null || !anchorContext.mounted) {
      return;
    }
    switch (selected) {
      case _CollaborationAction.copy:
        await Clipboard.setData(
          ClipboardData(text: widget.roomLink ?? widget.roomValue!),
        );
        if (!anchorContext.mounted) {
          return;
        }
        ScaffoldMessenger.of(anchorContext).showSnackBar(
          SnackBar(
            content: Text(widget.roomLink == null ? '房间码已复制' : '房间链接已复制'),
          ),
        );
      case _CollaborationAction.start:
        runAfterUiTeardown(widget.onStart);
      case _CollaborationAction.join:
        final onJoin = widget.onJoin;
        if (onJoin != null) {
          runAfterUiTeardown(onJoin);
        }
      case _CollaborationAction.leave:
        runAfterUiTeardown(widget.onLeave);
      case _CollaborationAction.end:
        final onEnd = widget.onEnd;
        if (onEnd != null) {
          runAfterUiTeardown(onEnd);
        }
    }
  }
}

enum _CollaborationAction { copy, start, join, leave, end }

class _CollaborationMenuHeader extends StatelessWidget {
  const _CollaborationMenuHeader({
    required this.title,
    required this.error,
    required this.roomText,
    required this.shareOriginConfigured,
    required this.usesRoomCode,
  });

  final String title;
  final String? error;
  final String? roomText;
  final bool shareOriginConfigured;
  final bool usesRoomCode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(color: cs.error, fontSize: 12, height: 1.25),
            ),
          ],
          if (roomText != null) ...[
            if (!shareOriginConfigured && usesRoomCode) ...[
              const SizedBox(height: 8),
              Text(
                '分享地址未配置，请复制房间码加入',
                style: TextStyle(color: cs.error, fontSize: 12, height: 1.25),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              roomText!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
