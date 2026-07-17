library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Element, SelectionOverlay;
import 'package:flutter/services.dart';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    as core
    show TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flow_muse/shared/utils/ui_lifecycle.dart';

import 'harmony_stylus_stroke_smoother.dart';
import 'pointer_pressure.dart';
import '../rendering/viewport_clamp.dart';
import '../input/outline_render_mode.dart';
import '../input/stroke_input_normalizer.dart';
import '../input/stroke_input_modeler.dart';
import '../input/stroke_input_sample.dart';
import '../input/input_policy.dart';
import '../input/stroke_recorder.dart';

const String _logTag = 'InkRecognition';
const int _smartLayoutClientRecognitionConcurrency = 3;

/// Which color picker to open programmatically.
enum ColorPickerTarget { stroke, background, font }

enum SmartLayoutRecognitionEngine { ai, myscript }

Scene _sceneWithLayoutPagesForLayout(Scene scene, CanvasLayout layout) {
  if (!layout.isPaged) {
    return scene;
  }
  var next = scene;
  final existingPageIds = {
    for (final element in scene.elements)
      if (element.isCanvasPage) element.id.value,
  };
  for (final page in layout.pages) {
    if (existingPageIds.contains(page.id)) {
      continue;
    }
    next = next.addElement(
      RectangleElement(
        id: ElementId(page.id),
        x: page.bounds.left,
        y: page.bounds.top,
        width: page.bounds.width,
        height: page.bounds.height,
        strokeColor: 'transparent',
        backgroundColor: 'transparent',
        opacity: 0,
        locked: true,
        customData: CanvasLayout.pageCustomData(page),
      ),
    );
  }
  return next;
}

/// Controller for [MarkdrawEditor]. Holds all editor state and logic.
///
/// Can be created internally by the widget or provided externally
/// (like [TextEditingController]).
enum SceneChangeSource { userEdit, undo, redo, remoteApply, restore }

enum _TwoFingerGestureMode { pan, zoom }

class MarkdrawController extends ChangeNotifier {
  MarkdrawController({
    MarkdrawEditorConfig config = const MarkdrawEditorConfig(),
  }) : _config = config {
    _layout = config.initialLayout.ensurePage();
    _editorState = EditorState(
      scene: _sceneWithLayoutPagesForLayout(Scene(), _layout),
      viewport: const ViewportState(),
      selectedIds: {},
      activeToolType: ToolType.select,
    );
    _activeTool = createTool(ToolType.select);
    _defaultStyle = config.initialStyle;
    _canvasBackgroundColor = config.initialBackground;

    _textFocusNode.addListener(_onTextFocusChanged);

    _imageCache.onImageDecoded = () {
      if (!_disposed) {
        notifyListeners();
      }
    };
  }

  final MarkdrawEditorConfig _config;

  // Core state
  late EditorState _editorState;
  late Tool _activeTool;
  final _adapter = RoughCanvasAdapter();
  final _historyManager = HistoryManager();
  final ClipboardService _clipboardService = const FlutterClipboardService();
  final _imageCache = ImageElementCache();
  final _flowchartCreator = FlowchartCreator();
  final _flowchartNavigator = FlowchartNavigator();
  final _mindmapCreator = MindmapCreator();
  // ignore: unused_field — retained for debug comparison with modeler output
  final _harmonyStylusStrokeSmoother = HarmonyStylusStrokeSmoother();
  final _normalizer = StrokeInputNormalizer();
  StrokeInputModeler? _modeler;
  final _policySelector = const InputPolicySelector();
  int? _activeDrawPointerId;
  int? _temporaryTouchPanPointerId;
  int? _activeStylusPointerId;
  final Set<int> _rejectedTouchPointers = {};
  bool _pressureEnabled = true;
  double _pressureExponent = 1.0;
  bool _palmRejectionEnabled = true;
  bool _twoFingerZoomEnabled = true;
  bool _singleFingerPanEnabled = true;
  bool _fingerDrawingEnabled = false;
  final bool _useUnifiedModeler = true;

  // debug/test 录制器：null 时不录制（release 默认关闭）
  StrokeRecorder? _recorder;
  bool get isRecording => _recorder != null;

  /// 开始录制当前 freedraw stroke 的规范化样本。仅 debug/test 使用。
  void startRecording() {
    _recorder = StrokeRecorder();
  }

  /// 结束录制，返回 JSON 字符串。录制内容可保存为文件供离线回放。
  String stopRecording() {
    final r = _recorder;
    _recorder = null;
    if (r == null) return '{}';
    final recording = r.finish(
      buildVersion: 'dev',
      deviceInfo: 'manual-record',
    );
    return const JsonEncoder.withIndent('  ').convert(recording.toJson());
  }

  /// viewport 仿射变换 [a,b,c,d,e,f]，scene = a*localX + c*localY + e, ...
  List<double> get _viewportTransform {
    final v = _editorState.viewport;
    final iz = 1.0 / v.zoom;
    return [iz, 0, 0, iz, v.offset.dx, v.offset.dy];
  }

  // UI state
  List<LibraryItem> _libraryItems = [];
  bool _showLibraryPanel = false;
  bool _showMarkdownPanel = false;
  bool _toolLocked = false;
  bool _isCompact = false;
  bool _isEditingLinear = false;
  bool _fontPickerOpen = false;
  bool _zenMode = false;
  bool _viewMode = false;
  ToolType? _toolBeforeViewMode;
  ColorPickerTarget? _pendingColorPicker;
  bool _pendingEyedropper = false;
  ElementStyle _defaultStyle = const ElementStyle();
  String _canvasBackgroundColor = '#ffffff';
  String _themeCanvasBackgroundColor = '#ffffff';
  bool _canvasBackgroundFollowsTheme = true;
  late CanvasLayout _layout;
  int? _gridSize;
  bool _objectsSnapMode = false;
  double _pressureSensitivity = 0.7;
  BrushType _activeBrushType = BrushType.fountainPen;
  bool _hasSelectedBrush = false;
  bool _brushPaletteRequested = false;
  bool _inkRecognitionMode = false;
  bool _smartInkLayoutMode = false;

  /// 每种笔形独立的状态缓存（参考 Saber 设计）。
  /// 切换笔形时自动保存/恢复颜色、粗细和压感灵敏度。
  final Map<BrushType, BrushState> _brushStates =
      Map<BrushType, BrushState>.from(BrushState.defaults);
  String? _documentName;

  // Link editor state
  bool _isLinkEditorOpen = false;
  bool _isLinkEditorEditing = false;
  bool _linkToElementMode = false;

  // Find state
  bool _isFindOpen = false;
  String _findQuery = '';
  List<ElementId> _findResults = [];
  int _findCurrentIndex = -1;

  // Copied style for paste-style
  ElementStyle? _copiedStyle;

  // Drag coalescing
  Scene? _sceneBeforeDrag;

  // Double-click detection
  DateTime? _lastPointerUpTime;

  /// Focus node for keyboard shortcut handling on the canvas.
  final keyboardFocusNode = FocusNode();

  // Text editing state
  ElementId? _editingTextElementId;

  /// Text controller for the inline text editing overlay.
  final textEditingController = TextEditingController();
  final _textFocusNode = FocusNode();
  bool _disposed = false;

  Object? _editableTextRegistration;
  TextSelection? Function()? _readEditableTextSelection;
  void Function(TextSelection selection)? _restoreEditableTextSelection;
  bool _isEditingExisting = false;
  String? _originalText;

  /// When true, suppresses auto-commit on text focus loss (e.g. during
  /// style changes that temporarily steal focus).
  bool suppressFocusCommit = false;

  // Frame label editing state
  ElementId? _editingFrameLabelId;

  // Canvas size cache (for followLink from pointer events)
  Size? _lastCanvasSize;
  Bounds? _contentBounds;
  Size _canvasSize = Size.zero;
  Offset _canvasGlobalOffset = Offset.zero;

  /// Current mouse position in screen coordinates; used for eraser cursor.
  Offset? mousePosition;

  // Pinch-to-zoom state
  double _pinchStartZoom = 1.0;
  Offset _pinchStartOffset = Offset.zero;
  Offset _pinchStartFocalPoint = Offset.zero;
  _TwoFingerGestureMode? _twoFingerGestureMode;
  bool _isViewportGesture = false;

  /// Callback invoked when the user toggles the theme. Set by [MarkdrawEditor].
  VoidCallback? onThemeToggle;

  /// Called whenever the scene changes (element add/update/remove).
  void Function(Scene scene, SceneChangeSource source)? onSceneChanged;
  void Function(FreedrawElement element)? onLiveFreedrawChanged;
  Timer? _liveFreedrawTimer;
  static const Duration _liveFreedrawBroadcastInterval = Duration(
    milliseconds: 50,
  );

  List<Element>? _lastChangedElements;

  /// Elements changed by the latest local tool result.
  ///
  /// `null` means callers must fall back to a full-scene sync (for example
  /// undo/redo, file changes, or complete scene replacement).
  List<Element>? get lastChangedElements => _lastChangedElements;

  /// Called after recognition-pen strokes settle and should be recognized.
  Future<InkRecognitionResult> Function(InkRecognitionRequest)? onRecognizeInk;
  Future<SmartLayoutResponse> Function(SmartLayoutRequest)? onSmartLayoutInk;
  Future<SmartLayoutRecognizedBlock> Function(SmartLayoutInkBlockRequest)?
  onRecognizeSmartLayoutBlock;
  Future<SmartLayoutResponse> Function(SmartLayoutComposeRequest)?
  onComposeSmartLayout;
  void Function(bool enabled)? onInkRecognitionModeChanged;

  Timer? _inkRecognitionTimer;
  String? _pendingInkSessionId;
  bool _recognizingInk = false;

  // --- Public getters ---

  /// The current editor state (scene, viewport, selection, tool type).
  EditorState get editorState => _editorState;

  /// The currently active tool instance.
  Tool get activeTool => _activeTool;

  /// The rough-drawing adapter used for rendering.
  RoughAdapter get adapter => _adapter;

  /// Undo/redo history manager.
  HistoryManager get historyManager => _historyManager;

  /// Cache for decoded image element bitmaps.
  ImageElementCache get imageCache => _imageCache;

  /// Immutable configuration for the editor.
  MarkdrawEditorConfig get config => _config;

  /// The current set of library items available for placement.
  List<LibraryItem> get libraryItems => _libraryItems;

  /// Whether the library panel is visible.
  bool get showLibraryPanel => _showLibraryPanel;

  /// Whether the split-pane markdown editor is visible.
  bool get showMarkdownPanel => _showMarkdownPanel;

  /// Whether the current tool stays active after use instead of reverting
  /// to the select tool.
  bool get toolLocked => _toolLocked;

  /// Whether the editor is in compact (mobile) layout mode.
  bool get isCompact => _isCompact;

  /// Whether a line/arrow is in point-editing mode (double-click activated).
  bool get isEditingLinear => _isEditingLinear;

  /// Whether the font picker overlay/sheet is currently open.
  bool get fontPickerOpen => _fontPickerOpen;

  /// The sticky default style applied to newly created elements.
  ElementStyle get defaultStyle => _defaultStyle;

  /// The canvas background color as a hex string.
  String get canvasBackgroundColor => _canvasBackgroundColor;
  bool get canvasBackgroundFollowsTheme => _canvasBackgroundFollowsTheme;

  /// Current canvas layout. Paged layout is synchronized through page elements.
  CanvasLayout get layout => _layout;

  Bounds? get contentBounds => _contentBounds;

  Size get canvasSize => _canvasSize;

  Offset get canvasGlobalOffset => _canvasGlobalOffset;

  bool get isPagedViewport => _layout.isPaged && _layout.pages.isNotEmpty;

  bool get canPanPagedViewportWithTouch =>
      _singleFingerPanEnabled &&
      !_fingerDrawingEnabled &&
      (!_palmRejectionEnabled || _activeStylusPointerId == null);

  PagedViewportMetrics? get pagedViewportMetrics => computePagedViewportMetrics(
    layout: _layout,
    viewport: _editorState.viewport,
    canvasSize: _canvasSize,
  );

  /// Current scene snapshot.
  Scene get currentScene => _editorState.scene;

  /// The snap grid size in pixels, or null if grid is off.
  int? get gridSize => _gridSize;

  /// Whether snap-to-objects alignment guides are enabled.
  bool get objectsSnapMode => _objectsSnapMode;

  double get pressureSensitivity => _pressureSensitivity;
  set pressureSensitivity(double value) {
    _pressureSensitivity = value.clamp(0.0, 1.0);
    _adapter.pressureSensitivity = _pressureSensitivity;
    // 保存到当前笔形状态（参考 Saber 独立笔状态）
    _brushStates[_activeBrushType] = _brushStates[_activeBrushType]!.copyWith(
      pressureSensitivity: _pressureSensitivity,
    );
    onBrushStateChanged?.call(
      _activeBrushType,
      _brushStates[_activeBrushType]!,
    );
    notifyListeners();
  }

  /// 轮廓渲染模式：polygon(直线段)或 quadratic(二次贝塞尔平滑)。
  /// 由 [RoughCanvasAdapter.outlineRenderMode] 同步。
  OutlineRenderMode get outlineRenderMode => _adapter.outlineRenderMode;
  set outlineRenderMode(OutlineRenderMode mode) {
    _adapter.outlineRenderMode = mode;
    notifyListeners();
  }

  BrushType get activeBrushType => _activeBrushType;

  /// 当前笔形的完整状态（颜色、粗细范围、压感灵敏度等）。
  /// UI 可据此渲染动态粗细滑块。
  BrushState get currentBrushState => _brushStates[_activeBrushType]!;

  void Function(BrushType type, BrushState state)? onBrushStateChanged;

  void applyEditorPreferences({
    required ToolType defaultTool,
    required BrushType defaultBrush,
    required Map<BrushType, BrushState> brushStates,
    required bool pressureEnabled,
    required double pressureExponent,
    required bool palmRejectionEnabled,
    required bool twoFingerZoomEnabled,
    required bool singleFingerPanEnabled,
    required bool fingerDrawingEnabled,
  }) {
    _brushStates.addAll(brushStates);
    _activeBrushType = defaultBrush;
    _restoreBrushState(defaultBrush);
    _pressureEnabled = pressureEnabled;
    _pressureExponent = pressureExponent.clamp(0.25, 4.0);
    _palmRejectionEnabled = palmRejectionEnabled;
    if (!palmRejectionEnabled) _rejectedTouchPointers.clear();
    _twoFingerZoomEnabled = twoFingerZoomEnabled;
    _singleFingerPanEnabled = singleFingerPanEnabled;
    _fingerDrawingEnabled = fingerDrawingEnabled;
    if (_editorState.activeToolType == defaultTool) {
      notifyListeners();
    } else {
      switchTool(defaultTool);
    }
  }

  set activeBrushType(BrushType value) {
    if (_activeBrushType == value) return;
    final previousType = _activeBrushType;
    final previousState = _rememberCurrentBrushState(notify: false);
    _activeBrushType = value;
    _restoreBrushState(value);
    notifyListeners();
    onBrushStateChanged?.call(previousType, previousState);
  }

  BrushState _rememberCurrentBrushState({bool notify = true}) {
    final state = _brushStates[_activeBrushType]!.copyWith(
      strokeColor: _defaultStyle.strokeColor,
      strokeWidth: _defaultStyle.strokeWidth,
      pressureSensitivity: _pressureSensitivity,
    );
    _brushStates[_activeBrushType] = state;
    if (notify) onBrushStateChanged?.call(_activeBrushType, state);
    return state;
  }

  void _restoreBrushState(BrushType value) {
    final saved = _brushStates[value]!;
    if (saved.strokeColor != null || saved.strokeWidth != null) {
      _defaultStyle = _defaultStyle.copyWith(strokeColor: saved.strokeColor);
      if (saved.strokeWidth != null) {
        _defaultStyle = ElementStyle(
          strokeColor: _defaultStyle.strokeColor,
          strokeWidth: saved.strokeWidth,
          strokeStyle: _defaultStyle.strokeStyle,
          fillStyle: _defaultStyle.fillStyle,
          roughness: _defaultStyle.roughness,
          opacity: _defaultStyle.opacity,
          roundness: _defaultStyle.roundness,
          fontSize: _defaultStyle.fontSize,
          fontFamily: _defaultStyle.fontFamily,
          textAlign: _defaultStyle.textAlign,
          verticalAlign: _defaultStyle.verticalAlign,
          arrowType: _defaultStyle.arrowType,
          startArrowhead: _defaultStyle.startArrowhead,
          startArrowheadNone: _defaultStyle.startArrowheadNone,
          endArrowhead: _defaultStyle.endArrowhead,
          endArrowheadNone: _defaultStyle.endArrowheadNone,
        );
      }
    }
    _pressureSensitivity = saved.pressureSensitivity;
    _adapter.pressureSensitivity = _pressureSensitivity;
  }

  bool get inkRecognitionMode => _inkRecognitionMode;
  set inkRecognitionMode(bool value) {
    if (_inkRecognitionMode == value) return;
    _inkRecognitionMode = value;
    if (!value) {
      _smartInkLayoutMode = false;
    }
    onInkRecognitionModeChanged?.call(value);
    notifyListeners();
  }

  bool get smartInkLayoutMode => _smartInkLayoutMode;
  set smartInkLayoutMode(bool value) {
    if (_smartInkLayoutMode == value) return;
    _smartInkLayoutMode = value;
    if (value && !_inkRecognitionMode) {
      _inkRecognitionMode = true;
      onInkRecognitionModeChanged?.call(true);
    }
    notifyListeners();
  }

  bool get canExportSmartLayout =>
      _editorState.scene.smartLayout != null &&
      !_editorState.scene.smartLayout!.isEmpty;

  /// The user-assigned document name, or null.
  String? get documentName => _documentName;

  /// The most recently copied element style for paste-style.
  ElementStyle? get copiedStyle => _copiedStyle;

  /// Whether zen mode is active (all chrome hidden).
  bool get zenMode => _zenMode;

  /// Whether view (read-only) mode is active.
  bool get viewMode => _viewMode;

  /// Whether the link editor overlay is visible.
  bool get isLinkEditorOpen => _isLinkEditorOpen;

  /// Whether the link editor is in editing (TextField) mode vs info mode.
  bool get isLinkEditorEditing => _isLinkEditorEditing;

  /// Whether the next click will set a link-to-element target.
  bool get linkToElementMode => _linkToElementMode;

  /// Whether the find bar is open.
  bool get isFindOpen => _isFindOpen;

  /// The current search query string in the find bar.
  String get findQuery => _findQuery;

  /// Element IDs matching the current find query.
  List<ElementId> get findResults => _findResults;

  /// Index of the currently highlighted find result (-1 if none).
  int get findCurrentIndex => _findCurrentIndex;

  /// Which color picker should auto-open, or null.
  ColorPickerTarget? get pendingColorPicker => _pendingColorPicker;

  /// Whether the eyedropper should auto-activate when the color picker opens.
  bool get pendingEyedropper => _pendingEyedropper;

  /// The element ID currently being inline-text-edited, or null.
  ElementId? get editingTextElementId => _editingTextElementId;

  /// The frame element ID whose label is being edited, or null.
  ElementId? get editingFrameLabelId => _editingFrameLabelId;

  /// Focus node for the inline text editing overlay.
  FocusNode get textFocusNode => _textFocusNode;

  /// Whether we are editing an existing text element (vs creating new).
  bool get isEditingExisting => _isEditingExisting;

  /// The original text content before editing began (for cancel/revert).
  String? get originalText => _originalText;

  /// The zoom level at the start of a pinch gesture.
  double get pinchStartZoom => _pinchStartZoom;

  /// The viewport offset at the start of a pinch gesture.
  Offset get pinchStartOffset => _pinchStartOffset;

  /// Pointer or touch mode based on compact layout state.
  InteractionMode get interactionMode =>
      _isCompact ? InteractionMode.touch : InteractionMode.pointer;

  /// Whether the active tool creates new elements (vs select/hand/eraser).
  bool get isCreationTool => switch (_editorState.activeToolType) {
    ToolType.select ||
    ToolType.hand ||
    ToolType.eraser ||
    ToolType.laser => false,
    _ => true,
  };

  /// Builds a [ToolContext] snapshot from current state for tool callbacks.
  ToolContext get toolContext => ToolContext(
    scene: _editorState.scene,
    viewport: _editorState.viewport,
    selectedIds: _editorState.selectedIds,
    clipboard: _editorState.clipboard,
    interactionMode: interactionMode,
    isEditingLinear: _isEditingLinear,
    gridSize: _gridSize,
    objectsSnapMode: _objectsSnapMode,
    brushType: _activeBrushType,
    inkRecognitionMode: _inkRecognitionMode,
  );

  /// The currently selected elements resolved from their IDs.
  List<Element> get selectedElements {
    return _editorState.selectedIds
        .map((id) => _editorState.scene.getElementById(id))
        .whereType<Element>()
        .toList();
  }

  /// The mouse cursor appropriate for the active tool.
  MouseCursor get cursorForTool {
    return switch (_editorState.activeToolType) {
      ToolType.select || ToolType.hand => SystemMouseCursors.basic,
      ToolType.eraser => SystemMouseCursors.none,
      ToolType.laser => SystemMouseCursors.precise,
      _ => SystemMouseCursors.precise,
    };
  }

  // --- Public setters ---

  /// Sets compact (mobile) layout mode. Called by LayoutBuilder.
  set isCompact(bool value) {
    if (_isCompact != value) {
      _isCompact = value;
      notifyListeners();
    }
  }

  /// Shows or hides the library panel.
  set showLibraryPanel(bool value) {
    _showLibraryPanel = value;
    notifyListeners();
  }

  /// Tracks whether the font picker overlay is open.
  set fontPickerOpen(bool value) {
    _fontPickerOpen = value;
    notifyListeners();
  }

  /// Enters or exits linear (point) editing mode for lines/arrows.
  set isEditingLinear(bool value) {
    _isEditingLinear = value;
    notifyListeners();
  }

  /// Sets the canvas background color (hex string).
  set canvasBackgroundColor(String value) {
    _canvasBackgroundColor = value;
    _canvasBackgroundFollowsTheme = false;
    notifyListeners();
  }

