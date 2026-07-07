import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/groups/groups.dart';
import '../../core/math/math.dart';
import '../bindings/bindings.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// Tool for erasing elements by clicking or dragging across them.
///
/// Click erases the single topmost element under the pointer.
/// Drag accumulates all elements the pointer passes over and erases them
/// on pointer-up. Locked elements are skipped. Erasing any group member
/// erases the entire outermost group. Cascading delete removes bound text,
/// releases frame children, cleans arrow bindings, and removes orphaned
/// image files.
class EraserTool implements Tool {
  bool _isDragging = false;
  final Set<ElementId> _hitIds = {};

  @override
  ToolType get type => ToolType.eraser;

  @override
  ToolResult? onPointerDown(Point point, ToolContext context) {
    _isDragging = true;
    _hitIds.clear();
    _hitTestAndExpand(point, context);
    return null;
  }

  @override
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
  }) {
    if (!_isDragging) return null;
    _hitTestAndExpand(point, context);
    return null;
  }

  @override
  ToolResult? onPointerUp(Point point, ToolContext context) {
    if (!_isDragging) return null;
    _hitTestAndExpand(point, context);
    final idsToDelete = Set<ElementId>.from(_hitIds);
    _isDragging = false;
    _hitIds.clear();
    if (idsToDelete.isEmpty) return null;
    return _buildDeleteResults(idsToDelete, context);
  }

  @override
  ToolResult? onKeyEvent(
    String key, {
    bool shift = false,
    bool ctrl = false,
    ToolContext? context,
  }) {
    if (key == 'Escape') {
      reset();
      return null;
    }
    return null;
  }

  @override
  ToolOverlay? get overlay {
    if (!_isDragging || _hitIds.isEmpty) return null;
    return ToolOverlay(eraserElementIds: Set.unmodifiable(_hitIds));
  }

  @override
  void reset() {
    _isDragging = false;
    _hitIds.clear();
  }

  /// Hit-test at [point], skip locked elements, expand groups.
  void _hitTestAndExpand(Point point, ToolContext context) {
    final hit = context.scene.getElementAtPoint(point);
    if (hit == null || hit.locked) return;

    // Expand to outermost group
    final groupId = GroupUtils.outermostGroupId(hit);
    if (groupId != null) {
      final members = GroupUtils.findGroupMembers(context.scene, groupId);
      for (final m in members) {
        if (!m.locked) _hitIds.add(m.id);
      }
    } else {
      _hitIds.add(hit.id);
    }
  }

  /// Build cascading delete results matching SelectTool's Delete behavior.
  CompoundResult _buildDeleteResults(
    Set<ElementId> idsToDelete,
    ToolContext context,
  ) {
    // Resolve elements
    final deletable = <Element>[];
    for (final id in idsToDelete) {
      final elem = context.scene.getElementById(id);
      if (elem != null) deletable.add(elem);
    }

    final results = <ToolResult>[
      for (final e in deletable) RemoveElementResult(e.id),
      SetSelectionResult({}),
    ];
    final deletedIds = deletable.map((e) => e.id).toSet();

    // Cascade: delete bound text children, and clean parent boundElements
    for (final elem in deletable) {
      // If this is a container/arrow, delete its bound text
      final boundText = context.scene.findBoundText(elem.id);
      if (boundText != null && !deletedIds.contains(boundText.id)) {
        results.add(RemoveElementResult(boundText.id));
        deletedIds.add(boundText.id);
      }

      // If this is bound text, update parent's boundElements list
      if (elem is TextElement && elem.containerId != null) {
        final parentId = ElementId(elem.containerId!);
        if (!deletedIds.contains(parentId)) {
          final parent = context.scene.getElementById(parentId);
          if (parent != null) {
            final newBound = parent.boundElements
                .where((b) => b.id != elem.id.value)
                .toList();
            results.add(
              UpdateElementResult(parent.copyWith(boundElements: newBound)),
            );
          }
        }
      }
    }

    // Release children of deleted frames
    for (final elem in deletable) {
      if (elem is FrameElement) {
        final released = FrameUtils.releaseFrameChildren(
          context.scene,
          elem.id,
        );
        for (final child in released) {
          if (!deletedIds.contains(child.id)) {
            results.add(UpdateElementResult(child));
          }
        }
      }
    }

    // Clean up orphaned image files
    for (final elem in deletable) {
      if (elem is ImageElement) {
        final fileId = elem.fileId;
        final stillReferenced = context.scene.activeElements.any(
          (e) =>
              e is ImageElement &&
              e.fileId == fileId &&
              !deletedIds.contains(e.id),
        );
        if (!stillReferenced && context.scene.files.containsKey(fileId)) {
          results.add(RemoveFileResult(fileId));
        }
      }
    }

    // Clear bindings on arrows that were bound to deleted elements
    final seen = <ElementId>{};
    for (final elem in deletable) {
      final arrows = BindingUtils.findBoundArrows(context.scene, elem.id);
      for (final arrow in arrows) {
        if (deletedIds.contains(arrow.id)) continue;
        if (seen.contains(arrow.id)) continue;
        seen.add(arrow.id);
        var updated = arrow;
        if (arrow.startBinding != null &&
            deletedIds.contains(ElementId(arrow.startBinding!.elementId))) {
          updated = updated.copyWithArrow(clearStartBinding: true);
        }
        if (arrow.endBinding != null &&
            deletedIds.contains(ElementId(arrow.endBinding!.elementId))) {
          updated = updated.copyWithArrow(clearEndBinding: true);
        }
        if (!identical(updated, arrow)) {
          results.add(UpdateElementResult(updated));
        }
      }
    }

    return CompoundResult(results);
  }
}
