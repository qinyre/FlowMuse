library;

import 'dart:convert';
import 'dart:math' as math;
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

/// Which color picker to open programmatically.
enum ColorPickerTarget { stroke, background, font }

/// Controller for [MarkdrawEditor]. Holds all editor state and logic.
///
/// Can be created internally by the widget or provided externally
/// (like [TextEditingController]).
class MarkdrawController extends ChangeNotifier {
  MarkdrawController({
    MarkdrawEditorConfig config = const MarkdrawEditorConfig(),
  }) : _config = config {
    _editorState = EditorState(
      scene: Scene(),
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
  ElementStyle _defaultStyle = const ElementStyle();
  String _canvasBackgroundColor = '#ffffff';
  int? _gridSize;
  bool _objectsSnapMode = false;
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

  /// Current mouse position in screen coordinates; used for eraser cursor.
  Offset? mousePosition;

  // Pinch-to-zoom state
  double _pinchStartZoom = 1.0;
  Offset _pinchStartOffset = Offset.zero;

  /// Callback invoked when the user toggles the theme. Set by [MarkdrawEditor].
  VoidCallback? onThemeToggle;

  /// Called whenever the scene changes (element add/update/remove).
  void Function(Scene)? onSceneChanged;

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

  /// The snap grid size in pixels, or null if grid is off.
  int? get gridSize => _gridSize;

  /// Whether snap-to-objects alignment guides are enabled.
  bool get objectsSnapMode => _objectsSnapMode;

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
    notifyListeners();
  }

  /// Caches the last known canvas size for link navigation from pointer events.
  set lastCanvasSize(Size? value) {
    _lastCanvasSize = value;
  }

  // --- Lifecycle ---

  /// Releases all resources: image cache, focus nodes, text controller.
  @override
  void dispose() {
    _disposed = true;
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
    _activeTool.reset();
    _activeTool = createTool(type);
    _editorState = _editorState.copyWith(
      activeToolType: type,
      selectedIds: type == ToolType.select ? null : {},
    );
    cancelTextEditing();
    restoreKeyboardFocusWhenStable();
    notifyListeners();
  }

  // --- Undo/Redo ---

  /// Undoes the last scene change.
  void undo() {
    final undone = _historyManager.undo(_editorState.scene);
    if (undone != null) {
      _editorState = _editorState.copyWith(scene: undone);
      onSceneChanged?.call(_editorState.scene);
      notifyListeners();
    }
  }

  /// Redoes the last undone scene change.
  void redo() {
    final redone = _historyManager.redo(_editorState.scene);
    if (redone != null) {
      _editorState = _editorState.copyWith(scene: redone);
      onSceneChanged?.call(_editorState.scene);
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
    return styled;
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

    final styled = isCreationTool ? _applyDefaultStyleToResult(result) : result;

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
      }
    }
    _editorState = newState;

    if (isSceneChangingResult(styled)) {
      onSceneChanged?.call(_editorState.scene);
    }

    notifyListeners();
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
    onSceneChanged?.call(_editorState.scene);
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
    onSceneChanged?.call(_editorState.scene);
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

  // --- Pointer handling ---

  /// Handles pointer down: commits text edits, dispatches to tool, handles
  /// link-to-element mode and link icon clicks.
  void onPointerDown(Offset localPosition) {
    restoreKeyboardFocusWhenStable();
    if (_editingTextElementId != null) {
      commitTextEditing();
    }
    // Frame label editing is committed by the overlay itself on submit/blur.
    // We don't force-commit here since the TextField handles its own focus.

    final point = toScene(localPosition);

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
  void onPointerMove(Offset localPosition, Offset delta) {
    final point = toScene(localPosition);
    applyResult(
      _activeTool.onPointerMove(
        point,
        toolContext,
        screenDelta: Offset(delta.dx, delta.dy),
      ),
    );
    mousePosition = localPosition;
    notifyListeners();
  }

  /// Handles pointer up: dispatches to tool, detects double-click for
  /// text/label editing, and pushes drag history.
  void onPointerUp(Offset localPosition) {
    final point = toScene(localPosition);
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
    _pinchStartZoom = _editorState.viewport.zoom;
    _pinchStartOffset = _editorState.viewport.offset;
  }

  /// Applies pinch-to-zoom and pan during a scale gesture.
  void onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    var newViewport = ViewportState(
      offset: _pinchStartOffset,
      zoom: _pinchStartZoom,
    );
    newViewport = newViewport.zoomAt(
      details.scale,
      details.localFocalPoint,
      minZoom: _config.minZoom,
      maxZoom: _config.maxZoom,
    );
    newViewport = newViewport.pan(details.focalPointDelta);
    applyResult(UpdateViewportResult(newViewport));
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
      final minX = pts.map((p) => p.x).reduce(math.min);
      final minY = pts.map((p) => p.y).reduce(math.min);
      final maxX = pts.map((p) => p.x).reduce(math.max);
      final maxY = pts.map((p) => p.y).reduce(math.max);
      final relPts = pts.map((p) => Point(p.x - minX, p.y - minY)).toList();

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
    if (background != null) {
      _canvasBackgroundColor = background;
    }
    notifyListeners();
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
    if (background != null) {
      _canvasBackgroundColor = background;
    }
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
    if (text == null || text.trim().isEmpty) return;

    final centerScene = _editorState.viewport.screenToScene(
      Offset(canvasSize.width / 2, canvasSize.height / 2),
    );

    final textElem = TextElement(
      id: ElementId.generate(),
      x: centerScene.dx,
      y: centerScene.dy,
      width: 10,
      height: 10,
      text: text.trim(),
    );

    final (w, h) = TextRenderer.measure(textElem);
    final sized = textElem.copyWith(
      width: math.max(w + 4, 20.0),
      height: math.max(h, textElem.fontSize * textElem.lineHeight),
    );

    _historyManager.push(_editorState.scene);
    applyResult(
      CompoundResult([
        AddElementResult(applyDefaultStyleToElement(sized)),
        SetSelectionResult({sized.id}),
      ]),
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
    onSceneChanged?.call(_editorState.scene);
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

  /// Requests programmatic opening of a color picker.
  void requestColorPicker(ColorPickerTarget target) {
    _pendingColorPicker = target;
    notifyListeners();
  }

  /// Clears the pending color picker request.
  void clearPendingColorPicker() {
    _pendingColorPicker = null;
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
    _gridSize = parseResult.value.settings.grid;
    _documentName = parseResult.value.settings.name;
    loadScene(SceneDocumentConverter.documentToScene(parseResult.value));
  }

  /// Applies Excalidraw JSON received from collaboration.
  void applyRemoteContent(String content, {bool closeTransientUi = true}) {
    final parseResult = ExcalidrawJsonCodec.parse(content);
    _canvasBackgroundColor = parseResult.value.settings.background;
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