  void setThemeCanvasBackground(String value) {
    _themeCanvasBackgroundColor = value;
    if (_canvasBackgroundFollowsTheme) {
      _canvasBackgroundColor = value;
      notifyListeners();
    }
  }

  void followThemeCanvasBackground() {
    _canvasBackgroundFollowsTheme = true;
    _canvasBackgroundColor = _themeCanvasBackgroundColor;
    notifyListeners();
  }

  void setLayout(CanvasLayout layout) {
    _layout = layout.ensurePage();
    _editorState = _editorState.copyWith(
      scene: _sceneWithLayoutPages(_editorState.scene),
    );
    notifyListeners();
  }

  /// Caches the last known canvas size for link navigation from pointer events.
  set lastCanvasSize(Size? value) {
    _lastCanvasSize = value;
  }

  set contentBounds(Bounds? value) {
    _contentBounds = value;
    _applyViewportConstraints();
  }

  set canvasSize(Size value) {
    _canvasSize = value;
    _applyViewportConstraints();
  }

  set canvasGlobalOffset(Offset value) {
    _canvasGlobalOffset = value;
  }

  // --- Lifecycle ---

  /// Releases all resources: image cache, focus nodes, text controller.
  @override
  void dispose() {
    _disposed = true;
    _inkRecognitionTimer?.cancel();
    _liveFreedrawTimer?.cancel();
    _imageCache.dispose();
    keyboardFocusNode.dispose();
    textEditingController.dispose();
    _textFocusNode.removeListener(_onTextFocusChanged);
    _textFocusNode.dispose();
    super.dispose();
  }

  void restoreKeyboardFocusWhenStable() {
    runWhenUiStable(() {
      if (!_disposed && keyboardFocusNode.canRequestFocus) {
        keyboardFocusNode.requestFocus();
      }
    });
  }

  void restoreTextFocusWhenStable() {
    runWhenUiStable(() {
      if (!_disposed && _textFocusNode.canRequestFocus) {
        _textFocusNode.requestFocus();
      }
    });
  }

  Object registerEditableText({
    required TextSelection? Function() readSelection,
    required void Function(TextSelection selection) restoreSelection,
  }) {
    final registration = Object();
    _editableTextRegistration = registration;
    _readEditableTextSelection = readSelection;
    _restoreEditableTextSelection = restoreSelection;
    return registration;
  }

  void unregisterEditableText(Object registration) {
    if (!identical(_editableTextRegistration, registration)) {
      return;
    }
    _editableTextRegistration = null;
    _readEditableTextSelection = null;
    _restoreEditableTextSelection = null;
  }

  TextSelection? get editableTextSelection =>
      _readEditableTextSelection?.call();

  void restoreEditableTextSelection(TextSelection selection) {
    _restoreEditableTextSelection?.call(selection);
  }

  // --- Tool management ---

  /// Switches to a different tool, resetting the previous one and clearing
  /// selection for non-select tools.
  void switchTool(ToolType type) {
    // In view mode, only the hand tool is allowed
    if (_viewMode && type != ToolType.hand) return;
    _cancelActiveToolInteraction();
    _activeTool = createTool(type);
    _editorState = _editorState.copyWith(
      activeToolType: type,
      selectedIds: type == ToolType.select ? null : {},
    );
    cancelTextEditing();
    restoreKeyboardFocusWhenStable();
    notifyListeners();
  }

  /// Activates the last selected brush, or requests brush selection.
  bool activateBrush() {
    if (_editorState.activeToolType == ToolType.freedraw ||
        !_hasSelectedBrush) {
      return true;
    }
    _restoreBrushState(_activeBrushType);
    switchTool(ToolType.freedraw);
    return false;
  }

  void selectBrush(BrushType type) {
    activeBrushType = type;
    _hasSelectedBrush = true;
    _restoreBrushState(type);
    switchTool(ToolType.freedraw);
  }

  void requestBrushPalette() {
    _brushPaletteRequested = true;
    notifyListeners();
  }

  bool takeBrushPaletteRequest() {
    if (!_brushPaletteRequested) {
      return false;
    }
    _brushPaletteRequested = false;
    return true;
  }

  // --- Undo/Redo ---

  /// Undoes the last scene change.
  void undo() {
    final undone = _historyManager.undo(_editorState.scene);
    if (undone != null) {
      _editorState = _editorState.copyWith(scene: undone);
      _syncLayoutFromScene();
      _lastChangedElements = null;
      onSceneChanged?.call(_editorState.scene, SceneChangeSource.undo);
      notifyListeners();
    }
  }

  /// Redoes the last undone scene change.
  void redo() {
    final redone = _historyManager.redo(_editorState.scene);
    if (redone != null) {
      _editorState = _editorState.copyWith(scene: redone);
      _syncLayoutFromScene();
      _lastChangedElements = null;
      onSceneChanged?.call(_editorState.scene, SceneChangeSource.redo);
      notifyListeners();
    }
  }

  // --- Zoom ---

  /// Zooms in by one step, centered on the canvas.
  void zoomIn(Size canvasSize) {
    final viewport = _editorState.viewport;
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final newZoom = (viewport.zoom + _config.zoomStep).clamp(
      _config.minZoom,
      _config.maxZoom,
    );
    final factor = newZoom / viewport.zoom;
    applyResult(
      UpdateViewportResult(
        viewport.zoomAt(
          factor,
          center,
          minZoom: _config.minZoom,
          maxZoom: _config.maxZoom,
        ),
      ),
    );
  }

  /// Zooms out by one step, centered on the canvas.
  void zoomOut(Size canvasSize) {
    final viewport = _editorState.viewport;
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final newZoom = (viewport.zoom - _config.zoomStep).clamp(
      _config.minZoom,
      _config.maxZoom,
    );
    final factor = newZoom / viewport.zoom;
    applyResult(
      UpdateViewportResult(
        viewport.zoomAt(
          factor,
          center,
          minZoom: _config.minZoom,
          maxZoom: _config.maxZoom,
        ),
      ),
    );
  }

  /// Resets the viewport to default zoom (1x) and offset (0, 0).
  void resetZoom() {
    applyResult(UpdateViewportResult(const ViewportState()));
  }

  /// Sets the viewport directly.
  void setViewport(ViewportState viewport) {
    applyResult(UpdateViewportResult(viewport));
  }

  /// Zooms to fit all scene elements within the canvas.
  void zoomToFit(Size canvasSize) {
    final bounds = ExportBounds.compute(_editorState.scene);
    if (bounds == null) return;
    applyResult(
      UpdateViewportResult(
        _editorState.viewport.fitToBounds(bounds, canvasSize, padding: 40),
      ),
    );
  }

  /// Zooms to fit the currently selected elements within the canvas.
  void zoomToSelection(Size canvasSize) {
    if (_editorState.selectedIds.isEmpty) return;
    final bounds = ExportBounds.compute(
      _editorState.scene,
      selectedIds: _editorState.selectedIds,
    );
    if (bounds == null) return;
    applyResult(
      UpdateViewportResult(
        _editorState.viewport.fitToBounds(bounds, canvasSize, padding: 40),
      ),
    );
  }

  // --- Default style application ---

  /// Applies the current [defaultStyle] to an element (used for newly
  /// created elements).
  Element applyDefaultStyleToElement(Element element) {
    Element styled = element.copyWith(
      strokeColor: _defaultStyle.strokeColor,
      backgroundColor: _defaultStyle.backgroundColor,
      strokeWidth: _defaultStyle.strokeWidth,
      strokeStyle: _defaultStyle.strokeStyle,
      fillStyle: _defaultStyle.fillStyle,
      roughness: _defaultStyle.roughness,
      opacity: _defaultStyle.opacity,
    );
    if (styled is TextElement) {
      styled = styled.copyWithText(
        fontSize: _defaultStyle.fontSize,
        fontFamily: _defaultStyle.fontFamily,
        textAlign: _defaultStyle.textAlign,
      );
    }
    if (styled is LineElement) {
      styled = styled.copyWithLine(
        startArrowhead: _defaultStyle.startArrowhead,
        clearStartArrowhead: _defaultStyle.startArrowheadNone,
        endArrowhead: _defaultStyle.endArrowhead,
        clearEndArrowhead: _defaultStyle.endArrowheadNone,
      );
    }
    if (styled is ArrowElement) {
      styled = styled.copyWithArrow(arrowType: _defaultStyle.arrowType);
    }
    if (_defaultStyle.roundness != null &&
        (styled is RectangleElement || styled is DiamondElement)) {
      final r = styled is DiamondElement
          ? Roundness.proportional(value: _defaultStyle.roundness!.value)
          : Roundness.adaptive(value: _defaultStyle.roundness!.value);
      styled = styled.copyWith(roundness: r);
    }
    return _attachCurrentPage(styled);
  }

  Element _attachCurrentPage(Element element) {
    if (!_layout.isPaged || element.isCanvasPage || element.pageId != null) {
      return element;
    }
    final page = _layout.pageAt(
      Offset(element.x + element.width / 2, element.y + element.height / 2),
    );
    if (page == null) {
      return element;
    }
    return element.copyWith(
      customData: _mergeCurrentPageCustomData(element.customData, page.id),
    );
  }

  Map<String, Object?> _mergeCurrentPageCustomData(
    Map<String, Object?>? customData,
    String pageId,
  ) {
    final next = {...?customData};
    final existingFlowMuse = next['flowMuse'];
    next['flowMuse'] = {
      if (existingFlowMuse is Map<String, Object?>) ...existingFlowMuse,
      'pageId': pageId,
    };
    return next;
  }

  Scene _sceneWithLayoutPages(Scene scene) {
    return _sceneWithLayoutPagesForLayout(scene, _layout);
  }

  void _syncLayoutFromScene({
    CanvasLayoutType? fallbackType,
    CanvasPageTemplate? fallbackTemplate,
    CanvasPageFlow? fallbackPageFlow,
  }) {
    _layout = CanvasLayout.fromScene(
      _editorState.scene.elements,
      fallbackType: fallbackType ?? _layout.type,
      fallbackTemplate: fallbackTemplate ?? _layout.template,
      fallbackPageFlow: fallbackPageFlow ?? _layout.pageFlow,
    );
  }

  ToolResult _applyDefaultStyleToResult(ToolResult result) {
    if (result is AddElementResult) {
      return AddElementResult(applyDefaultStyleToElement(result.element));
    }
    if (result is CompoundResult) {
      return CompoundResult(
        result.results.map(_applyDefaultStyleToResult).toList(),
      );
    }
    return result;
  }

  // --- Result application ---

  /// Applies a [ToolResult] to the editor state (scene, viewport, selection).
  void applyResult(ToolResult? result) {
    if (result == null) return;

    final constrained = _constrainViewport(result);
    final styled = isCreationTool
        ? _applyDefaultStyleToResult(constrained)
        : constrained;

    _syncToSystemClipboard(styled);

    if (_isEditingLinear && _containsSelectionChange(styled)) {
      _isEditingLinear = false;
    }

    final newState = _editorState.applyResult(styled);
    if (newState.activeToolType != _editorState.activeToolType) {
      final previousToolType = _editorState.activeToolType;
      _activeTool.reset();
      _activeTool = createTool(newState.activeToolType);

      if (previousToolType == ToolType.text) {
        _startTextEditing(newState);
      } else if (previousToolType == ToolType.mindmap) {
        // After creating a mind-map root node via tap, enter text editing
        // for the newly created (and now selected) node.
        _enterMindmapNodeEditing();
      }
    }
    _editorState = newState;

    if (isSceneChangingResult(styled)) {
      _lastChangedElements = _changedElementsFromResult(
        styled,
        _editorState.scene,
      );
      onSceneChanged?.call(_editorState.scene, SceneChangeSource.userEdit);
      _scheduleInkRecognitionFromResult(styled);
    }

    notifyListeners();
  }

  List<Element>? _changedElementsFromResult(ToolResult result, Scene scene) {
    final ids = <ElementId>{};
    var requiresFullScene = false;

    void collect(ToolResult item) {
      switch (item) {
        case AddElementResult(:final element):
        case UpdateElementResult(:final element):
          ids.add(element.id);
        case RemoveElementResult(:final id):
          ids.add(id);
        case AddFileResult():
        case RemoveFileResult():
        case SetSmartLayoutResult():
          requiresFullScene = true;
        case CompoundResult(:final results):
          for (final child in results) {
            collect(child);
          }
        case SetSelectionResult():
        case UpdateViewportResult():
        case SwitchToolResult():
        case SetClipboardResult():
          break;
      }
    }

    collect(result);
    if (requiresFullScene) return null;
    return [
      for (final element in scene.elements)
        if (ids.contains(element.id)) element,
    ];
  }

  ToolResult _constrainViewport(ToolResult result) {
    if (result is CompoundResult) {
      return CompoundResult(result.results.map(_constrainViewport).toList());
    }
    if (result is! UpdateViewportResult) return result;
    if (_canvasSize.width <= 0 || _canvasSize.height <= 0) return result;
    return UpdateViewportResult(_constrainedViewport(result.viewport));
  }

  ViewportState _constrainedViewport(ViewportState viewport) {
    var constrained = viewport;
    if (isPagedViewport) {
      constrained = clampPagedViewport(
        layout: _layout,
        viewport: constrained,
        canvasSize: _canvasSize,
      );
    }
    if (!isPagedViewport && _contentBounds != null) {
      constrained = clampViewportToBounds(
        constrained,
        _contentBounds,
        _canvasSize,
      );
    }
    return constrained;
  }

  void _applyViewportConstraints() {
    if (_canvasSize.width <= 0 || _canvasSize.height <= 0) {
      return;
    }
    final clamped = _constrainedViewport(_editorState.viewport);
    if (clamped != _editorState.viewport) {
      _editorState = _editorState.copyWith(viewport: clamped);
      notifyListeners();
    }
  }

  Bounds? get _pdfContentBounds {
    if (!_layout.pages.any((page) => page.source == 'pdf')) return null;
    final pdfPages = _layout.pages;
    var bounds = Bounds.fromLTWH(
      pdfPages.first.bounds.left,
      pdfPages.first.bounds.top,
      pdfPages.first.bounds.width,
      pdfPages.first.bounds.height,
    );
    for (final page in pdfPages.skip(1)) {
      bounds = bounds.union(
        Bounds.fromLTWH(
          page.bounds.left,
          page.bounds.top,
          page.bounds.width,
          page.bounds.height,
        ),
      );
    }
    return bounds;
  }

  void _syncToSystemClipboard(ToolResult result) {
    if (result is SetClipboardResult && result.elements.isNotEmpty) {
      final text = ClipboardCodec.serialize(result.elements);
      _clipboardService.copyText(text);
    } else if (result is CompoundResult) {
      for (final r in result.results) {
        _syncToSystemClipboard(r);
      }
    }
  }

  bool _containsSelectionChange(ToolResult result) {
    if (result is SetSelectionResult) return true;
    if (result is CompoundResult) {
      return result.results.any(_containsSelectionChange);
    }
    return false;
  }

  void _scheduleInkRecognitionFromResult(ToolResult result) {
    final sessionId = _pendingRecognitionSessionId(result);
    if (sessionId == null || onRecognizeInk == null) {
      return;
    }
    debugPrint('[$_logTag] ⏳ 调度识别 | sessionId: $sessionId | 1秒后触发');
    _pendingInkSessionId = sessionId;
    _inkRecognitionTimer?.cancel();
    _inkRecognitionTimer = Timer(const Duration(seconds: 1), () {
      final pending = _pendingInkSessionId;
      if (pending != null) {
        unawaited(_recognizePendingInkSession(pending));
      }
    });
  }

  String? _pendingRecognitionSessionId(ToolResult result) {
    final element = switch (result) {
      AddElementResult(:final element) ||
      UpdateElementResult(:final element) => element,
      _ => null,
    };
    if (element != null) {
      if (element is FreedrawElement &&
          element.isComplete &&
          element.customData?[recognitionStrokePendingKey] == true) {
        final sessionId = element.customData?[recognitionStrokeSessionKey];
        return sessionId is String ? sessionId : null;
      }
    }
    if (result is CompoundResult) {
      for (final child in result.results.reversed) {
        final sessionId = _pendingRecognitionSessionId(child);
        if (sessionId != null) {
          return sessionId;
        }
      }
    }
    return null;
  }

  Future<void> _recognizePendingInkSession(String sessionId) async {
    if (_recognizingInk || onRecognizeInk == null || _disposed) {
      return;
    }
    final request = _buildInkRecognitionRequest(
      sessionId,
      _pendingInkStrokes(sessionId),
    );
    if (request == null) {
      debugPrint('[$_logTag] ⏭️ 跳过识别 | sessionId: $sessionId | 无待处理笔画');
      return;
    }
    debugPrint(
      '[$_logTag] 🚀 开始识别 | sessionId: $sessionId | '
      '笔画数: ${request.strokes.length} | hint: ${request.hint}',
    );
    _recognizingInk = true;
    if (_activeTool is FreedrawTool) {
      (_activeTool as FreedrawTool).startNewSession();
    }
    try {
      final result = await onRecognizeInk!(request);
      if (_disposed) {
        return;
      }
      final pendingStrokes = _pendingInkStrokes(sessionId);
      if (pendingStrokes.isEmpty) {
        return;
      }
      final elements = result.elements
          .map(_elementFromRecognizedInk)
          .whereType<Element>()
          .toList();
      debugPrint(
        '[$_logTag] 📥 自动识别结果 | sessionId: $sessionId | '
        '服务端返回: ${result.elements.length} 个元素 | 成功转换: ${elements.length} 个元素',
      );
      if (elements.isEmpty) {
        _clearPendingInkSession(sessionId);
        return;
      }
      pushHistory();
      applyResult(
        CompoundResult([
          for (final stroke in pendingStrokes) RemoveElementResult(stroke.id),
          for (final element in elements) AddElementResult(element),
          SetSelectionResult({for (final element in elements) element.id}),
        ]),
      );
      if (_pendingInkSessionId == sessionId) {
        _pendingInkSessionId = null;
      }
    } catch (_) {
      debugPrint('[$_logTag] 🔄 识别失败，回退 | sessionId: $sessionId');
      if (!_disposed) {
        _clearPendingInkSession(sessionId);
      }
    } finally {
      _recognizingInk = false;
      final pending = _pendingInkSessionId;
      if (!_disposed && pending != null && pending != sessionId) {
        _inkRecognitionTimer?.cancel();
        _inkRecognitionTimer = Timer(const Duration(seconds: 1), () {
          final next = _pendingInkSessionId;
          if (next != null) {
            unawaited(_recognizePendingInkSession(next));
          }
        });
      }
    }
  }

