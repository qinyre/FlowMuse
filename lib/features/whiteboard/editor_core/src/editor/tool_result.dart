import '../core/elements/elements.dart';
import '../core/math/math.dart';
import '../core/scene/scene_exports.dart';
import '../rendering/interactive/interaction_mode.dart';
import '../rendering/interactive/snap_line.dart';
import '../rendering/viewport_state.dart';
import 'tool_type.dart';

/// A mutation description produced by a tool. Tools return these instead of
/// directly modifying state, enabling undo/redo and decoupling from state
/// management.
sealed class ToolResult {}

/// Add a new element to the scene.
class AddElementResult extends ToolResult {
  final Element element;
  AddElementResult(this.element);
}

/// Update an existing element in the scene.
class UpdateElementResult extends ToolResult {
  final Element element;
  UpdateElementResult(this.element);
}

/// Remove an element from the scene by ID.
class RemoveElementResult extends ToolResult {
  final ElementId id;
  RemoveElementResult(this.id);
}

/// Set the current selection to the given element IDs.
class SetSelectionResult extends ToolResult {
  final Set<ElementId> selectedIds;
  SetSelectionResult(this.selectedIds);
}

/// Update the viewport (pan/zoom).
class UpdateViewportResult extends ToolResult {
  final ViewportState viewport;
  UpdateViewportResult(this.viewport);
}

/// Apply multiple results in order.
class CompoundResult extends ToolResult {
  final List<ToolResult> results;
  CompoundResult(this.results);
}

/// Switch to a different tool.
class SwitchToolResult extends ToolResult {
  final ToolType toolType;
  SwitchToolResult(this.toolType);
}

/// Set the clipboard contents for copy/paste.
class SetClipboardResult extends ToolResult {
  final List<Element> elements;
  SetClipboardResult(this.elements);
}

/// Add a file to the scene's file store.
class AddFileResult extends ToolResult {
  final String fileId;
  final ImageFile file;
  AddFileResult({required this.fileId, required this.file});
}

/// Remove a file from the scene's file store.
class RemoveFileResult extends ToolResult {
  final String fileId;
  RemoveFileResult(this.fileId);
}

/// A read-only snapshot of the editor state, provided to tools for
/// decision-making.
class ToolContext {
  final Scene scene;
  final ViewportState viewport;
  final Set<ElementId> selectedIds;
  final List<Element> clipboard;
  final InteractionMode interactionMode;
  final bool isEditingLinear;
  final int? gridSize;
  final bool objectsSnapMode;

  ToolContext({
    required this.scene,
    required this.viewport,
    required Set<ElementId> selectedIds,
    this.clipboard = const [],
    this.interactionMode = InteractionMode.pointer,
    this.isEditingLinear = false,
    this.gridSize,
    this.objectsSnapMode = false,
  }) : selectedIds = Set.unmodifiable(selectedIds);
}

/// Transient UI overlay data produced by tools during interaction (e.g.,
/// shape preview, line points, marquee rectangle).
class ToolOverlay {
  final Bounds? creationBounds;
  final List<Point>? creationPoints;
  final Bounds? marqueeRect;
  final Bounds? bindTargetBounds;

  /// Rotation angle of the binding target element, so the indicator can be
  /// drawn rotated to match.
  final double bindTargetAngle;

  /// True when the line tool detects proximity to the start point,
  /// indicating the line will close into a polygon on finalization.
  final bool creationClosed;

  /// Element IDs that the eraser tool will delete on pointer-up.
  /// Non-null during an eraser drag to allow the UI to dim these elements.
  final Set<ElementId>? eraserElementIds;

  /// Scene-space center of the snap-to-close indicator circle, shown when
  /// dragging a line endpoint near its opposite endpoint.
  final Point? closeIndicatorCenter;

  /// Snap-to-object guide lines to render during move/resize.
  final List<SnapLine> snapLines;

  const ToolOverlay({
    this.creationBounds,
    this.creationPoints,
    this.marqueeRect,
    this.bindTargetBounds,
    this.bindTargetAngle = 0.0,
    this.creationClosed = false,
    this.eraserElementIds,
    this.closeIndicatorCenter,
    this.snapLines = const [],
  });
}

/// Returns true if [result] modifies the scene (adds, updates, or removes
/// elements). Used to decide whether to push to the undo history.
bool isSceneChangingResult(ToolResult? result) {
  if (result == null) return false;
  return switch (result) {
    AddElementResult() => true,
    UpdateElementResult() => true,
    RemoveElementResult() => true,
    AddFileResult() => true,
    RemoveFileResult() => true,
    CompoundResult(:final results) => results.any(isSceneChangingResult),
    SetSelectionResult() => false,
    UpdateViewportResult() => false,
    SwitchToolResult() => false,
    SetClipboardResult() => false,
  };
}
