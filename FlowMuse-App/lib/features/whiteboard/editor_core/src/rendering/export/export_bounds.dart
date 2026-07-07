import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../../core/scene/scene_exports.dart';

/// Computes bounding rect for export from full scene or selected subset.
class ExportBounds {
  /// Computes the export bounding box for the given [scene].
  ///
  /// If [selectedIds] is provided and non-empty, only those elements (plus
  /// their bound text children) are included. If null, all active elements
  /// are included.
  ///
  /// Returns null if no elements qualify (empty scene or empty selection).
  /// Adds [padding] on all sides.
  static Bounds? compute(
    Scene scene, {
    Set<ElementId>? selectedIds,
    double padding = 20.0,
  }) {
    final elements = _collectElements(scene, selectedIds);
    if (elements.isEmpty) return null;

    Bounds? result;
    for (final e in elements) {
      final b = Bounds.fromLTWH(e.x, e.y, e.width, e.height);
      result = result == null ? b : result.union(b);
    }

    if (result == null) return null;

    return Bounds.fromLTWH(
      result.left - padding,
      result.top - padding,
      result.size.width + padding * 2,
      result.size.height + padding * 2,
    );
  }

  static List<Element> _collectElements(
    Scene scene,
    Set<ElementId>? selectedIds,
  ) {
    if (selectedIds != null) {
      if (selectedIds.isEmpty) return const [];

      final selected = <Element>[];
      final selectedIdValues = selectedIds.map((id) => id.value).toSet();

      for (final e in scene.elements) {
        if (e.isDeleted) continue;
        if (selectedIdValues.contains(e.id.value)) {
          selected.add(e);
        }
      }

      // Also include bound text whose parent is in the selection
      for (final e in scene.elements) {
        if (e.isDeleted) continue;
        if (e is TextElement &&
            e.containerId != null &&
            selectedIdValues.contains(e.containerId)) {
          // Avoid duplicates if bound text was already in selection
          if (!selectedIdValues.contains(e.id.value)) {
            selected.add(e);
          }
        }
      }

      // Include frame children when frame is in selection
      final addedIds = <String>{};
      for (final e in scene.elements) {
        if (e.isDeleted) continue;
        if (e.frameId != null &&
            selectedIdValues.contains(e.frameId) &&
            !selectedIdValues.contains(e.id.value) &&
            !addedIds.contains(e.id.value)) {
          selected.add(e);
          addedIds.add(e.id.value);
        }
      }

      // Include frame when any of its children is in selection
      for (final e in scene.elements) {
        if (e.isDeleted) continue;
        if (e.frameId != null && selectedIdValues.contains(e.id.value)) {
          if (!selectedIdValues.contains(e.frameId) &&
              !addedIds.contains(e.frameId)) {
            final frame = scene.getElementById(ElementId(e.frameId!));
            if (frame != null) {
              selected.add(frame);
              addedIds.add(e.frameId!);
            }
          }
        }
      }

      return selected;
    }

    // Full scene: all active elements
    return scene.activeElements;
  }
}
