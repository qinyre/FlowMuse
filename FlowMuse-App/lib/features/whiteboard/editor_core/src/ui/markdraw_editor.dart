library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Element, SelectionOverlay;
import 'package:flutter/services.dart';

import 'package:flow_muse/features/account/widgets/account_avatar.dart';
import 'package:flow_muse/features/whiteboard/speech_recognition/models/speech_recognition_event.dart';
import 'package:flow_muse/features/whiteboard/speech_recognition/services/speech_recognition_service.dart';
import 'package:flow_muse/features/whiteboard/speech_recognition/services/speech_recognition_service_factory.dart';
import 'package:flow_muse/shared/storage/local_settings_repository.dart';
import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

import 'studio_rail_icon_button.dart';
import 'zoom_controls.dart';

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
    this.onExportSmartMarkdown,
    this.onExportSmartLatex,
    this.onShare,
    this.onImportImage,
    this.onImportLibrary,
    this.onExportLibrary,
    this.onThemeModeChanged,
    this.currentThemeMode,
    this.onSceneChanged,
    this.onLiveFreedrawChanged,
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
    this.onShareCollaboration,
    this.onPointerPresence,
    this.onVisibleSceneBoundsChanged,
    this.onDocumentRenamed,
    this.onRecognizeInk,
    this.onSmartLayoutInk,
    this.onRecognizeSmartLayoutBlock,
    this.onComposeSmartLayout,
    this.canvasThemeBackground = '#ffffff',
    this.useFlatBackgrounds = false,
    this.onEyedropperPressed,
    this.speechRecognitionService,
    this.fingerDrawingEnabled = false,
    this.onFingerDrawingEnabledChanged,
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
  final VoidCallback? onExportSmartMarkdown;
  final VoidCallback? onExportSmartLatex;
  final VoidCallback? onShare;
  final VoidCallback? onImportImage;
  final VoidCallback? onImportLibrary;
  final VoidCallback? onExportLibrary;

  /// Theme — widget doesn't own ThemeMode, just shows buttons + calls back.
  final void Function(ThemeMode)? onThemeModeChanged;
  final ThemeMode? currentThemeMode;

  /// Called when the scene changes (for auto-save, etc.).
  final void Function(Scene scene, SceneChangeSource source)? onSceneChanged;
  final void Function(FreedrawElement element)? onLiveFreedrawChanged;

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
  final Future<void> Function()? onShareCollaboration;
  final void Function(Offset localPosition, bool pointerDown)?
  onPointerPresence;
  final void Function(Size canvasSize)? onVisibleSceneBoundsChanged;
  final VoidCallback? onDocumentRenamed;
  final Future<InkRecognitionResult> Function(InkRecognitionRequest)?
  onRecognizeInk;
  final Future<SmartLayoutResponse> Function(SmartLayoutRequest)?
  onSmartLayoutInk;
  final Future<SmartLayoutRecognizedBlock> Function(SmartLayoutInkBlockRequest)?
  onRecognizeSmartLayoutBlock;
  final Future<SmartLayoutResponse> Function(SmartLayoutComposeRequest)?
  onComposeSmartLayout;
  final String canvasThemeBackground;
  final bool useFlatBackgrounds;
  final SpeechRecognitionService? speechRecognitionService;
  final bool fingerDrawingEnabled;
  final ValueChanged<bool>? onFingerDrawingEnabledChanged;

  /// Optional override for the eyedropper toolbar button.
  /// When provided (e.g. HarmonyOS), calling this replaces the canvas picker.
  final VoidCallback? onEyedropperPressed;

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