  InkRecognitionRequest? _buildInkRecognitionRequest(
    String sessionId,
    List<FreedrawElement> strokes, {
    String hint = 'text',
  }) {
    if (strokes.isEmpty) {
      return null;
    }
    final absoluteStrokes = <InkRecognitionStroke>[];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final stroke in strokes) {
      final points = <InkRecognitionPoint>[];
      final pointTimes = _recognitionPointTimes(stroke);
      for (var i = 0; i < stroke.points.length; i++) {
        final point = stroke.points[i];
        final x = stroke.x + point.x;
        final y = stroke.y + point.y;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
        points.add(
          InkRecognitionPoint(
            x: x,
            y: y,
            t: i < pointTimes.length ? pointTimes[i] : null,
          ),
        );
      }
      if (points.length >= 2) {
        absoluteStrokes.add(
          InkRecognitionStroke(id: stroke.id.value, points: points),
        );
      }
    }
    if (absoluteStrokes.isEmpty) {
      return null;
    }
    return InkRecognitionRequest(
      sessionId: sessionId,
      strokes: absoluteStrokes,
      bounds: InkRecognitionBounds(
        x: minX,
        y: minY,
        width: math.max(maxX - minX, 1.0),
        height: math.max(maxY - minY, 1.0),
      ),
      hint: hint,
    );
  }

  List<int> _recognitionPointTimes(FreedrawElement stroke) {
    final raw = stroke.customData?[recognitionStrokePointTimesKey];
    if (raw is! List<Object?>) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is num) item.toInt(),
    ];
  }

  List<FreedrawElement> _pendingInkStrokes(String sessionId) {
    return [
      for (final element in _editorState.scene.elements)
        if (element is FreedrawElement &&
            !element.isDeleted &&
            element.customData?[recognitionStrokeSessionKey] == sessionId &&
            element.customData?[recognitionStrokePendingKey] == true)
          element,
    ];
  }

  Element? _elementFromRecognizedInk(InkRecognizedElement recognized) {
    final x = recognized.x;
    final y = recognized.y;
    final width = math.max(recognized.width, 1.0);
    final height = math.max(recognized.height, 1.0);
    switch (recognized.type) {
      case 'text':
        final text = recognized.text?.trim();
        if (text == null || text.isEmpty) {
          return null;
        }
        return _measuredTextElement(text, x, y, width, height);
      case 'math':
        final text = (recognized.latex ?? recognized.text)?.trim();
        if (text == null || text.isEmpty) {
          return null;
        }
        return _measuredTextElement(text, x, y, width, height, isMath: true);
      case 'rectangle':
        return RectangleElement(
          id: ElementId.generate(),
          x: x,
          y: y,
          width: width,
          height: height,
        );
      case 'ellipse':
        return EllipseElement(
          id: ElementId.generate(),
          x: x,
          y: y,
          width: width,
          height: height,
        );
      case 'diamond':
        return DiamondElement(
          id: ElementId.generate(),
          x: x,
          y: y,
          width: width,
          height: height,
        );
      case 'line':
        return LineElement(
          id: ElementId.generate(),
          x: x,
          y: y,
          width: width,
          height: height,
          points: _recognizedLinePoints(recognized, x, y, width, height),
        );
      case 'arrow':
        return ArrowElement(
          id: ElementId.generate(),
          x: x,
          y: y,
          width: width,
          height: height,
          points: _recognizedLinePoints(recognized, x, y, width, height),
        );
    }
    return null;
  }

  TextElement _measuredTextElement(
    String text,
    double x,
    double y,
    double width,
    double height, {
    bool isMath = false,
  }) {
    final anchor = _smartInkLayoutMode
        ? _nearestTemplateAnchor(Rect.fromLTWH(x, y, width, height))
        : null;
    final vertical = anchor?.writingMode == TemplateWritingMode.vertical;
    final flowMuseData = anchor == null && !isMath
        ? null
        : <String, Object?>{
            if (anchor != null) 'pageId': anchor.pageId,
            'smartLayout': true,
            if (isMath) 'smartLayoutType': 'math',
            if (vertical) 'writingMode': 'vertical',
          };
    final element = TextElement(
      id: ElementId.generate(),
      x: anchor?.position.dx ?? x,
      y: anchor?.position.dy ?? y,
      width: vertical
          ? math.max(anchor!.fontSize * 1.2, width)
          : math.max(width, 1.0),
      height: vertical
          ? math.max(text.runes.length * anchor!.lineHeight, height)
          : math.max(height, 1.0),
      text: text,
      fontSize: anchor?.fontSize ?? 20.0,
      lineHeight: _textLineHeightForTemplateAnchor(anchor),
      customData: flowMuseData == null ? null : {'flowMuse': flowMuseData},
    );
    final styled = applyDefaultStyleToElement(element) as TextElement;
    final (measuredWidth, measuredHeight) = TextRenderer.measure(styled);
    return styled.copyWith(
      width: math.max(measuredWidth, styled.width),
      height: math.max(measuredHeight, styled.height),
    );
  }

  TemplateAnchor? _nearestTemplateAnchor(Rect bounds) {
    if (!_layout.isPaged) return null;
    final page = _layout.pageAt(bounds.center);
    if (page == null) return null;
    return TemplateAnchorResolver.resolve(page).nearestAnchor(bounds);
  }

  double _textLineHeightForTemplateAnchor(TemplateAnchor? anchor) {
    if (anchor == null || anchor.fontSize <= 0) return 1.25;
    return anchor.lineHeight / anchor.fontSize;
  }

  List<Point> _recognizedLinePoints(
    InkRecognizedElement recognized,
    double x,
    double y,
    double width,
    double height,
  ) {
    if (recognized.points.length >= 2) {
      return [
        for (final point in recognized.points) Point(point.x - x, point.y - y),
      ];
    }
    return [Point.zero, Point(width, height)];
  }

  void _clearPendingInkSession(String sessionId) {
    final strokes = _pendingInkStrokes(sessionId);
    if (strokes.isEmpty) {
      return;
    }
    applyResult(
      CompoundResult([
        for (final stroke in strokes)
          UpdateElementResult(
            stroke.copyWith(
              customData: {
                ...?stroke.customData,
                recognitionStrokePendingKey: false,
              },
            ),
          ),
      ]),
    );
    if (_pendingInkSessionId == sessionId) {
      _pendingInkSessionId = null;
    }
  }

  // --- Text editing ---

  void _startTextEditing(EditorState state) {
    if (state.selectedIds.length != 1) return;
    final id = state.selectedIds.first;
    final element = state.scene.getElementById(id);
    if (element == null || element.type != 'text') return;

    _editingTextElementId = id;
    _isEditingExisting = false;
    _originalText = null;
    textEditingController.text = '';
    restoreTextFocusWhenStable();
  }

  /// Begins inline editing of an existing text element (double-click).
  void startTextEditingExisting(TextElement element) {
    _historyManager.push(_editorState.scene);
    _editingTextElementId = element.id;
    _isEditingExisting = true;
    _originalText = element.text;
    textEditingController.text = element.text;
    textEditingController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: element.text.length,
    );
    _editorState = _editorState.applyResult(SetSelectionResult({element.id}));
    notifyListeners();
    restoreTextFocusWhenStable();
  }

  /// Begins editing the bound text of a shape, creating it if needed.
  void startBoundTextEditing(Element shape) {
    _historyManager.push(_editorState.scene);
    final existing = _editorState.scene.findBoundText(shape.id);
    if (existing != null) {
      _editingTextElementId = existing.id;
      _isEditingExisting = true;
      _originalText = existing.text;
      textEditingController.text = existing.text;
      textEditingController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: existing.text.length,
      );
    } else {
      final newTextId = ElementId.generate();
      final textElem = TextElement(
        id: newTextId,
        x: shape.x,
        y: shape.y,
        width: shape.width,
        height: shape.height,
        text: '',
        containerId: shape.id.value,
        textAlign: core.TextAlign.center,
      );
      _editorState = _editorState.applyResult(AddElementResult(textElem));
      final newBound = [
        ...shape.boundElements,
        BoundElement(id: newTextId.value, type: 'text'),
      ];
      _editorState = _editorState.applyResult(
        UpdateElementResult(shape.copyWith(boundElements: newBound)),
      );
      _editingTextElementId = newTextId;
      _isEditingExisting = false;
      _originalText = null;
      textEditingController.text = '';
    }
    notifyListeners();
    restoreTextFocusWhenStable();
  }

  /// Begins editing the label of an arrow, creating it if needed.
  void startArrowLabelEditing(ArrowElement arrow) {
    _historyManager.push(_editorState.scene);
    final existing = _editorState.scene.findBoundText(arrow.id);
    if (existing != null) {
      _editingTextElementId = existing.id;
      _isEditingExisting = true;
      _originalText = existing.text;
      textEditingController.text = existing.text;
      textEditingController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: existing.text.length,
      );
    } else {
      final mid = ArrowLabelUtils.computeLabelPosition(arrow);
      final newTextId = ElementId.generate();
      final textElem = TextElement(
        id: newTextId,
        x: mid.x,
        y: mid.y,
        width: 100,
        height: 24,
        text: '',
        containerId: arrow.id.value,
        textAlign: core.TextAlign.center,
      );
      _editorState = _editorState.applyResult(AddElementResult(textElem));
      final newBound = [
        ...arrow.boundElements,
        BoundElement(id: newTextId.value, type: 'text'),
      ];
      _editorState = _editorState.applyResult(
        UpdateElementResult(arrow.copyWith(boundElements: newBound)),
      );
      _editingTextElementId = newTextId;
      _isEditingExisting = false;
      _originalText = null;
      textEditingController.text = '';
    }
    notifyListeners();
    restoreTextFocusWhenStable();
  }

  void _onTextFocusChanged() {
    if (!_textFocusNode.hasFocus &&
        _editingTextElementId != null &&
        !suppressFocusCommit) {
      commitTextEditing();
    }
  }

  /// Commits the current inline text edit, measuring and updating bounds.
  /// Removes the element if text is empty.
  void commitTextEditing() {
    final id = _editingTextElementId;
    if (id == null) return;

    final text = textEditingController.text.trim();
    if (text.isEmpty) {
      final element = _editorState.scene.getElementById(id);
      _editorState = _editorState.applyResult(RemoveElementResult(id));
      if (element is TextElement && element.containerId != null) {
        final parentId = ElementId(element.containerId!);
        final parent = _editorState.scene.getElementById(parentId);
        if (parent != null) {
          final newBound = parent.boundElements
              .where((b) => b.id != id.value)
              .toList();
          _editorState = _editorState.applyResult(
            UpdateElementResult(parent.copyWith(boundElements: newBound)),
          );
        }
      }
      _editorState = _editorState.applyResult(SetSelectionResult({}));
    } else {
      final element = _editorState.scene.getElementById(id);
      if (element is TextElement) {
        final measured = element.copyWithText(text: text);
        final isBound = element.containerId != null;
        if (isBound) {
          _editorState = _editorState.applyResult(
            UpdateElementResult(measured),
          );
        } else if (!element.autoResize && element.width > 0) {
          final (_, h) = TextRenderer.measure(
            measured,
            maxWidth: element.width,
          );
          final updated = measured.copyWith(
            height: math.max(h, element.height),
          );
          _editorState = _editorState.applyResult(UpdateElementResult(updated));
        } else {
          final (w, h) = TextRenderer.measure(measured);
          final updated = measured.copyWith(
            width: math.max(w + 4, 20.0),
            height: math.max(h, element.fontSize * element.lineHeight),
          );
          _editorState = _editorState.applyResult(UpdateElementResult(updated));
        }
      }
    }
    _editingTextElementId = null;
    _isEditingExisting = false;
    _originalText = null;
    textEditingController.clear();
    _lastChangedElements = null;
    onSceneChanged?.call(_editorState.scene, SceneChangeSource.userEdit);
    notifyListeners();
    // Request focus after the frame rebuilds — the TextEditingOverlay removal
    // detaches _textFocusNode, which triggers Scaffold's FocusScope.unfocus().
    // A synchronous requestFocus() here would be overridden by that unfocus.
    restoreKeyboardFocusWhenStable();
  }

  /// Cancels inline text editing, reverting to original text or removing
  /// the element if it was newly created.
  void cancelTextEditing() {
    if (_editingTextElementId != null) {
      if (_isEditingExisting && _originalText != null) {
        final element = _editorState.scene.getElementById(
          _editingTextElementId!,
        );
        if (element is TextElement) {
          _editorState = _editorState.applyResult(
            UpdateElementResult(element.copyWithText(text: _originalText!)),
          );
        }
      } else {
        final element = _editorState.scene.getElementById(
          _editingTextElementId!,
        );
        _editorState = _editorState.applyResult(
          RemoveElementResult(_editingTextElementId!),
        );
        if (element is TextElement && element.containerId != null) {
          final parentId = ElementId(element.containerId!);
          final parent = _editorState.scene.getElementById(parentId);
          if (parent != null) {
            final newBound = parent.boundElements
                .where((b) => b.id != _editingTextElementId!.value)
                .toList();
            _editorState = _editorState.applyResult(
              UpdateElementResult(parent.copyWith(boundElements: newBound)),
            );
          }
        }
        _editorState = _editorState.applyResult(SetSelectionResult({}));
      }
      _editingTextElementId = null;
      _isEditingExisting = false;
      _originalText = null;
      textEditingController.clear();
      notifyListeners();
      restoreKeyboardFocusWhenStable();
    }
  }

  // -- Frame label editing --------------------------------------------------

  /// Begins editing a frame's label text.
  void startFrameLabelEditing(FrameElement frame) {
    _editingFrameLabelId = frame.id;
    notifyListeners();
  }

  /// Commits a frame label edit if the label changed.
  void commitFrameLabel(String newLabel) {
    final id = _editingFrameLabelId;
    if (id == null) return;
    final element = _editorState.scene.getElementById(id);
    if (element is! FrameElement) {
      _editingFrameLabelId = null;
      notifyListeners();
      return;
    }
    final trimmed = newLabel.trim();
    if (trimmed.isNotEmpty && trimmed != element.label) {
      pushHistory();
      applyResult(UpdateElementResult(element.copyWithLabel(trimmed)));
    }
    _editingFrameLabelId = null;
    notifyListeners();
    restoreKeyboardFocusWhenStable();
  }

  /// Cancels frame label editing without saving.
  void cancelFrameLabelEditing() {
    _editingFrameLabelId = null;
    notifyListeners();
    restoreKeyboardFocusWhenStable();
  }

  /// Hit-tests whether a scene point is within a frame's label area.
  FrameElement? hitTestFrameLabel(Point scenePoint) {
    const labelHeight = 18.0; // 14px font + padding
    const labelPadding = 4.0;
    for (final element in _editorState.scene.activeElements.reversed) {
      if (element is! FrameElement) continue;
      final labelTop = element.y - labelPadding - labelHeight;
      final labelBottom = element.y - labelPadding;
      // Estimate label width: ~8px per character at 14px font
      final labelWidth = (element.label.length * 8.0).clamp(
        40.0,
        element.width,
      );
      if (scenePoint.x >= element.x &&
          scenePoint.x <= element.x + labelWidth &&
          scenePoint.y >= labelTop &&
          scenePoint.y <= labelBottom) {
        return element;
      }
    }
    return null;
  }

  /// Called on every keystroke during inline text editing to live-update
  /// the element bounds.
  void onTextChanged() {
    final id = _editingTextElementId;
    if (id == null) return;
    final element = _editorState.scene.getElementById(id);
    if (element is! TextElement) return;

    final text = textEditingController.text;
    final measured = element.copyWithText(text: text);
    final isBound = element.containerId != null;
    if (isBound) {
      _editorState = _editorState.applyResult(UpdateElementResult(measured));
    } else if (!element.autoResize && element.width > 0) {
      final (_, h) = TextRenderer.measure(measured, maxWidth: element.width);
      final updated = measured.copyWith(height: math.max(h, element.height));
      _editorState = _editorState.applyResult(UpdateElementResult(updated));
    } else {
      final (w, h) = TextRenderer.measure(measured);
      final updated = measured.copyWith(
        width: math.max(w + 4, 20.0),
        height: math.max(h, element.fontSize * element.lineHeight),
      );
      _editorState = _editorState.applyResult(UpdateElementResult(updated));
    }
    final changed = _editorState.scene.getElementById(id);
    _lastChangedElements = changed == null ? const [] : [changed];
    onSceneChanged?.call(_editorState.scene, SceneChangeSource.userEdit);
    notifyListeners();
  }

  // --- Library ---

  /// Adds the currently selected elements to the library.
  void addToLibrary() {
    final selected = selectedElements;
    if (selected.isEmpty) return;

    final name = 'Item ${_libraryItems.length + 1}';
    final item = LibraryUtils.createFromElements(
      elements: selected,
      name: name,
      allSceneElements: _editorState.scene.activeElements,
      sceneFiles: _editorState.scene.files,
    );
    _libraryItems = [..._libraryItems, item];
    _showLibraryPanel = true;
    notifyListeners();
  }

  /// Places a library item at the center of the visible canvas area.
  void placeLibraryItem(LibraryItem item, Size screenSize) {
    final centerScene = _editorState.viewport.screenToScene(
      Offset(screenSize.width / 2, screenSize.height / 2),
    );
    final position = Point(centerScene.dx, centerScene.dy);

    _historyManager.push(_editorState.scene);
    applyResult(LibraryUtils.instantiate(item: item, position: position));
  }

  /// Places a library item at a specific screen position (for drag-and-drop).
  void placeLibraryItemAt(LibraryItem item, Offset screenPosition) {
    final scenePos = _editorState.viewport.screenToScene(screenPosition);
    final position = Point(scenePos.dx, scenePos.dy);

    _historyManager.push(_editorState.scene);
    applyResult(LibraryUtils.instantiate(item: item, position: position));
  }

  /// Removes a library item by its ID.
  void removeLibraryItem(String id) {
    _libraryItems = _libraryItems.where((i) => i.id != id).toList();
    notifyListeners();
  }

  /// Replaces the full library items list (e.g. after import).
  set libraryItems(List<LibraryItem> items) {
    _libraryItems = items;
    notifyListeners();
  }

  // --- Viewport ---

  /// Resolves decoded images for all image files in the scene. Returns null
  /// if no images are available yet.
  Map<String, ui.Image>? resolveImages() {
    final files = _editorState.scene.files;
    if (files.isEmpty) return null;
    final resolved = <String, ui.Image>{};
    for (final entry in files.entries) {
      final image = _imageCache.getImage(entry.key, entry.value);
      if (image != null) {
        resolved[entry.key] = image;
      }
    }
    return resolved.isEmpty ? null : resolved;
  }

  /// Converts a screen-space offset to a scene-space point.
  Point toScene(Offset screenPos) {
    final scene = _editorState.viewport.screenToScene(screenPos);
    return Point(scene.dx, scene.dy);
  }

  /// Converts a screen-space offset to a scene-space point WITHOUT rounding.
  /// Used exclusively by freedraw to avoid 1 scene-pixel quantization noise.
  Point toScenePrecise(Offset screenPos) {
    final scene = _editorState.viewport.screenToScenePrecise(screenPos);
    return Point(scene.dx, scene.dy);
  }

  bool canCreateAt(Point point) {
    final isPdfLayout =
        _layout.isPaged && _layout.pages.any((page) => page.source == 'pdf');
    if (!isPdfLayout) return true;
    final offset = Offset(point.x, point.y);
    return _layout.pages.any((page) => page.bounds.contains(offset));
  }

  // --- Pointer handling ---

  bool _isStylus(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  bool get _usesTemporaryTouchPan =>
      _singleFingerPanEnabled &&
      !_fingerDrawingEnabled &&
      _editorState.activeToolType != ToolType.hand;

  /// Handles pointer down: commits text edits, dispatches to tool, handles
  /// link-to-element mode and link icon clicks.
  void onPointerDown(PointerEvent event) {
    if (_isViewportGesture) return;
    if (event.kind == PointerDeviceKind.touch &&
        _palmRejectionEnabled &&
        _activeStylusPointerId != null) {
      _rejectedTouchPointers.add(event.pointer);
      return;
    }
    if (event.kind == PointerDeviceKind.touch && _usesTemporaryTouchPan) {
      if (!_palmRejectionEnabled || _activeStylusPointerId == null) {
        _temporaryTouchPanPointerId ??= event.pointer;
      }
      return;
    }
    if (_isStylus(event.kind)) {
      _activeStylusPointerId = event.pointer;
      if (_palmRejectionEnabled) {
        final touchPointer = _temporaryTouchPanPointerId;
        if (touchPointer != null) {
          _rejectedTouchPointers.add(touchPointer);
        }
        _temporaryTouchPanPointerId = null;
      }
    }
    if (isCreationTool && !shouldDispatchToCreationTool(event.kind)) return;
    restoreKeyboardFocusWhenStable();
    if (_editingTextElementId != null) {
      commitTextEditing();
    }
    // Frame label editing is committed by the overlay itself on submit/blur.
    // We don't force-commit here since the TextField handles its own focus.

    if (_useUnifiedModeler && _activeTool is FreedrawTool) {
      // --- Unified modeler path for freedraw ---
      final sample = _normalizer.normalize(event, phase: StrokePhase.down);
      _recorder?.record(
        sample,
        viewportZoom: _editorState.viewport.zoom,
        viewportTransform: _viewportTransform,
      );
      _activeDrawPointerId = sample.pointerId;
      _modeler = StrokeInputModeler(
        _policySelector.select(sample.kind),
        useRealPressure: _pressureEnabled,
        pressureExponent: _pressureExponent,
      );
      final r = _modeler!.process(sample);
      if (r.point == null) return;

      final sceneOffset = _editorState.viewport.screenToScenePrecise(
        Offset(r.point!.x, r.point!.y),
      );
      final point = Point(sceneOffset.dx, sceneOffset.dy);

      if (isCreationTool && !canCreateAt(point)) {
        _modeler = null;
        _activeDrawPointerId = null;
        return;
      }

      _sceneBeforeDrag = _editorState.scene;
      applyResult(
        _activeTool.onPointerDown(point, toolContext, pressure: r.pressure),
      );
      return;
    }

    // --- Legacy path (non-freedraw tools or feature flag off) ---
    final effectiveLocalPosition = event.localPosition;
    final point = _activeTool is FreedrawTool
        ? toScenePrecise(effectiveLocalPosition)
        : toScene(effectiveLocalPosition);

    if (isCreationTool && !canCreateAt(point)) {
      return;
    }

    // Link-to-element mode: clicking an element sets the link target
    if (_linkToElementMode) {
      final hit = _editorState.scene.getElementAtPoint(point);
      if (hit != null && _editorState.selectedIds.length == 1) {
        final sourceId = _editorState.selectedIds.first;
        if (hit.id != sourceId) {
          setElementLink(sourceId, '#${hit.id.value}');
          _linkToElementMode = false;
          _isLinkEditorOpen = false;
          _isLinkEditorEditing = false;
          notifyListeners();
          return;
        }
      }
      _linkToElementMode = false;
      notifyListeners();
      return;
    }

    // Check if click hit a link icon
    final linkedElement = hitTestLinkIcon(point);
    if (linkedElement != null) {
      // Need canvas size for followLink — use a reasonable fallback
      followLink(linkedElement.link!, _lastCanvasSize ?? const Size(800, 600));
      return;
    }

    // Close link editor when clicking elsewhere
    if (_isLinkEditorOpen) {
      closeLinkEditor();
    }

    _sceneBeforeDrag = _editorState.scene;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (_activeTool is SelectTool) {
      applyResult(
        (_activeTool as SelectTool).onPointerDown(
          point,
          toolContext,
          shift: shift,
        ),
      );
    } else {
      applyResult(_activeTool.onPointerDown(point, toolContext));
    }
  }

  /// Handles pointer move: dispatches to the active tool.
  void onPointerMove(PointerEvent event) {
    if (_isViewportGesture) return;
    if (_rejectedTouchPointers.contains(event.pointer)) return;
    if (event.pointer == _temporaryTouchPanPointerId) {
      applyResult(UpdateViewportResult(_editorState.viewport.pan(event.delta)));
      return;
    }
    if (event.kind == PointerDeviceKind.touch && _usesTemporaryTouchPan) {
      return;
    }
    if (_useUnifiedModeler &&
        _activeTool is FreedrawTool &&
        _activeDrawPointerId != null) {
      // --- Unified modeler path for freedraw ---
      if (event.pointer != _activeDrawPointerId) return;
      final sample = _normalizer.normalize(event, phase: StrokePhase.move);
      _recorder?.record(
        sample,
        viewportZoom: _editorState.viewport.zoom,
        viewportTransform: _viewportTransform,
      );
      final r = _modeler!.process(sample);
      if (r.point == null) return; // dropped by modeler
      final sceneOffset = _editorState.viewport.screenToScenePrecise(
        Offset(r.point!.x, r.point!.y),
      );
      final point = Point(sceneOffset.dx, sceneOffset.dy);
      applyResult(
        _activeTool.onPointerMove(
          point,
          toolContext,
          screenDelta: event.delta,
          pressure: r.pressure,
        ),
      );
      _scheduleLiveFreedraw();
      mousePosition = event.localPosition;
      notifyListeners();
      return;
    }

    // --- Legacy path (non-freedraw tools or feature flag off) ---
    if (isCreationTool && !shouldDispatchToCreationTool(event.kind)) return;
    final point = _activeTool is FreedrawTool
        ? toScenePrecise(event.localPosition)
        : toScene(event.localPosition);
    applyResult(
      _activeTool.onPointerMove(point, toolContext, screenDelta: event.delta),
    );
    _scheduleLiveFreedraw();
    mousePosition = event.localPosition;
    notifyListeners();
  }

  /// Handles pointer up: dispatches to tool, detects double-click for
  /// text/label editing, and pushes drag history.
  void onPointerUp(PointerEvent event) {
    if (_isViewportGesture) return;
    if (_rejectedTouchPointers.remove(event.pointer)) return;
    if (event.pointer == _temporaryTouchPanPointerId) {
      _temporaryTouchPanPointerId = null;
      return;
    }
    if (_isStylus(event.kind) && event.pointer == _activeStylusPointerId) {
      _activeStylusPointerId = null;
    }
    if (event.kind == PointerDeviceKind.touch && _usesTemporaryTouchPan) {
      return;
    }
    if (_useUnifiedModeler &&
        _activeTool is FreedrawTool &&
        _activeDrawPointerId != null) {
      // --- Unified modeler path for freedraw ---
      if (event.pointer != _activeDrawPointerId) return;
      _cancelPendingLiveFreedraw();
      final sample = _normalizer.normalize(event, phase: StrokePhase.up);
      _recorder?.record(
        sample,
        viewportZoom: _editorState.viewport.zoom,
        viewportTransform: _viewportTransform,
      );
      final r = _modeler!.process(sample); // flushes real endpoint

      if (r.point != null) {
        final sceneOffset = _editorState.viewport.screenToScenePrecise(
          Offset(r.point!.x, r.point!.y),
        );
        final point = Point(sceneOffset.dx, sceneOffset.dy);
        applyResult(
          _activeTool.onPointerMove(point, toolContext, pressure: r.pressure),
        );
        applyResult(
          _activeTool.onPointerUp(point, toolContext, pressure: r.pressure),
        );
      }

      _modeler = null;
      _activeDrawPointerId = null;

      if (_sceneBeforeDrag != null &&
          !identical(_editorState.scene, _sceneBeforeDrag)) {
        _historyManager.push(_sceneBeforeDrag!);
      }
      _sceneBeforeDrag = null;
      return;
    }

    // --- Legacy path (non-freedraw tools or feature flag off) ---
    if (isCreationTool && !shouldDispatchToCreationTool(event.kind)) return;
    final point = _activeTool is FreedrawTool
        ? toScenePrecise(event.localPosition)
        : toScene(event.localPosition);
    final now = DateTime.now();
    final isDoubleClick =
        _lastPointerUpTime != null &&
        now.difference(_lastPointerUpTime!).inMilliseconds < 300;
    _lastPointerUpTime = now;

    if (_activeTool is LineTool) {
      applyResult(
        (_activeTool as LineTool).onPointerUp(
          point,
          toolContext,
          isDoubleClick: isDoubleClick,
        ),
      );
    } else if (_activeTool is ArrowTool) {
      applyResult(
        (_activeTool as ArrowTool).onPointerUp(
          point,
          toolContext,
          isDoubleClick: isDoubleClick,
        ),
      );
    } else {
      applyResult(_activeTool.onPointerUp(point, toolContext));
    }

    // Double-click dispatch for text editing, line editing, and frame labels
    if (isDoubleClick &&
        _activeTool is SelectTool &&
        _editingTextElementId == null) {
      // Check frame label area first (above the frame, not inside it)
      final frameHit = hitTestFrameLabel(point);
      if (frameHit != null) {
        startFrameLabelEditing(frameHit);
      } else {
        final hit = _editorState.scene.getElementAtPoint(point);
        if (hit is TextElement) {
          startTextEditingExisting(hit);
        } else if (hit != null && BoundTextUtils.isTextContainer(hit)) {
          startBoundTextEditing(hit);
        } else if (hit is ArrowElement) {
          startArrowLabelEditing(hit);
        } else if (hit is LineElement) {
          _isEditingLinear = true;
          notifyListeners();
        } else if (hit is FrameElement) {
          startFrameLabelEditing(hit);
        }
      }
    }

    if (_sceneBeforeDrag != null &&
        !identical(_editorState.scene, _sceneBeforeDrag)) {
      _historyManager.push(_sceneBeforeDrag!);
    }
    _sceneBeforeDrag = null;
  }

  /// Handles pointer cancel: discards uncommitted stroke for modeler path,
  /// resets the active tool without committing.
  void onPointerCancel(PointerEvent event) {
    if (_isViewportGesture) return;
    if (_rejectedTouchPointers.remove(event.pointer)) return;
    if (event.pointer == _temporaryTouchPanPointerId) {
      _temporaryTouchPanPointerId = null;
      return;
    }
    if (_isStylus(event.kind) && event.pointer == _activeStylusPointerId) {
      _activeStylusPointerId = null;
    }
    if (event.kind == PointerDeviceKind.touch && _usesTemporaryTouchPan) {
      return;
    }
    _modeler?.reset(reason: 'cancel');
    _modeler = null;
    _activeDrawPointerId = null;
    _cancelActiveToolInteraction();
    _sceneBeforeDrag = null;
  }

  /// Handles pointer hover: updates tool cursor position.
  void onPointerHover(Offset localPosition) {
    final point = toScene(localPosition);
    _activeTool.onPointerMove(point, toolContext);
    mousePosition = localPosition;
    notifyListeners();
  }

  /// Handles scroll-wheel zoom.
  void onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final ctrl =
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      if (isPagedViewport && !ctrl) {
        scrollPagedViewportBy(event.scrollDelta.dy);
        return;
      }
      final factor = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
      final newViewport = _editorState.viewport.zoomAt(
        factor,
        event.localPosition,
        minZoom: _config.minZoom,
        maxZoom: _config.maxZoom,
      );
      applyResult(UpdateViewportResult(newViewport));
    }
  }

  /// Records the starting zoom and offset for a pinch gesture.
  void onScaleStart(ScaleStartDetails details) {
    if (!_twoFingerZoomEnabled && !_fingerDrawingEnabled) return;
    _pinchStartZoom = _editorState.viewport.zoom;
    _pinchStartOffset = _editorState.viewport.offset;
    _pinchStartFocalPoint = details.localFocalPoint;
    _twoFingerGestureMode = null;
  }

  /// Applies pinch-to-zoom and pan during a scale gesture.
  void onScaleUpdate(ScaleUpdateDetails details) {
    if (!_twoFingerZoomEnabled && !_fingerDrawingEnabled) return;
    if (details.pointerCount < 2) return;
    final mode = _twoFingerGestureMode ?? _resolveTwoFingerGesture(details);
    if (mode == null) return;
    _twoFingerGestureMode = mode;
    if (!_isViewportGesture) {
      _isViewportGesture = true;
      _cancelActiveInteractionForViewportGesture();
    }
    final newZoom = mode == _TwoFingerGestureMode.zoom
        ? (_pinchStartZoom * details.scale)
              .clamp(_config.minZoom, _config.maxZoom)
              .toDouble()
        : _pinchStartZoom;
    final focalPoint = mode == _TwoFingerGestureMode.zoom
        ? _pinchStartFocalPoint
        : details.localFocalPoint;

    // Both `scale` and the focal point are cumulative from the start of the
    // gesture. Keep the scene point under the initial focal point anchored
    // beneath the current focal point so pan and zoom stay continuous.
    final anchoredScenePoint = Offset(
      _pinchStartOffset.dx + _pinchStartFocalPoint.dx / _pinchStartZoom,
      _pinchStartOffset.dy + _pinchStartFocalPoint.dy / _pinchStartZoom,
    );
    final newViewport = ViewportState(
      offset: Offset(
        anchoredScenePoint.dx - focalPoint.dx / newZoom,
        anchoredScenePoint.dy - focalPoint.dy / newZoom,
      ),
      zoom: newZoom,
    );
    applyResult(UpdateViewportResult(newViewport));
  }

  _TwoFingerGestureMode? _resolveTwoFingerGesture(
    ScaleUpdateDetails details,
  ) {
    if ((details.scale - 1).abs() >= 0.02) {
      return _TwoFingerGestureMode.zoom;
    }
    if ((details.localFocalPoint - _pinchStartFocalPoint).distance >= 2) {
      return _TwoFingerGestureMode.pan;
    }
    return null;
  }

  /// Releases any tool interaction once a two-finger viewport gesture wins.
  /// This keeps raw pointer events from applying a second pan or mutating a
  /// shape while [GestureDetector] owns the viewport transform.
  void _cancelActiveInteractionForViewportGesture() {
    _modeler?.reset(reason: 'viewport gesture');
    _modeler = null;
    _activeDrawPointerId = null;
    _temporaryTouchPanPointerId = null;
    _activeStylusPointerId = null;
    _cancelActiveToolInteraction();
    _sceneBeforeDrag = null;
  }

  void _cancelActiveToolInteraction() {
    if (_activeTool is FreedrawTool) {
      _cancelPendingLiveFreedraw();
      _emitLiveFreedraw((_activeTool as FreedrawTool).cancelStroke());
    } else {
      _activeTool.reset();
    }
  }

  void _emitLiveFreedraw([FreedrawElement? element]) {
    final callback = onLiveFreedrawChanged;
    if (callback == null) return;
    final live =
        element ??
        (_activeTool is FreedrawTool
            ? (_activeTool as FreedrawTool).buildLiveElement(toolContext)
            : null);
    if (live == null) return;
    callback(applyDefaultStyleToElement(live) as FreedrawElement);
  }

  void _scheduleLiveFreedraw() {
    if (onLiveFreedrawChanged == null || _liveFreedrawTimer != null) {
      return;
    }
    _liveFreedrawTimer = Timer(_liveFreedrawBroadcastInterval, () {
      _liveFreedrawTimer = null;
      _emitLiveFreedraw();
    });
  }

  void _cancelPendingLiveFreedraw() {
    _liveFreedrawTimer?.cancel();
    _liveFreedrawTimer = null;
  }

  /// Marks the end of a two-finger viewport gesture.
  void onScaleEnd(ScaleEndDetails details) {
    _isViewportGesture = false;
    _twoFingerGestureMode = null;
  }

  // --- Style changes ---

  /// Applies a style change to selected elements and updates the sticky
  /// default style. Handles bound text, frame opacity propagation, and
  /// text re-measurement.
  void applyStyleChange(ElementStyle style) {
    final wasEditing = _editingTextElementId != null;
    final savedSelection = wasEditing ? editableTextSelection : null;
    if (wasEditing) suppressFocusCommit = true;

    // Update sticky defaults
    _defaultStyle = ElementStyle(
      strokeColor: style.strokeColor ?? _defaultStyle.strokeColor,
      backgroundColor: style.backgroundColor ?? _defaultStyle.backgroundColor,
      strokeWidth: style.strokeWidth ?? _defaultStyle.strokeWidth,
      strokeStyle: style.strokeStyle ?? _defaultStyle.strokeStyle,
      fillStyle: style.fillStyle ?? _defaultStyle.fillStyle,
      roughness: style.roughness ?? _defaultStyle.roughness,
      opacity: style.opacity ?? _defaultStyle.opacity,
      fontSize: style.fontSize ?? _defaultStyle.fontSize,
      fontFamily: style.fontFamily ?? _defaultStyle.fontFamily,
      textAlign: style.textAlign ?? _defaultStyle.textAlign,
      verticalAlign: style.verticalAlign ?? _defaultStyle.verticalAlign,
      startArrowhead: style.startArrowheadNone
          ? null
          : (style.startArrowhead ?? _defaultStyle.startArrowhead),
      startArrowheadNone:
          style.startArrowheadNone ||
          (style.startArrowhead == null && _defaultStyle.startArrowheadNone),
      endArrowhead: style.endArrowheadNone
          ? null
          : (style.endArrowhead ?? _defaultStyle.endArrowhead),
      endArrowheadNone:
          style.endArrowheadNone ||
          (style.endArrowhead == null && _defaultStyle.endArrowheadNone),
      arrowType: style.arrowType ?? _defaultStyle.arrowType,
      roundness:
          style.roundness ??
          (style.hasRoundness ? null : _defaultStyle.roundness),
    );
    if (_editorState.activeToolType == ToolType.freedraw) {
      _rememberCurrentBrushState();
    }

    final elements = selectedElements;
    if (elements.isEmpty) {
      notifyListeners();
      restoreTextFocus(wasEditing, savedSelection);
      return;
    }

    _historyManager.push(_editorState.scene);

    // When editing bound text, strokeColor targets the text, not the shape.
    final editingBoundText = _editingTextElementId != null
        ? _editorState.scene.getElementById(_editingTextElementId!)
        : null;
    final isEditingBoundText =
        editingBoundText is TextElement && editingBoundText.containerId != null;

    // Apply style to selected elements — but exclude strokeColor from the
    // parent shape when the user is editing its bound text.
    final shapeStyle = isEditingBoundText && style.strokeColor != null
        ? style.copyWith(clearStrokeColor: true)
        : style;
    final result = PropertyPanelState.applyStyle(elements, shapeStyle);
    applyResult(result);

    // When opacity changes on a frame, propagate to all children
    if (style.opacity != null) {
      for (final e in elements) {
        if (e is FrameElement) {
          final children = FrameUtils.findFrameChildren(
            _editorState.scene,
            e.id,
          );
          for (final child in children) {
            applyResult(
              UpdateElementResult(child.copyWith(opacity: style.opacity)),
            );
          }
        }
      }
    }

    // Also apply text properties to bound text of selected containers
    if (style.fontSize != null ||
        style.fontFamily != null ||
        style.textAlign != null ||
        style.verticalAlign != null ||
        style.strokeColor != null) {
      for (final e in elements) {
        final bt = _editorState.scene.findBoundText(e.id);
        if (bt != null) {
          var updated = bt.copyWithText(
            fontSize: style.fontSize,
            fontFamily: style.fontFamily,
            textAlign: style.textAlign,
            verticalAlign: style.verticalAlign,
          );
          if (style.strokeColor != null) {
            updated = updated.copyWith(strokeColor: style.strokeColor);
          }
          applyResult(UpdateElementResult(updated));
        }
      }
    }

    // Re-measure text bounds after font-related style changes
    if (style.fontSize != null || style.fontFamily != null) {
      _remeasureSelectedTextElements();
    }

    restoreTextFocus(wasEditing, savedSelection);
  }

  /// Restores text editing focus and selection after a style change dialog.
  void restoreTextFocus(bool wasEditing, TextSelection? savedSelection) {
    if (!wasEditing || _editingTextElementId == null) {
      suppressFocusCommit = false;
      return;
    }
    restoreTextFocusWhenStable();
    runAfterUiFrame(() {
      if (_disposed) {
        return;
      }
      suppressFocusCommit = false;
      if (savedSelection != null && _editingTextElementId != null) {
        restoreEditableTextSelection(savedSelection);
      }
    });
  }

  /// Re-measures selected text elements and updates their bounds.
  void _remeasureSelectedTextElements() {
    for (final e in selectedElements) {
      if (e is! TextElement) continue;
      if (e.containerId != null) continue;

      // Re-fetch from scene since applyResult may have updated it
      final current = _editorState.scene.getElementById(e.id);
      if (current is! TextElement) continue;

      final validated = TextBoundsValidator.validateElement(current);
      if (!identical(validated, current)) {
        applyResult(UpdateElementResult(validated));
      }
    }
  }

  // --- Key dispatch ---

  /// Dispatches a key event to the active tool (for programmatic shortcuts).
  void dispatchKey(String key, {bool shift = false, bool ctrl = false}) {
    if (key == 'Escape' && _activeTool is FreedrawTool) {
      _cancelActiveToolInteraction();
      return;
    }
    final result = _activeTool.onKeyEvent(
      key,
      shift: shift,
      ctrl: ctrl,
      context: toolContext,
    );
    if (isSceneChangingResult(result)) {
      _historyManager.push(_editorState.scene);
    }
    applyResult(result);
  }

  // --- Selection helpers ---

  /// Whether the user is currently dragging a point handle on a line/arrow.
  bool isDraggingPointHandle() {
    return _activeTool is SelectTool &&
        (_activeTool as SelectTool).isDraggingPoint;
  }

  /// Returns point handle positions for the selected line/arrow, or null.
  List<Point>? buildPointHandles() {
    if (_editorState.selectedIds.length != 1) return null;
    final elem = _editorState.scene.getElementById(
      _editorState.selectedIds.first,
    );
    if (elem == null) return null;
    if (elem is LineElement) {
      // Always show endpoint handles for simple 2-point lines/arrows
      // (their bounding box is hidden). For 3+ point lines, require
      // double-click to enter linear editing mode.
      if (elem.points.length <= 2 || _isEditingLinear) {
        return elem.points
            .map((p) => Point(elem.x + p.x, elem.y + p.y))
            .toList();
      }
    }
    return null;
  }

  /// Returns segment midpoint positions for elbow arrow editing, or null.
  List<Point>? buildSegmentMidpoints() {
    if (!_isEditingLinear) return null;
    if (_editorState.selectedIds.length != 1) return null;
    final elem = _editorState.scene.getElementById(
      _editorState.selectedIds.first,
    );
    if (elem == null) return null;
    if (elem is! ArrowElement || !elem.elbowed) return null;
    if (elem.points.length < 2) return null;

    final midpoints = <Point>[];
    for (var i = 0; i < elem.points.length - 1; i++) {
      final a = elem.points[i];
      final b = elem.points[i + 1];
      midpoints.add(Point(elem.x + (a.x + b.x) / 2, elem.y + (a.y + b.y) / 2));
    }
    return midpoints;
  }

  /// Returns midpoint handles for adding new points to a line, or null.
  List<Point>? buildMidpointHandles() {
    if (!_isEditingLinear) return null;
    if (_editorState.selectedIds.length != 1) return null;
    final elem = _editorState.scene.getElementById(
      _editorState.selectedIds.first,
    );
    if (elem == null) return null;
    if (elem is! LineElement) return null;
    if (elem is ArrowElement && elem.elbowed) return null;
    if (elem.points.length < 2) return null;

    final midpoints = <Point>[];
    for (var i = 0; i < elem.points.length - 1; i++) {
      final a = elem.points[i];
      final b = elem.points[i + 1];
      midpoints.add(Point(elem.x + (a.x + b.x) / 2, elem.y + (a.y + b.y) / 2));
    }
    return midpoints;
  }

  /// Builds the selection overlay (bounding box + handles) for the current
  /// selection, or null if nothing is selected.
  SelectionOverlay? buildSelectionOverlay() {
    if (_editorState.selectedIds.isEmpty) return null;
    final selected = _editorState.selectedIds
        .map((id) => _editorState.scene.getElementById(id))
        .whereType<Element>()
        .toList();
    if (selected.isEmpty) return null;
    return SelectionOverlay.fromElements(selected, mode: interactionMode);
  }

  // --- Preview element ---

  /// Builds a transient preview element from the tool overlay (shown during
  /// creation drag), or null if no preview is active.
  Element? buildPreviewElement(ToolOverlay? overlay) {
    if (overlay == null) return null;
    final toolType = _editorState.activeToolType;
    const previewId = ElementId('__preview__');
    const previewSeed = 42;

    Element? element;

    if (overlay.creationBounds != null) {
      final b = overlay.creationBounds!;
      element = switch (toolType) {
        ToolType.rectangle => RectangleElement(
          id: previewId,
          x: b.left,
          y: b.top,
          width: b.size.width,
          height: b.size.height,
          seed: previewSeed,
        ),
        ToolType.ellipse => EllipseElement(
          id: previewId,
          x: b.left,
          y: b.top,
          width: b.size.width,
          height: b.size.height,
          seed: previewSeed,
        ),
        ToolType.diamond => DiamondElement(
          id: previewId,
          x: b.left,
          y: b.top,
          width: b.size.width,
          height: b.size.height,
          seed: previewSeed,
        ),
        _ => null,
      };
    }

    if (element == null &&
        overlay.creationPoints != null &&
        overlay.creationPoints!.length >= 2) {
      final pts = overlay.creationPoints!;
      final isFreedrawPreview = toolType == ToolType.freedraw;
      // A live freedraw preview is rendered unconditionally, so it does not
      // need culling bounds or a per-frame conversion to relative points.
      // Keep the input list in scene coordinates until pointer-up creates the
      // final persisted element.
      final minX = isFreedrawPreview
          ? 0.0
          : pts.map((p) => p.x).reduce(math.min);
      final minY = isFreedrawPreview
          ? 0.0
          : pts.map((p) => p.y).reduce(math.min);
      final maxX = isFreedrawPreview
          ? 0.0
          : pts.map((p) => p.x).reduce(math.max);
      final maxY = isFreedrawPreview
          ? 0.0
          : pts.map((p) => p.y).reduce(math.max);
      final relPts = isFreedrawPreview
          ? pts
          : pts.map((p) => Point(p.x - minX, p.y - minY)).toList();

      element = switch (toolType) {
        ToolType.line => LineElement(
          id: previewId,
          x: minX,
          y: minY,
          width: maxX - minX,
          height: maxY - minY,
          points: relPts,
          seed: previewSeed,
          closed: overlay.creationClosed,
        ),
        ToolType.arrow => ArrowElement(
          id: previewId,
          x: minX,
          y: minY,
          width: maxX - minX,
          height: maxY - minY,
          points: relPts,
          seed: previewSeed,
          endArrowhead: Arrowhead.arrow,
        ),
        ToolType.freedraw => FreedrawElement(
          id: previewId,
          x: minX,
          y: minY,
          width: maxX - minX,
          height: maxY - minY,
          points: relPts,
          pressures: overlay.creationPressures ?? const [],
          simulatePressure:
              overlay.creationPressures == null ||
              overlay.creationPressures!.isEmpty,
          isComplete: false,
          seed: previewSeed,
        ),
        _ => null,
      };
    }

    return element != null ? applyDefaultStyleToElement(element) : null;
  }

  // --- Scene management ---

  void _endTextEditingBeforeSceneReplace() {
    if (_editingTextElementId == null) {
      return;
    }
    _editingTextElementId = null;
    _isEditingExisting = false;
    _originalText = null;
    textEditingController.clear();
    _textFocusNode.unfocus();
  }

  void closeTransientUiForSceneReplace() {
    _endTextEditingBeforeSceneReplace();
    _editingFrameLabelId = null;
    _fontPickerOpen = false;
    _isLinkEditorOpen = false;
    _isLinkEditorEditing = false;
    _linkToElementMode = false;
    _isFindOpen = false;
    _findQuery = '';
    _findResults = [];
    _findCurrentIndex = -1;
    suppressFocusCommit = false;
    _pendingColorPicker = null;
  }

  /// Loads a new scene, clearing undo history. Use for file-open operations.
  void loadScene(Scene scene, {String? background}) {
    closeTransientUiForSceneReplace();
    _historyManager.clear();
    final validated = TextBoundsValidator.validateScene(scene);
    _editorState = _editorState.copyWith(scene: validated, selectedIds: {});
    _syncLayoutFromScene();
    _editorState = _editorState.copyWith(
      scene: _sceneWithLayoutPages(validated),
    );
    _applyViewportConstraints();
    if (background != null) {
      _canvasBackgroundColor = background;
    }
    _prewarmImageCache();
    notifyListeners();
  }

  /// 串行预解码场景中的图片,避免渲染时 resolveImages 对所有图片
  /// 并发触发 instantiateImageCodec 导致内存压力/解码失败。
  /// 对齐 importPdfPages 的逐页 await 串行策略。
  Future<void> _prewarmImageCache() async {
    final files = _editorState.scene.files;
    if (files.isEmpty) return;
    // 同步先把所有 fileId 占位为"解码中",这样 loadScene 的 notifyListeners
    // 触发首次渲染时,resolveImages → getImage 不会并发启动 _decode,
    // 而是全部返回 null,等预热串行解码完后逐张 notifyListeners 显示。
    _imageCache.markDecoding(files.keys);
    for (final entry in files.entries) {
      if (!_disposed) {
        await _imageCache.decodeAndWait(entry.key, entry.value);
      }
    }
    if (!_disposed) notifyListeners();
  }

  /// Replaces the scene while preserving undo/redo history.
  ///
  /// Unlike [loadScene], this pushes the current scene onto the undo stack
  /// so the change can be undone. Used by the split-pane text editor.
  void applyScene(Scene scene, {String? background}) {
    closeTransientUiForSceneReplace();
    _historyManager.push(_editorState.scene);
    final validated = TextBoundsValidator.validateScene(scene);
    _editorState = _editorState.copyWith(scene: validated, selectedIds: {});
    _syncLayoutFromScene();
    _editorState = _editorState.copyWith(
      scene: _sceneWithLayoutPages(validated),
    );
    _applyViewportConstraints();
    if (background != null) {
      _canvasBackgroundColor = background;
    }
    notifyListeners();
  }

  /// Replaces the scene without pushing to the undo stack.
  ///
  /// Used for coalescing rapid edits (e.g. consecutive text-pane keystrokes)
  /// into a single undo entry. Call [applyScene] first to create the undo
  /// point, then [replaceScene] for subsequent updates in the same session.
  void replaceScene(Scene scene, {String? background}) {
    closeTransientUiForSceneReplace();
    final validated = TextBoundsValidator.validateScene(scene);
    _editorState = _editorState.copyWith(scene: validated, selectedIds: {});
    _syncLayoutFromScene();
    _editorState = _editorState.copyWith(
      scene: _sceneWithLayoutPages(validated),
    );
    _applyViewportConstraints();
    if (background != null) {
      _canvasBackgroundColor = background;
    }
    notifyListeners();
  }

  /// Applies a scene received from collaboration without touching undo history.
  void applyRemoteScene(
    Scene scene, {
    String? background,
    bool closeTransientUi = true,
  }) {
    if (closeTransientUi) {
      closeTransientUiForSceneReplace();
    }
    final validated = TextBoundsValidator.validateScene(scene);
    _editorState = _editorState.copyWith(scene: validated);
    _syncLayoutFromScene();
    _editorState = _editorState.copyWith(
      scene: _sceneWithLayoutPages(validated),
    );
    _applyViewportConstraints();
    if (background != null) {
      _canvasBackgroundColor = background;
    }
    _lastChangedElements = null;
    onSceneChanged?.call(_editorState.scene, SceneChangeSource.remoteApply);
    notifyListeners();
  }

  /// Applies collaboration element updates without rebuilding the full scene.
  void applyRemoteElements(Iterable<Element> elements) {
    final updates = [
      for (final element in elements)
        if (element is TextElement && element.containerId == null)
          TextBoundsValidator.validateElement(element)
        else
          element,
    ];
    if (updates.isEmpty) return;
    _editorState = _editorState.copyWith(
      scene: _editorState.scene.upsertRemoteElements(updates),
    );
    if (updates.any((element) => element.isCanvasPage)) {
      _syncLayoutFromScene();
      _applyViewportConstraints();
    }
    _lastChangedElements = null;
    onSceneChanged?.call(_editorState.scene, SceneChangeSource.remoteApply);
    notifyListeners();
  }

  /// Clears the scene and undo history.
  void clear() {
    closeTransientUiForSceneReplace();
    _historyManager.clear();
    _editorState = _editorState.copyWith(scene: Scene(), selectedIds: {});
    notifyListeners();
  }

  /// Returns the set of font families used by text elements in the scene.
  Set<String> getSceneFontFamilies() {
    return _editorState.scene.activeElements
        .whereType<TextElement>()
        .map((e) => e.fontFamily)
        .toSet();
  }

  /// Saves the current scene to the undo stack.
  void pushHistory() {
    _historyManager.push(_editorState.scene);
  }

  /// Toggles the split-pane markdown editor panel.
  void toggleMarkdownPanel() {
    _showMarkdownPanel = !_showMarkdownPanel;
    notifyListeners();
  }

  void toggleInkRecognitionMode() {
    inkRecognitionMode = !_inkRecognitionMode;
  }

  void toggleSmartInkLayoutMode() {
    smartInkLayoutMode = !_smartInkLayoutMode;
  }

  Future<bool> runGlobalSmartLayout({
    SmartLayoutRecognitionEngine engine = SmartLayoutRecognitionEngine.ai,
    void Function(int completed, int total)? onProgress,
  }) async {
    final layoutCallback = onSmartLayoutInk;
    final blockCallback = onRecognizeSmartLayoutBlock;
    final composeCallback = onComposeSmartLayout;
    final myScriptCallback = onRecognizeInk;
    final canRecognizeWithAI =
        layoutCallback != null ||
        (blockCallback != null && composeCallback != null);
    final canRecognizeWithMyScript =
        myScriptCallback != null && composeCallback != null;
    if ((engine == SmartLayoutRecognitionEngine.ai && !canRecognizeWithAI) ||
        (engine == SmartLayoutRecognitionEngine.myscript &&
            !canRecognizeWithMyScript) ||
        _recognizingInk) {
      return false;
    }
    _recognizingInk = true;
    try {
      final inkGroups = _smartLayoutInkGroups();
      if (inkGroups.isEmpty) return false;
      if (_disposed) return false;
      final request = await _buildSmartLayoutRequest(inkGroups, engine: engine);
      if (_disposed || request.blocks.isEmpty) return false;
      SmartLayoutResponse response;
      try {
        if (engine == SmartLayoutRecognitionEngine.myscript) {
          final recognized = await _recognizeSmartLayoutBlocksInParallel(
            request.blocks,
            (block) {
              final strokes = inkGroups[block.id] ?? const <FreedrawElement>[];
              return _recognizeSmartLayoutBlockWithMyScript(
                block,
                strokes,
                myScriptCallback!,
              );
            },
            onProgress,
          );
          if (_disposed) return false;
          response = await composeCallback!(
            SmartLayoutComposeRequest(pages: request.pages, blocks: recognized),
          );
        } else if (blockCallback != null && composeCallback != null) {
          final recognized = await _recognizeSmartLayoutBlocksInParallel(
            request.blocks,
            blockCallback,
            onProgress,
          );
          if (_disposed) return false;
          response = await composeCallback(
            SmartLayoutComposeRequest(pages: request.pages, blocks: recognized),
          );
        } else {
          response = await layoutCallback!(request);
          onProgress?.call(request.blocks.length, request.blocks.length);
        }
      } catch (error, stackTrace) {
        debugPrint('[$_logTag] 智能排版请求失败: $error');
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (_disposed) return false;
      final replacement = _elementsFromSmartLayoutResponse(response);
      if (replacement.isEmpty) return false;
      final successBlockIds = {
        for (final block in response.blocks)
          if (block.isSuccess) block.id,
      };
      final removableInk = [
        for (final entry in inkGroups.entries)
          if (successBlockIds.contains(entry.key)) ...entry.value,
      ];
      final removableSmartText = _smartLayoutGeneratedTextElements();
      pushHistory();
      applyResult(
        CompoundResult([
          for (final stroke in removableInk) RemoveElementResult(stroke.id),
          for (final text in removableSmartText) RemoveElementResult(text.id),
          for (final element in replacement) AddElementResult(element),
          SetSmartLayoutResult(response.document),
          SetSelectionResult({for (final element in replacement) element.id}),
        ]),
      );
      return true;
    } finally {
      _recognizingInk = false;
    }
  }

  Future<List<SmartLayoutRecognizedBlock>>
  _recognizeSmartLayoutBlocksInParallel(
    List<SmartLayoutInkBlockRequest> blocks,
    Future<SmartLayoutRecognizedBlock> Function(SmartLayoutInkBlockRequest)
    recognize,
    void Function(int completed, int total)? onProgress,
  ) async {
    if (blocks.isEmpty) {
      onProgress?.call(0, 0);
      return const [];
    }
    final results = List<SmartLayoutRecognizedBlock?>.filled(
      blocks.length,
      null,
    );
    var nextIndex = 0;
    var completed = 0;
    Object? firstError;
    StackTrace? firstStackTrace;
    onProgress?.call(0, blocks.length);

    Future<void> worker() async {
      while (true) {
        if (_disposed) return;
        if (firstError != null) return;
        final index = nextIndex;
        if (index >= blocks.length) return;
        nextIndex++;
        try {
          results[index] = await recognize(blocks[index]);
          completed++;
          onProgress?.call(completed, blocks.length);
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
          return;
        }
      }
    }

    final workerCount = math.min(
      _smartLayoutClientRecognitionConcurrency,
      blocks.length,
    );
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, firstStackTrace ?? StackTrace.current);
    }
    if (_disposed) {
      throw StateError('智能识别已取消');
    }
    final missingIndex = results.indexWhere((result) => result == null);
    if (missingIndex >= 0) {
      throw StateError('智能识别结果不完整：第 ${missingIndex + 1} 个块未返回');
    }
    return [for (final result in results) result!];
  }

  String exportSmartLayout(SmartLayoutExportFormat format) {
    final document = _editorState.scene.smartLayout;
    if (document == null || document.isEmpty) return '';
    return SmartLayoutExporter.export(document, format);
  }

  Future<SmartLayoutRequest> _buildSmartLayoutRequest(
    Map<String, List<FreedrawElement>> inkGroups, {
    SmartLayoutRecognitionEngine engine = SmartLayoutRecognitionEngine.ai,
  }) async {
    final pages = _layout.ensurePage().pages.map((page) {
      final geometry = TemplateAnchorResolver.resolve(page);
      return SmartLayoutPageRequest(
        id: page.id,
        index: page.index,
        bounds: Bounds.fromLTWH(
          page.bounds.left,
          page.bounds.top,
          page.bounds.width,
          page.bounds.height,
        ),
        template: page.template,
        anchors: [
          for (final anchor in geometry.anchors)
            {
              'x': anchor.position.dx,
              'y': anchor.position.dy,
              'crossAxis': anchor.crossAxis,
              'mainAxis': anchor.mainAxis,
              'fontSize': anchor.fontSize,
              'lineHeight': anchor.lineHeight,
              'writingMode': anchor.writingMode.name,
              'pageId': anchor.pageId,
            },
        ],
      );
    }).toList();
    final blocks = <SmartLayoutInkBlockRequest>[];
    for (final entry in inkGroups.entries) {
      final block = await _smartLayoutInkBlockRequest(
        entry.key,
        entry.value,
        includeImage: engine == SmartLayoutRecognitionEngine.ai,
      );
      if (block != null) {
        blocks.add(block);
      }
    }
    return SmartLayoutRequest(pages: pages, blocks: blocks);
  }

  List<FreedrawElement> _smartLayoutInkElements() {
    return [
      for (final element in _editorState.scene.activeElements)
        if (element is FreedrawElement &&
            brushTypeFromCustomData(element.customData) !=
                BrushType.highlighter)
          element,
    ];
  }

  Map<String, List<FreedrawElement>> _smartLayoutInkGroups() {
    final sessionGroups = <String, List<FreedrawElement>>{};
    for (final element in _smartLayoutInkElements()) {
      final sessionId =
          element.customData?[recognitionStrokeSessionKey] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        continue;
      }
      final pageId = _pageIdForElement(element);
      final groupId = pageId == null ? sessionId : '$pageId:$sessionId';
      sessionGroups
          .putIfAbsent(groupId, () => <FreedrawElement>[])
          .add(element);
    }
    return sessionGroups;
  }

  CanvasPage? _pageForElement(Element element) {
    if (!_layout.isPaged) {
      final pages = _layout.ensurePage().pages;
      return pages.isEmpty ? null : pages.first;
    }
    return _layout.pageAt(
      Offset(element.x + element.width / 2, element.y + element.height / 2),
    );
  }

  String? _pageIdForElement(Element element) {
    final rawPageId = _flowMuseData(element)?['pageId'];
    if (rawPageId is String && rawPageId.isNotEmpty) {
      return rawPageId;
    }
    if (!_layout.isPaged) {
      final pages = _layout.ensurePage().pages;
      return pages.isEmpty ? null : pages.first.id;
    }
    final page = _pageForElement(element);
    return page?.id;
  }

  Future<SmartLayoutInkBlockRequest?> _smartLayoutInkBlockRequest(
    String id,
    List<FreedrawElement> strokes, {
    bool includeImage = true,
  }) async {
    if (strokes.isEmpty) return null;
    final bounds = _boundsForElements(strokes);
    if (bounds == null) return null;
    final imageBytes = includeImage ? await _renderInkBlockPng(strokes) : null;
    if (includeImage && (imageBytes == null || imageBytes.isEmpty)) {
      return null;
    }
    return SmartLayoutInkBlockRequest(
      id: id,
      pageId: _pageIdForElement(strokes.first),
      bounds: bounds,
      strokeBounds: [
        for (final stroke in strokes)
          Bounds.fromLTWH(
            stroke.x,
            stroke.y,
            math.max(stroke.width, 1.0),
            math.max(stroke.height, 1.0),
          ),
      ],
      startedAt: _startedAtForStrokes(strokes),
      imageBase64: imageBytes == null ? '' : base64Encode(imageBytes),
    );
  }

  Future<SmartLayoutRecognizedBlock> _recognizeSmartLayoutBlockWithMyScript(
    SmartLayoutInkBlockRequest block,
    List<FreedrawElement> strokes,
    Future<InkRecognitionResult> Function(InkRecognitionRequest) recognize,
  ) async {
    final request = _buildInkRecognitionRequest(
      block.id,
      strokes,
      hint: 'auto',
    );
    if (request == null) {
      return SmartLayoutRecognizedBlock(
        id: block.id,
        pageId: block.pageId,
        type: 'error',
        bounds: block.bounds,
        strokeBounds: block.strokeBounds,
        startedAt: block.startedAt,
        error: '没有可识别的笔迹点',
      );
    }
    try {
      final result = await recognize(request);
      return _smartLayoutBlockFromInkRecognitionResult(block, result);
    } catch (error) {
      return SmartLayoutRecognizedBlock(
        id: block.id,
        pageId: block.pageId,
        type: 'error',
        bounds: block.bounds,
        strokeBounds: block.strokeBounds,
        startedAt: block.startedAt,
        error: error.toString(),
      );
    }
  }

  SmartLayoutRecognizedBlock _smartLayoutBlockFromInkRecognitionResult(
    SmartLayoutInkBlockRequest block,
    InkRecognitionResult result,
  ) {
    final elements = result.elements.where((element) {
      final text = (element.latex ?? element.text ?? '').trim();
      return text.isNotEmpty;
    }).toList();
    if (elements.isEmpty) {
      return SmartLayoutRecognizedBlock(
        id: block.id,
        pageId: block.pageId,
        type: 'error',
        bounds: block.bounds,
        strokeBounds: block.strokeBounds,
        startedAt: block.startedAt,
        error: 'MyScript 未返回文字',
      );
    }
    InkRecognizedElement? formula;
    for (final element in elements) {
      if (element.type == 'math' || (element.latex ?? '').trim().isNotEmpty) {
        formula = element;
        break;
      }
    }
    if (formula != null) {
      final latex = (formula.latex ?? formula.text ?? '').trim();
      return SmartLayoutRecognizedBlock(
        id: block.id,
        pageId: block.pageId,
        type: 'formula',
        text: latex,
        latex: latex,
        bounds: block.bounds,
        strokeBounds: block.strokeBounds,
        startedAt: block.startedAt,
      );
    }
    elements.sort((a, b) {
      final byY = a.y.compareTo(b.y);
      if (byY != 0) return byY;
      return a.x.compareTo(b.x);
    });
    final text = elements
        .map((element) => (element.text ?? element.latex ?? '').trim())
        .where((value) => value.isNotEmpty)
        .join('');
    if (text.isEmpty) {
      return SmartLayoutRecognizedBlock(
        id: block.id,
        pageId: block.pageId,
        type: 'error',
        bounds: block.bounds,
        strokeBounds: block.strokeBounds,
        startedAt: block.startedAt,
        error: 'MyScript 未返回文字',
      );
    }
    return SmartLayoutRecognizedBlock(
      id: block.id,
      pageId: block.pageId,
      type: 'text',
      text: text,
      bounds: block.bounds,
      strokeBounds: block.strokeBounds,
      startedAt: block.startedAt,
    );
  }

  Bounds? _boundsForElements(List<Element> elements) {
    Bounds? result;
    for (final element in elements) {
      final bounds = Bounds.fromLTWH(
        element.x,
        element.y,
        math.max(element.width, 1.0),
        math.max(element.height, 1.0),
      );
      result = result == null ? bounds : result.union(bounds);
    }
    return result;
  }

  int? _startedAtForStrokes(List<FreedrawElement> strokes) {
    int? startedAt;
    for (final stroke in strokes) {
      final value = stroke.customData?[recognitionStrokeStartedAtKey];
      if (value is num) {
        final timestamp = value.toInt();
        startedAt = startedAt == null
            ? timestamp
            : (timestamp < startedAt ? timestamp : startedAt);
      }
    }
    return startedAt;
  }

  Future<Uint8List?> _renderInkBlockPng(List<FreedrawElement> strokes) {
    var scene = Scene();
    for (final stroke in strokes) {
      scene = scene.addElement(stroke);
    }
    return PngExporter.export(
      scene,
      _adapter,
      scale: 2,
      backgroundColor: const Color(0xffffffff),
      embedMarkdraw: false,
    );
  }

  List<TextElement> _smartLayoutGeneratedTextElements() {
    return [
      for (final element in _editorState.scene.activeElements)
        if (element is TextElement &&
            _flowMuseData(element)?['smartLayout'] == true)
          element,
    ];
  }

  List<Element> _elementsFromSmartLayoutResponse(SmartLayoutResponse response) {
    final articlePageIds = {
      for (final page in response.pages)
        if (page.isArticle) page.pageId,
    };
    final elements = <Element>[
      if (articlePageIds.isNotEmpty)
        ..._elementsFromSmartLayout(
          response.document,
          articlePageIds: articlePageIds,
          useTemplateAnchors: true,
        ),
    ];
    for (final block in response.blocks) {
      if (!block.isSuccess || articlePageIds.contains(block.pageId)) {
        continue;
      }
      final element = _textElementFromRecognizedBlock(block);
      if (element != null) {
        elements.add(element);
      }
    }
    return elements;
  }

  List<Element> _elementsFromSmartLayout(
    SmartLayoutDocument document, {
    Set<String> articlePageIds = const {},
    bool useTemplateAnchors = false,
  }) {
    final blocks = [...document.blocks]
      ..sort((a, b) => a.order.compareTo(b.order));
    final elements = <Element>[];
    final occupiedByPage = <String, List<Bounds>>{};
    final layoutIndexByPage = <String, int>{};
    for (final block in blocks) {
      if (articlePageIds.isNotEmpty &&
          (block.pageId == null || !articlePageIds.contains(block.pageId))) {
        continue;
      }
      if (block.text.trim().isEmpty) {
        continue;
      }
      final pageKey = block.pageId ?? '';
      final pageLayoutIndex = layoutIndexByPage[pageKey] ?? 0;
      final occupied = occupiedByPage.putIfAbsent(pageKey, () => <Bounds>[]);
      final blockElements = _textElementsFromSmartLayoutBlock(
        block,
        pageLayoutIndex,
        occupied,
        useTemplateAnchors: useTemplateAnchors,
      );
      for (final element in blockElements) {
        elements.add(element);
        occupied.add(
          Bounds.fromLTWH(element.x, element.y, element.width, element.height),
        );
      }
      layoutIndexByPage[pageKey] =
          pageLayoutIndex + _smartLayoutLineSpan(block.text);
    }
    return elements;
  }

  Map<String, Object?>? _flowMuseData(Element element) {
    final raw = element.customData?['flowMuse'];
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) return Map<String, Object?>.from(raw);
    return null;
  }

  TextElement? _textElementFromRecognizedBlock(
    SmartLayoutRecognizedBlock block,
  ) {
    final text = block.type == 'formula'
        ? (block.latex?.trim().isNotEmpty == true
              ? block.latex!.trim()
              : block.text?.trim())
        : block.text?.trim();
    if (text == null || text.isEmpty) return null;
    final fontSize = _fontSizeForRecognizedBlock(block, text);
    final element = TextElement(
      id: ElementId.generate(),
      x: block.bounds.left,
      y: block.bounds.top,
      width: math.max(block.bounds.size.width, 80),
      height: math.max(block.bounds.size.height, 28),
      text: text,
      fontSize: fontSize,
      fontFamily: _defaultStyle.fontFamily ?? TextElement.defaultFontFamily,
      lineHeight: 1.25,
      customData: {
        'flowMuse': {
          if (block.pageId != null) 'pageId': block.pageId,
          'smartLayout': true,
          'blockId': block.id,
          if (block.type == 'formula') 'smartLayoutType': 'math',
        },
      },
    );
    final styled = _applySmartLayoutTextStyle(element);
    final (measuredWidth, measuredHeight) = TextRenderer.measure(styled);
    return styled.copyWith(
      width: math.max(styled.width, measuredWidth),
      height: math.max(styled.height, measuredHeight),
    );
  }

  double _fontSizeForRecognizedBlock(
    SmartLayoutRecognizedBlock block,
    String text,
  ) {
    if (block.type == 'formula') {
      return math.max(16, math.min(block.bounds.size.height * 0.72, 40));
    }
    final lineCount = math.max(1, text.split('\n').length);
    final estimatedLineHeight = block.bounds.size.height / lineCount;
    return math.max(12, math.min(estimatedLineHeight * 0.72, 48));
  }

  List<TextElement> _textElementsFromSmartLayoutBlock(
    SmartLayoutBlock block,
    int layoutIndex,
    List<Bounds> occupied, {
    bool useTemplateAnchors = false,
  }) {
    final lines = _smartLayoutDisplayLines(block.text);
    if (lines.length <= 1) {
      return [
        _textElementFromSmartLayoutBlock(
          block,
          layoutIndex,
          occupied,
          useTemplateAnchors: useTemplateAnchors,
        ),
      ];
    }
    final elements = <TextElement>[];
    final localOccupied = [...occupied];
    final totalLineCount = math.max(lines.length, 1);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        continue;
      }
      final lineBlock = SmartLayoutBlock(
        id: '${block.id}-line-$i',
        type: block.type,
        text: line,
        latex: block.type == 'math' ? line : block.latex,
        pageId: block.pageId,
        bounds: _lineBoundsForSmartLayoutBlock(block, i, totalLineCount),
        order: block.order,
        writingMode: block.writingMode,
        sourceIds: block.sourceIds,
      );
      final element = _textElementFromSmartLayoutBlock(
        lineBlock,
        layoutIndex + i,
        localOccupied,
        useTemplateAnchors: useTemplateAnchors,
      );
      elements.add(element);
      localOccupied.add(
        Bounds.fromLTWH(element.x, element.y, element.width, element.height),
      );
    }
    return elements;
  }

  TextElement _textElementFromSmartLayoutBlock(
    SmartLayoutBlock block,
    int layoutIndex,
    List<Bounds> occupied, {
    bool useTemplateAnchors = false,
  }) {
    final anchor = useTemplateAnchors
        ? _templateAnchorForSmartLayoutBlock(block, layoutIndex)
        : null;
    final initialBounds = anchor == null
        ? (block.bounds ?? _fallbackSmartLayoutBounds(block, layoutIndex))
        : _smartLayoutBoundsForTemplateAnchor(anchor, block, layoutIndex);
    final vertical =
        anchor?.writingMode == TemplateWritingMode.vertical ||
        block.writingMode == 'vertical';
    final text = block.type == 'math' && block.latex?.trim().isNotEmpty == true
        ? block.latex!.trim()
        : _trimSmartLayoutDisplayText(block.text);
    final element = TextElement(
      id: ElementId.generate(),
      x: initialBounds.left,
      y: initialBounds.top,
      width: math.max(initialBounds.size.width, vertical ? 28 : 80),
      height: math.max(initialBounds.size.height, 28),
      text: text,
      fontSize: anchor?.fontSize ?? (block.type == 'heading' ? 28 : 20),
      fontFamily: _defaultStyle.fontFamily ?? TextElement.defaultFontFamily,
      lineHeight: _textLineHeightForTemplateAnchor(anchor),
      customData: {
        'flowMuse': {
          if (block.pageId != null) 'pageId': block.pageId,
          'smartLayout': true,
          'blockId': block.id,
          if (block.type == 'math') 'smartLayoutType': 'math',
          if (vertical) 'writingMode': 'vertical',
        },
      },
    );
    final styled = _applySmartLayoutTextStyle(element);
    final measured = _measureSmartLayoutText(styled, vertical: vertical);
    final anchored = anchor == null
        ? measured
        : _alignSmartLayoutTextToAnchor(measured, anchor, vertical);
    final placedBounds = _nonOverlappingSmartLayoutBounds(
      Bounds.fromLTWH(anchored.x, anchored.y, anchored.width, anchored.height),
      block,
      layoutIndex,
      occupied,
      vertical,
    );
    return anchored.copyWith(x: placedBounds.left, y: placedBounds.top);
  }

  TextElement _applySmartLayoutTextStyle(TextElement element) {
    final styled = element.copyWith(
      strokeColor: _defaultStyle.strokeColor,
      backgroundColor: _defaultStyle.backgroundColor,
      strokeWidth: _defaultStyle.strokeWidth,
      strokeStyle: _defaultStyle.strokeStyle,
      fillStyle: _defaultStyle.fillStyle,
      roughness: _defaultStyle.roughness,
      opacity: _defaultStyle.opacity,
    );
    return _attachCurrentPage(
          styled.copyWithText(
            fontFamily: _defaultStyle.fontFamily,
            textAlign: _defaultStyle.textAlign,
          ),
        )
        as TextElement;
  }

  TextElement _measureSmartLayoutText(
    TextElement element, {
    required bool vertical,
  }) {
    if (!vertical) {
      final (measuredWidth, measuredHeight) = TextRenderer.measure(element);
      return element.copyWith(
        width: math.max(element.width, measuredWidth),
        height: math.max(element.height, measuredHeight),
      );
    }
    final chars = element.text.runes
        .map((rune) => String.fromCharCode(rune))
        .where((char) => char.trim().isNotEmpty)
        .toList();
    var measuredWidth = element.width;
    for (final char in chars) {
      final (charWidth, _) = TextRenderer.measure(
        element.copyWithText(text: char),
      );
      measuredWidth = math.max(measuredWidth, charWidth);
    }
    final measuredHeight = math.max(
      element.height,
      chars.length * element.fontSize * element.lineHeight,
    );
    return element.copyWith(width: measuredWidth, height: measuredHeight);
  }

  TextElement _alignSmartLayoutTextToAnchor(
    TextElement element,
    TemplateAnchor anchor,
    bool vertical,
  ) {
    if (vertical) {
      return element.copyWith(
        x: anchor.crossAxis - element.width / 2,
        y: anchor.position.dy,
      );
    }
    final painter = TextRenderer.buildTextPainter(element);
    painter.layout(maxWidth: element.width);
    final metrics = painter.computeLineMetrics();
    final firstLineHeight = metrics.isEmpty
        ? element.fontSize * element.lineHeight
        : metrics.first.height;
    final firstLineBottom = metrics.isEmpty
        ? element.fontSize
        : metrics.first.baseline + metrics.first.descent;
    painter.dispose();
    final y = anchor.textAlignment == TemplateAnchorTextAlignment.bottom
        ? anchor.crossAxis - firstLineBottom
        : anchor.crossAxis - firstLineHeight / 2;
    return element.copyWith(x: anchor.position.dx, y: y);
  }

  int _smartLayoutLineSpan(String text) {
    final normalized = _trimSmartLayoutDisplayText(text);
    if (normalized.isEmpty) {
      return 1;
    }
    return math.max(1, normalized.split('\n').length);
  }

  List<String> _smartLayoutDisplayLines(String text) {
    return _trimSmartLayoutDisplayText(
      text,
    ).replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  }

  Bounds? _lineBoundsForSmartLayoutBlock(
    SmartLayoutBlock block,
    int lineIndex,
    int lineCount,
  ) {
    final bounds = block.bounds;
    if (bounds == null || lineCount <= 1) {
      return bounds;
    }
    final lineHeight = math.max(bounds.size.height / lineCount, 1.0);
    return Bounds.fromLTWH(
      bounds.left,
      bounds.top + lineHeight * lineIndex,
      bounds.size.width,
      lineHeight,
    );
  }

  String _trimSmartLayoutDisplayText(String text) {
    var normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    while (normalized.startsWith('\n')) {
      normalized = normalized.substring(1);
    }
    return normalized.replaceFirst(RegExp(r'[ \t\n]+$'), '');
  }

  TemplateAnchor? _templateAnchorForSmartLayoutBlock(
    SmartLayoutBlock block,
    int layoutIndex,
  ) {
    final page = _smartLayoutPageForBlock(block);
    if (page == null) return null;
    final anchors = TemplateAnchorResolver.resolve(page).anchors;
    if (anchors.isEmpty) return null;
    return anchors[math.min(layoutIndex, anchors.length - 1)];
  }

  Bounds _smartLayoutBoundsForTemplateAnchor(
    TemplateAnchor anchor,
    SmartLayoutBlock block,
    int layoutIndex,
  ) {
    final page = _smartLayoutPageForBlock(block);
    final content = page == null
        ? null
        : TemplateAnchorResolver.resolve(page).contentRect;
    if (anchor.writingMode == TemplateWritingMode.vertical) {
      return Bounds.fromLTWH(
        anchor.position.dx,
        anchor.position.dy,
        math.max(anchor.fontSize * 1.2, 28),
        content == null
            ? math.max(block.bounds?.size.height ?? 240, anchor.lineHeight)
            : math.max(content.bottom - anchor.position.dy, anchor.lineHeight),
      );
    }
    return Bounds.fromLTWH(
      anchor.position.dx,
      anchor.position.dy,
      content == null
          ? math.max(block.bounds?.size.width ?? 320, anchor.lineHeight)
          : math.max(content.right - anchor.position.dx, anchor.lineHeight),
      anchor.lineHeight,
    );
  }

  Bounds _fallbackSmartLayoutBounds(SmartLayoutBlock block, int layoutIndex) {
    final page = _smartLayoutPageForBlock(block);
    if (page == null) {
      return Bounds.fromLTWH(0, layoutIndex * 40.0, 240, 32);
    }
    final geometry = TemplateAnchorResolver.resolve(page);
    final content = geometry.contentRect;
    if (block.writingMode == 'vertical') {
      return Bounds.fromLTWH(
        content.right - 36 - layoutIndex * 44.0,
        content.top,
        36,
        math.min(240, content.height),
      );
    }
    return Bounds.fromLTWH(
      content.left,
      content.top + layoutIndex * 40.0,
      math.min(320, content.width),
      32,
    );
  }

  Bounds _nonOverlappingSmartLayoutBounds(
    Bounds candidate,
    SmartLayoutBlock block,
    int layoutIndex,
    List<Bounds> occupied,
    bool vertical,
  ) {
    var placed = candidate;
    if (occupied.isEmpty) {
      return placed;
    }
    final page = _smartLayoutPageForBlock(block);
    final contentRect = page == null
        ? null
        : TemplateAnchorResolver.resolve(page).contentRect;
    for (var attempts = 0; attempts < occupied.length + 8; attempts++) {
      final collision = occupied
          .where((bounds) => placed.intersects(bounds))
          .fold<Bounds?>(null, (merged, bounds) {
            return merged == null ? bounds : merged.union(bounds);
          });
      if (collision == null) {
        return placed;
      }
      if (vertical) {
        final nextLeft = collision.left - placed.size.width - 12;
        placed = Bounds.fromLTWH(
          contentRect == null ? nextLeft : math.max(contentRect.left, nextLeft),
          contentRect?.top ?? candidate.top,
          placed.size.width,
          placed.size.height,
        );
      } else {
        final nextTop = collision.bottom + 12;
        placed = Bounds.fromLTWH(
          contentRect?.left ?? candidate.left,
          contentRect == null ? nextTop : math.min(nextTop, contentRect.bottom),
          placed.size.width,
          placed.size.height,
        );
      }
    }
    if (vertical) {
      return Bounds.fromLTWH(
        candidate.left - layoutIndex * (candidate.size.width + 12),
        candidate.top,
        candidate.size.width,
        candidate.size.height,
      );
    }
    return Bounds.fromLTWH(
      candidate.left,
      candidate.top + layoutIndex * (candidate.size.height + 12),
      candidate.size.width,
      candidate.size.height,
    );
  }

  CanvasPage? _smartLayoutPageForBlock(SmartLayoutBlock block) {
    if (!_layout.isPaged) return null;
    final pages = _layout.ensurePage().pages;
    if (pages.isEmpty) return null;
    final pageId = block.pageId;
    if (pageId != null) {
      for (final page in pages) {
        if (page.id == pageId) {
          return page;
        }
      }
    }
    final bounds = block.bounds;
    if (bounds != null) {
      return _layout.pageAt(Offset(bounds.center.x, bounds.center.y));
    }
    return pages.first;
  }

  bool get canConvertSelectionToText {
    final elements = selectedElements;
    return elements.isNotEmpty &&
        elements.every((element) => element is FreedrawElement);
  }

  Future<void> convertSelectedInkToText() async {
    if (_recognizingInk ||
        onRecognizeInk == null ||
        !canConvertSelectionToText) {
      return;
    }
    final strokes = selectedElements.whereType<FreedrawElement>().toList();
    final sessionId = ElementId.generate().value;
    final request = _buildInkRecognitionRequest(sessionId, strokes);
    if (request == null) {
      return;
    }
    debugPrint(
      '[$_logTag] 🎯 手动转换选中笔迹 | sessionId: $sessionId | '
      '选中笔画数: ${strokes.length} | 请求笔画数: ${request.strokes.length}',
    );
    _recognizingInk = true;
    try {
      final result = await onRecognizeInk!(request);
      if (_disposed) {
        return;
      }
      final elements = result.elements
          .map(_elementFromRecognizedInk)
          .whereType<Element>()
          .toList();
      debugPrint(
        '[$_logTag] 📥 手动转换结果 | sessionId: $sessionId | '
        '服务端返回: ${result.elements.length} 个元素 | 成功转换: ${elements.length} 个元素',
      );
      if (elements.isEmpty) {
        return;
      }
      pushHistory();
      applyResult(
        CompoundResult([
          for (final stroke in strokes) RemoveElementResult(stroke.id),
          for (final element in elements) AddElementResult(element),
          SetSelectionResult({for (final element in elements) element.id}),
        ]),
      );
    } finally {
      _recognizingInk = false;
    }
  }

  /// Toggles tool lock mode (tool stays active after use).
  void toggleToolLocked() {
    _toolLocked = !_toolLocked;
    _editorState = _editorState.copyWith(toolLocked: _toolLocked);
    if (!_toolLocked) {
      switchTool(ToolType.select);
    } else {
      notifyListeners();
    }
  }

  /// Toggles the snap grid on (20px) or off.
  void toggleGrid() {
    _gridSize = _gridSize == null ? 20 : null;
    notifyListeners();
  }

  /// Toggles snap-to-objects alignment guides.
  void toggleObjectsSnapMode() {
    _objectsSnapMode = !_objectsSnapMode;
    notifyListeners();
  }

  /// Pans the viewport by the given scene-coordinate deltas.
  void panViewport(double dx, double dy) {
    final viewport = _editorState.viewport;
    final newViewport = ViewportState(
      offset: Offset(viewport.offset.dx + dx, viewport.offset.dy + dy),
      zoom: viewport.zoom,
    );
    applyResult(UpdateViewportResult(newViewport));
  }

  void scrollPagedViewportBy(double screenDelta) {
    if (!isPagedViewport) {
      return;
    }
    final viewport = _editorState.viewport;
    final sceneDelta = screenDelta / viewport.zoom;
    final newViewport = ViewportState(
      offset: _layout.isRightToLeft
          ? Offset(viewport.offset.dx - sceneDelta, viewport.offset.dy)
          : Offset(viewport.offset.dx, viewport.offset.dy + sceneDelta),
      zoom: viewport.zoom,
    );
    applyResult(UpdateViewportResult(newViewport));
  }

  void scrollToPage(int pageIndex) {
    if (!isPagedViewport || _canvasSize.width <= 0 || _canvasSize.height <= 0) {
      return;
    }
    final pages = _layout.pages;
    final index = pageIndex.clamp(0, pages.length - 1);
    final page = pages[index];
    final viewport = _editorState.viewport;
    final targetOffset = _layout.isRightToLeft
        ? Offset(
            _rightToLeftPageViewportX(page, viewport.zoom),
            viewport.offset.dy,
          )
        : Offset(viewport.offset.dx, page.bounds.top);
    setViewport(ViewportState(offset: targetOffset, zoom: viewport.zoom));
  }

  double _rightToLeftPageViewportX(CanvasPage page, double zoom) {
    if (_canvasSize.width <= 0) {
      return page.bounds.left;
    }
    final visibleWidth = _canvasSize.width / math.max(zoom, 0.0001);
    if (visibleWidth >= page.bounds.width) {
      return page.bounds.center.dx - visibleWidth / 2;
    }
    return page.bounds.right - visibleWidth;
  }

  void appendPageAfterLastAndScroll() {
    if (!isPagedViewport) {
      return;
    }
    final nextIndex = _layout.pages.length;
    insertBlankPage(afterIndex: nextIndex - 1);
    scrollToPage(nextIndex);
  }

  /// Cycles font size through presets [16, 20, 28, 36].
  void cycleFontSize({required bool increase}) {
    const presets = [16.0, 20.0, 28.0, 36.0];
    final current = _defaultStyle.fontSize ?? 20.0;

    double newSize;
    if (increase) {
      newSize = presets.firstWhere(
        (s) => s > current,
        orElse: () => presets.last,
      );
    } else {
      newSize = presets.lastWhere(
        (s) => s < current,
        orElse: () => presets.first,
      );
    }

    applyStyleChange(ElementStyle(fontSize: newSize));
  }

  /// Copies the style from the first selected element.
  void copyStyle() {
    final elements = selectedElements;
    if (elements.isEmpty) return;
    final e = elements.first;

    // Resolve text properties from element itself or its bound text
    double? fontSize;
    String? fontFamily;
    core.TextAlign? textAlign;
    VerticalAlign? verticalAlign;
    if (e is TextElement) {
      fontSize = e.fontSize;
      fontFamily = e.fontFamily;
      textAlign = e.textAlign;
      verticalAlign = e.verticalAlign;
    } else {
      final bt = _editorState.scene.findBoundText(e.id);
      if (bt != null) {
        fontSize = bt.fontSize;
        fontFamily = bt.fontFamily;
        textAlign = bt.textAlign;
        verticalAlign = bt.verticalAlign;
      }
    }

    _copiedStyle = ElementStyle(
      strokeColor: e.strokeColor,
      backgroundColor: e.backgroundColor,
      strokeWidth: e.strokeWidth,
      strokeStyle: e.strokeStyle,
      fillStyle: e.fillStyle,
      roughness: e.roughness,
      opacity: e.opacity,
      roundness: e.roundness,
      hasRoundness: e.roundness != null,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      verticalAlign: verticalAlign,
      arrowType: e is ArrowElement ? e.arrowType : null,
      startArrowhead: e is LineElement ? e.startArrowhead : null,
      startArrowheadNone: e is LineElement && e.startArrowhead == null,
      endArrowhead: e is LineElement ? e.endArrowhead : null,
      endArrowheadNone: e is LineElement && e.endArrowhead == null,
    );
  }

  /// Applies the previously copied style to the current selection.
  void pasteStyle() {
    if (_copiedStyle == null) return;
    final elements = selectedElements;
    if (elements.isEmpty) return;
    applyStyleChange(_copiedStyle!);
  }

  /// Pastes clipboard text as a new TextElement at viewport center.
  Future<void> pasteAsPlaintext(Size canvasSize) async {
    final text = await _clipboardService.readText();
    if (text == null) return;
    insertPlainText(text, canvasSize: canvasSize);
  }

  /// Inserts plain text as one standard TextElement at the viewport center.
  void insertPlainText(
    String text, {
    Size? canvasSize,
    bool adaptiveLayout = false,
  }) {
    insertPlainTexts(
      [text],
      canvasSize: canvasSize,
      adaptiveLayout: adaptiveLayout,
    );
  }

  /// Inserts multiple standard text elements as one undoable scene change.
  void insertPlainTexts(
    Iterable<String> texts, {
    Size? canvasSize,
    bool adaptiveLayout = false,
  }) {
    final normalized = [
      for (final text in texts)
        if (text.trim().isNotEmpty) text.trim(),
    ];
    if (normalized.isEmpty) return;

    final targetSize =
        canvasSize ??
        _lastCanvasSize ??
        (_canvasSize.isEmpty ? const Size(800, 600) : _canvasSize);

    final centerScene = _editorState.viewport.screenToScene(
      Offset(targetSize.width / 2, targetSize.height / 2),
    );
    final elements = <Element>[];
    final occupied = adaptiveLayout
        ? [
            for (final element in _editorState.scene.activeElements)
              if (!element.isCanvasPage && !element.isPdfBackground)
                Bounds.fromLTWH(
                  element.x,
                  element.y,
                  element.width,
                  element.height,
                ),
          ]
        : <Bounds>[];
    final insertionAreas = adaptiveLayout
        ? _adaptiveTextInsertionAreas(targetSize)
        : <({Rect rect, String? pageId})>[];
    final pageElements = <Element>[];
    final preparedTexts = adaptiveLayout
        ? [
            for (final text in normalized)
              ..._splitAdaptiveText(
                text,
                insertionAreas.first.rect.width,
                insertionAreas.first.rect.height * 0.8,
              ),
          ]
        : normalized;
    var areaIndex = 0;
    var y = centerScene.dy;
    for (final text in preparedTexts) {
      var insertionArea = adaptiveLayout ? insertionAreas[areaIndex] : null;
      final textElem = TextElement(
        id: ElementId.generate(),
        x: insertionArea?.rect.left ?? centerScene.dx,
        y: insertionArea?.rect.top ?? y,
        width: 10,
        height: 10,
        text: text,
        fontFamily: _defaultStyle.fontFamily ?? TextElement.defaultFontFamily,
        fontSize: _defaultStyle.fontSize ?? 20,
        autoResize: !adaptiveLayout,
        customData: insertionArea?.pageId == null
            ? null
            : CanvasLayout.elementCustomData(insertionArea!.pageId!),
      );
      final naturalWidth = TextRenderer.measure(textElem).$1 + 4;
      var width = insertionArea == null
          ? naturalWidth
          : math.min(
              insertionArea.rect.width,
              math.max(
                320.0,
                math.min(naturalWidth, insertionArea.rect.width * 0.6),
              ),
            );
      var height = TextRenderer.measure(textElem, maxWidth: width).$2;
      if (insertionArea != null &&
          height > insertionArea.rect.height * 0.8 &&
          width < insertionArea.rect.width) {
        width = insertionArea.rect.width;
        height = TextRenderer.measure(textElem, maxWidth: width).$2;
      }
      Bounds? placement;
      while (insertionArea != null && placement == null) {
        placement = _findTextInsertionBounds(
          insertionArea.rect,
          width,
          height,
          occupied,
        );
        if (placement != null) break;
        areaIndex++;
        if (areaIndex >= insertionAreas.length) {
          if (_layout.isPaged) {
            final appended = _appendAdaptiveTextPage();
            insertionAreas.add((rect: appended.rect, pageId: appended.pageId));
            pageElements.add(appended.element);
          } else {
            final previous = insertionAreas.last.rect;
            insertionAreas.add((
              rect: previous.shift(Offset(0, previous.height + 24)),
              pageId: null,
            ));
          }
        }
        insertionArea = insertionAreas[areaIndex];
      }
      final sized = textElem.copyWith(
        x: placement?.left,
        y: placement?.top,
        width: math.max(width, 20.0),
        height: math.max(height, textElem.fontSize * textElem.lineHeight),
        customData: insertionArea?.pageId == null
            ? null
            : CanvasLayout.elementCustomData(insertionArea!.pageId!),
      );
      final styled = applyDefaultStyleToElement(sized);
      elements.add(styled);
      occupied.add(
        Bounds.fromLTWH(styled.x, styled.y, styled.width, styled.height),
      );
      y += sized.height + 24;
    }

    _historyManager.push(_editorState.scene);
    applyResult(
      CompoundResult([
        for (final page in pageElements) AddElementResult(page),
        for (final element in elements) AddElementResult(element),
        SetSelectionResult({for (final element in elements) element.id}),
      ]),
    );
  }

  List<({Rect rect, String? pageId})> _adaptiveTextInsertionAreas(
    Size canvasSize,
  ) {
    final visible = _editorState.viewport.visibleRect(canvasSize);
    if (_layout.isPaged) {
      final page = _layout.pageAt(visible.center);
      if (page != null) {
        final index = _layout.pages.indexWhere((item) => item.id == page.id);
        return [
          for (final item in _layout.pages.skip(math.max(index, 0)))
            (rect: item.bounds.deflate(72), pageId: item.id),
        ];
      }
    }
    return [
      (
        rect: visible.deflate(math.min(32, visible.shortestSide / 8)),
        pageId: null,
      ),
    ];
  }

  List<String> _splitAdaptiveText(String text, double width, double maxHeight) {
    final runes = text.runes.toList();
    final chunks = <String>[];
    var offset = 0;
    while (offset < runes.length) {
      var low = 1;
      var high = runes.length - offset;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        final candidate = String.fromCharCodes(
          runes.sublist(offset, offset + mid),
        );
        if (_adaptiveTextHeight(candidate, width) <= maxHeight) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      var end = offset + low;
      if (end < runes.length) {
        final minimumBreak = offset + low ~/ 2;
        for (var index = end - 1; index >= minimumBreak; index--) {
          if (runes[index] == 10 || runes[index] == 32) {
            end = index + 1;
            break;
          }
        }
      }
      final chunk = String.fromCharCodes(runes.sublist(offset, end)).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      offset = end;
    }
    return chunks;
  }

  double _adaptiveTextHeight(String text, double width) {
    final element = TextElement(
      id: ElementId('measure'),
      x: 0,
      y: 0,
      width: width,
      height: 10,
      text: text,
      fontFamily: _defaultStyle.fontFamily ?? TextElement.defaultFontFamily,
      fontSize: _defaultStyle.fontSize ?? 20,
      autoResize: false,
    );
    return TextRenderer.measure(element, maxWidth: width).$2;
  }

  ({Rect rect, String pageId, Element element}) _appendAdaptiveTextPage() {
    final index = _layout.pages.length;
    final pageId = 'page-${ElementId.generate().value}';
    final size = CanvasLayout.pageSizeForTemplate(_layout.template);
    final page = CanvasPage(
      id: pageId,
      index: index,
      bounds: CanvasLayout.pageBoundsForIndex(
        index: index,
        pageSize: size,
        pageFlow: _layout.pageFlow,
      ),
      template: _layout.template,
      pageFlow: _layout.pageFlow,
    );
    _layout = _layout.copyWith(pages: [..._layout.pages, page]);
    return (
      rect: page.bounds.deflate(72),
      pageId: pageId,
      element: RectangleElement(
        id: ElementId(pageId),
        x: page.bounds.left,
        y: page.bounds.top,
        width: page.bounds.width,
        height: page.bounds.height,
        strokeColor: 'transparent',
        backgroundColor: 'transparent',
        opacity: 0,
        locked: true,
        customData: CanvasLayout.pageCustomData(page),
      ),
    );
  }

  Bounds? _findTextInsertionBounds(
    Rect area,
    double width,
    double height,
    List<Bounds> occupied,
  ) {
    const gap = 24.0;
    final xCandidates = <double>[
      area.left,
      math.max(area.left, area.right - width),
    ];
    final yCandidates = <double>[
      area.top,
      for (final bounds in occupied) bounds.bottom + gap,
    ]..sort();

    for (final y in yCandidates) {
      for (final x in xCandidates) {
        final candidate = Bounds.fromLTWH(x, y, width, height);
        if (candidate.right <= area.right &&
            (height > area.height || candidate.bottom <= area.bottom) &&
            !occupied.any(candidate.intersects)) {
          return candidate;
        }
      }
    }
    return null;
  }

  /// Renames the document. Empty string is treated as null (no name).
  void renameDocument(String name) {
    _documentName = name.isEmpty ? null : name;
    notifyListeners();
  }

  /// Clears the canvas, pushing the current scene to undo history.
  void resetCanvas() {
    _historyManager.push(_editorState.scene);
    _editorState = _editorState.copyWith(scene: Scene(), selectedIds: {});
    _documentName = null;
    _lastChangedElements = null;
    onSceneChanged?.call(_editorState.scene, SceneChangeSource.userEdit);
    notifyListeners();
  }

  /// Toggles zen mode — hides all chrome.
  void toggleZenMode() {
    _zenMode = !_zenMode;
    notifyListeners();
  }

  /// Toggles view (read-only) mode — forces hand tool, blocks switching.
  void toggleViewMode() {
    _viewMode = !_viewMode;
    if (_viewMode) {
      _toolBeforeViewMode = _editorState.activeToolType;
      switchTool(ToolType.hand);
      _editorState = _editorState.copyWith(selectedIds: {});
    } else {
      switchTool(_toolBeforeViewMode ?? ToolType.select);
      _toolBeforeViewMode = null;
    }
    notifyListeners();
  }

  // --- Find on canvas ---

  /// Opens the find bar.
  void openFind() {
    _isFindOpen = true;
    notifyListeners();
  }

  /// Closes the find bar and clears search state.
  void closeFind() {
    _isFindOpen = false;
    _findQuery = '';
    _findResults = [];
    _findCurrentIndex = -1;
    notifyListeners();
  }

  /// Searches the scene for elements matching [query].
  void updateFindQuery(String query) {
    _findQuery = query;
    if (query.isEmpty) {
      _findResults = [];
      _findCurrentIndex = -1;
      notifyListeners();
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = <ElementId>[];
    final seen = <String>{};

    for (final element in _editorState.scene.activeElements) {
      if (element is TextElement) {
        if (element.text.toLowerCase().contains(lowerQuery)) {
          if (element.containerId != null) {
            // Bound text — navigate to parent container
            if (seen.add(element.containerId!)) {
              results.add(ElementId(element.containerId!));
            }
          } else {
            if (seen.add(element.id.value)) {
              results.add(element.id);
            }
          }
        }
      } else if (element is FrameElement) {
        if (element.label.toLowerCase().contains(lowerQuery)) {
          if (seen.add(element.id.value)) {
            results.add(element.id);
          }
        }
      }
    }

    _findResults = results;
    _findCurrentIndex = results.isEmpty ? -1 : 0;

    // Auto-select first match
    if (_findCurrentIndex >= 0) {
      applyResult(SetSelectionResult({_findResults[_findCurrentIndex]}));
    }
    notifyListeners();
  }

  /// Advances to the next find result, wrapping around.
  void findNext(Size canvasSize) {
    if (_findResults.isEmpty) return;
    _findCurrentIndex = (_findCurrentIndex + 1) % _findResults.length;
    _selectAndRevealFindResult(canvasSize);
  }

  /// Goes to the previous find result, wrapping around.
  void findPrevious(Size canvasSize) {
    if (_findResults.isEmpty) return;
    _findCurrentIndex =
        (_findCurrentIndex - 1 + _findResults.length) % _findResults.length;
    _selectAndRevealFindResult(canvasSize);
  }

  void _selectAndRevealFindResult(Size canvasSize) {
    final id = _findResults[_findCurrentIndex];
    _selectAndRevealElement(id, canvasSize);
  }

  // --- Link editor ---

  /// Opens the link editor overlay in editing mode (for Ctrl+K or button).
  void openLinkEditor() {
    _isLinkEditorOpen = true;
    _isLinkEditorEditing = true;
    notifyListeners();
  }

  /// Closes the link editor overlay.
  void closeLinkEditor() {
    _isLinkEditorOpen = false;
    _isLinkEditorEditing = false;
    _linkToElementMode = false;
    notifyListeners();
  }

  /// Shows the link overlay in info mode (element has a link, just display it).
  void showLinkInfo() {
    _isLinkEditorOpen = true;
    _isLinkEditorEditing = false;
    notifyListeners();
  }

  /// Sets or clears the link on an element.
  void setElementLink(ElementId id, String? link) {
    _historyManager.push(_editorState.scene);
    final element = _editorState.scene.getElementById(id);
    if (element == null) return;
    if (link == null || link.isEmpty) {
      applyResult(UpdateElementResult(element.copyWith(clearLink: true)));
    } else {
      applyResult(UpdateElementResult(element.copyWith(link: link)));
    }
  }

  /// Enters "link to element" mode — next click on an element sets the link.
  void enterLinkToElementMode() {
    _linkToElementMode = true;
    notifyListeners();
  }

  /// Follows a link: element links (#id) navigate on canvas, URLs call onLinkOpen.
  /// Automatically prepends protocol if missing (file:/// for absolute paths,
  /// https:// for everything else).
  void followLink(String link, Size canvasSize) {
    if (link.startsWith('#')) {
      final targetIdStr = link.substring(1);
      final target = _editorState.scene.getElementById(ElementId(targetIdStr));
      if (target == null) return;
      _selectAndRevealElement(ElementId(targetIdStr), canvasSize);
    } else {
      _config.onLinkOpen?.call(_normalizeUrl(link));
    }
  }

  /// Prepends a protocol scheme if the link doesn't already have one.
  static String _normalizeUrl(String url) {
    if (url.contains('://')) return url; // already has scheme
    if (url.startsWith('/')) return 'file:///$url';
    return 'https://$url';
  }

  /// Selects an element and pans/zooms to reveal it (shared by find and followLink).
  void _selectAndRevealElement(ElementId id, Size canvasSize) {
    applyResult(SetSelectionResult({id}));

    final bounds = ExportBounds.compute(
      _editorState.scene,
      selectedIds: {id},
      padding: 40,
    );
    if (bounds == null) return;

    final visible = _editorState.viewport.visibleRect(canvasSize);
    final elemRect = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.size.width,
      bounds.size.height,
    );
    if (!visible.overlaps(elemRect)) {
      applyResult(
        UpdateViewportResult(
          _editorState.viewport.fitToBounds(bounds, canvasSize, padding: 80),
        ),
      );
    }
    notifyListeners();
  }

  /// Hit-tests whether a point is on a link icon (above top-right corner).
  Element? hitTestLinkIcon(Point scenePoint) {
    const iconRadius = 10.0; // iconSize/2 + padding
    for (final element in _editorState.scene.activeElements.reversed) {
      if (element.link == null || element.link!.isEmpty) continue;
      // Skip selected elements — they show the overlay instead
      if (_editorState.selectedIds.contains(element.id)) continue;
      // Icon center matches _drawLinkIcon positioning
      final cx = element.x + element.width - 8; // iconSize/2
      final cy = element.y - 18; // iconSize + 2
      if (scenePoint.x >= cx - iconRadius &&
          scenePoint.x <= cx + iconRadius &&
          scenePoint.y >= cy - iconRadius &&
          scenePoint.y <= cy + iconRadius) {
        return element;
      }
    }
    return null;
  }

  // --- Flowchart ---

  /// The flowchart creator for building connected node sequences.
  FlowchartCreator get flowchartCreator => _flowchartCreator;

  /// Creates flowchart node(s) from the selected node in [direction].
  void flowchartCreate(LinkDirection direction) {
    final selected = selectedElements;
    if (selected.length != 1 ||
        !FlowchartUtils.isFlowchartNode(selected.first)) {
      return;
    }
    _flowchartCreator.createNodes(
      startNode: selected.first,
      direction: direction,
      scene: _editorState.scene,
    );
    notifyListeners();
  }

  /// Commits pending flowchart elements to the scene.
  void flowchartCommit() {
    if (!_flowchartCreator.isCreating) return;
    _historyManager.push(_editorState.scene);
    applyResult(_flowchartCreator.commit());
  }

  /// Cancels pending flowchart creation, discarding preview elements.
  void flowchartCancel() {
    if (!_flowchartCreator.isCreating) return;
    _flowchartCreator.clear();
    notifyListeners();
  }

  /// Navigates to a connected flowchart node in [direction].
  void flowchartNavigate(LinkDirection direction) {
    final selected = selectedElements;
    if (selected.length != 1) return;
    final targetId = _flowchartNavigator.exploreByDirection(
      selected.first,
      _editorState.scene,
      direction,
    );
    if (targetId != null) {
      applyResult(SetSelectionResult({targetId}));
    }
  }

  /// Ends flowchart navigation, clearing visited state.
  void flowchartNavigateEnd() {
    if (!_flowchartNavigator.isExploring) return;
    _flowchartNavigator.clear();
  }

  // --- Mind map ---

  /// The mind-map creator.
  MindmapCreator get mindmapCreator => _mindmapCreator;

  /// Pending preview elements for the active creator (flowchart or mind-map).
  /// Used by [StaticCanvasPainter] to render translucent previews.
  List<Element> get pendingPreviewElements {
    if (_flowchartCreator.isCreating) return _flowchartCreator.pendingElements;
    return const [];
  }

  /// Creates a mind-map root node at the centre of the visible canvas area,
  /// commits it, switches back to the select tool, and enters text editing.
  void mindmapCreateRoot() {
    final center = _editorState.viewport.screenToScene(
      Offset(_canvasSize.width / 2, _canvasSize.height / 2),
    );
    _historyManager.push(_editorState.scene);
    final result = _mindmapCreator.createRoot(Point(center.dx, center.dy));
    applyResult(result);
    switchTool(ToolType.select);
    _enterMindmapNodeEditing();
  }

  /// Inserts a complete content tree using the deterministic mind-map layout.
  /// The whole tree is one scene change and can be removed with one undo.
  void insertMindmap(MindmapNode tree, {Size? canvasSize}) {
    final targetSize =
        canvasSize ??
        _lastCanvasSize ??
        (_canvasSize.isEmpty ? const Size(800, 600) : _canvasSize);
    final visible = _editorState.viewport.visibleRect(targetSize);
    final placementRect = _layout.isPaged
        ? (_layout.pageAt(visible.center)?.bounds ?? visible)
        : visible;
    final placementArea = placementRect.deflate(
      math.min(48.0, placementRect.shortestSide / 8),
    );
    final preview = MindmapLayout.treeToElements(
      tree,
      origin: const Point(0, 0),
    );
    final previewBounds = preview
        .map(
          (element) => Bounds.fromLTWH(
            element.x,
            element.y,
            element.width,
            element.height,
          ),
        )
        .reduce((bounds, element) => bounds.union(element));
    final origin = Point(
      previewBounds.size.width <= placementArea.width
          ? placementArea.center.dx - previewBounds.center.x
          : placementArea.left - previewBounds.left,
      previewBounds.size.height <= placementArea.height
          ? placementArea.center.dy - previewBounds.center.y
          : placementArea.top - previewBounds.top,
    );
    final elements = MindmapLayout.treeToElements(tree, origin: origin);
    final root = elements.whereType<RectangleElement>().firstOrNull;

    _historyManager.push(_editorState.scene);
    applyResult(
      CompoundResult([
        for (final element in elements) AddElementResult(element),
        if (root != null) SetSelectionResult({root.id}),
      ]),
    );
  }

  /// Adds a child node to the single selected mind-map node, then reflows
  /// the whole tree so the parent re-centres over its children (auto-reflow,
  /// like XMind/MindNode).
  void mindmapAddChild() {
    final selected = selectedElements;
    if (selected.length != 1 || !MindmapUtils.isMindmapNode(selected.first)) {
      return;
    }
    final sceneElements = _editorState.scene.elements;
    final rootNode = MindmapUtils.rootOf(selected.first, sceneElements);
    final tree = MindmapUtils.treeFromScene(rootNode, sceneElements);

    // Append a new child to the selected node's tree node.
    final parentTreeNode = _findTreeNode(tree, selected.first.id.value) ?? tree;
    parentTreeNode.children.add(
      MindmapNode(text: '分支 ${parentTreeNode.children.length + 1}'),
    );

    _historyManager.push(_editorState.scene);
    final result = _applyReflow(tree, rootNode);
    applyResult(result);
    _enterMindmapNodeEditing();
  }

  /// Adds a sibling below the single selected mind-map node, then reflows.
  void mindmapAddSibling() {
    final selected = selectedElements;
    if (selected.length != 1 || !MindmapUtils.isMindmapNode(selected.first)) {
      return;
    }
    final sceneElements = _editorState.scene.elements;
    final rootNode = MindmapUtils.rootOf(selected.first, sceneElements);
    final tree = MindmapUtils.treeFromScene(rootNode, sceneElements);

    final parentTreeNode = _findParentTreeNode(tree, selected.first.id.value);
    if (parentTreeNode == null) return; // selected is root — no sibling
    final idx = parentTreeNode.children.indexWhere(
      (c) => c.sourceId == selected.first.id.value,
    );
    parentTreeNode.children.insert(idx + 1, MindmapNode(text: '分支'));

    _historyManager.push(_editorState.scene);
    final result = _applyReflow(tree, rootNode);
    applyResult(result);
    _enterMindmapNodeEditing();
  }

  /// Finds the [MindmapNode] in [tree] whose sourceId matches [id].
  MindmapNode? _findTreeNode(MindmapNode tree, String id) {
    if (tree.sourceId == id) return tree;
    for (final child in tree.children) {
      final found = _findTreeNode(child, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Finds the parent of the tree node whose sourceId matches [id].
  MindmapNode? _findParentTreeNode(MindmapNode tree, String id) {
    for (final child in tree.children) {
      if (child.sourceId == id) return tree;
      final found = _findParentTreeNode(child, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Runs the reflow and builds a ToolResult: updates for existing nodes
  /// (position + style by depth/branch) + updates for existing edges (points
  /// recomputed from new node positions) + adds for new elements + selection.
  ToolResult _applyReflow(MindmapNode tree, Element rootNode) {
    final origin = Point(rootNode.x, rootNode.y);
    final plan = MindmapLayout.reflowTree(tree, origin: origin);
    final results = <ToolResult>[];

    // Build a lookup of new node positions by sourceId, so we can recompute
    // existing edges against the post-reflow coordinates.
    final newPosByNodeId = <String, ElementUpdate>{
      for (final u in plan.nodeUpdates) u.nodeId: u,
    };

    // Update existing nodes: look up by sourceId, move + restyle.
    for (final u in plan.nodeUpdates) {
      final node = _editorState.scene.getElementById(ElementId(u.nodeId));
      if (node == null) continue;
      results.add(_updateMindmapNode(node, u));
    }

    // Recompute existing mind-map edges: their sampled Bézier points don't
    // follow node moves (renderer doesn't resolve bindings), so regenerate
    // them against the post-reflow node positions.
    final scene = _editorState.scene;
    for (final e in scene.elements) {
      if (e.isDeleted) continue;
      if (e is! ArrowElement) continue;
      if (!MindmapUtils.isMindmapEdge(e)) continue;
      final startId = e.startBinding?.elementId;
      final endId = e.endBinding?.elementId;
      if (startId == null || endId == null) continue;
      // Only touch edges whose endpoints moved (are in this tree's reflow).
      if (!newPosByNodeId.containsKey(startId) &&
          !newPosByNodeId.containsKey(endId)) {
        continue;
      }
      // Use post-reflow positions (from newPosByNodeId) so the edge matches
      // where the nodes *will* be after this result is applied.
      results.add(
        UpdateElementResult(
          _recomputeEdgeFromPlan(e, startId, endId, newPosByNodeId, scene),
        ),
      );
    }

    // Add brand-new elements (new node rect + text + edge).
    for (final e in plan.newElements) {
      results.add(AddElementResult(e));
    }

    // Select the first new node rect for immediate text editing.
    final newNode = plan.newElements
        .where((e) => e.type == 'rectangle')
        .firstOrNull;
    if (newNode != null) {
      results.add(SetSelectionResult({newNode.id}));
    }

    return CompoundResult(results);
  }

  /// Moves an existing mind-map node to its new position and restyles it
  /// (background/size by depth, branch colour). Also repositions its bound
  /// text element.
  ToolResult _updateMindmapNode(Element node, ElementUpdate u) {
    final scene = _editorState.scene;
    final boundText = scene.findBoundText(node.id);

    // Restyle the rectangle by depth/branch. We re-derive the style the same
    // way _buildPair does, by querying MindmapLayout's public helpers.
    final (bg, stroke, strokeWidth, roundnessValue) =
        MindmapLayout.styleForNode(depth: u.depth, branchIndex: u.branchIndex);
    final updatedRect = (node as RectangleElement).copyWith(
      x: u.x,
      y: u.y,
      backgroundColor: bg,
      strokeColor: stroke,
      strokeWidth: strokeWidth,
      roundness: Roundness.adaptive(value: roundnessValue),
    );

    if (boundText == null) {
      return UpdateElementResult(updatedRect);
    }
    final (textColor, fontSize) =
        MindmapLayout.textStyleForNode(depth: u.depth);
    // copyWithText handles font size; copyWith handles position + text colour
    // (TextElement has no single method covering both).
    final updatedText = boundText
        .copyWithText(fontSize: fontSize)
        .copyWith(x: u.x, y: u.y, strokeColor: textColor);
    return CompoundResult([
      UpdateElementResult(updatedRect),
      UpdateElementResult(updatedText),
    ]);
  }

  /// Recomputes an existing mind-map edge's Bézier points from the post-reflow
  /// positions of its endpoints. Width/height come from the current element
  /// (node size is constant); x/y come from the reflow plan.
  ArrowElement _recomputeEdgeFromPlan(
    ArrowElement edge,
    String startId,
    String endId,
    Map<String, ElementUpdate> newPosByNodeId,
    Scene scene,
  ) {
    final parent = scene.getElementById(ElementId(startId));
    final child = scene.getElementById(ElementId(endId));
    if (parent == null || child == null) return edge;
    // Apply the new x/y from the plan (width/height unchanged).
    final pu = newPosByNodeId[startId];
    final cu = newPosByNodeId[endId];
    final parentMoved = parent.copyWith(
      x: pu?.x ?? parent.x,
      y: pu?.y ?? parent.y,
    );
    final childMoved = child.copyWith(
      x: cu?.x ?? child.x,
      y: cu?.y ?? child.y,
    );
    return MindmapLayout.recomputeEdge(edge, parentMoved, childMoved);
  }

  /// No-op in the immediate-commit model; kept for parity with flowchart.
  void mindmapCancel() {
    _mindmapCreator.clear();
    notifyListeners();
  }

  /// Starts editing the text of the most recently added mind-map node (the
  /// currently selected element), reusing the bound-text editing path.
  void _enterMindmapNodeEditing() {
    final selected = selectedElements;
    if (selected.length != 1) return;
    final node = selected.first;
    final text = _editorState.scene.findBoundText(node.id);
    if (text != null) {
      startTextEditingExisting(text);
    } else {
      startBoundTextEditing(node);
    }
  }

  /// Requests programmatic opening of a color picker.
  void requestColorPicker(ColorPickerTarget target) {
    _pendingColorPicker = target;
    notifyListeners();
  }

  /// Clears the pending color picker request.
  void clearPendingColorPicker() {
    _pendingColorPicker = null;
  }

  /// Opens the stroke color picker AND auto-activates the eyedropper.
  void requestEyedropper() {
    _pendingColorPicker = ColorPickerTarget.stroke;
    _pendingEyedropper = true;
    notifyListeners();
  }

  /// Clears the eyedropper auto-activate flag.
  void clearPendingEyedropper() {
    _pendingEyedropper = false;
  }

  // --- Eyedropper sampling ---

  /// Renders the scene to an offscreen image for pixel sampling.
  ///
  /// Call once when entering eyedropper mode, then use [sampleColorFromImage]
  /// to read pixels without re-rendering.
  Future<ui.Image?> renderSceneImage(Size canvasSize) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Fill with canvas background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
      Paint()..color = parseColor(_canvasBackgroundColor),
    );

    final painter = StaticCanvasPainter(
      scene: _editorState.scene,
      adapter: _adapter,
      viewport: _editorState.viewport,
      layout: _layout,
      resolvedImages: resolveImages(),
    );
    painter.paint(canvas, canvasSize);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      canvasSize.width.ceil(),
      canvasSize.height.ceil(),
    );
    picture.dispose();
    return image;
  }

  /// Exports a card-sized cover thumbnail for the current note.
  ///
  /// Paged notes render the first page. Unbounded notes render the current
  /// content bounds, or a stable blank canvas frame when the scene is empty.
  Future<Uint8List?> exportCoverThumbnail({
    Size outputSize = const Size(308, 408),
  }) async {
    if (outputSize.width <= 0 || outputSize.height <= 0) {
      return null;
    }
    final sourceRect = _coverThumbnailSourceRect(outputSize);

    const padding = 10.0;
    final drawableWidth = math.max(1.0, outputSize.width - padding * 2);
    final drawableHeight = math.max(1.0, outputSize.height - padding * 2);
    final sourceWidth = math.max(1.0, sourceRect.width);
    final sourceHeight = math.max(1.0, sourceRect.height);
    final zoom = math.min(
      drawableWidth / sourceWidth,
      drawableHeight / sourceHeight,
    );
    final renderedWidth = sourceWidth * zoom;
    final renderedHeight = sourceHeight * zoom;
    final horizontalInset = (outputSize.width - renderedWidth) / 2;
    final verticalInset = (outputSize.height - renderedHeight) / 2;
    final viewport = ViewportState(
      offset: Offset(
        sourceRect.left - horizontalInset / zoom,
        sourceRect.top - verticalInset / zoom,
      ),
      zoom: zoom,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & outputSize,
      Paint()..color = parseColor(_canvasBackgroundColor),
    );
    StaticCanvasPainter(
      scene: _editorState.scene,
      adapter: _adapter,
      viewport: viewport,
      layout: _layout,
      resolvedImages: resolveImages(),
      gridSize: _gridSize,
      contentBounds: _contentBounds,
      renderPageShadows: false,
    ).paint(canvas, outputSize);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      outputSize.width.ceil(),
      outputSize.height.ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return byteData?.buffer.asUint8List();
  }

  Rect _coverThumbnailSourceRect(Size outputSize) {
    if (_layout.isPaged) {
      final layoutWithPage = _layout.ensurePage();
      return layoutWithPage.pages.first.bounds;
    }
    final bounds = ExportBounds.compute(_editorState.scene, padding: 40);
    if (bounds == null) {
      return _emptyUnboundedThumbnailRect(outputSize);
    }
    return Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.size.width,
      bounds.size.height,
    );
  }

  Rect _emptyUnboundedThumbnailRect(Size outputSize) {
    final aspectRatio = outputSize.width / outputSize.height;
    const height = CanvasLayout.pageHeight;
    final width = height * aspectRatio;
    return Rect.fromCenter(center: Offset.zero, width: width, height: height);
  }

  /// Reads the pixel color at [screenPosition] from a pre-rendered [image].
  ///
  /// Returns a hex color string like '#ff0000', or null if out of bounds.
  Future<String?> sampleColorFromImage(
    ui.Image image,
    Offset screenPosition,
  ) async {
    final px = screenPosition.dx.round();
    final py = screenPosition.dy.round();
    if (px < 0 || py < 0 || px >= image.width || py >= image.height) {
      return null;
    }

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;

    final offset = (py * image.width + px) * 4;
    final r = byteData.getUint8(offset);
    final g = byteData.getUint8(offset + 1);
    final b = byteData.getUint8(offset + 2);

    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  // --- Convenience methods for serialization / export / import ---

  /// Serializes the current scene to a string in the given [format].
  String serializeScene({
    DocumentFormat format = DocumentFormat.markdraw,
    bool includeDeleted = false,
  }) {
    final doc = SceneDocumentConverter.sceneToDocument(
      _editorState.scene,
      settings: CanvasSettings(
        background: _canvasBackgroundColor,
        backgroundFollowsTheme: _canvasBackgroundFollowsTheme,
        grid: _gridSize,
        name: _documentName,
      ),
      includeDeleted: includeDeleted,
    );
    return switch (format) {
      DocumentFormat.markdraw => DocumentSerializer.serialize(doc),
      DocumentFormat.excalidraw => ExcalidrawJsonCodec.serialize(doc),
      _ => DocumentSerializer.serialize(doc),
    };
  }

  /// Serializes the current scene as an Excalidraw JSON object.
  Map<String, Object?> serializeExcalidrawSceneJson({
    bool includeDeleted = false,
  }) {
    return jsonDecode(
          serializeScene(
            format: DocumentFormat.excalidraw,
            includeDeleted: includeDeleted,
          ),
        )
        as Map<String, Object?>;
  }

  /// Loads a scene from file content. Detects format from [filename].
  void loadFromContent(String content, String filename) {
    final format = DocumentService.detectFormat(filename);
    final parseResult = switch (format) {
      DocumentFormat.markdraw => DocumentParser.parse(content),
      DocumentFormat.excalidraw => ExcalidrawJsonCodec.parse(content),
      _ => throw ArgumentError(
        'Use importLibraryFromContent for library files',
      ),
    };
    _canvasBackgroundColor = parseResult.value.settings.background;
    _canvasBackgroundFollowsTheme =
        parseResult.value.settings.backgroundFollowsTheme;
    if (_canvasBackgroundFollowsTheme) {
      _canvasBackgroundColor = _themeCanvasBackgroundColor;
    }
    _gridSize = parseResult.value.settings.grid;
    _documentName = parseResult.value.settings.name;
    loadScene(SceneDocumentConverter.documentToScene(parseResult.value));
  }

  /// Applies Excalidraw JSON received from collaboration.
  void applyRemoteContent(String content, {bool closeTransientUi = true}) {
    final parseResult = ExcalidrawJsonCodec.parse(content);
    _canvasBackgroundColor = parseResult.value.settings.background;
    _canvasBackgroundFollowsTheme =
        parseResult.value.settings.backgroundFollowsTheme;
    if (_canvasBackgroundFollowsTheme) {
      _canvasBackgroundColor = _themeCanvasBackgroundColor;
    }
    _gridSize = parseResult.value.settings.grid;
    _documentName = parseResult.value.settings.name;
    applyRemoteScene(
      SceneDocumentConverter.documentToScene(
        parseResult.value,
        regenerateIndices: false,
      ),
      closeTransientUi: closeTransientUi,
    );
  }

  /// Applies a full Excalidraw scene object received from collaboration.
  void applyRemoteExcalidrawSceneJson(
    Map<String, Object?> sceneJson, {
    bool closeTransientUi = true,
  }) {
    applyRemoteContent(
      jsonEncode(sceneJson),
      closeTransientUi: closeTransientUi,
    );
  }

  /// Exports the scene (or selection) as PNG bytes.
  Future<Uint8List?> exportPng({int scale = 2, bool selectedOnly = true}) {
    final selectedIds = selectedOnly && _editorState.selectedIds.isNotEmpty
        ? _editorState.selectedIds
        : null;
    return PngExporter.export(
      _editorState.scene,
      _adapter,
      scale: scale,
      backgroundColor: parseColor(_canvasBackgroundColor),
      selectedIds: selectedIds,
    );
  }

  /// Copies the scene (or selection) as a PNG image to the system clipboard.
  Future<void> copyAsPng() async {
    final bytes = await exportPng();
    if (bytes == null) return;
    await _clipboardService.copyImage(bytes);
  }

  /// Exports the scene (or selection) as an SVG string.
  String exportSvg({bool selectedOnly = true}) {
    final selectedIds = selectedOnly && _editorState.selectedIds.isNotEmpty
        ? _editorState.selectedIds
        : null;
    return SvgExporter.export(
      _editorState.scene,
      backgroundColor: _canvasBackgroundColor,
      selectedIds: selectedIds,
    );
  }

  /// Imports an image from raw bytes, decodes it, and adds it to the scene.
  ///
  /// [canvasSize] is used to center the image in the current viewport.
  Future<void> importImage(
    Uint8List bytes,
    String filename,
    Size canvasSize,
  ) async {
    final ext = filename.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/png',
    };

    final digest = sha1.convert(bytes);
    final fileId = digest.toString().substring(0, 8);
    final imageFile = ImageFile(mimeType: mimeType, bytes: bytes);

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final decodedImage = frame.image;
    final naturalWidth = decodedImage.width.toDouble();
    final naturalHeight = decodedImage.height.toDouble();

    double width = naturalWidth;
    double height = naturalHeight;
    const maxSize = 800.0;
    if (width > maxSize || height > maxSize) {
      final scale = maxSize / (width > height ? width : height);
      width *= scale;
      height *= scale;
    }

    final centerScene = _editorState.viewport.screenToScene(
      Offset(canvasSize.width / 2, canvasSize.height / 2),
    );
    final x = centerScene.dx - width / 2;
    final y = centerScene.dy - height / 2;

    final element = ImageElement(
      id: ElementId.generate(),
      x: x,
      y: y,
      width: width,
      height: height,
      fileId: fileId,
      mimeType: mimeType,
      status: 'pending',
    );

    _imageCache.putImage(fileId, decodedImage);

    pushHistory();
    applyResult(
      CompoundResult([
        AddFileResult(fileId: fileId, file: imageFile),
        AddElementResult(element),
        SetSelectionResult({element.id}),
      ]),
    );
  }

  void insertBlankPage({int? afterIndex}) {
    if (!_layout.isPaged) {
      return;
    }
    final pages = [..._layout.ensurePage().pages];
    final insertIndex = ((afterIndex ?? pages.length - 1) + 1).clamp(
      0,
      pages.length,
    );
    final pageId = 'page-${ElementId.generate().value}';
    final pageSize = CanvasLayout.pageSizeForTemplate(_layout.template);
    final newPage = CanvasPage(
      id: pageId,
      index: insertIndex,
      bounds: CanvasLayout.pageBoundsForIndex(
        index: insertIndex,
        pageSize: pageSize,
        pageFlow: _layout.pageFlow,
      ),
      template: _layout.template,
      pageFlow: _layout.pageFlow,
    );
    pages.insert(insertIndex, newPage);
    _applyPageOrder(pages);
  }

  void deletePage(String pageId) {
    if (!_layout.isPaged || _layout.pages.length <= 1) {
      return;
    }
    final remaining = [
      for (final page in _layout.pages)
        if (page.id != pageId) page,
    ];
    if (remaining.length == _layout.pages.length) {
      return;
    }
    final results = <ToolResult>[
      for (final element in _editorState.scene.elements)
        if (element.pageId == pageId || element.id.value == pageId)
          RemoveElementResult(element.id),
    ];
    _layout = _layout.copyWith(pages: remaining);
    results.addAll(_pageReorderResults(remaining));
    pushHistory();
    applyResult(CompoundResult(results));
    _syncLayoutFromScene();
  }

  void reorderPage(String pageId, int newIndex) {
    if (!_layout.isPaged) {
      return;
    }
    final pages = [..._layout.pages];
    final oldIndex = pages.indexWhere((page) => page.id == pageId);
    if (oldIndex < 0) {
      return;
    }
    final page = pages.removeAt(oldIndex);
    pages.insert(newIndex.clamp(0, pages.length), page);
    _applyPageOrder(pages);
  }

  void _applyPageOrder(List<CanvasPage> pages) {
    final results = _pageReorderResults(pages);
    pushHistory();
    applyResult(CompoundResult(results));
    _syncLayoutFromScene();
  }

  List<ToolResult> _pageReorderResults(List<CanvasPage> pages) {
    final oldPagesById = {for (final page in _layout.pages) page.id: page};
    final nextPages = <CanvasPage>[];
    final deltaByPageId = <String, Offset>{};

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pageFlow = page.pageFlow;
      final next = CanvasPage(
        id: page.id,
        index: i,
        bounds: CanvasLayout.pageBoundsForIndex(
          index: i,
          pageSize: page.bounds.size,
          pageFlow: pageFlow,
        ),
        template: page.template,
        pageFlow: pageFlow,
        source: page.source,
      );
      nextPages.add(next);
      deltaByPageId[page.id] =
          next.bounds.topLeft -
          (oldPagesById[page.id]?.bounds.topLeft ?? next.bounds.topLeft);
    }

    _layout = _layout.copyWith(pages: nextPages);
    final existingPageElementIds = {
      for (final element in _editorState.scene.elements)
        if (element.isCanvasPage) element.id.value,
    };
    final results = <ToolResult>[];

    for (final page in nextPages) {
      final pageElement = _editorState.scene.getElementById(ElementId(page.id));
      if (pageElement == null || !existingPageElementIds.contains(page.id)) {
        results.add(
          AddElementResult(
            RectangleElement(
              id: ElementId(page.id),
              x: page.bounds.left,
              y: page.bounds.top,
              width: page.bounds.width,
              height: page.bounds.height,
              strokeColor: 'transparent',
              backgroundColor: 'transparent',
              opacity: 0,
              locked: true,
              customData: CanvasLayout.pageCustomData(page),
            ),
          ),
        );
      } else {
        results.add(
          UpdateElementResult(
            pageElement.copyWith(
              x: page.bounds.left,
              y: page.bounds.top,
              width: page.bounds.width,
              height: page.bounds.height,
              customData: CanvasLayout.pageCustomData(page),
            ),
          ),
        );
      }
    }

    for (final element in _editorState.scene.elements) {
      if (element.isCanvasPage || element.isDeleted) {
        continue;
      }
      final pageId = element.pageId;
      final delta = pageId == null ? null : deltaByPageId[pageId];
      if (delta == null || delta == Offset.zero) {
        continue;
      }
      results.add(
        UpdateElementResult(
          element.copyWith(x: element.x + delta.dx, y: element.y + delta.dy),
        ),
      );
    }
    return results;
  }

  Future<void> importPdfPages(
    List<PdfRenderedPage> pages,
    Size canvasSize, {
    String? documentName,
    bool asBackground = false,
  }) async {
    if (pages.isEmpty) {
      return;
    }

    if (asBackground) {
      closeTransientUiForSceneReplace();
      _historyManager.clear();
      _editorState = _editorState.copyWith(scene: Scene(), selectedIds: {});
      _layout = CanvasLayout(
        type: CanvasLayoutType.paged,
        template: _layout.template,
        pageFlow: _layout.pageFlow,
      );
    }

    final results = <ToolResult>[];
    final nextPages = <CanvasPage>[];
    var cursor = Offset.zero;

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pageId = 'page-${page.pageNumber}';
      final pageBounds = Rect.fromLTWH(
        cursor.dx,
        cursor.dy,
        page.width,
        page.height,
      );
      if (_layout.isPaged) {
        final canvasPage = CanvasPage(
          id: pageId,
          index: i,
          bounds: pageBounds,
          template: _layout.template,
          pageFlow: _layout.pageFlow,
          source: 'pdf',
        );
        nextPages.add(canvasPage);
        results.add(
          AddElementResult(
            RectangleElement(
              id: ElementId(pageId),
              x: pageBounds.left,
              y: pageBounds.top,
              width: pageBounds.width,
              height: pageBounds.height,
              strokeColor: 'transparent',
              backgroundColor: 'transparent',
              opacity: 0,
              locked: true,
              customData: CanvasLayout.pageCustomData(canvasPage),
            ),
          ),
        );
      }

      final digest = sha1.convert(page.bytes);
      final fileId = 'pdf-${digest.toString().substring(0, 12)}';
      final imageFile = ImageFile(mimeType: page.mimeType, bytes: page.bytes);
      final codec = await ui.instantiateImageCodec(page.bytes);
      final frame = await codec.getNextFrame();
      _imageCache.putImage(fileId, frame.image);

      final element = ImageElement(
        id: ElementId.generate(),
        x: pageBounds.left,
        y: pageBounds.top,
        width: page.width,
        height: page.height,
        fileId: fileId,
        mimeType: page.mimeType,
        status: 'pending',
        locked: asBackground,
        customData: asBackground
            ? CanvasLayout.pdfBackgroundCustomData(pageId)
            : (_layout.isPaged ? CanvasLayout.elementCustomData(pageId) : null),
      );
      results
        ..add(AddFileResult(fileId: fileId, file: imageFile))
        ..add(AddElementResult(element));

      cursor = _layout.isRightToLeft
          ? Offset(cursor.dx - page.width - CanvasLayout.pageGap, 0)
          : Offset(0, cursor.dy + page.height + CanvasLayout.pageGap);
    }

    if (_layout.isPaged) {
      _layout = _layout.copyWith(pages: nextPages);
    }
    if (documentName != null && documentName.trim().isNotEmpty) {
      _documentName = documentName.trim();
    }
    pushHistory();
    applyResult(CompoundResult([...results, SetSelectionResult({})]));
    final effectiveCanvasSize = _canvasSize.width > 0 && _canvasSize.height > 0
        ? _canvasSize
        : canvasSize;
    if (asBackground) {
      this.canvasSize = effectiveCanvasSize;
      contentBounds = _pdfContentBounds;
    }
    setViewport(
      _fitRectViewport(
        Rect.fromLTWH(0, 0, pages.first.width, pages.first.height),
        effectiveCanvasSize,
      ),
    );
  }

  ViewportState _fitRectViewport(Rect rect, Size canvasSize) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      return ViewportState(offset: rect.topLeft);
    }
    final widthZoom = rect.width <= 0 ? 1.0 : canvasSize.width / rect.width;
    final heightZoom = rect.height <= 0 ? 1.0 : canvasSize.height / rect.height;
    final zoom = math
        .max(widthZoom, heightZoom)
        .clamp(_config.minZoom, _config.maxZoom);
    return ViewportState(offset: rect.topLeft, zoom: zoom);
  }

  /// Imports library items from file content. Detects format from [filename].
  void importLibraryFromContent(String content, String filename) {
    final format = DocumentService.detectFormat(filename);
    final ParseResult<LibraryDocument> result;
    switch (format) {
      case DocumentFormat.markdrawLibrary:
        result = LibraryCodec.parse(content);
      case DocumentFormat.excalidrawLibrary:
        result = ExcalidrawLibCodec.parse(content);
      case DocumentFormat.markdraw:
      case DocumentFormat.excalidraw:
        throw ArgumentError('Not a library file');
    }
    _libraryItems = [..._libraryItems, ...result.value.items];
    _showLibraryPanel = true;
    notifyListeners();
  }

  /// Serializes the current library items to a string.
  String exportLibraryContent({
    DocumentFormat format = DocumentFormat.excalidrawLibrary,
  }) {
    final doc = LibraryDocument(items: _libraryItems);
    return switch (format) {
      DocumentFormat.excalidrawLibrary => ExcalidrawLibCodec.serialize(doc),
      DocumentFormat.markdrawLibrary => LibraryCodec.serialize(doc),
      _ => ExcalidrawLibCodec.serialize(doc),
    };
  }
}
