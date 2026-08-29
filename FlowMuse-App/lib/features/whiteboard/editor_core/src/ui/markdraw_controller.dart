library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Element, SelectionOverlay;
import 'package:flutter/services.dart';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    as core
    show TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flow_muse/shared/utils/ui_lifecycle.dart';

import '../core/elements/collaboration_element_owner.dart';
import '../core/serialization/external_export_sanitizer.dart';
import '../config/writing_feature_flags.dart';
import 'harmony_stylus_stroke_smoother.dart';
import 'pointer_pressure.dart';
import '../rendering/viewport_clamp.dart';
import '../rendering/local_wet_ink_state.dart';
import '../input/active_preview_metrics_probe.dart';
import '../input/outline_render_mode.dart';
import '../input/stroke_input_normalizer.dart';
import '../input/stroke_input_modeler.dart';
import '../input/stroke_input_sample.dart';
import '../input/input_policy.dart';
import '../input/stroke_recorder.dart';

const String _logTag = 'InkRecognition';
const int _smartLayoutClientRecognitionConcurrency = 3;

/// 用户取消智能排版识别准备时抛出（UI 层捕获后静默处理，不弹失败提示）。
class SmartLayoutCancelledException implements Exception {}

/// Which color picker to open programmatically.
enum ColorPickerTarget { stroke, background, font }

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
enum SceneChangeSource { userEdit, undo, redo, reset, remoteApply, restore }

enum _TwoFingerGestureMode { pan, zoom }

typedef LiveInkFreedrawCallback =
    void Function(ActiveFreedrawView view, ElementStyle style, bool terminal);