class _MarkdrawEditorState extends State<MarkdrawEditor>
    with WidgetsBindingObserver {
  static const _toolbarDockKey = 'whiteboard.toolbarDock.v1';
  static const _controlGroupPositionKey = 'whiteboard.controlGroupPosition.v1';
  static const _controlGroupReservedExtent = 120.0;
  static const _speechNoticeKey = 'whiteboard.speechRecognitionNoticeSeen.v1';

  MarkdrawController? _ownController;
  ToolbarDock _toolbarDock = ToolbarDock.top;
  ControlGroupPosition _controlGroupPosition = ControlGroupPosition.bottomLeft;
  bool _toolbarCollapsed = false;
  bool _propertyPanelCollapsed = false;
  String _propertyPanelContext = '';
  late final SpeechRecognitionService _speechService;
  StreamSubscription<SpeechRecognitionEvent>? _speechSubscription;
  SpeechRecognitionState _speechState = SpeechRecognitionState.idle;
  bool _speechAvailable = false;
  String _speechPreview = '';
  bool _speechFinalCommitted = false;

  MarkdrawController get _controller =>
      widget.controller ??
      (_ownController ??= MarkdrawController(config: widget.config));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speechService =
        widget.speechRecognitionService ?? createSpeechRecognitionService();
    _speechSubscription = _speechService.events.listen(_onSpeechEvent);
    unawaited(_checkSpeechAvailability());
    _controller.addListener(_onControllerChanged);
    _controller.onSceneChanged = widget.onSceneChanged;
    _controller.onLiveFreedrawChanged = widget.onLiveFreedrawChanged;
    _controller.onRecognizeInk = widget.onRecognizeInk;
    _controller.onSmartLayoutInk = widget.onSmartLayoutInk;
    _controller.onRecognizeSmartLayoutBlock =
        widget.onRecognizeSmartLayoutBlock;
    _controller.onComposeSmartLayout = widget.onComposeSmartLayout;
    _controller.setThemeCanvasBackground(widget.canvasThemeBackground);
    _controller.restoreKeyboardFocusWhenStable();
    unawaited(_restoreEditorChrome());
  }

  @override
  void didUpdateWidget(MarkdrawEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      _controller.addListener(_onControllerChanged);
      _controller.onSceneChanged = widget.onSceneChanged;
      _controller.onLiveFreedrawChanged = widget.onLiveFreedrawChanged;
      _controller.onRecognizeInk = widget.onRecognizeInk;
      _controller.onSmartLayoutInk = widget.onSmartLayoutInk;
      _controller.onRecognizeSmartLayoutBlock =
          widget.onRecognizeSmartLayoutBlock;
      _controller.onComposeSmartLayout = widget.onComposeSmartLayout;
      _controller.setThemeCanvasBackground(widget.canvasThemeBackground);
    } else if (widget.onRecognizeInk != oldWidget.onRecognizeInk) {
      _controller.onRecognizeInk = widget.onRecognizeInk;
    }
    if (widget.onLiveFreedrawChanged != oldWidget.onLiveFreedrawChanged) {
      _controller.onLiveFreedrawChanged = widget.onLiveFreedrawChanged;
    }
    if (widget.onSmartLayoutInk != oldWidget.onSmartLayoutInk) {
      _controller.onSmartLayoutInk = widget.onSmartLayoutInk;
    }
    if (widget.onRecognizeSmartLayoutBlock !=
        oldWidget.onRecognizeSmartLayoutBlock) {
      _controller.onRecognizeSmartLayoutBlock =
          widget.onRecognizeSmartLayoutBlock;
    }
    if (widget.onComposeSmartLayout != oldWidget.onComposeSmartLayout) {
      _controller.onComposeSmartLayout = widget.onComposeSmartLayout;
    }
    if (widget.canvasThemeBackground != oldWidget.canvasThemeBackground) {
      _controller.setThemeCanvasBackground(widget.canvasThemeBackground);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speechSubscription?.cancel());
    unawaited(_speechService.dispose());
    _controller.removeListener(_onControllerChanged);
    _ownController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_cancelSpeech());
    }
  }

  Future<void> _checkSpeechAvailability() async {
    final available = await _speechService.isAvailable();
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleSpeech() async {
    if (_speechState != SpeechRecognitionState.idle) {
      await _speechService.stop();
      return;
    }
    await _showSpeechNoticeOnce();
    _speechFinalCommitted = false;
    await _speechService.start();
  }

  Future<void> _cancelSpeech() async {
    if (_speechState == SpeechRecognitionState.idle) return;
    await _speechService.cancel();
    if (mounted) {
      setState(() {
        _speechState = SpeechRecognitionState.idle;
        _speechPreview = '';
        _speechFinalCommitted = false;
      });
    }
  }

  Future<void> _showSpeechNoticeOnce() async {
    try {
      if (await defaultLocalSettingsRepository.readBool(_speechNoticeKey) ==
          true) {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('FlowMuse 默认不保存录音。语音可能由设备、浏览器或其识别服务处理。'),
          ),
        );
      }
      await defaultLocalSettingsRepository.writeBool(_speechNoticeKey, true);
    } catch (error) {
      debugPrint('[FlowMuseCreateNote] speech notice failed: $error');
    }
  }

  void _onSpeechEvent(SpeechRecognitionEvent event) {
    if (!mounted) return;
    switch (event) {
      case SpeechRecognitionResult(:final text, :final isFinal):
        if (isFinal) {
          if (_speechFinalCommitted) return;
          _speechFinalCommitted = true;
          _controller.insertPlainText(text, canvasSize: _getCanvasSize());
          setState(() {
            _speechPreview = '';
            _speechState = SpeechRecognitionState.idle;
          });
        } else {
          setState(() => _speechPreview = text);
        }
      case SpeechRecognitionStateChanged(:final state):
        setState(() {
          _speechState = state;
          if (state == SpeechRecognitionState.starting) {
            _speechFinalCommitted = false;
          }
          if (state == SpeechRecognitionState.idle) _speechPreview = '';
        });
      case SpeechRecognitionFailed(:final code, :final message):
        setState(() {
          _speechState = SpeechRecognitionState.idle;
          _speechPreview = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_speechErrorMessage(code, message))),
        );
    }
  }

  String _speechErrorMessage(SpeechRecognitionErrorCode code, String message) =>
      switch (code) {
        SpeechRecognitionErrorCode.permissionDenied => '未获得麦克风权限',
        SpeechRecognitionErrorCode.unavailable => '当前设备不支持语音转文字',
        SpeechRecognitionErrorCode.busy => '语音识别服务正忙，请稍后重试',
        SpeechRecognitionErrorCode.noSpeech => '没有检测到语音',
        SpeechRecognitionErrorCode.network => '语音识别网络不可用',
        SpeechRecognitionErrorCode.cancelled => '语音识别已取消',
        SpeechRecognitionErrorCode.unknown =>
          message.trim().isEmpty ? '语音识别失败' : '语音识别失败：$message',
      };

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final context = _propertyPanelContextKey();
    setState(() {
      if (_propertyPanelContext != context) {
        _propertyPanelCollapsed = false;
      }
      _propertyPanelContext = context;
    });
  }

  Size _getCanvasSize() => context.size ?? const Size(800, 600);

  void _noop() {}

  Future<void> _restoreEditorChrome() async {
    final storedValues = await Future.wait([
      defaultLocalSettingsRepository.readString(_toolbarDockKey),
      defaultLocalSettingsRepository.readString(_controlGroupPositionKey),
    ]);
    if (!mounted) {
      return;
    }
    final toolbarDock = ToolbarDock.values.where(
      (item) => item.name == storedValues[0],
    );
    final restoredToolbarDock = toolbarDock.isEmpty
        ? _toolbarDock
        : toolbarDock.first;
    final controlGroupPosition = ControlGroupPosition.values.where(
      (item) => item.name == storedValues[1],
    );
    setState(() {
      _toolbarDock = restoredToolbarDock;
      _controlGroupPosition = controlGroupPosition.isEmpty
          ? _legacyControlGroupPositionFor(restoredToolbarDock)
          : controlGroupPosition.first;
    });
  }

  ControlGroupPosition _legacyControlGroupPositionFor(ToolbarDock dock) {
    return dock == ToolbarDock.left
        ? ControlGroupPosition.bottomRight
        : ControlGroupPosition.bottomLeft;
  }

  void _setToolbarDock(ToolbarDock dock) {
    if (_toolbarDock == dock) {
      return;
    }
    setState(() {
      _toolbarDock = dock;
      _toolbarCollapsed = false;
    });
    unawaited(
      defaultLocalSettingsRepository.writeString(_toolbarDockKey, dock.name),
    );
  }

  void _setToolbarCollapsed(bool collapsed) {
    setState(() => _toolbarCollapsed = collapsed);
  }

  void _setControlGroupPosition(ControlGroupPosition position) {
    if (_controlGroupPosition == position) {
      return;
    }
    setState(() => _controlGroupPosition = position);
    unawaited(
      defaultLocalSettingsRepository.writeString(
        _controlGroupPositionKey,
        position.name,
      ),
    );
  }

  Future<void> _showControlGroupPositionDialog() async {
    final selected = await showDialog<ControlGroupPosition>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('控制组位置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final position in ControlGroupPosition.values)
              RadioListTile<ControlGroupPosition>(
                value: position,
                groupValue: _controlGroupPosition,
                title: Text(_controlGroupPositionLabel(position)),
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      _setControlGroupPosition(selected);
    }
  }

  String _controlGroupPositionLabel(ControlGroupPosition position) {
    return switch (position) {
      ControlGroupPosition.topLeft => '左上',
      ControlGroupPosition.topRight => '右上',
      ControlGroupPosition.bottomLeft => '左下',
      ControlGroupPosition.bottomRight => '右下',
    };
  }

  void _collapsePropertyPanel() {
    setState(() {
      _propertyPanelCollapsed = true;
      _propertyPanelContext = _propertyPanelContextKey();
    });
  }

  void _expandPropertyPanel() {
    setState(() => _propertyPanelCollapsed = false);
  }

  String _propertyPanelContextKey() {
    final selectedIds =
        _controller.selectedElements.map((element) => element.id.value).toList()
          ..sort();
    return '${_controller.editorState.activeToolType.name}:${selectedIds.join(',')}';
  }

  Widget _buildToolbar({required bool compact}) {
    if (compact) {
      return CompactToolbar(
        controller: _controller,
        dock: _toolbarDock,
        onDockChanged: _setToolbarDock,
        onCollapse: () => _setToolbarCollapsed(true),
        useFlatBackground: widget.useFlatBackgrounds,
        onEyedropperPressed: widget.onEyedropperPressed,
        onSpeechPressed: _toggleSpeech,
        speechActive: _speechState != SpeechRecognitionState.idle,
        speechAvailable: _speechAvailable,
      );
    }
    return DesktopToolbar(
      controller: _controller,
      onImportImage: widget.onImportImage,
      dock: _toolbarDock,
      onDockChanged: _setToolbarDock,
      onCollapse: () => _setToolbarCollapsed(true),
      useFlatBackground: widget.useFlatBackgrounds,
      onEyedropperPressed: widget.onEyedropperPressed,
      onSpeechPressed: _toggleSpeech,
      speechActive: _speechState != SpeechRecognitionState.idle,
      speechAvailable: _speechAvailable,
    );
  }

  Widget _buildDetachedControlGroups() {
    final alignToRight = _toolbarDock == ToolbarDock.left;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignToRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!_controller.viewMode)
          _buildControlSurface(UndoRedoControls(controller: _controller)),
        if (!_controller.viewMode && widget.config.showZoomControls)
          const SizedBox(height: 8),
        if (widget.config.showZoomControls)
          _buildControlSurface(
            ZoomControls(
              controller: _controller,
              getCanvasSize: _getCanvasSize,
            ),
          ),
      ],
    );
  }

  Widget _buildControlSurface(Widget child) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _buildToolbarExpandButton() {
    final icon = switch (_toolbarDock) {
      ToolbarDock.top => Icons.keyboard_arrow_down,
      ToolbarDock.left => Icons.keyboard_arrow_right,
      ToolbarDock.right => Icons.keyboard_arrow_left,
    };
    return StudioRailIconButton(
      tooltip: '展开工具栏',
      size: 40,
      onPressed: () => _setToolbarCollapsed(false),
      child: Icon(icon, size: 24),
    );
  }

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
                  constraints.maxWidth < 720 ||
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
    final showNavigationTools = showEditChrome && widget.config.showToolbar;
    final showTopToolbar =
        showNavigationTools &&
        _toolbarDock == ToolbarDock.top &&
        !_toolbarCollapsed;
    final propertyPanelOnRight = _toolbarDock == ToolbarDock.left;
    final safeArea = MediaQuery.paddingOf(context);
    final chromeHeight = showTopToolbar ? 112.0 : 56.0;
    final canvasTopInset = showChrome ? safeArea.top + chromeHeight : 0.0;
    final topChromeOffset = safeArea.top + chromeHeight + 12;
    final bottomChromeOffset = safeArea.bottom + 12;
    final showDetachedControls =
        showChrome && (!_controller.viewMode || widget.config.showZoomControls);
    final controlGroupAtTop =
        _controlGroupPosition == ControlGroupPosition.topLeft ||
        _controlGroupPosition == ControlGroupPosition.topRight;
    final controlGroupOnLeft =
        _controlGroupPosition == ControlGroupPosition.topLeft ||
        _controlGroupPosition == ControlGroupPosition.bottomLeft;
    final controlGroupSharesVerticalToolbar =
        showNavigationTools &&
        _toolbarDock != ToolbarDock.top &&
        ((_toolbarDock == ToolbarDock.left) == controlGroupOnLeft);
    final verticalToolbarTop =
        controlGroupSharesVerticalToolbar && controlGroupAtTop
        ? topChromeOffset + _controlGroupReservedExtent
        : safeArea.top + 56;
    final verticalToolbarBottom =
        controlGroupSharesVerticalToolbar && !controlGroupAtTop
        ? bottomChromeOffset + _controlGroupReservedExtent
        : null;
    Widget body = Stack(
      children: [
        // Full-bleed canvas + desktop library panel
        Padding(
          padding: EdgeInsets.only(top: canvasTopInset),
          child: Row(
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
        ),
        if (showChrome)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GlassNavigationBar(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              if (isCompact && constraints.maxWidth < 480) {
                                return const SizedBox.shrink();
                              }
                              final titleInset = isCompact
                                  ? constraints.maxWidth / 3
                                  : 320.0;
                              if (constraints.maxWidth <= titleInset * 2 + 32) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: titleInset,
                                ),
                                child: Center(
                                  child: _DocumentTitle(
                                    controller: _controller,
                                    onDocumentRenamed: widget.onDocumentRenamed,
                                    maxWidth: isCompact ? 160 : 260,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showEditChrome)
                                _LeftChrome(
                                  controller: _controller,
                                  compact: isCompact,
                                  showMenu: widget.config.showMenu,
                                  showTitle: false,
                                  onBack: widget.onBack,
                                  onOpen: widget.onOpen,
                                  onSave: widget.onSave,
                                  onSaveAs: widget.onSaveAs,
                                  onExportPng: widget.onExportPng,
                                  onExportSvg: widget.onExportSvg,
                                  onExportSmartMarkdown:
                                      widget.onExportSmartMarkdown,
                                  onExportSmartLatex: widget.onExportSmartLatex,
                                  onShare: widget.onShare,
                                  onImportImage: widget.onImportImage,
                                  onImportLibrary: widget.onImportLibrary,
                                  onExportLibrary: widget.onExportLibrary,
                                  onThemeModeChanged: widget.onThemeModeChanged,
                                  currentThemeMode: widget.currentThemeMode,
                                  onDocumentRenamed: widget.onDocumentRenamed,
                                  onChooseControlGroupPosition:
                                      _showControlGroupPositionDialog,
                                ),
                              if (isCompact &&
                                  widget.onFingerDrawingEnabledChanged !=
                                      null) ...[
                                const SizedBox(width: 4),
                                _FingerDrawingSwitch(
                                  value: widget.fingerDrawingEnabled,
                                  onChanged:
                                      widget.onFingerDrawingEnabledChanged!,
                                ),
                              ],
                              if (!isCompact &&
                                  widget.saveStatusLabel != null) ...[
                                const SizedBox(width: 8),
                                _StatusPill(label: widget.saveStatusLabel!),
                              ],
                              if (!isCompact &&
                                  widget.onFingerDrawingEnabledChanged !=
                                      null) ...[
                                const SizedBox(width: 8),
                                _FingerDrawingSwitch(
                                  value: widget.fingerDrawingEnabled,
                                  onChanged:
                                      widget.onFingerDrawingEnabledChanged!,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RightChrome(
                                saveStatusLabel: widget.saveStatusLabel,
                                showSaveStatus: false,
                                collaborating: widget.collaborating,
                                collaborationConnecting:
                                    widget.collaborationConnecting,
                                collaborationError: widget.collaborationError,
                                collaborationStatusLabel:
                                    widget.collaborationStatusLabel,
                                roomLink: widget.roomLink,
                                roomValue: widget.roomValue,
                                shareOriginConfigured:
                                    widget.shareOriginConfigured,
                                collaboratorCount: widget.collaboratorCount,
                                collaborationParticipants:
                                    widget.collaborationParticipants,
                                isCollaborationOwner:
                                    widget.isCollaborationOwner,
                                onStartCollaboration:
                                    widget.onStartCollaboration,
                                onJoinCollaboration: widget.onJoinCollaboration,
                                onLeaveCollaboration:
                                    widget.onLeaveCollaboration,
                                onEndCollaboration: widget.onEndCollaboration,
                                onShareCollaboration:
                                    widget.onShareCollaboration,
                                viewMode: _controller.viewMode,
                                zenMode: _controller.zenMode,
                                onExitViewMode: _controller.toggleViewMode,
                                onExitZenMode: _controller.toggleZenMode,
                                toolbarExpandButton:
                                    showNavigationTools &&
                                        _toolbarDock == ToolbarDock.top &&
                                        _toolbarCollapsed
                                    ? _buildToolbarExpandButton()
                                    : null,
                              ),
                              if (!isCompact &&
                                  widget.config.showHelpButton) ...[
                                const SizedBox(width: 8),
                                VerticalDivider(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                                const HelpButton(),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_controller.zenMode)
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _StatusPill(
                      label: '退出专注模式',
                      onTap: _controller.toggleZenMode,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (showNavigationTools && showTopToolbar)
          Positioned(
            top: safeArea.top + 60,
            left: 8,
            right: 8,
            child: Center(child: _buildToolbar(compact: isCompact)),
          ),
        if (showNavigationTools && _toolbarDock != ToolbarDock.top)
          Positioned(
            top: verticalToolbarTop,
            bottom: verticalToolbarBottom,
            left: _toolbarDock == ToolbarDock.left ? 8 : null,
            right: _toolbarDock == ToolbarDock.right ? 8 : null,
            child: Align(
              alignment: _toolbarDock == ToolbarDock.left
                  ? Alignment.topLeft
                  : Alignment.topRight,
              child: _toolbarCollapsed
                  ? _buildToolbarExpandButton()
                  : _buildToolbar(compact: isCompact),
            ),
          ),
        if (showDetachedControls)
          Positioned(
            top: controlGroupAtTop ? topChromeOffset : null,
            bottom: controlGroupAtTop ? null : bottomChromeOffset,
            left: controlGroupOnLeft ? 12 : null,
            right: controlGroupOnLeft ? null : 12,
            child: _buildDetachedControlGroups(),
          ),
        // Floating property panel — desktop left side
        if (showEditChrome &&
            !isCompact &&
            widget.config.showPropertyPanel &&
            (_controller.selectedElements.isNotEmpty ||
                _controller.isCreationTool))
          if (_propertyPanelCollapsed)
            Positioned(
              top: topChromeOffset,
              left: propertyPanelOnRight ? null : 0,
              right: propertyPanelOnRight ? 0 : null,
              child: StudioRailIconButton(
                tooltip: '展开属性面板',
                size: 40,
                onPressed: _expandPropertyPanel,
                child: const Icon(Icons.tune, size: 20),
              ),
            )
          else
            Positioned(
              top: topChromeOffset,
              left: propertyPanelOnRight ? null : 12,
              right: propertyPanelOnRight ? 12 : null,
              bottom: 12,
              child: PropertyPanel(
                controller: _controller,
                onCollapse: _collapsePropertyPanel,
                dockOnRight: propertyPanelOnRight,
              ),
            ),
        // Find overlay
        if (_controller.isFindOpen)
          Positioned(
            bottom: bottomChromeOffset,
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
          _buildLinkOverlay(topChromeOffset),
        if (_speechState != SpeechRecognitionState.idle)
          Positioned(
            left: 16,
            right: 16,
            bottom: safeArea.bottom + 24,
            child: Center(
              child: _SpeechRecognitionOverlay(
                text: _speechPreview,
                stopping: _speechState == SpeechRecognitionState.stopping,
                onCancel: _cancelSpeech,
                onFinish: _speechService.stop,
              ),
            ),
          ),
      ],
    );
    if (!isCompact && _controller.showMarkdownPanel) {
      body = MarkdrawSplitPane(controller: _controller, child: body);
    }
    return body;
  }

  Widget _buildLinkOverlay(double topOffset) {
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
      top: top.clamp(topOffset, double.infinity),
      child: LinkOverlay(
        controller: _controller,
        getCanvasSize: _getCanvasSize,
      ),
    );
  }
}

class _SpeechRecognitionOverlay extends StatelessWidget {
  const _SpeechRecognitionOverlay({
    required this.text,
    required this.stopping,
    required this.onCancel,
    required this.onFinish,
  });

  final String text;
  final bool stopping;
  final VoidCallback onCancel;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: text.isEmpty ? '正在聆听' : '识别结果：$text',
      child: Material(
        color: colors.surfaceContainerHigh,
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mic, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    text.isEmpty ? (stopping ? '正在生成文字…' : '正在聆听…') : text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(onPressed: onCancel, child: const Text('取消')),
                FilledButton.tonal(
                  onPressed: stopping ? null : onFinish,
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavigationBar extends StatelessWidget {
  const _GlassNavigationBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.78),
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LeftChrome extends StatelessWidget {
  const _LeftChrome({
    required this.controller,
    required this.compact,
    required this.showMenu,
    this.showTitle = true,
    required this.onBack,
    required this.onOpen,
    required this.onSave,
    required this.onSaveAs,
    required this.onExportPng,
    required this.onExportSvg,
    required this.onExportSmartMarkdown,
    required this.onExportSmartLatex,
    required this.onShare,
    required this.onImportImage,
    required this.onImportLibrary,
    required this.onExportLibrary,
    required this.onThemeModeChanged,
    required this.currentThemeMode,
    required this.onDocumentRenamed,
    required this.onChooseControlGroupPosition,
  });

  final MarkdrawController controller;
  final bool compact;
  final bool showMenu;
  final bool showTitle;
  final VoidCallback? onBack;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;
  final VoidCallback? onSaveAs;
  final VoidCallback? onExportPng;
  final VoidCallback? onExportSvg;
  final VoidCallback? onExportSmartMarkdown;
  final VoidCallback? onExportSmartLatex;
  final VoidCallback? onShare;
  final VoidCallback? onImportImage;
  final VoidCallback? onImportLibrary;
  final VoidCallback? onExportLibrary;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ThemeMode? currentThemeMode;
  final VoidCallback? onDocumentRenamed;
  final VoidCallback onChooseControlGroupPosition;

  @override
  Widget build(BuildContext context) {
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
                  onExportSmartMarkdown: onExportSmartMarkdown,
                  onExportSmartLatex: onExportSmartLatex,
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
                  onChooseControlGroupPosition: onChooseControlGroupPosition,
                )
              : HamburgerMenu(
                  controller: controller,
                  onOpen: onOpen,
                  onSave: onSave,
                  onSaveAs: onSaveAs,
                  onExportPng: onExportPng,
                  onExportSvg: onExportSvg,
                  onExportSmartMarkdown: onExportSmartMarkdown,
                  onExportSmartLatex: onExportSmartLatex,
                  onShare: onShare,
                  onImportImage: onImportImage,
                  onThemeModeChanged: onThemeModeChanged,
                  currentThemeMode: currentThemeMode,
                  onDocumentRenamed: onDocumentRenamed,
                  onChooseControlGroupPosition: onChooseControlGroupPosition,
                ),
        if (showTitle) ...[
          const SizedBox(width: 10),
          _DocumentTitle(
            controller: controller,
            onDocumentRenamed: onDocumentRenamed,
            maxWidth: compact ? 120 : 168,
          ),
        ],
      ],
    );
  }
}

class _FingerDrawingSwitch extends StatelessWidget {
  const _FingerDrawingSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('手指绘制', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(width: 4),
        Tooltip(
          message: '开启后单指绘制，双指缩放或移动画布',
          child: Switch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _DocumentTitle extends StatelessWidget {
  const _DocumentTitle({
    required this.controller,
    required this.onDocumentRenamed,
    required this.maxWidth,
  });

  final MarkdrawController controller;
  final VoidCallback? onDocumentRenamed;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = controller.documentName?.trim().isNotEmpty == true
        ? controller.documentName!.trim()
        : '未命名白板';
    return Tooltip(
      message: '重命名',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () =>
            showRenameDocumentDialog(context, controller, onDocumentRenamed),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
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
    );
  }
}

class _RightChrome extends StatelessWidget {
  const _RightChrome({
    required this.saveStatusLabel,
    this.showSaveStatus = true,
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
    required this.onShareCollaboration,
    required this.viewMode,
    required this.zenMode,
    required this.onExitViewMode,
    required this.onExitZenMode,
    this.toolbarExpandButton,
  });

  final String? saveStatusLabel;
  final bool showSaveStatus;
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
  final Future<void> Function()? onShareCollaboration;
  final bool viewMode;
  final bool zenMode;
  final VoidCallback onExitViewMode;
  final VoidCallback onExitZenMode;
  final Widget? toolbarExpandButton;

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
          if (!compact && showSaveStatus && saveStatusLabel != null)
            _StatusPill(label: saveStatusLabel!),
          if (!compact &&
              showSaveStatus &&
              saveStatusLabel != null &&
              canCollaborate)
            const SizedBox(width: 8),
          if (collaborating && collaborationParticipants.isNotEmpty) ...[
            _ParticipantAvatarStack(participants: collaborationParticipants),
            const SizedBox(width: 8),
          ],
          if (toolbarExpandButton != null) ...[
            toolbarExpandButton!,
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
              onShare: onShareCollaboration,
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
    return StudioRailIconButton(
      tooltip: tooltip,
      size: 44,
      onPressed: onPressed,
      child: Icon(icon, size: 20),
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
              color: cs.shadow.withValues(alpha: 0.14),
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
            color: cs.shadow.withValues(alpha: 0.14),
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
        borderRadius: BorderRadius.circular(12),
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
      borderRadius: BorderRadius.circular(12),
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
    required this.onShare,
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
  final Future<void> Function()? onShare;

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _showCollaborationMenu(
    BuildContext anchorContext,
    String label,
  ) async {
    final selected = await showAnchoredPopupMenu<_CollaborationAction>(
      context: anchorContext,
      placement: AnchoredPopupPlacement.below,
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
        if ((widget.roomLink != null || widget.roomValue != null) &&
            widget.onShare != null)
          const PopupMenuItem<_CollaborationAction>(
            value: _CollaborationAction.share,
            child: ListTile(
              leading: Icon(Icons.ios_share),
              title: Text('分享房间码'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (!widget.collaborating || !widget.isOwner)
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
      case _CollaborationAction.share:
        final onShare = widget.onShare;
        if (onShare != null) {
          unawaited(runAfterUiTeardownAsync(onShare));
        }
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

enum _CollaborationAction { copy, share, start, join, leave, end }

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
