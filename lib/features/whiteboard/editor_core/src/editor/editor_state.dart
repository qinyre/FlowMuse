import '../core/elements/elements.dart';
import '../core/scene/scene_exports.dart';
import '../rendering/viewport_state.dart';
import 'tool_result.dart';
import 'tool_type.dart';

/// An immutable value object representing the editor's state.
///
/// Holds the scene, viewport, selection, active tool type, and clipboard.
/// Use [applyResult] to produce a new state from a [ToolResult].
class EditorState {
  final Scene scene;
  final ViewportState viewport;
  final Set<ElementId> selectedIds;
  final ToolType activeToolType;
  final List<Element> clipboard;
  final bool toolLocked;

  EditorState({
    required this.scene,
    required this.viewport,
    required this.selectedIds,
    required this.activeToolType,
    this.clipboard = const [],
    this.toolLocked = false,
  });

  /// Applies a [ToolResult] to produce a new [EditorState].
  /// Returns this state unchanged if [result] is null.
  EditorState applyResult(ToolResult? result) {
    if (result == null) return this;

    return switch (result) {
      AddElementResult(:final element) => copyWith(
        scene: scene.addElement(element),
      ),
      UpdateElementResult(:final element) => copyWith(
        scene: scene.updateElement(element),
      ),
      RemoveElementResult(:final id) => copyWith(
        scene: scene.removeElement(id),
      ),
      SetSelectionResult(:final selectedIds) => copyWith(
        selectedIds: selectedIds,
      ),
      UpdateViewportResult(:final viewport) => copyWith(viewport: viewport),
      SwitchToolResult(:final toolType) =>
        toolLocked && toolType == ToolType.select
            ? this
            : copyWith(activeToolType: toolType),
      SetClipboardResult(:final elements) => copyWith(clipboard: elements),
      AddFileResult(:final fileId, :final file) => copyWith(
        scene: scene.addFile(fileId, file),
      ),
      RemoveFileResult(:final fileId) => copyWith(
        scene: scene.removeFile(fileId),
      ),
      CompoundResult(:final results) => results.fold(
        this,
        (state, r) => state.applyResult(r),
      ),
    };
  }

  /// Creates a copy with the given fields replaced.
  EditorState copyWith({
    Scene? scene,
    ViewportState? viewport,
    Set<ElementId>? selectedIds,
    ToolType? activeToolType,
    List<Element>? clipboard,
    bool? toolLocked,
  }) {
    return EditorState(
      scene: scene ?? this.scene,
      viewport: viewport ?? this.viewport,
      selectedIds: selectedIds ?? this.selectedIds,
      activeToolType: activeToolType ?? this.activeToolType,
      clipboard: clipboard ?? this.clipboard,
      toolLocked: toolLocked ?? this.toolLocked,
    );
  }
}