class MarkdrawController extends ChangeNotifier {
  MarkdrawController({
    MarkdrawEditorConfig config = const MarkdrawEditorConfig(),
    this.activePreviewMetricsProbe,
    this.writingFlags = writingFeatureFlags,
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
  final ActivePreviewMetricsProbe? activePreviewMetricsProbe;
  final WritingFeatureFlags writingFlags;
  final LocalWetInkState localWetInkState = LocalWetInkState();
  int _nextLocalWetInkEpoch = 0;
  int? _activePreviewStrokeEpoch;
  int? _activePreviewMaxInputSeq;

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
  bool Function()? shouldUseLiveInkV2;
  LiveInkFreedrawCallback? onLiveInkChanged;
  ValueChanged<String>? onLiveInkCancelled;

  /// 宿主注入的本地结果预处理回调（仅本地用户变更经过；远端 applyRemote*、
  /// undo/redo、reset 不经过）。执行顺序固定于 default style 之后、系统剪贴板
  /// 副作用之前（v4 §5.1）。
  ToolResult? Function(ToolResult result, Scene currentScene)?
  onPrepareLocalResult;

  /// 当前本地创建者快照解析器（宿主注入；split pane sidecar 用于新增行盖章，
  /// 见 v4 §9.1 规则 3）。null = 无协作上下文，不盖章。
  CollaborationCreator? Function()? localCreatorResolver;
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
  Future<SmartLayoutVisionResponse> Function(SmartLayoutVisionRequest)?
  onVisionSmartLayout;

  /// 低置信裁剪重问：整页识别后把握不足的块裁出局部图无上下文转写。
  Future<SmartLayoutTranscribeResponse> Function(
  SmartLayoutTranscribeRequest)?
  onTranscribeCrop;
  ValueChanged<String>? onMindmapOperationError;
  void Function(bool enabled)? onInkRecognitionModeChanged;

  Timer? _inkRecognitionTimer;
  String? _pendingInkSessionId;
  bool _recognizingInk = false;

  // --- 智能排版识别准备（v2 视觉管线）取消状态 ---
  bool _smartLayoutPrepareActive = false;
  bool _smartLayoutPrepareCancelled = false;

  // --- 智能排版草稿编辑态（预览即编辑：可拖动、确认落地、取消零残留） ---
  bool _smartLayoutDraftActive = false;
  Scene? _draftBaseScene;
  ViewportState? _draftPreviousViewport;
  ToolType _draftPreviousTool = ToolType.select;
  Set<ElementId> _draftParticipants = {};
  List<ElementId> _smartLayoutDraftLowConfidenceIds = const [];

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

  ActivePreviewPaintMarker? get activePreviewPaintMarker {
    final strokeEpoch = _activePreviewStrokeEpoch;
    final maxInputSeq = _activePreviewMaxInputSeq;
    if (strokeEpoch == null || maxInputSeq == null) return null;
    return ActivePreviewPaintMarker(
      strokeEpoch: strokeEpoch,
      maxInputSeq: maxInputSeq,
    );
  }

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
    _cancelActiveToolInteraction(ActivePreviewTerminalReason.dispose);
    localWetInkState.clear(notify: false);
    localWetInkState.dispose();
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
    // 草稿编辑态：只允许"选择+拖动参与者"，禁止切换工具
    if (_smartLayoutDraftActive && type != ToolType.select) return;
    _cancelActiveToolInteraction(ActivePreviewTerminalReason.toolSwitch);
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
    if (_smartLayoutDraftActive) return;
    final undone = _historyManager.undo(_editorState.scene);
    if (undone != null) {
      _editorState = _editorState.copyWith(
        scene: undone,
        selectedIds: _validSelectionForScene(undone),
      );
      _syncLayoutFromScene();
      _lastChangedElements = null;
      onSceneChanged?.call(_editorState.scene, SceneChangeSource.undo);
      notifyListeners();
    }
  }

  /// Redoes the last undone scene change.
  void redo() {
    if (_smartLayoutDraftActive) return;
    final redone = _historyManager.redo(_editorState.scene);
    if (redone != null) {
      _editorState = _editorState.copyWith(
        scene: redone,
        selectedIds: _validSelectionForScene(redone),
      );
      _syncLayoutFromScene();
      _lastChangedElements = null;
      onSceneChanged?.call(_editorState.scene, SceneChangeSource.redo);
      notifyListeners();
    }
  }

  Set<ElementId> _validSelectionForScene(Scene scene) {
    final activeIds = {for (final element in scene.activeElements) element.id};
    return _editorState.selectedIds.intersection(activeIds);
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
    return SmartLayoutUtils.mergePageCustomData(customData, pageId);
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
  ///
  /// [applyDefaultStyle] 为 false 时跳过创建工具的默认样式套用，用于
  /// 手写转文字等"元素已定型（含字号/颜色/尺寸测量）"的复合结果，
  /// 避免 sticky 默认样式二次覆盖识别产物。
  void applyResult(ToolResult? result, {bool applyDefaultStyle = true}) {
    if (result == null) return;

    final constrained = _constrainViewport(result);
    final styled = applyDefaultStyle && isCreationTool
        ? _applyDefaultStyleToResult(constrained)
        : constrained;

    final prepared =
        onPrepareLocalResult?.call(styled, _editorState.scene) ?? styled;

    _syncToSystemClipboard(prepared);

    if (_isEditingLinear && _containsSelectionChange(prepared)) {
      _isEditingLinear = false;
    }

    final newState = _editorState.applyResult(prepared);
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

    if (isSceneChangingResult(prepared)) {
      // 草稿编辑态：临时场景改动不触发保存/协作广播/识别调度
      if (!_smartLayoutDraftActive) {
        _lastChangedElements = _changedElementsFromResult(
          styled,
          _editorState.scene,
        );
        onSceneChanged?.call(_editorState.scene, SceneChangeSource.userEdit);
        _scheduleInkRecognitionFromResult(prepared);
      }
    }

    notifyListeners();
  }

  /// 文本编辑等内部路径的统一收口：经 onPrepareLocalResult 盖章后应用并
  /// 替换 _editorState（v4 §5.1：不得只覆盖公开 applyResult）。
  EditorState _applyLocalResult(ToolResult? result) {
    final prepared = result == null
        ? null
        : onPrepareLocalResult?.call(result, _editorState.scene) ?? result;
    _editorState = _editorState.applyResult(prepared);
    return _editorState;
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
      // 转换产物已在 _elementFromRecognizedInk 内完成样式与尺寸测量，
      // 跳过 applyResult 的默认样式二次套用（sticky 字号/颜色不得覆盖识别结果）。
      final inkStyle = _dominantInkStyle(pendingStrokes);
      final elements = result.elements
          .map(
            (recognized) =>
                _elementFromRecognizedInk(recognized, inkStyle: inkStyle),
          )
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
        applyDefaultStyle: false,
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

  Element? _elementFromRecognizedInk(
    InkRecognizedElement recognized, {
    ({String color, double opacity})? inkStyle,
  }) {
    final x = recognized.x;
    final y = recognized.y;
    final width = math.max(recognized.width, 1.0);
    final height = math.max(recognized.height, 1.0);
    switch (recognized.type) {
      case 'text':
        final text = _normalizeRecognizedText(recognized.text);
        if (text == null) {
          return null;
        }
        return _measuredTextElement(
          text,
          x,
          y,
          width,
          height,
          inkColor: inkStyle?.color,
          inkOpacity: inkStyle?.opacity,
        );
      case 'math':
        final text = _normalizeRecognizedText(
          recognized.latex ?? recognized.text,
        );
        if (text == null) {
          return null;
        }
        return _measuredTextElement(
          text,
          x,
          y,
          width,
          height,
          isMath: true,
          inkColor: inkStyle?.color,
          inkOpacity: inkStyle?.opacity,
        );
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
    String? inkColor,
    double? inkOpacity,
  }) {
    final anchor = _smartInkLayoutMode
        ? _nearestTemplateAnchor(Rect.fromLTWH(x, y, width, height))
        : null;
    final vertical = anchor?.writingMode == TemplateWritingMode.vertical;
    final fontSize =
        anchor?.fontSize ??
        InkTextSizing.estimateFontSize(
          inkWidth: width,
          inkHeight: height,
          text: text,
          isMath: isMath,
        );
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
      fontSize: fontSize,
      lineHeight: _textLineHeightForTemplateAnchor(anchor),
      customData: flowMuseData == null ? null : {'flowMuse': flowMuseData},
    );
    var styled = applyDefaultStyleToElement(element) as TextElement;
    // 识别字号（跟随笔迹/模板锚点）与源笔迹颜色优先于 sticky 默认样式，
    // 否则用户改过一次字号/笔色后，转换结果会静默偏离手写原貌。
    styled = styled
        .copyWith(strokeColor: inkColor, opacity: inkOpacity)
        .copyWithText(fontSize: fontSize);
    if (vertical) {
      final (measuredWidth, measuredHeight) = TextRenderer.measure(styled);
      return styled.copyWith(
        width: math.max(measuredWidth, styled.width),
        height: math.max(measuredHeight, styled.height),
      );
    }
    if (isMath) {
      // latex 源码的文本测量 ≠ Math.tex 渲染尺寸（display 分式高约 2.2em），
      // 框高按 2.4em 余量兜底，避免公式被 ClipRect 裁剪。
      final (measuredWidth, measuredHeight) = TextRenderer.measure(styled);
      final sized = styled.copyWith(
        width: math.max(measuredWidth + 4, styled.width),
        height: math.max(
          math.max(measuredHeight, styled.height),
          styled.fontSize * 2.4,
        ),
      );
      return anchor == null
          ? sized
          : _alignSmartLayoutTextToAnchor(sized, anchor, false);
    }
    // 横排文本：框紧包裹测量后的文本，垂直居中于笔迹包围盒。
    final (measuredWidth, measuredHeight) = TextRenderer.measure(styled);
    final boxWidth = math.max(measuredWidth + 4, 20.0);
    final boxHeight = math.max(
      measuredHeight,
      styled.fontSize * styled.lineHeight,
    );
    final sized = styled.copyWith(
      x: x,
      y: y + (height - boxHeight) / 2,
      width: boxWidth,
      height: boxHeight,
    );
    return anchor == null
        ? sized
        : _alignSmartLayoutTextToAnchor(sized, anchor, false);
  }

  String? _normalizeRecognizedText(String? raw) {
    final text = raw?.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  /// 源笔迹的主导颜色：按累计点数最多的颜色，不透明度取该色加权均值。
  ({String color, double opacity})? _dominantInkStyle(
    List<FreedrawElement> strokes,
  ) {
    if (strokes.isEmpty) {
      return null;
    }
    final colorWeights = <String, double>{};
    final colorOpacitySums = <String, double>{};
    for (final stroke in strokes) {
      final weight = stroke.points.length.toDouble();
      colorWeights[stroke.strokeColor] =
          (colorWeights[stroke.strokeColor] ?? 0) + weight;
      colorOpacitySums[stroke.strokeColor] =
          (colorOpacitySums[stroke.strokeColor] ?? 0) + stroke.opacity * weight;
    }
    var dominantColor = strokes.first.strokeColor;
    var bestWeight = -1.0;
    colorWeights.forEach((color, weight) {
      if (weight > bestWeight) {
        bestWeight = weight;
        dominantColor = color;
      }
    });
    final weight = colorWeights[dominantColor]!;
    if (weight <= 0) {
      return (color: dominantColor, opacity: 1.0);
    }
    return (
      color: dominantColor,
      opacity: colorOpacitySums[dominantColor]! / weight,
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
    _applyLocalResult(SetSelectionResult({element.id}));
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
      _applyLocalResult(AddElementResult(textElem));
      final newBound = [
        ...shape.boundElements,
        BoundElement(id: newTextId.value, type: 'text'),
      ];
      _applyLocalResult(
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
      _applyLocalResult(AddElementResult(textElem));
      final newBound = [
        ...arrow.boundElements,
        BoundElement(id: newTextId.value, type: 'text'),
      ];
      _applyLocalResult(
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
      _applyLocalResult(RemoveElementResult(id));
      if (element is TextElement && element.containerId != null) {
        final parentId = ElementId(element.containerId!);
        final parent = _editorState.scene.getElementById(parentId);
        if (parent != null) {
          final newBound = parent.boundElements
              .where((b) => b.id != id.value)
              .toList();
          _applyLocalResult(
            UpdateElementResult(parent.copyWith(boundElements: newBound)),
          );
        }
      }
      _applyLocalResult(SetSelectionResult({}));
    } else {
      final element = _editorState.scene.getElementById(id);
      if (element is TextElement) {
        _applyLocalResult(
          UpdateElementResult(_textElementWithContent(element, text)),
        );
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
          _applyLocalResult(
            UpdateElementResult(element.copyWithText(text: _originalText!)),
          );
        }
      } else {
        final element = _editorState.scene.getElementById(
          _editingTextElementId!,
        );
        _applyLocalResult(RemoveElementResult(_editingTextElementId!));
        if (element is TextElement && element.containerId != null) {
          final parentId = ElementId(element.containerId!);
          final parent = _editorState.scene.getElementById(parentId);
          if (parent != null) {
            final newBound = parent.boundElements
                .where((b) => b.id != _editingTextElementId!.value)
                .toList();
            _applyLocalResult(
              UpdateElementResult(parent.copyWith(boundElements: newBound)),
            );
          }
        }
        _applyLocalResult(SetSelectionResult({}));
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
    _applyLocalResult(
      UpdateElementResult(_textElementWithContent(element, text)),
    );
    final changed = _editorState.scene.getElementById(id);
    _lastChangedElements = changed == null ? const [] : [changed];
    onSceneChanged?.call(_editorState.scene, SceneChangeSource.userEdit);
    notifyListeners();
  }

  TextElement _textElementWithContent(TextElement element, String text) {
    final measured = element.copyWithText(text: text);
    if (element.containerId != null) return measured;

    if (!element.autoResize && element.width > 0) {
      final (_, height) = TextRenderer.measure(
        measured,
        maxWidth: element.width,
      );
      return measured.copyWith(height: math.max(height, element.height));
    }

    final (width, height) = TextRenderer.measure(measured);
    final desiredWidth = math.max(width + 4, 20.0);
    final canvasSize = _canvasSize.isEmpty ? const Size(800, 600) : _canvasSize;
    final visible = _editorState.viewport.visibleRect(canvasSize);
    final bounds = _layout.isPaged
        ? (_layout.pageAt(Offset(element.x, element.y))?.bounds ?? visible)
        : visible;
    final area = bounds.deflate(math.min(48.0, bounds.shortestSide / 8));
    final minWidth = math.min(320.0, area.width);
    final x = element.x.clamp(area.left, area.right - minWidth).toDouble();
    final maxWidth = area.right - x;

    if (desiredWidth <= maxWidth) {
      return measured.copyWith(
        x: x,
        width: desiredWidth,
        height: math.max(height, element.fontSize * element.lineHeight),
      );
    }

    final (_, wrappedHeight) = TextRenderer.measure(
      measured,
      maxWidth: maxWidth,
    );
    return measured
        .copyWithText(autoResize: false)
        .copyWith(x: x, width: maxWidth, height: wrappedHeight);
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
    // 素材模板不保留协作身份（v4 §9.3）。
    final sanitizedItem = item.copyWith(
      elements: [for (final e in item.elements) withoutCreator(e)],
    );
    _libraryItems = [..._libraryItems, sanitizedItem];
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
    if (!_layout.isPaged) return true;
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
      final freedrawTool = _activeTool as FreedrawTool;
      freedrawTool.prepareStrokeLiveMode(shouldUseLiveInkV2?.call() ?? false);
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
      final r = kReleaseMode
          ? _modeler!.process(sample)
          : developer.Timeline.timeSync(
              'whiteboard.input_model',
              () => _modeler!.process(sample),
              arguments: {'phase': sample.phase.name},
            );
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
      _startActivePreviewStroke();
      applyResult(
        _activeTool.onPointerDown(point, toolContext, pressure: r.pressure),
      );
      _recordAcceptedActivePreviewPoint();
      _publishLocalWetInk();
      if (freedrawTool.activeView?.strokeLiveMode ?? false) {
        _emitLiveFreedraw();
      }
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

    // 草稿编辑态：只允许点击"方案参与者"（空白与非参与者不响应，禁误选/框选）
    if (_smartLayoutDraftActive) {
      final hit = _editorState.scene.getElementAtPoint(point);
      if (hit == null || !_draftParticipants.contains(hit.id)) {
        return;
      }
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
      final r = kReleaseMode
          ? _modeler!.process(sample)
          : developer.Timeline.timeSync(
              'whiteboard.input_model',
              () => _modeler!.process(sample),
              arguments: {'phase': sample.phase.name},
            );
      if (r.point == null) {
        activePreviewMetricsProbe?.recordRejectedRawSample(
          r.reason ?? r.decision.name,
        );
        return;
      }
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
      _recordAcceptedActivePreviewPoint();
      _scheduleLiveFreedraw();
      mousePosition = event.localPosition;
      if (writingFlags.layeredWetInk) {
        _publishLocalWetInk();
      } else {
        notifyListeners();
      }
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
      final r = kReleaseMode
          ? _modeler!.process(sample)
          : developer.Timeline.timeSync(
              'whiteboard.input_model',
              () => _modeler!.process(sample),
              arguments: {'phase': sample.phase.name},
            ); // flushes real endpoint

      if (r.point != null) {
        final sceneOffset = _editorState.viewport.screenToScenePrecise(
          Offset(r.point!.x, r.point!.y),
        );
        final point = Point(sceneOffset.dx, sceneOffset.dy);
        applyResult(
          _activeTool.onPointerMove(point, toolContext, pressure: r.pressure),
        );
        _recordAcceptedActivePreviewPoint();
        final activeView = (_activeTool as FreedrawTool).activeView;
        if (activeView?.strokeLiveMode ?? false) {
          _emitLiveFreedraw(terminal: true);
        }
        final finalResult = _activeTool.onPointerUp(
          point,
          toolContext,
          pressure: r.pressure,
        );
        if (writingFlags.layeredWetInk) {
          localWetInkState.clear(notify: false);
        }
        applyResult(finalResult);
      }

      _finishActivePreviewStroke(ActivePreviewTerminalReason.pointerUp);

      _modeler = null;
      _activeDrawPointerId = null;

      if (!_smartLayoutDraftActive &&
          _sceneBeforeDrag != null &&
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
    _cancelActiveToolInteraction(ActivePreviewTerminalReason.cancel);
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

  _TwoFingerGestureMode? _resolveTwoFingerGesture(ScaleUpdateDetails details) {
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
    _cancelActiveToolInteraction(ActivePreviewTerminalReason.viewportGesture);
    _sceneBeforeDrag = null;
  }

  void _cancelActiveToolInteraction(ActivePreviewTerminalReason reason) {
    _finishActivePreviewStroke(reason);
    if (_activeTool is FreedrawTool) {
      final tool = _activeTool as FreedrawTool;
      final activeView = tool.activeView;
      _cancelPendingLiveFreedraw();
      if (activeView?.strokeLiveMode ?? false) {
        tool.cancelStroke();
        onLiveInkCancelled?.call(activeView!.strokeId.value);
      } else {
        _emitLiveFreedraw(element: tool.cancelStroke());
      }
      if (writingFlags.layeredWetInk) {
        localWetInkState.clear(
          notify: reason != ActivePreviewTerminalReason.dispose,
        );
      }
    } else {
      _activeTool.reset();
    }
  }

  void _emitLiveFreedraw({FreedrawElement? element, bool terminal = false}) {
    final tool = _activeTool;
    if (tool is FreedrawTool) {
      final activeView = tool.activeView;
      if (activeView?.strokeLiveMode ?? false) {
        onLiveInkChanged?.call(activeView!, _defaultStyle, terminal);
        return;
      }
    }
    final callback = onLiveFreedrawChanged;
    if (callback == null) return;
    final live =
        element ??
        (tool is FreedrawTool ? tool.buildLiveElement(toolContext) : null);
    if (live == null) return;
    callback(applyDefaultStyleToElement(live) as FreedrawElement);
  }

  void _scheduleLiveFreedraw() {
    final tool = _activeTool;
    final activeView = tool is FreedrawTool ? tool.activeView : null;
    final hasCallback = activeView?.strokeLiveMode ?? false
        ? onLiveInkChanged != null
        : onLiveFreedrawChanged != null;
    if (!hasCallback || _liveFreedrawTimer != null) {
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

  void _startActivePreviewStroke() {
    final probe = activePreviewMetricsProbe;
    if (probe == null && !writingFlags.layeredWetInk) return;
    _activePreviewStrokeEpoch = probe?.startStroke() ?? ++_nextLocalWetInkEpoch;
    _activePreviewMaxInputSeq = null;
  }

  void _recordAcceptedActivePreviewPoint() {
    final probe = activePreviewMetricsProbe;
    final strokeEpoch = _activePreviewStrokeEpoch;
    if (probe == null || strokeEpoch == null) return;
    _activePreviewMaxInputSeq = probe.recordAcceptedPoint(strokeEpoch);
  }

  void _publishLocalWetInk() {
    if (!writingFlags.layeredWetInk || _activeTool is! FreedrawTool) return;
    final strokeEpoch = _activePreviewStrokeEpoch;
    final view = (_activeTool as FreedrawTool).activeView;
    if (strokeEpoch == null || view == null) return;
    localWetInkState.publish(
      LocalWetInkFrame(
        strokeEpoch: strokeEpoch,
        view: view,
        style: _defaultStyle,
        maxInputSeq: _activePreviewMaxInputSeq,
      ),
    );
  }

  void _finishActivePreviewStroke(ActivePreviewTerminalReason reason) {
    final strokeEpoch = _activePreviewStrokeEpoch;
    if (strokeEpoch != null) {
      activePreviewMetricsProbe?.finishStroke(strokeEpoch, reason);
    }
    _activePreviewStrokeEpoch = null;
    _activePreviewMaxInputSeq = null;
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
      _cancelActiveToolInteraction(ActivePreviewTerminalReason.cancel);
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

  
  /// 智能排版幽灵预览状态（画布层监听；null = 关闭）。
  final ValueNotifier<SmartLayoutGhostSpec?> smartLayoutGhost =
      ValueNotifier<SmartLayoutGhostSpec?>(null);

  /// 模板选择准备（v2 模板卡片制）：识别（认字+图文配对+裁剪重问）完成后
  /// 预落位三张模板，交给模板选择卡展示真实内容缩略图。
  /// 返回 null = 本页无可排版手写内容；识别失败直接抛异常（无经典管线回退），
  /// 由 UI 提示重试；用户取消则抛 [SmartLayoutCancelledException]（UI 静默处理）。
  ///
  /// [onProgress] 仅在裁剪重问（逐块转写）阶段回调：`completed` = 已完成块数
  /// （无论重问结果是否被采用）、`total` = 待转写文本块数；阶段开始时先回调
  /// 一次 (0, total)。整页截图与 VLM 整页识别阶段不回调。
  Future<SmartLayoutTemplatePreparation?> prepareSmartLayoutTemplates({
    required String pageId,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_recognizingInk) {
      throw StateError('智能排版进行中，请稍候');
    }
    if (_disposed) {
      throw StateError('编辑器已释放');
    }
    CanvasPage? page;
    for (final candidate in _layout.pages) {
      if (candidate.id == pageId) {
        page = candidate;
        break;
      }
    }
    if (page == null) {
      throw StateError('页面不存在: $pageId');
    }
    if (onVisionSmartLayout == null) {
      throw StateError('没有可用的识别引擎');
    }
    _recognizingInk = true;
    _smartLayoutPrepareActive = true;
    // 取消状态在下一次准备开始时重置（契约：取消只作用于当次准备）。
    _smartLayoutPrepareCancelled = false;
    try {
      final (:groups, noiseStrokeIds: pageNoiseIds) =
          _smartLayoutInkGroupsForPage(pageId);
      if (groups.isEmpty) {
        return null;
      }
      final preparation = await _prepareVisionRecognition(
        page,
        groups,
        onProgress,
        noiseStrokeIds: pageNoiseIds,
      );
      if (_disposed) {
        throw StateError('编辑器已释放');
      }
      return preparation;
    } finally {
      _recognizingInk = false;
      _smartLayoutPrepareActive = false;
    }
  }

  /// 请求取消进行中的智能排版识别准备（幂等；未在准备中时为空操作）。
  ///
  /// 取消后 [prepareSmartLayoutTemplates] 在下一个检查点抛
  /// [SmartLayoutCancelledException]；已发出的截图/VLM 请求不强行中断 HTTP，
  /// 待其返回后在检查点收尾。prepare 本就不修改场景，取消保证场景零残留；
  /// 取消状态在下一次 prepare 开始时重置。
  void cancelSmartLayoutPreparation() {
    if (!_smartLayoutPrepareActive) return;
    _smartLayoutPrepareCancelled = true;
  }

  /// 取消检查点：准备被用户取消时立即中止后续阶段。
  void _throwIfSmartLayoutCancelled() {
    if (_smartLayoutPrepareCancelled) {
      throw SmartLayoutCancelledException();
    }
  }

  /// 按用户点选的模板把准备结果装配成计划（确定性；随后进入既有草稿态）。
  ///
  /// [keepHandwriting]：保留手写模式——文本块笔迹不删除、经 moveDeltas 整体
  /// 移动占位（布局源取 layoutsKeepInk，同一 content 的二次引擎调用产物，
  /// 无额外 VLM 成本）。默认 false 行为不变（转写印刷体、笔迹删除）。
  SmartLayoutPlanResult buildSmartLayoutPlanForTemplate(
    SmartLayoutTemplatePreparation preparation,
    SmartLayoutTemplateKind kind, {
    bool keepHandwriting = false,
  }) {
    final content = keepHandwriting
        ? preparation.content.withTextAsInk()
        : preparation.content;
    final cachedLayouts = keepHandwriting
        ? preparation.layoutsKeepInk
        : preparation.layouts;
    final layout =
        cachedLayouts[kind] ??
        SmartLayoutTemplateEngine.layout(kind: kind, content: content);
    if (layout == null) {
      return const SmartLayoutPlanResult(error: '内容过多，请分页后再试');
    }
    // 保留手写：文本块笔迹从删除清单排除（引擎已把它们放进 moveDeltas
    // 并计入 selectIds）；对应灰区矩形同步排除，避免幽灵预览盖住保留墨迹。
    final keepInkStrokeIds = keepHandwriting
        ? _textInkStrokeIds(preparation.content)
        : const <ElementId>{};
    final plan = SmartLayoutPlan(
      pageId: preparation.pageId,
      style: kind,
      confidence: preparation.confidence,
      description: layout.description,
      addElements: layout.addElements,
      moveDeltas: layout.moveDeltas,
      removeIds: [
        for (final id in preparation.removeIds)
          if (!keepInkStrokeIds.contains(id)) id,
      ],
      failedStrokeIds: preparation.failedStrokeIds,
      selectIds: {
        ...{for (final element in layout.addElements) element.id},
        ...layout.moveDeltas.keys,
      },
      document: layout.document,
      previewRects: layout.previewRects,
      removalRects: keepHandwriting
          ? [
              for (final rect in preparation.removalRects)
                if (!preparation.textClusterRects.contains(rect)) rect,
            ]
          : preparation.removalRects,
      failureRects: preparation.failureRects,
    );
    return SmartLayoutPlanResult(
      plan: _attachVisionLowConfidence(plan, preparation.confidenceByBlockId),
      failures: preparation.failures,
    );
  }

  /// 文本单元的墨迹笔迹 id（keepAsInk 时从删除清单排除、随 moveDeltas 移动）。
  Set<ElementId> _textInkStrokeIds(SmartLayoutContent content) => {
    for (final unit in content.textUnits)
      ...[for (final id in unit.memberIds) ElementId(id)],
  };

  /// 应用计划：一次 History 提交（删除→移动→新增→文档→选区）。
  bool applySmartLayoutPlan(
    SmartLayoutPlan plan, {
    bool dropFailedBlocks = false,
  }) {
    if (_disposed) return false;
    pushHistory();
    final results = <ToolResult>[
      for (final id in plan.removeIds) RemoveElementResult(id),
      if (dropFailedBlocks)
        for (final id in plan.failedStrokeIds) RemoveElementResult(id),
    ];
    results.addAll(
      SmartLayoutMoveBuilder.buildResults(_editorState.scene, plan.moveDeltas),
    );
    results.addAll([
      for (final element in plan.addElements)
        AddElementResult(
          element.copyWith(
            customData: SmartLayoutUtils.mergePageCustomData(
              element.customData,
              plan.pageId,
            ),
          ),
        ),
    ]);
    results.add(SetSmartLayoutResult(plan.document));
    results.add(SetSelectionResult(plan.selectIds));
    applyResult(CompoundResult(results));
    smartLayoutGhost.value = null;
    return true;
  }

  /// 设置/清除画布幽灵预览。
  void setSmartLayoutGhost(SmartLayoutGhostSpec? spec) {
    smartLayoutGhost.value = spec;
  }

  /// 是否处于智能排版草稿编辑态。
  bool get smartLayoutDraftActive => _smartLayoutDraftActive;

  /// 进入草稿编辑态：把排版计划应用到一个临时场景并整体渲染，
  /// 参与者默认全选（可整组拖动/点选单个），方案外元素不响应；不推历史、不触发保存/广播。
  void enterSmartLayoutDraft(SmartLayoutPlan plan) {
    if (_smartLayoutDraftActive || _disposed) return;
    _draftBaseScene = _editorState.scene;
    _draftPreviousViewport = _editorState.viewport;
    _draftPreviousTool = _editorState.activeToolType;
    _draftParticipants = {
      ...plan.moveDeltas.keys,
      ...plan.addElements.map((element) => element.id),
    };
    _smartLayoutDraftLowConfidenceIds = [
      for (final item in plan.lowConfidenceTexts) item.elementId,
    ];
    final tempScene = _buildDraftScene(plan);
    _smartLayoutDraftActive = true;
    // 适配框 = 页框 ∪ 预落位矩形（走查 #10：排版结果可能贴近/超出页缘，
    // 只看页框会把新内容挤出视野；previewRects 与页框同为场景坐标）。
    final viewport = _fitViewportToRects(plan.pageId, plan.previewRects);
    _editorState = _editorState.copyWith(
      scene: tempScene,
      selectedIds: _draftParticipants,
      activeToolType: ToolType.select,
      viewport: viewport ?? _editorState.viewport,
    );
    _activeTool = createTool(ToolType.select);
    notifyListeners();
  }

  /// 确认落地：以草稿中的最终坐标在真实场景上产生**一次**历史提交。
  bool commitSmartLayoutDraft(
    SmartLayoutPlan plan, {
    bool dropFailedBlocks = false,
  }) {
    if (!_smartLayoutDraftActive || _disposed) return false;
    final draft = _editorState.scene;
    final base = _draftBaseScene!;
    final finalDeltas = <ElementId, ui.Offset>{};
    // 计算既有参与者最终位移（草稿位置 - 基础位置）
    for (final id in _draftParticipants) {
      Element? baseElement;
      for (final element in base.activeElements) {
        if (element.id == id) {
          baseElement = element;
          break;
        }
      }
      if (baseElement == null) continue; // 新增元素在 addElements 里
      Element? draftElement;
      for (final element in draft.activeElements) {
        if (element.id == id) {
          draftElement = element;
          break;
        }
      }
      if (draftElement == null) continue;
      final dx = draftElement.x - baseElement.x;
      final dy = draftElement.y - baseElement.y;
      if (dx != 0 || dy != 0) {
        finalDeltas[id] = ui.Offset(dx, dy);
      }
    }
    // 新增元素的最终形态（含拖动后的位置）
    final finalAdds = <Element>[];
    for (final element in plan.addElements) {
      Element? draftElement;
      for (final candidate in draft.activeElements) {
        if (candidate.id == element.id) {
          draftElement = candidate;
          break;
        }
      }
      finalAdds.add(
        draftElement ??
            element.copyWith(
              customData: SmartLayoutUtils.mergePageCustomData(
                element.customData,
                plan.pageId,
              ),
            ),
      );
    }
    // 还原真实场景，再一次性提交
    _smartLayoutDraftActive = false;
    _smartLayoutDraftPreviousSceneRestore(plan);
    pushHistory();
    final results = <ToolResult>[
      for (final id in plan.removeIds) RemoveElementResult(id),
      if (dropFailedBlocks)
        for (final id in plan.failedStrokeIds) RemoveElementResult(id),
      ...SmartLayoutMoveBuilder.buildResults(base, finalDeltas),
      for (final element in finalAdds) AddElementResult(element),
      SetSmartLayoutResult(plan.document),
      SetSelectionResult({
        ...{for (final element in finalAdds) element.id},
        ...finalDeltas.keys,
      }),
    ];
    applyResult(CompoundResult(results));
    smartLayoutGhost.value = null;
    return true;
  }

  /// 取消草稿：完全还原进入前场景与视口（零残留）。
  void cancelSmartLayoutDraft() {
    if (!_smartLayoutDraftActive) return;
    _smartLayoutDraftActive = false;
    final base = _draftBaseScene!;
    _editorState = _editorState.copyWith(
      scene: base,
      selectedIds: {},
      activeToolType: _draftPreviousTool,
      viewport: _draftPreviousViewport ?? _editorState.viewport,
    );
    _activeTool = createTool(_draftPreviousTool);
    _draftBaseScene = null;
    _draftParticipants = {};
    _draftPreviousViewport = null;
    _smartLayoutDraftLowConfidenceIds = const [];
    smartLayoutGhost.value = null;
    notifyListeners();
  }

  /// 内部：提交前把草稿场景换回真实场景（不触发保存/广播）。
  void _smartLayoutDraftPreviousSceneRestore(SmartLayoutPlan plan) {
    _editorState = _editorState.copyWith(scene: _draftBaseScene);
    _draftBaseScene = null;
    _draftParticipants = {};
    _draftPreviousViewport = null;
    _smartLayoutDraftLowConfidenceIds = const [];
  }

  Scene _buildDraftScene(SmartLayoutPlan plan) {
    var temp = _editorState.scene;
    temp = _applyResultsToScene(
      temp,
      [
        for (final id in plan.removeIds) RemoveElementResult(id),
        ...SmartLayoutMoveBuilder.buildResults(temp, plan.moveDeltas),
        for (final element in plan.addElements)
          AddElementResult(
            element.copyWith(
              customData: SmartLayoutUtils.mergePageCustomData(
                element.customData,
                plan.pageId,
              ),
            ),
          ),
      ],
    );
    return temp;
  }

  Scene _applyResultsToScene(Scene scene, List<ToolResult> results) {
    var next = scene;
    for (final result in results) {
      next = switch (result) {
        AddElementResult(:final element) => next.addElement(element),
        UpdateElementResult(:final element) => next.updateElement(element),
        RemoveElementResult(:final id) => next.softDeleteElement(id),
        _ => next,
      };
    }
    return next;
  }

  /// 草稿进入视口适配：适配框 = 页框 ∪ [previewRects]（场景坐标并集）。
  /// 页面不存在时返回 null（调用方保持当前视口）。
  ViewportState? _fitViewportToRects(String pageId, List<ui.Rect> previewRects) {
    CanvasPage? page;
    for (final candidate in _layout.pages) {
      if (candidate.id == pageId) {
        page = candidate;
        break;
      }
    }
    if (page == null) return null;
    var union = page.bounds;
    for (final rect in previewRects) {
      union = union.expandToInclude(rect);
    }
    final size = _lastCanvasSize ?? const ui.Size(800, 600);
    return _editorState.viewport.fitToBounds(
      Bounds.fromLTWH(union.left, union.top, union.width, union.height),
      size,
      padding: 32,
    );
  }

  /// 视觉优先管线：整页截图交 VLM 判定，匹配回场景原稿后走现有 PPT 模板。
  /// 返回 null = 回退经典管线（未接线 / 截图失败 / 接口异常 / 风格未接管 / 匹配项过少）。
  /// 视觉识别准备（v2）：整页截图 + Set-of-Mark 编号 → VLM 认字/图文配对 →
  /// 裁剪重问 → 结构层 content → 三模板预落位 + 成功/失败账本。
  /// 失败路径（截图失败/识别异常/无内容）一律抛异常，由 UI 提示重试；
  /// v2 无经典管线回退。
  Future<SmartLayoutTemplatePreparation?> _prepareVisionRecognition(
    CanvasPage page,
    Map<String, List<FreedrawElement>> inkGroups,
    void Function(int completed, int total)? onProgress, {
    List<ElementId> noiseStrokeIds = const [],
  }) async {
    final visionCallback = onVisionSmartLayout;
    if (visionCallback == null) {
      throw StateError('没有可用的识别引擎');
    }
    final pageBounds = ui.Rect.fromLTWH(
      page.bounds.left,
      page.bounds.top,
      page.bounds.width,
      page.bounds.height,
    );
    // 导出区外扩一圈：SoM 徽章悬在簇框上方、裁剪重问外扩 16pt 都需要画布边缘有余量。
    final exportMargin =
        _visionExportMarginPx *
        math.max(pageBounds.width, pageBounds.height) /
        _visionExportLongestSide;
    final exportBounds = pageBounds.inflate(exportMargin);
    Uint8List? cleanPng;
    Uint8List? markedPng;
    final clusterRects = <String, ui.Rect>{
      for (final entry in inkGroups.entries)
        entry.key: _inkGroupBounds(entry.value),
    };
    final figures = _smartLayoutFigureUnits(page.id);
    // Set-of-Mark：墨迹簇 + 页面可移动元素全部作为候选对象，按阅读序（上→左）
    // 编号 m1..mN，编号与对象的映射留在客户端，服务端/VLM 只见编号。
    final markCandidates = <({String key, ui.Rect rect, bool isText})>[
      for (final entry in clusterRects.entries)
        (key: entry.key, rect: entry.value, isText: true),
      for (final entry in figures.rects.entries)
        (key: entry.key, rect: entry.value, isText: false),
    ]..sort((a, b) {
      final byTop = a.rect.top.compareTo(b.rect.top);
      return byTop != 0 ? byTop : a.rect.left.compareTo(b.rect.left);
    });
    final textMarks = <String, String>{};
    final figureMarks = <String, String>{};
    final markLabels = <({String id, ui.Rect bounds})>[];
    final markIds = <String>[];
    for (var i = 0; i < markCandidates.length; i++) {
      final markId = 'm${i + 1}';
      markIds.add(markId);
      markLabels.add((id: markId, bounds: markCandidates[i].rect));
      if (markCandidates[i].isText) {
        textMarks[markId] = markCandidates[i].key;
      } else {
        figureMarks[markId] = markCandidates[i].key;
      }
    }
    try {
      // 双导出：干净截图供裁剪重问（无标记，避免徽章被二次转写），
      // 带标记截图只发 VLM 做编号引用。
      cleanPng = await exportRegionPng(
        exportBounds,
        maxLongestSide: _visionExportLongestSide,
      );
      markedPng = await exportRegionPng(
        exportBounds,
        maxLongestSide: _visionExportLongestSide,
        afterPaint: (canvas, zoom) =>
            _drawVisionMarkOverlay(canvas, zoom, exportBounds, markLabels),
      );
    } catch (error) {
      debugPrint('[$_logTag] 视觉排版截图失败: $error');
      throw StateError('页面截图失败，请重试');
    }
    if (cleanPng == null ||
        cleanPng.isEmpty ||
        markedPng == null ||
        markedPng.isEmpty ||
        _disposed) {
      throw StateError('页面截图失败，请重试');
    }
    _throwIfSmartLayoutCancelled(); // 检查点：截图两连导出后
    final vision = await visionCallback(
      SmartLayoutVisionRequest(
        pageId: page.id,
        imageBase64: base64Encode(markedPng),
        marks: markIds,
      ),
    );
    if (_disposed) {
      throw StateError('编辑器已释放');
    }
    _throwIfSmartLayoutCancelled(); // 检查点：vision 回调返回后（已发出的请求不强行中断）
    // 无有效元素 = VLM 没认出任何内容（v2 无回退，直接提示重试）。
    if (vision.elements.isEmpty) {
      debugPrint('[$_logTag] 视觉排版无元素');
      throw StateError('未能识别出页面内容，请重试');
    }

    final match = SmartLayoutVisionMatcher.match(
      elements: vision.elements,
      textMarks: textMarks,
      figureMarks: figureMarks,
      allClusterKeys: clusterRects.keys.toSet(),
    );
    if (match.matchedItemCount < 1) {
      debugPrint('[$_logTag] 视觉排版无匹配项');
      throw StateError('未能识别出页面内容，请重试');
    }
    _throwIfSmartLayoutCancelled(); // 检查点：识别匹配与逐块转写阶段之间

    // 文本项转写：每个认领的笔迹簇合并后**先走整页 VLM 文本**；把握不足
    // （< kSmartLayoutTranscribeRetryThreshold）或无文本的块再走低置信裁剪
    // 重问（局部图无上下文单块转写，新结果把握更高才采用）。
    final recognition = await _recognizeVisionTextBlocks(
      page,
      vision.elements,
      match.textClaims,
      inkGroups,
      clusterRects,
      cleanPng,
      exportBounds,
      onProgress: onProgress,
    );
    if (_disposed) {
      throw StateError('编辑器已释放');
    }
    _throwIfSmartLayoutCancelled(); // 检查点：逐块转写全部返回后
    final textBlocksByIndex = recognition.blocks;
    final textElementsByIndex = <int, TextElement>{};
    final textSourceByIndex = <int, ui.Rect>{};
    for (final entry in match.textClaims.entries) {
      final block = textBlocksByIndex[entry.key];
      if (block == null || !block.isSuccess) continue;
      // 纯标点/纯符号转写（如"、"、"~"，无字母/数字/CJK）不生成文本元素、
      // 不进排版流；其笔迹按成功结算（随方案静默删除，与失败红区区分）。
      if (isPunctuationOnlyText(block.text)) continue;
      var union = clusterRects[entry.value.first]!;
      for (final key in entry.value.skip(1)) {
        union = union.expandToInclude(clusterRects[key]!);
      }
      final textElement = _textElementFromRecognizedBlock(block);
      if (textElement == null) continue;
      textElementsByIndex[entry.key] = textElement;
      textSourceByIndex[entry.key] = union;
    }

    LayoutUnit makeTextUnit(int index) {
      final element = textElementsByIndex[index]!;
      return LayoutUnit(
        key: 'vision-$index',
        sourceBounds: textSourceByIndex[index]!,
        size: ui.Size(element.width, element.height),
        kind: LayoutUnitKind.text,
        textElement: element,
        // 该块笔迹元素 id：保留手写模式随方案移动、从删除清单排除；
        // 转写模式（默认）仍整块删除。
        memberIds: [
          for (final key in match.textClaims[index] ?? const <String>[])
            ...[
              for (final stroke in inkGroups[key] ?? const <FreedrawElement>[])
                stroke.id.value,
            ],
        ],
      );
    }

    // 图形单元预先构建（VLM 配对、几何兜底与松散集合共用）。
    LayoutUnit? buildFigureUnit(int index) {
      final unitKey = match.figureClaims[index];
      if (unitKey == null) return null;
      final rect = figures.rects[unitKey];
      final representative = figures.elements[unitKey];
      if (rect == null || representative == null) return null;
      return LayoutUnit(
        key: unitKey,
        sourceBounds: rect,
        size: ui.Size(rect.width, rect.height),
        kind: representative is ImageElement
            ? LayoutUnitKind.image
            : LayoutUnitKind.shape,
        element: representative,
        memberIds: figures.memberIds[unitKey] ?? [unitKey],
      );
    }

    final figureUnitByIndex = <int, LayoutUnit>{};
    for (final index in match.figureClaims.keys) {
      final unit = buildFigureUnit(index);
      if (unit != null) figureUnitByIndex[index] = unit;
    }

    // title：第一个 role=title 且成功创建的文本项（仅 1 个，AI 侧已去重）。
    int? titleIndex;
    for (final index in match.textClaims.keys) {
      if (vision.elements[index].role == 'title') {
        if (textElementsByIndex.containsKey(index)) {
          titleIndex = index;
        }
        break;
      }
    }

    // pairId 配对：同 ID 的 caption+figure 各取第一项（VLM 主注先落）。
    final captionIndexByPair = <String, int>{};
    for (final index in match.textClaims.keys) {
      if (index == titleIndex) continue;
      final pairId = vision.elements[index].pairId?.trim();
      if (pairId != null &&
          pairId.isNotEmpty &&
          !captionIndexByPair.containsKey(pairId)) {
        captionIndexByPair[pairId] = index;
      }
    }
    final figureIndexByPair = <String, int>{};
    for (final index in match.figureClaims.keys) {
      final pairId = vision.elements[index].pairId?.trim();
      if (pairId != null &&
          pairId.isNotEmpty &&
          !figureIndexByPair.containsKey(pairId)) {
        figureIndexByPair[pairId] = index;
      }
    }
    // 一图可收多个标签、一文本只归一图：先收 VLM 主注，几何兜底再补漏。
    final pairTextsByFigureIndex = <int, List<LayoutUnit>>{};
    final pairedTextIndexes = <int>{};
    final pairedFigureIndexes = <int>{};
    void attachText(int figureIndex, int textIndex) {
      (pairTextsByFigureIndex[figureIndex] ??= []).add(makeTextUnit(textIndex));
      pairedTextIndexes.add(textIndex);
      // 图已被配对消费：不再落入 looseFigures（Set 幂等，多标签只记一次）。
      pairedFigureIndexes.add(figureIndex);
    }

    for (final entry in figureIndexByPair.entries) {
      final captionIndex = captionIndexByPair[entry.key];
      if (captionIndex == null) continue;
      if (figureUnitByIndex[entry.value] == null ||
          !textElementsByIndex.containsKey(captionIndex)) {
        continue;
      }
      attachText(entry.value, captionIndex);
      pairedFigureIndexes.add(entry.value);
    }

    // 客户端几何配对兜底：VLM pairId 漏配时（走查实况：图注与图分家成独立
    // 正文条目），图旁短标签（caption 角色 / "图N"式 / 去空白 ≤10 字）按
    // 包围盒间隙就近绑图补漏。分配语义"一图可收多标签、一文只归最近图"：
    // 图侧无容量上限，已收 VLM 主注的图仍是合法兜底目标（pairId 主注 +
    // 兜底标签同图成组）。确定性见 matchUnpairedCaptionsByGeometry。
    final fallbackPairs = matchUnpairedCaptionsByGeometry(
      captions: {
        for (final index in match.textClaims.keys)
          if (index != titleIndex &&
              !pairedTextIndexes.contains(index) &&
              textElementsByIndex.containsKey(index))
            if (_figureLabelPairMaxGap(vision.elements[index])
                case final maxGap?)
              index: (
                bounds: textSourceByIndex[index]!,
                maxGap: maxGap,
              ),
      },
      figures: {
        for (final index in match.figureClaims.keys)
          if (figureUnitByIndex[index] != null)
            index: figureUnitByIndex[index]!.sourceBounds,
      },
    );
    fallbackPairs.forEach((textIndex, figureIndex) {
      attachText(figureIndex, textIndex);
    });

    // 松散项按阅读顺序（先上后左）排列——确定性。
    int readingCompare(ui.Rect a, ui.Rect b) {
      final byTop = a.top.compareTo(b.top);
      return byTop != 0 ? byTop : a.left.compareTo(b.left);
    }

    // 组装配对：每图一条 FigureTextPair（bind 按原稿几何分上/下标签栈），
    // 配对按图原稿阅读序排序（不依赖 VLM 返回顺序，确定性）。
    final pairs =
        [
          for (final entry in pairTextsByFigureIndex.entries)
            FigureTextPair.bind(
              figure: figureUnitByIndex[entry.key]!,
              texts: entry.value,
            ),
        ]..sort(
          (a, b) => readingCompare(a.figure.sourceBounds, b.figure.sourceBounds),
        );

    final looseTexts =
        [
          for (final index in textElementsByIndex.keys)
            if (index != titleIndex && !pairedTextIndexes.contains(index))
              makeTextUnit(index),
        ]..sort(
          (a, b) => readingCompare(a.sourceBounds, b.sourceBounds),
        );
    final looseFigures = <LayoutUnit>[];
    for (final index in match.figureClaims.keys) {
      if (pairedFigureIndexes.contains(index)) continue;
      final unit = figureUnitByIndex[index];
      if (unit != null) looseFigures.add(unit);
    }
    looseFigures.sort(
      (a, b) => readingCompare(a.sourceBounds, b.sourceBounds),
    );

    final content = SmartLayoutContent(
      pageId: page.id,
      contentArea: ui.Rect.fromLTWH(
        page.bounds.left + 72,
        page.bounds.top + 72,
        page.bounds.width - 144,
        page.bounds.height - 144,
      ),
      title: titleIndex == null ? null : makeTextUnit(titleIndex),
      pairs: pairs,
      looseTexts: looseTexts,
      looseFigures: looseFigures,
    );

    _throwIfSmartLayoutCancelled(); // 检查点：结构层组装与模板预落位之间
    // 全空内容（无标题、无配对、无松散图文）：VLM 认领了簇但文字全部未被
    // 救回（如只回显编号被服务端剥空且重问失败）——退化页会组装出空模板卡，
    // 没有意义，直接提示重试。figure-only 页（有图无字）不视为空。
    if (content.title == null &&
        content.pairs.isEmpty &&
        content.looseTexts.isEmpty &&
        content.looseFigures.isEmpty) {
      throw StateError('未能识别出页面内容，请重试');
    }

    // 成功/失败账本：每个簇按其归属文本项的转写结果分入删除或红区；未认领簇直接红区。
    final successByClusterKey = <String, bool>{};
    match.textClaims.forEach((index, keys) {
      final success = textBlocksByIndex[index]?.isSuccess ?? false;
      for (final key in keys) {
        successByClusterKey[key] = success;
      }
    });
    final removeStrokeIds = <ElementId>[
      // 噪点笔画（<8×8pt）：识别不涉及，随方案静默删除，消除残留墨点。
      ...noiseStrokeIds,
      for (final text in _pageScopedOldSmartText(page.id)) text.id,
    ];
    final failedStrokeIds = <ElementId>[];
    final removalRects = <ui.Rect>[];
    final failureRects = <ui.Rect>[];
    final failures = <SmartLayoutFailureInfo>[];
    void account(String key) {
      final rect = clusterRects[key]!;
      if (successByClusterKey[key] == true) {
        removalRects.add(rect);
        removeStrokeIds.addAll([
          for (final stroke in inkGroups[key] ?? const <FreedrawElement>[])
            stroke.id,
        ]);
        return;
      }
      failureRects.add(rect);
      failedStrokeIds.addAll([
        for (final stroke in inkGroups[key] ?? const <FreedrawElement>[])
          stroke.id,
      ]);
      failures.add(
        SmartLayoutFailureInfo(
          blockId: 'vision-failed-${failureRects.length}',
          bounds: rect,
          error: '疑似手写内容未被识别成功',
        ),
      );
    }

    // 确定性顺序：先被认领的簇（按文本项序），再未认领的簇。
    for (final key in successByClusterKey.keys) {
      account(key);
    }
    for (final key in match.unclaimedClusterKeys) {
      account(key);
    }

    // 低置信校对直查表：blockId（== VLM 元素 id）→ 重问后的有效把握。
    final confidenceByBlockId = <String, double>{
      for (final index in textElementsByIndex.keys)
        vision.elements[index].id ?? 'e$index':
            recognition.confidences[index] ?? vision.elements[index].confidence,
    };

    // 三张模板预落位：模板卡缩略图与"放不下"禁用态共用（同输入同输出）。
    final layouts = <SmartLayoutTemplateKind, SmartLayoutTemplateLayoutResult?>{
      for (final kind in SmartLayoutTemplateKind.values)
        kind: SmartLayoutTemplateEngine.layout(kind: kind, content: content),
    };
    // 保留手写变体：同一 content 把文本单元置 keepAsInk 后二次引擎调用
    // （无额外 VLM 成本），"保留手写笔迹"开关与缩略图共用。
    final layoutsKeepInk =
        <SmartLayoutTemplateKind, SmartLayoutTemplateLayoutResult?>{
          for (final kind in SmartLayoutTemplateKind.values)
            kind: SmartLayoutTemplateEngine.layout(
              kind: kind,
              content: content.withTextAsInk(),
            ),
        };
    // 成功识别文本块的来源簇矩形："保留手写"装配时从灰区排除（墨迹保留）。
    final textClusterRects = <ui.Rect>[
      for (final entry in match.textClaims.entries)
        if (textElementsByIndex.containsKey(entry.key))
          for (final key in entry.value) clusterRects[key]!,
    ];
    final textConfidences = <double>[
      for (final index in textElementsByIndex.keys)
        recognition.confidences[index] ?? vision.elements[index].confidence,
    ];
    final confidence = textConfidences.isEmpty
        ? 0.0
        : textConfidences.reduce((a, b) => a + b) / textConfidences.length;
    return SmartLayoutTemplatePreparation(
      pageId: page.id,
      content: content,
      layouts: layouts,
      layoutsKeepInk: layoutsKeepInk,
      removeIds: removeStrokeIds,
      failedStrokeIds: failedStrokeIds,
      removalRects: removalRects,
      failureRects: failureRects,
      failures: failures,
      confidence: confidence,
      confidenceByBlockId: confidenceByBlockId,
      textClusterRects: textClusterRects,
    );
  }

  /// 视觉装配收尾：把低置信文本项（把握不足）挂到计划上，供草稿态
  /// 橙色高亮与校对编辑条。模板引擎创建的元素都在 customData.flowMuse.blockId
  /// 里带着来源块 id（== VLM 元素 id），按 blockId 直查，无启发式。
  /// 把握取重问后的有效值：裁剪重问已救回的项不再标橙。
  SmartLayoutPlan _attachVisionLowConfidence(
    SmartLayoutPlan plan,
    Map<String, double> confidenceByBlockId,
  ) {
    final texts = <SmartLayoutLowConfidenceText>[];
    for (final element in plan.addElements) {
      final blockId = _flowMuseData(element)?['blockId'] as String?;
      if (blockId == null || blockId.isEmpty) continue;
      final confidence = confidenceByBlockId[blockId];
      if (confidence == null ||
          confidence >= kSmartLayoutLowConfidenceThreshold) {
        continue;
      }
      texts.add(
        SmartLayoutLowConfidenceText(
          elementId: element.id,
          confidence: confidence,
        ),
      );
    }
    if (texts.isEmpty) return plan;
    return plan.withLowConfidenceTexts(texts);
  }

  /// 草稿态低置信文本项快照（id + 当前文字），供校对编辑条构建。
  List<({ElementId id, String text})> get smartLayoutDraftProofreadItems {
    if (!_smartLayoutDraftActive ||
        _smartLayoutDraftLowConfidenceIds.isEmpty) {
      return const [];
    }
    final scene = _editorState.scene;
    final items = <({ElementId id, String text})>[];
    for (final id in _smartLayoutDraftLowConfidenceIds) {
      for (final element in scene.activeElements) {
        if (element.id == id && element is TextElement) {
          items.add((id: id, text: element.text));
          break;
        }
      }
    }
    return items;
  }

  /// 草稿态全文文本项快照（id + 当前文字），供"核对全文"构建。
  /// 来源 = 草稿场景中带智能排版标记（flowMuse.smartLayout）的文本元素。
  /// 保留手写草稿无新增文本元素（文本以墨迹移动）→ 空列表。
  List<({ElementId id, String text})> get smartLayoutDraftAllTextItems {
    if (!_smartLayoutDraftActive) return const [];
    final items = <({ElementId id, String text})>[];
    for (final element in _editorState.scene.activeElements) {
      if (element is TextElement &&
          _flowMuseData(element)?['smartLayout'] == true) {
        items.add((id: element.id, text: element.text));
      }
    }
    return items;
  }

  /// 草稿态低置信文本矩形的实时快照（改字/拖动后重取，橙色高亮用）。
  List<ui.Rect> get smartLayoutDraftLowConfidenceRects {
    if (!_smartLayoutDraftActive ||
        _smartLayoutDraftLowConfidenceIds.isEmpty) {
      return const [];
    }
    final scene = _editorState.scene;
    final rects = <ui.Rect>[];
    for (final id in _smartLayoutDraftLowConfidenceIds) {
      for (final element in scene.activeElements) {
        if (element.id == id) {
          rects.add(
            ui.Rect.fromLTWH(
              element.x,
              element.y,
              element.width,
              element.height,
            ),
          );
          break;
        }
      }
    }
    return rects;
  }

  /// 草稿态就地改字：更新临时场景中的文本并按当前字号重测尺寸（位置保持）。
  /// 提交时 commitSmartLayoutDraft 会按 id 采用草稿场景的最终形态，无需额外登记。
  bool reviseSmartLayoutDraftText(ElementId id, String newText) {
    if (!_smartLayoutDraftActive || _disposed) return false;
    final scene = _editorState.scene;
    TextElement? current;
    for (final element in scene.activeElements) {
      if (element.id == id && element is TextElement) {
        current = element;
        break;
      }
    }
    if (current == null) return false;
    final trimmed = newText.trim();
    // 空文本会产出不可见的空文字元素（笔迹已删、橙框圈空盒），拒绝保存。
    if (trimmed.isEmpty) return false;
    var candidate = current.copyWithText(text: trimmed);
    // 与创建/引擎一致的尺寸规则：横排 max(现值, 测量) 只放不缩，
    // 避免改字后盒子跳动。（v2 转写一律横排，无竖排文本进草稿。）
    final (measuredWidth, measuredHeight) = TextRenderer.measure(candidate);
    candidate = candidate.copyWith(
      width: math.max(current.width, measuredWidth),
      height: math.max(current.height, measuredHeight),
    );
    // 草稿场景内原位替换（同 id）；提交时按 id 采用草稿最终形态。
    applyResult(UpdateElementResult(candidate));
    return true;
  }

  
  /// 视觉路径逐文本项转写：整页 VLM 文本单引擎（智能排版不再使用 MyScript，
  /// 其仅保留在独立"手写字迹识别"入口）；把握不足或无文本的块走低置信裁剪
  /// 重问（裁剪自无标记干净截图）。返回各项文本块与"有效把握"
  /// （重问后可能高于 VLM 自报值）。
  Future<
    ({Map<int, SmartLayoutRecognizedBlock> blocks, Map<int, double> confidences})
  >
  _recognizeVisionTextBlocks(
    CanvasPage page,
    List<SmartLayoutVisionElement> elements,
    Map<int, List<String>> textClaims,
    Map<String, List<FreedrawElement>> inkGroups,
    Map<String, ui.Rect> clusterRects,
    Uint8List? cleanPagePng,
    ui.Rect exportBounds, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final requests = <SmartLayoutInkBlockRequest>[];
    final unionsByRequestId = <String, ui.Rect>{};
    final indexByRequestId = <String, int>{};
    for (final entry in textClaims.entries) {
      final index = entry.key;
      var union = clusterRects[entry.value.first]!;
      for (final key in entry.value.skip(1)) {
        union = union.expandToInclude(clusterRects[key]!);
      }
      final requestId = 'v-e$index';
      unionsByRequestId[requestId] = union;
      indexByRequestId[requestId] = index;
      final strokes = [
        for (final key in entry.value)
          ...(inkGroups[key] ?? const <FreedrawElement>[]),
      ];
      if (strokes.isEmpty) continue;
      requests.add(
        SmartLayoutInkBlockRequest(
          id: requestId,
          pageId: page.id,
          bounds: Bounds.fromLTWH(
            union.left,
            union.top,
            union.width,
            union.height,
          ),
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
          // 视觉路径不需要块级截图（整页截图已发 VLM；重问时按块裁剪）。
          imageBase64: '',
        ),
      );
    }
    // 干净整页截图（无 SoM 标记）延迟解码：只有存在待重问的块才解一次
    // （并发 worker 共享）。
    final retryRequestIds = <String>{
      for (final request in requests)
        if (shouldReAskTranscription(
          text: elements[indexByRequestId[request.id]!].text,
          confidence: elements[indexByRequestId[request.id]!].confidence,
        ))
          request.id,
    };
    Future<ui.Image?>? decodeFuture;
    Future<ui.Image?> pageImage() {
      if (cleanPagePng == null) return Future.value(null);
      return decodeFuture ??= _decodeUiImage(cleanPagePng);
    }

    final effectiveConfidenceByIndex = <int, double>{};
    Future<SmartLayoutRecognizedBlock> recognizeOne(
      SmartLayoutInkBlockRequest request,
    ) async {
      final index = indexByRequestId[request.id]!;
      final visionElement = elements[index];
      var text = visionElement.text?.trim() ?? '';
      var confidence = visionElement.confidence;
      // 低置信裁剪重问：从干净整页截图裁出该块（外扩 16pt），无上下文单块转写；
      // 新结果有文字且把握更高才采用（KIE-HVQA：上下文隔离降幻觉）。
      if (retryRequestIds.contains(request.id) && onTranscribeCrop != null) {
        try {
          final image = await pageImage();
          if (image != null) {
            final reAsk = await _transcribeCropFromImage(
              pageImage: image,
              pageBounds: exportBounds,
              blockRect: unionsByRequestId[request.id]!,
            );
            final adopted = adoptTranscription(
              currentText: text,
              currentConfidence: text.isEmpty ? -1 : confidence,
              reAsk: reAsk,
            );
            if (adopted != null) {
              text = adopted.text;
              confidence = adopted.confidence;
            }
          }
        } catch (error) {
          // 重问失败不影响主流程：保留整页识别的原结果。
          debugPrint('[$_logTag] 裁剪重问失败，保留原结果: $error');
        }
      }
      effectiveConfidenceByIndex[index] = confidence;
      final isSuccess = text.isNotEmpty;
      // 引用 id 用元素 id（校对链路一致）、边界用认领簇并集。
      final elementId = visionElement.id ?? 'e$index';
      final unionRect = unionsByRequestId[request.id];
      return SmartLayoutRecognizedBlock(
        id: elementId,
        pageId: page.id,
        type: isSuccess ? 'text' : 'error',
        text: isSuccess ? text : null,
        bounds: unionRect == null
            ? request.bounds
            : Bounds.fromLTWH(unionRect.left, unionRect.top, unionRect.width,
                  unionRect.height),
        strokeBounds: const [],
        startedAt: request.startedAt,
        error: isSuccess ? null : 'vlm-no-text',
      );
    }

    var results = <SmartLayoutRecognizedBlock>[];
    if (requests.isNotEmpty) {
      results = await _recognizeSmartLayoutBlocksInParallel(
        requests,
        recognizeOne,
        onProgress,
      );
    } else {
      // 无待转写块：仍回调一次，让进度条以 total=0 直接完成。
      onProgress?.call(0, 0);
    }
    await decodeFuture;
    if (_smartLayoutPrepareCancelled) {
      throw SmartLayoutCancelledException(); // 检查点：干净整页图解码返回后
    }
    return (
      blocks: {
        for (var i = 0; i < requests.length; i++)
          indexByRequestId[requests[i].id]!: results[i],
      },
      confidences: effectiveConfidenceByIndex,
    );
  }

  /// 裁剪重问触发条件：无文本（VLM 未给出转写）或把握低于重问阈值。
  @visibleForTesting
  static bool shouldReAskTranscription({
    required String? text,
    required double confidence,
  }) {
    return (text ?? '').trim().isEmpty ||
        confidence < kSmartLayoutTranscribeRetryThreshold;
  }

  /// "图N"式短标签（如"图1""图 2"）：即使 role 不是 caption 也参与
  /// 就近配对（间隙阈值放宽到 kSmartLayoutFigureLabelPairMaxGap）。
  static final RegExp _figureLabelPattern = RegExp(r'^图\s*\d*$');

  /// 去空白匹配（短标签判定用："图 1 介绍"与"图1介绍"同权）。
  static final RegExp _whitespacePattern = RegExp(r'\s');

  /// 图旁标签配对候选及其与图的包围盒间隙上限（null = 非候选）：caption
  /// 角色、"图N"式短标签（≤6 字，间隙放宽到 kSmartLayoutFigureLabelPairMaxGap），
  /// 或去空白不超过 10 字的短文本块（走查实况：上方"小懒羊睡觉"/下方
  /// "图1介绍"这类短标签 role=body 且非图N，也需要绑图，不再散落正文；
  /// 其余候选间隙 64pt）。
  static double? _figureLabelPairMaxGap(SmartLayoutVisionElement element) {
    final text = element.text?.trim() ?? '';
    if (text.length <= 6 && _figureLabelPattern.hasMatch(text)) {
      return kSmartLayoutFigureLabelPairMaxGap;
    }
    if (element.role == 'caption') return kSmartLayoutCaptionPairMaxGap;
    if (text.isEmpty) return null;
    return text.replaceAll(_whitespacePattern, '').length <= 10
        ? kSmartLayoutCaptionPairMaxGap
        : null;
  }

  /// 纯标点/纯符号转写判定：不含任何字母/数字/CJK（如"、"、"~"）的文本
  /// 不生成文本元素，其笔迹随方案静默删除。空文本返回 false（由既有
  /// 失败红区路径处理，不在此改变其归属）。
  @visibleForTesting
  static bool isPunctuationOnlyText(String? text) {
    final trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) return false;
    return !_meaningfulTextPattern.hasMatch(trimmed);
  }

  /// 有意义字符：ASCII 字母数字、拉丁扩展字母、假名/谚文/CJK 汉字
  /// （CJK 标点 、。等在 \u3000-\u303F，不计入）。
  static final RegExp _meaningfulTextPattern = RegExp(
    r'[0-9A-Za-z\u00C0-\u024F\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF'
    r'\uAC00-\uD7AF\uF900-\uFAFF]',
  );

  /// 图旁标签几何配对兜底（纯函数）：VLM pairId 配对失败时，把未配对的
  /// 图旁标签按包围盒间隙就近绑到未配对的图。分配语义"一图可收多标签、
  /// 一文只归一图"：每个文本取（间隙, 图 top, 图 index）字典序最小且不超
  /// 过该项 maxGap 的图——等价于对全部（文本，图）候选边按间隙升序做全局
  /// 贪心（图侧无容量上限，文本间互不争用，同分图取 top 小者、文本按
  /// index 升序消费）。确定性：同输入同输出。返回 textIndex → figureIndex。
  @visibleForTesting
  static Map<int, int> matchUnpairedCaptionsByGeometry({
    required Map<int, ({ui.Rect bounds, double maxGap})> captions,
    required Map<int, ui.Rect> figures,
  }) {
    final result = <int, int>{};
    final figureIndexes = figures.keys.toList()..sort();
    for (final textIndex in captions.keys.toList()..sort()) {
      final caption = captions[textIndex]!;
      int? bestFigure;
      var bestDistance = double.infinity;
      var bestTop = double.infinity;
      for (final figureIndex in figureIndexes) {
        final figureBounds = figures[figureIndex]!;
        final distance = _boundingBoxGap(caption.bounds, figureBounds);
        if (distance > caption.maxGap) continue;
        if (distance < bestDistance ||
            (distance == bestDistance && figureBounds.top < bestTop)) {
          bestDistance = distance;
          bestTop = figureBounds.top;
          bestFigure = figureIndex;
        }
      }
      if (bestFigure != null) {
        result[textIndex] = bestFigure;
      }
    }
    return result;
  }

  /// 两个包围盒的净间隙：x 向净距 + y 向净距（相交/重叠方向记 0）。
  static double _boundingBoxGap(ui.Rect a, ui.Rect b) {
    final dx = math.max(
      0.0,
      math.max(a.left, b.left) - math.min(a.right, b.right),
    );
    final dy = math.max(
      0.0,
      math.max(a.top, b.top) - math.min(a.bottom, b.bottom),
    );
    return dx + dy;
  }

  /// 低置信裁剪重问的择优规则：新结果有文字且把握严格更高才采用——与原文
  /// 不同 → 采用新文；与原文相同 → 采信原文并把把握提升到新值（两次独立
  /// 读一致，清除存疑橙框）。端点失败、无文字（模型自认看不清）或把握
  /// 不升 → 保留原结果。
  @visibleForTesting
  static ({String text, double confidence})? adoptTranscription({
    required String currentText,
    required double currentConfidence,
    required SmartLayoutTranscribeResponse? reAsk,
  }) {
    if (reAsk == null) return null;
    final text = reAsk.text.trim();
    if (text.isEmpty) return null;
    if (reAsk.confidence <= currentConfidence) return null;
    if (text == currentText) {
      return (text: currentText, confidence: reAsk.confidence);
    }
    return (text: text, confidence: reAsk.confidence);
  }

  /// 裁剪重问的外扩边距（pt）：给识别留出上下文边缘，避免字被裁半。
  static const double _visionCropPadding = 16.0;

  /// 智能排版整页导出的最长边像素（与 exportRegionPng 的默认值一致）。
  static const double _visionExportLongestSide = 1568;

  /// 导出区外扩的目标像素余量：SoM 徽章（约 22px 高）悬在簇框上方需要边距。
  static const double _visionExportMarginPx = 28;

  Future<SmartLayoutTranscribeResponse?> _transcribeCropFromImage({
    required ui.Image pageImage,
    required ui.Rect pageBounds,
    required ui.Rect blockRect,
  }) async {
    final callback = onTranscribeCrop;
    if (callback == null) return null;
    final zoom = pageImage.width / math.max(pageBounds.width, 1.0);
    final cropRect = Rect.fromLTWH(
      blockRect.left - _visionCropPadding,
      blockRect.top - _visionCropPadding,
      blockRect.width + _visionCropPadding * 2,
      blockRect.height + _visionCropPadding * 2,
    ).intersect(pageBounds);
    if (cropRect.width <= 0 || cropRect.height <= 0) return null;
    final src = Rect.fromLTWH(
      (cropRect.left - pageBounds.left) * zoom,
      (cropRect.top - pageBounds.top) * zoom,
      math.max(cropRect.width * zoom, 1.0),
      math.max(cropRect.height * zoom, 1.0),
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawImageRect(
      pageImage,
      src,
      Rect.fromLTWH(0, 0, src.width, src.height),
      Paint(),
    );
    final picture = recorder.endRecording();
    ui.Image? cropped;
    try {
      cropped = await picture.toImage(
        src.width.round().clamp(1, 4096),
        src.height.round().clamp(1, 4096),
      );
      final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return callback(
        SmartLayoutTranscribeRequest(
          imageBase64: base64Encode(byteData.buffer.asUint8List()),
          imageMime: 'image/png',
        ),
      );
    } finally {
      cropped?.dispose();
      picture.dispose();
    }
  }

  Future<ui.Image?> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// 页内可移动元素 → 版式图形单元（整组共用一个单元），供视觉匹配与模板移动。
  ({Map<String, Element> elements, Map<String, ui.Rect> rects,
  Map<String, List<String>> memberIds}) _smartLayoutFigureUnits(String pageId) {
    final elements = <String, Element>{};
    final rects = <String, ui.Rect>{};
    final memberIds = <String, List<String>>{};
    void addUnit(String key, List<Element> members) {
      var union = _placementBoundsForElement(members.first);
      for (final member in members.skip(1)) {
        union = union.union(_placementBoundsForElement(member));
      }
      elements[key] = members.first;
      rects[key] = ui.Rect.fromLTWH(
        union.left,
        union.top,
        union.size.width,
        union.size.height,
      );
      memberIds[key] = [
        for (final member in members) member.id.value,
      ];
    }

    for (final element in _smartLayoutPageElements(pageId)) {
      final groupId = GroupUtils.outermostGroupId(element);
      if (groupId == null) {
        addUnit(element.id.value, [element]);
        continue;
      }
      if (elements.containsKey(groupId)) continue;
      final members = GroupUtils.findGroupMembers(_editorState.scene, groupId);
      if (members.isEmpty) continue;
      addUnit(groupId, members);
    }
    return (elements: elements, rects: rects, memberIds: memberIds);
  }

  /// SoM 编号徽章落位：悬在簇框左上角上方（间隙 2px，不遮笔迹——VLM 曾把
  /// 框内徽章当成手写内容抄进转写）；顶部余量不足退到框下方，底部也不足
  /// （画布贴边）才回框内左上角；横向贴边时向内收。
  @visibleForTesting
  static Rect visionMarkLabelRect({
    required Rect boxRect,
    required Size labelSize,
    required Size canvasSize,
  }) {
    const gap = 2.0;
    final left = boxRect.left
        .clamp(0.0, math.max(0.0, canvasSize.width - labelSize.width))
        .toDouble();
    if (boxRect.top >= labelSize.height + gap) {
      return Rect.fromLTWH(
        left,
        boxRect.top - labelSize.height - gap,
        labelSize.width,
        labelSize.height,
      );
    }
    if (boxRect.bottom + gap + labelSize.height <= canvasSize.height) {
      return Rect.fromLTWH(
        left,
        boxRect.bottom + gap,
        labelSize.width,
        labelSize.height,
      );
    }
    return Rect.fromLTWH(
      left,
      math.max(0.0, boxRect.top),
      labelSize.width,
      labelSize.height,
    );
  }

  /// Set-of-Mark 叠加：把编号标记画进导出截图（场景坐标→导出像素坐标），
  /// VLM 读图上编号输出 markIds，不做坐标回归。徽章悬在簇框外侧上方，
  /// 不遮笔迹（见 visionMarkLabelRect）。
  void _drawVisionMarkOverlay(
    Canvas canvas,
    double zoom,
    ui.Rect pageBounds,
    List<({String id, ui.Rect bounds})> marks,
  ) {
    const markColors = [
      Color(0xFFE5484D),
      Color(0xFF3B82F6),
      Color(0xFF22C55E),
      Color(0xFFF08C00),
      Color(0xFF9333EA),
      Color(0xFF0EA5E9),
      Color(0xFFE11D8F),
      Color(0xFF84CC16),
    ];
    final canvasSize = ui.Size(
      pageBounds.width * zoom,
      pageBounds.height * zoom,
    );
    for (var i = 0; i < marks.length; i++) {
      final mark = marks[i];
      final pixelRect = Rect.fromLTWH(
        (mark.bounds.left - pageBounds.left) * zoom,
        (mark.bounds.top - pageBounds.top) * zoom,
        mark.bounds.width * zoom,
        mark.bounds.height * zoom,
      );
      final color = markColors[i % markColors.length];
      canvas.drawRect(
        pixelRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: mark.id,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelRect = visionMarkLabelRect(
        boxRect: pixelRect,
        labelSize: Size(textPainter.width + 10, textPainter.height + 6),
        canvasSize: canvasSize,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(3)),
        Paint()..color = color,
      );
      textPainter.paint(canvas, labelRect.topLeft + const Offset(5, 3));
      textPainter.dispose();
    }
  }

  /// 页内墨迹聚类 + 噪点账本：v2 全页纯几何聚类（会话维度不参与），
  /// 竖排窄高列整列不拆；杂散小笔画（<8×8pt）不进聚类，其 id 经
  /// [noiseStrokeIds] 返回、由调用方并入方案删除清单（应用时静默删除，
  /// 消除"没排干净"的残留墨点；prepare 不改场景、取消零残留）。
  /// 键形如 `<pageId>:c<N>`。
  ({Map<String, List<FreedrawElement>> groups, List<ElementId> noiseStrokeIds})
  _smartLayoutInkGroupsForPage(String pageId) {
    final pageStrokes = [
      for (final element in _smartLayoutInkElements())
        if (_pageIdForElement(element) == pageId) element,
    ];
    final noiseStrokeIds = <ElementId>[];
    final clustered = <FreedrawElement>[];
    for (final stroke in pageStrokes) {
      if (SmartLayoutInkClusterer.isNoiseStroke(stroke)) {
        noiseStrokeIds.add(stroke.id);
      } else {
        clustered.add(stroke);
      }
    }
    final clusters = SmartLayoutInkClusterer.cluster(clustered);
    return (
      groups: <String, List<FreedrawElement>>{
        for (var i = 0; i < clusters.length; i++) '$pageId:c$i': clusters[i],
      },
      noiseStrokeIds: noiseStrokeIds,
    );
  }

  List<TextElement> _pageScopedOldSmartText(String pageId) {
    return [
      for (final element in _smartLayoutGeneratedTextElements())
        if (_pageIdForElement(element) == pageId) element,
    ];
  }

  List<Element> _smartLayoutPageElements(String pageId) {
    return [
      for (final element in _editorState.scene.activeElements)
        if (_pageIdForElement(element) == pageId &&
            !element.isCanvasPage &&
            !element.isPdfBackground &&
            !element.locked &&
            !_isMindmapElement(element) &&
            element is! FreedrawElement)
          element,
    ];
  }

  bool _isMindmapElement(Element element) {
    final role = _flowMuseData(element)?['role'];
    return role == 'mindmap-node' || role == 'mindmap-edge';
  }

  
  
  ui.Rect _inkGroupBounds(List<FreedrawElement> strokes) {
    var bounds = _placementBoundsForElement(strokes.first);
    for (final stroke in strokes.skip(1)) {
      bounds = bounds.union(_placementBoundsForElement(stroke));
    }
    return ui.Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.size.width,
      bounds.size.height,
    );
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
        if (_smartLayoutPrepareCancelled) return; // 取消后不再领取新块
        final index = nextIndex;
        if (index >= blocks.length) return;
        nextIndex++;
        try {
          results[index] = await recognize(blocks[index]);
          completed++;
          if (!_smartLayoutPrepareCancelled) {
            onProgress?.call(completed, blocks.length);
          }
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
    if (_smartLayoutPrepareCancelled) {
      // 已发出的块请求不强行中断（worker await 返回后到这里收尾），
      // 取消以用户意图优先于"结果不完整"检查。
      throw SmartLayoutCancelledException();
    }
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

  
  List<FreedrawElement> _smartLayoutInkElements() {
    return [
      for (final element in _editorState.scene.activeElements)
        if (element is FreedrawElement &&
            brushTypeFromCustomData(element.customData) !=
                BrushType.highlighter)
          element,
    ];
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

  Bounds _placementBoundsForElement(Element element) {
    final visual = AlignmentUtils.visualBounds(element);
    final minExtent = element is LineElement
        ? math.max(element.strokeWidth, 8.0)
        : 0.0;
    final width = math.max(visual.size.width, minExtent);
    final height = math.max(visual.size.height, minExtent);
    return Bounds.fromLTWH(
      visual.center.x - width / 2,
      visual.center.y - height / 2,
      width,
      height,
    );
  }

  List<Bounds> _scenePlacementBounds({Set<ElementId> excludedIds = const {}}) {
    return [
      for (final element in _editorState.scene.activeElements)
        if (!excludedIds.contains(element.id) &&
            !element.isCanvasPage &&
            !element.isPdfBackground)
          _placementBoundsForElement(element),
    ];
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

  List<TextElement> _smartLayoutGeneratedTextElements() {
    return [
      for (final element in _editorState.scene.activeElements)
        if (element is TextElement &&
            _flowMuseData(element)?['smartLayout'] == true)
          element,
    ];
  }

  Map<String, Object?>? _flowMuseData(Element element) {
    final raw = element.customData?['flowMuse'];
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) return Map<String, Object?>.from(raw);
    return null;
  }

  /// 识别文本块 → 排版文本元素。转写一律横排（TextRenderer.measure 定尺寸，
  /// 不写 writingMode:'vertical'）——竖排信息只保留在聚类/识别阶段（竖排列
  /// 整块识别防每字一块），走查实况：竖排印刷体观感如故障。
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
      // 同 _recognizePendingInkSession：转换产物已定型，跳过默认样式二次套用。
      final inkStyle = _dominantInkStyle(strokes);
      final elements = result.elements
          .map(
            (recognized) =>
                _elementFromRecognizedInk(recognized, inkStyle: inkStyle),
          )
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
        applyDefaultStyle: false,
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
    final occupied = adaptiveLayout ? _scenePlacementBounds() : <Bounds>[];
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
      final page = pageForVisibleRect(visible);
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
    final lastPage = _layout.pages.lastOrNull;
    final bounds = switch (_layout.pageFlow) {
      CanvasPageFlow.topToBottom => Rect.fromLTWH(
        lastPage?.bounds.left ?? 0,
        lastPage == null ? 0 : lastPage.bounds.bottom + CanvasLayout.pageGap,
        size.width,
        size.height,
      ),
      CanvasPageFlow.rightToLeft => Rect.fromLTWH(
        lastPage == null
            ? 0
            : lastPage.bounds.left - CanvasLayout.pageGap - size.width,
        lastPage?.bounds.top ?? 0,
        size.width,
        size.height,
      ),
    };
    final page = CanvasPage(
      id: pageId,
      index: index,
      bounds: bounds,
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

  /// Returns the page with the largest overlap with [visible], or the
  /// nearest page (smallest distance, ties broken by page index) when the
  /// rect does not intersect any page. Returns null only when the layout
  /// has no pages — with pages present this never returns null.
  ///
  /// NOTE: callers that need "is the viewport inside a page" must not rely
  /// on a null return (nearest fallback); test overlap explicitly.
  CanvasPage? pageForVisibleRect(Rect visible) {
    if (_layout.pages.isEmpty) return null;
    CanvasPage? bestOverlap;
    var bestArea = 0.0;
    for (final page in _layout.pages) {
      final intersection = page.bounds.intersect(visible);
      final area = intersection.isEmpty
          ? 0.0
          : intersection.width * intersection.height;
      if (area > bestArea ||
          (area == bestArea &&
              area > 0 &&
              (bestOverlap == null || page.index < bestOverlap.index))) {
        bestArea = area;
        bestOverlap = page;
      }
    }
    if (bestOverlap != null) return bestOverlap;

    CanvasPage? nearest;
    var nearestDistance = double.infinity;
    for (final page in _layout.pages) {
      final dx = visible.right < page.bounds.left
          ? page.bounds.left - visible.right
          : (page.bounds.right < visible.left
                ? visible.left - page.bounds.right
                : 0.0);
      final dy = visible.bottom < page.bounds.top
          ? page.bounds.top - visible.bottom
          : (page.bounds.bottom < visible.top
                ? visible.top - page.bounds.bottom
                : 0.0);
      final distance = dx * dx + dy * dy;
      if (distance < nearestDistance ||
          (distance == nearestDistance &&
              (nearest == null || page.index < nearest.index))) {
        nearestDistance = distance;
        nearest = page;
      }
    }
    return nearest;
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

  Bounds? _findStrictInsertionBounds(
    Rect area,
    double width,
    double height,
    List<Bounds> occupied, {
    Bounds? preferred,
  }) {
    return SmartLayoutPlacement.findInsertionBounds(
      area,
      width,
      height,
      occupied,
      preferred: preferred,
    );
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
    onSceneChanged?.call(_editorState.scene, SceneChangeSource.reset);
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
    final preview = MindmapLayout.treeToElements(
      tree,
      origin: const Point(0, 0),
    );
    final previewBounds = preview
        .map(_placementBoundsForElement)
        .reduce((bounds, element) => bounds.union(element));
    final occupied = _scenePlacementBounds()
        .map((bounds) => _inflateBounds(bounds, 12))
        .toList();
    final placement = _mindmapPlacement(
      previewBounds,
      visible,
      targetSize,
      occupied,
    );
    final dx = placement.bounds.left - previewBounds.left;
    final dy = placement.bounds.top - previewBounds.top;
    final elements = [
      for (final element in preview)
        _mindmapElementOnPage(
          element.copyWith(x: element.x + dx, y: element.y + dy),
          placement.pageId,
        ),
    ];
    final childNodeIds = {
      for (final edge in elements.whereType<ArrowElement>())
        if (MindmapUtils.isMindmapEdge(edge) && edge.endBinding != null)
          edge.endBinding!.elementId,
    };
    final root = elements
        .whereType<RectangleElement>()
        .where((element) => !childNodeIds.contains(element.id.value))
        .firstOrNull;
    final viewportResult = root == null || _rectContainsElement(visible, root)
        ? null
        : UpdateViewportResult(_viewportCenteredOn(root, targetSize));

    _historyManager.push(_editorState.scene);
    applyResult(
      CompoundResult([
        if (placement.pageElement != null)
          AddElementResult(placement.pageElement!),
        for (final element in elements) AddElementResult(element),
        if (root != null) SetSelectionResult({root.id}),
        ?viewportResult,
      ]),
    );
  }

  ({Bounds bounds, String? pageId, Element? pageElement}) _mindmapPlacement(
    Bounds preview,
    Rect visible,
    Size canvasSize,
    List<Bounds> occupied,
  ) {
    if (_layout.isPaged) {
      final areas = _adaptiveTextInsertionAreas(canvasSize);
      for (final area in areas) {
        if (preview.size.width > area.rect.width ||
            preview.size.height > area.rect.height) {
          continue;
        }
        final centered = Bounds.fromLTWH(
          area.rect.center.dx - preview.size.width / 2,
          area.rect.center.dy - preview.size.height / 2,
          preview.size.width,
          preview.size.height,
        );
        if (!occupied.any(centered.intersects)) {
          return (bounds: centered, pageId: area.pageId, pageElement: null);
        }
        final scanned = _findTextInsertionBounds(
          area.rect,
          preview.size.width,
          preview.size.height,
          occupied,
        );
        if (scanned != null) {
          return (bounds: scanned, pageId: area.pageId, pageElement: null);
        }
      }

      final standardContent = Rect.fromLTWH(
        0,
        0,
        CanvasLayout.pageSizeForTemplate(_layout.template).width,
        CanvasLayout.pageSizeForTemplate(_layout.template).height,
      ).deflate(72);
      if (preview.size.width > standardContent.width ||
          preview.size.height > standardContent.height) {
        throw StateError('思维导图超出页面，请减少分支后重试');
      }
      final appended = _appendAdaptiveTextPage();
      return (
        bounds: Bounds.fromLTWH(
          appended.rect.center.dx - preview.size.width / 2,
          appended.rect.center.dy - preview.size.height / 2,
          preview.size.width,
          preview.size.height,
        ),
        pageId: appended.pageId,
        pageElement: appended.element,
      );
    }

    final inner = visible.deflate(math.min(32, visible.shortestSide / 8));
    if (preview.size.width <= inner.width &&
        preview.size.height <= inner.height) {
      final centered = Bounds.fromLTWH(
        inner.center.dx - preview.size.width / 2,
        inner.center.dy - preview.size.height / 2,
        preview.size.width,
        preview.size.height,
      );
      if (!occupied.any(centered.intersects)) {
        return (bounds: centered, pageId: null, pageElement: null);
      }
      final scanned = _findTextInsertionBounds(
        inner,
        preview.size.width,
        preview.size.height,
        occupied,
      );
      if (scanned != null) {
        return (bounds: scanned, pageId: null, pageElement: null);
      }
    }

    final width = math.max(inner.width, preview.size.width + 48);
    final left = visible.left + 24;
    final preferredLeft = left + (width - preview.size.width) / 2;
    final topCandidates = <double>{
      inner.bottom + 24,
      for (final bounds in occupied)
        if (bounds.right >= preferredLeft &&
            bounds.left <= preferredLeft + preview.size.width &&
            bounds.bottom >= inner.bottom + 24)
          bounds.bottom + 24,
    }.toList()..sort();
    for (final top in topCandidates) {
      final candidate = Bounds.fromLTWH(
        preferredLeft,
        top,
        preview.size.width,
        preview.size.height,
      );
      if (!occupied.any(candidate.intersects)) {
        return (bounds: candidate, pageId: null, pageElement: null);
      }
    }

    final height = math.max(inner.height, preview.size.height + 48);
    final area = Rect.fromLTWH(left, inner.bottom + 24, width, height);
    return (
      bounds: Bounds.fromLTWH(
        area.center.dx - preview.size.width / 2,
        area.center.dy - preview.size.height / 2,
        preview.size.width,
        preview.size.height,
      ),
      pageId: null,
      pageElement: null,
    );
  }

  Bounds _inflateBounds(Bounds bounds, double padding) => Bounds.fromLTWH(
    bounds.left - padding,
    bounds.top - padding,
    bounds.size.width + padding * 2,
    bounds.size.height + padding * 2,
  );

  Element _mindmapElementOnPage(Element element, String? pageId) {
    if (pageId == null) return element;
    return element.copyWith(
      customData: _mergeCurrentPageCustomData(element.customData, pageId),
    );
  }

  bool _rectContainsElement(Rect rect, Element element) =>
      rect.contains(Offset(element.x, element.y)) &&
      rect.contains(
        Offset(element.x + element.width, element.y + element.height),
      );

  ViewportState _viewportCenteredOn(Element element, Size canvasSize) {
    final viewport = _editorState.viewport;
    final visibleWidth = canvasSize.width / viewport.zoom;
    final visibleHeight = canvasSize.height / viewport.zoom;
    return ViewportState(
      offset: Offset(
        element.x + element.width / 2 - visibleWidth / 2,
        element.y + element.height / 2 - visibleHeight / 2,
      ),
      zoom: viewport.zoom,
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

    final result = _applyReflow(tree, rootNode);
    if (result == null) {
      onMindmapOperationError?.call('当前页面没有足够空间，请减少分支');
      return;
    }
    _historyManager.push(_editorState.scene);
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

    final result = _applyReflow(tree, rootNode);
    if (result == null) {
      onMindmapOperationError?.call('当前页面没有足够空间，请减少分支');
      return;
    }
    _historyManager.push(_editorState.scene);
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
  ToolResult? _applyReflow(MindmapNode tree, Element rootNode) {
    var origin = Point(rootNode.x, rootNode.y);
    if (_layout.isPaged && rootNode.pageId != null) {
      final page = _layout.pages
          .where((candidate) => candidate.id == rootNode.pageId)
          .firstOrNull;
      if (page == null) return null;
      final content = page.bounds.deflate(72);
      final preview = MindmapLayout.treeToElements(tree, origin: origin);
      final previewBounds = preview
          .map(_placementBoundsForElement)
          .reduce((left, right) => left.union(right));
      final treeNodeIds = _mindmapTreeNodeIds(tree);
      final occupied = [
        for (final element in _editorState.scene.activeElements)
          if (!_belongsToMindmapTree(element, treeNodeIds) &&
              !element.isCanvasPage &&
              !element.isPdfBackground)
            _inflateBounds(_placementBoundsForElement(element), 12),
      ];
      final placement = _findStrictInsertionBounds(
        content,
        previewBounds.size.width,
        previewBounds.size.height,
        occupied,
        preferred: previewBounds,
      );
      if (placement == null) return null;
      origin = Point(
        origin.x + placement.left - previewBounds.left,
        origin.y + placement.top - previewBounds.top,
      );
    }
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
      results.add(AddElementResult(_mindmapElementOnPage(e, rootNode.pageId)));
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

  Set<String> _mindmapTreeNodeIds(MindmapNode tree) {
    final ids = <String>{};
    void visit(MindmapNode node) {
      if (node.sourceId != null) ids.add(node.sourceId!);
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(tree);
    return ids;
  }

  bool _belongsToMindmapTree(Element element, Set<String> nodeIds) {
    if (nodeIds.contains(element.id.value)) return true;
    if (element is TextElement &&
        element.containerId != null &&
        nodeIds.contains(element.containerId)) {
      return true;
    }
    if (element is ArrowElement && MindmapUtils.isMindmapEdge(element)) {
      final startId = element.startBinding?.elementId;
      final endId = element.endBinding?.elementId;
      return startId != null &&
          endId != null &&
          nodeIds.contains(startId) &&
          nodeIds.contains(endId);
    }
    return false;
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
    final (textColor, fontSize) = MindmapLayout.textStyleForNode(
      depth: u.depth,
    );
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
    final childMoved = child.copyWith(x: cu?.x ?? child.x, y: cu?.y ?? child.y);
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

  /// Renders an arbitrary scene-space rectangle to PNG bytes, mirroring the
  /// live canvas (background color, grid, dark-mode grid colors, page-union
  /// clipping, math-text skipping). Pixels only: never embeds markdraw
  /// metadata — the bytes may be sent to external AI services.
  Future<Uint8List?> exportRegionPng(
    Rect sceneBounds, {
    double maxLongestSide = 1568,
    void Function(Canvas canvas, double zoom)? afterPaint,
  }) async {
    if (sceneBounds.width <= 0 || sceneBounds.height <= 0) return null;
    final longest = maxLongestSide <= 0 ? 1568.0 : maxLongestSide;
    final sourceWidth = math.max(1.0, sceneBounds.width);
    final sourceHeight = math.max(1.0, sceneBounds.height);
    final zoom = longest / math.max(sourceWidth, sourceHeight);
    final pixelSize = Size(
      (sourceWidth * zoom).ceilToDouble(),
      (sourceHeight * zoom).ceilToDouble(),
    );
    final viewport = ViewportState(offset: sceneBounds.topLeft, zoom: zoom);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & pixelSize,
      Paint()..color = parseColor(_canvasBackgroundColor),
    );
    StaticCanvasPainter(
      scene: _editorState.scene,
      adapter: _adapter,
      viewport: viewport,
      layout: _layout,
      resolvedImages: _peekResolvedImages(),
      gridSize: _gridSize,
      isDarkBackground:
          parseColor(_canvasBackgroundColor).computeLuminance() < 0.5,
      contentBounds: _contentBounds,
      renderPageShadows: false,
      skipMathText: true,
    ).paint(canvas, pixelSize);
    // Set-of-Mark 等叠加层：画在场景之上、导出像素坐标空间。
    afterPaint?.call(canvas, zoom);

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(
        pixelSize.width.ceil(),
        pixelSize.height.ceil(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  /// Peek-only image resolution for region export: unlike [resolveImages],
  /// never triggers async decodes or per-image repaints; prewarmRegionImages
  /// has already cached everything the region needs.
  Map<String, ui.Image>? _peekResolvedImages() {
    final files = _editorState.scene.files;
    if (files.isEmpty) return null;
    final resolved = <String, ui.Image>{};
    for (final entry in files.entries) {
      final image = _imageCache.peek(entry.key);
      if (image != null) resolved[entry.key] = image;
    }
    return resolved.isEmpty ? null : resolved;
  }

  /// Decodes images intersecting [sceneBounds] into the element cache so a
  /// region render cannot silently miss LRU-evicted files.
  ///
  /// Returns how many intersecting images failed to decode.
  Future<int> prewarmRegionImages(Rect sceneBounds) async {
    var failed = 0;
    final intersecting = <String, ImageFile>{};
    for (final element in _editorState.scene.elements) {
      if (element is! ImageElement || element.isDeleted) continue;
      final bounds = Rect.fromLTWH(
        element.x,
        element.y,
        element.width,
        element.height,
      );
      if (!bounds.overlaps(sceneBounds)) continue;
      final file = _editorState.scene.files[element.fileId];
      if (file != null) intersecting[element.fileId] = file;
    }
    if (intersecting.isEmpty) return 0;
    // 同步占位相交 fileId：预热 await 窗口内一次交互重绘的 getImage 不应
    // 自行启动并发解码（破坏串行预热的内存约束）。占位后 getImage 直接
    // 返回 null，由下方循环串行解码（与已在途的其他预热共享解码 Future）。
    // 只占位相交子集——全量占位会让未解码的非相交 fileId 在中断路径上
    // 永久滞留在途表（只有 _decode 的 finally 移除），那些图片本会话
    // 再也不渲染。
    _imageCache.markDecoding(intersecting.keys);
    // 暂停解码完成回调：每次完成都 notifyListeners（markdraw_controller
    // 构造函数中注册）会触发全画布重绘，resolveImages 对场景所有未缓存
    // fileId 并发启动解码（>50 图场景即解码风暴 + LRU 挤掉刚预热条目）。
    // 对齐 loadScene"预热完统一刷"语义（_prewarmImageCache）。
    // 用可嵌套的暂停计数而非保存/恢复回调字段：两次预热窗口重叠时，
    // 后启动者捕获到的"先前回调"是前者暂停后的值，恢复会互覆，
    // 可能把 controller 的重绘闭包在本会话内永久丢失。
    _imageCache.pauseDecodedCallback();
    try {
      for (final entry in intersecting.entries) {
        if (_disposed) break;
        await _imageCache.decodeAndWait(entry.key, entry.value);
        if (_imageCache.peek(entry.key) == null) failed++;
      }
    } finally {
      _imageCache.resumeDecodedCallback();
      // 异常/中断路径上未取得解码所有权的残留占位必须释放：占位会让
      // getImage 对该 fileId 永远返回 null，本会话图片不再渲染。
      _imageCache.releaseDecodingPlaceholders(intersecting.keys);
    }
    if (!_disposed) notifyListeners();
    return failed;
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
    return serializeSceneWithAliases(
      format: format,
      includeDeleted: includeDeleted,
    ).text;
  }

  /// 单次构建 MarkdrawDocument，同时返回序列化文本与 alias→ElementId
  /// 映射（split pane sidecar 用；避免重复生成 alias，v4 T4 工作项 1）。
  /// settings 实参块与重构前 serializeScene 完全一致（背景/网格/文档名
  /// 不丢），switch 兜底分支同样保持一致。
  ({String text, Map<String, String> aliases}) serializeSceneWithAliases({
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
    final text = switch (format) {
      DocumentFormat.excalidraw => ExcalidrawJsonCodec.serialize(doc),
      _ => DocumentSerializer.serialize(doc),
    };
    return (text: text, aliases: doc.aliases);
  }

  /// 外部导出专用：先净化 collaborationOwner 再序列化。文件保存对话框、
  /// 系统分享等外部出口只能调用本方法（v4 §10.3）；内部持久化与协作
  /// 链路继续调用 [serializeScene]。
  String serializeSceneForExternalExport({
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
    final sanitized = sanitizeDocumentForExternalExport(doc);
    return switch (format) {
      DocumentFormat.excalidraw => ExcalidrawJsonCodec.serialize(sanitized),
      _ => DocumentSerializer.serialize(sanitized),
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
  void loadFromContent(
    String content,
    String filename, {
    bool isExternalImport = false,
  }) {
    final format = DocumentService.detectFormat(filename);
    final parseResult = switch (format) {
      DocumentFormat.markdraw => DocumentParser.parse(content),
      DocumentFormat.excalidraw => ExcalidrawJsonCodec.parse(content),
      _ => throw ArgumentError(
        'Use importLibraryFromContent for library files',
      ),
    };
    var document = parseResult.value;
    if (isExternalImport) {
      // 外部文件的 collaborationOwner 不可信：打开为本地笔记先剥离
      // （v4 §10.4）。内部本地笔记恢复不走本参数。
      document = sanitizeDocumentForExternalExport(document);
    }
    _canvasBackgroundColor = document.settings.background;
    _canvasBackgroundFollowsTheme = document.settings.backgroundFollowsTheme;
    if (_canvasBackgroundFollowsTheme) {
      _canvasBackgroundColor = _themeCanvasBackgroundColor;
    }
    _gridSize = document.settings.grid;
    _documentName = document.settings.name;
    loadScene(SceneDocumentConverter.documentToScene(document));
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
  Future<Uint8List?> exportPng({
    int scale = 2,
    bool selectedOnly = true,
    bool embedMarkdraw = true,
  }) {
    final selectedIds = selectedOnly && _editorState.selectedIds.isNotEmpty
        ? _editorState.selectedIds
        : null;
    return PngExporter.export(
      sanitizeSceneForExternalExport(_editorState.scene),
      _adapter,
      scale: scale,
      backgroundColor: parseColor(_canvasBackgroundColor),
      selectedIds: selectedIds,
      embedMarkdraw: embedMarkdraw,
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
      sanitizeSceneForExternalExport(_editorState.scene),
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
    // 双保险：历史遗留 item 可能带 owner，导出前统一净化（v4 §10.2）。
    final doc = LibraryDocument(
      items: [
        for (final item in _libraryItems)
          item.copyWith(
            elements: [for (final e in item.elements) withoutCreator(e)],
          ),
      ],
    );
    return switch (format) {
      DocumentFormat.excalidrawLibrary => ExcalidrawLibCodec.serialize(doc),
      DocumentFormat.markdrawLibrary => LibraryCodec.serialize(doc),
      _ => ExcalidrawLibCodec.serialize(doc),
    };
  }
}
