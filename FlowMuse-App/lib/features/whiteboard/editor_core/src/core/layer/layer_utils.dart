import '../elements/elements.dart';
import '../math/fractional_index.dart';
import '../scene/scene.dart';

/// Stateless utilities for layer ordering operations.
///
/// All methods return updated elements. The caller wraps them in
/// `UpdateElementResult` instances.
class LayerUtils {
  LayerUtils._();

  /// Assign fractional indices to any elements that have a null index.
  ///
  /// Returns updated copies only for elements that had null indices.
  static List<Element> ensureIndices(Scene scene) {
    final active = scene.activeElements;
    // Collect existing indices in order
    final withIndex = active.where((e) => e.index != null).toList()
      ..sort((a, b) => a.index!.compareTo(b.index!));

    final withoutIndex = active.where((e) => e.index == null).toList();
    if (withoutIndex.isEmpty) return [];

    // Generate keys after the last existing index
    final lastIndex = withIndex.isNotEmpty ? withIndex.last.index : null;
    final keys = FractionalIndex.generateNKeys(
      withoutIndex.length,
      after: lastIndex,
    );

    final results = <Element>[];
    for (var i = 0; i < withoutIndex.length; i++) {
      results.add(withoutIndex[i].copyWith(index: keys[i]));
    }
    return results;
  }

  /// Move selected elements above all others.
  static List<Element> bringToFront(Scene scene, Set<ElementId> ids) {
    if (ids.isEmpty) return [];
    final (ordered, indexUpdates) = _ensuredOrderedActive(scene);
    final selected = <Element>[];
    final others = <Element>[];
    for (final e in ordered) {
      if (ids.contains(e.id)) {
        selected.add(e);
      } else {
        others.add(e);
      }
    }
    if (selected.isEmpty || others.isEmpty) return indexUpdates;

    // Already at front?
    final topIndex = others.last.index;
    if (selected.first.index != null &&
        topIndex != null &&
        selected.first.index!.compareTo(topIndex) > 0 &&
        selected.length == 1) {
      return indexUpdates;
    }

    final keys = FractionalIndex.generateNKeys(
      selected.length,
      after: topIndex,
    );
    final results = <Element>[...indexUpdates];
    final indexUpdateIds = indexUpdates.map((e) => e.id).toSet();
    for (var i = 0; i < selected.length; i++) {
      final updated = selected[i].copyWith(index: keys[i]);
      if (indexUpdateIds.contains(updated.id)) {
        // Replace the index-assignment entry with the final position
        results.removeWhere((e) => e.id == updated.id);
      }
      results.add(updated);
    }
    return results;
  }

  /// Move selected elements below all others.
  static List<Element> sendToBack(Scene scene, Set<ElementId> ids) {
    if (ids.isEmpty) return [];
    final (ordered, indexUpdates) = _ensuredOrderedActive(scene);
    final selected = <Element>[];
    final others = <Element>[];
    for (final e in ordered) {
      if (ids.contains(e.id)) {
        selected.add(e);
      } else {
        others.add(e);
      }
    }
    if (selected.isEmpty || others.isEmpty) return indexUpdates;

    final bottomIndex = others.first.index;
    final keys = FractionalIndex.generateNKeys(
      selected.length,
      before: bottomIndex,
    );
    final results = <Element>[...indexUpdates];
    final indexUpdateIds = indexUpdates.map((e) => e.id).toSet();
    for (var i = 0; i < selected.length; i++) {
      final updated = selected[i].copyWith(index: keys[i]);
      if (indexUpdateIds.contains(updated.id)) {
        results.removeWhere((e) => e.id == updated.id);
      }
      results.add(updated);
    }
    return results;
  }

  /// Move selected elements one position forward (up) in the stack.
  static List<Element> bringForward(Scene scene, Set<ElementId> ids) {
    if (ids.isEmpty) return [];
    final (ordered, indexUpdates) = _ensuredOrderedActive(scene);

    // Find the first non-selected element that is above any selected element
    // and swap positions.
    final results = <Element>[...indexUpdates];
    final indexUpdateIds = indexUpdates.map((e) => e.id).toSet();
    for (var i = ordered.length - 1; i >= 0; i--) {
      if (!ids.contains(ordered[i].id)) continue;

      // Find the next non-selected element above
      var j = i + 1;
      while (j < ordered.length && ids.contains(ordered[j].id)) {
        j++;
      }
      if (j >= ordered.length) continue; // already at top

      // Swap indices between ordered[i] and ordered[j]
      final above = ordered[j];
      final current = ordered[i];
      final aboveIdx = above.index!;
      final currentIdx = current.index!;
      final updatedCurrent = current.copyWith(index: aboveIdx);
      final updatedAbove = above.copyWith(index: currentIdx);

      // Replace any index-assignment entries for these elements
      if (indexUpdateIds.contains(current.id)) {
        results.removeWhere((e) => e.id == current.id);
      }
      if (indexUpdateIds.contains(above.id)) {
        results.removeWhere((e) => e.id == above.id);
      }
      results.add(updatedCurrent);
      results.add(updatedAbove);

      // Update the ordered list so subsequent swaps see the new state
      ordered[i] = updatedAbove;
      ordered[j] = updatedCurrent;
      break;
    }
    return results;
  }

  /// Move selected elements one position backward (down) in the stack.
  static List<Element> sendBackward(Scene scene, Set<ElementId> ids) {
    if (ids.isEmpty) return [];
    final (ordered, indexUpdates) = _ensuredOrderedActive(scene);

    final results = <Element>[...indexUpdates];
    final indexUpdateIds = indexUpdates.map((e) => e.id).toSet();
    for (var i = 0; i < ordered.length; i++) {
      if (!ids.contains(ordered[i].id)) continue;

      // Find the next non-selected element below
      var j = i - 1;
      while (j >= 0 && ids.contains(ordered[j].id)) {
        j--;
      }
      if (j < 0) continue; // already at bottom

      final below = ordered[j];
      final current = ordered[i];
      final belowIdx = below.index!;
      final currentIdx = current.index!;
      final updatedCurrent = current.copyWith(index: belowIdx);
      final updatedBelow = below.copyWith(index: currentIdx);

      if (indexUpdateIds.contains(current.id)) {
        results.removeWhere((e) => e.id == current.id);
      }
      if (indexUpdateIds.contains(below.id)) {
        results.removeWhere((e) => e.id == below.id);
      }
      results.add(updatedCurrent);
      results.add(updatedBelow);

      ordered[i] = updatedBelow;
      ordered[j] = updatedCurrent;
      break;
    }
    return results;
  }

  /// Get active elements ordered by fractional index, ensuring all have indices.
  ///
  /// Returns a tuple of (ordered elements, index-assignment updates).
  /// The second list contains elements that had null indices and were assigned
  /// new ones — the caller must include these in its result.
  static (List<Element>, List<Element>) _ensuredOrderedActive(Scene scene) {
    final active = scene.activeElements;
    final withIndex = active.where((e) => e.index != null).toList()
      ..sort((a, b) => a.index!.compareTo(b.index!));
    final withoutIndex = active.where((e) => e.index == null).toList();

    if (withoutIndex.isEmpty) return (withIndex, []);

    final lastIndex = withIndex.isNotEmpty ? withIndex.last.index : null;
    final keys = FractionalIndex.generateNKeys(
      withoutIndex.length,
      after: lastIndex,
    );

    final indexUpdates = <Element>[];
    final indexed = <Element>[];
    for (var i = 0; i < withoutIndex.length; i++) {
      final updated = withoutIndex[i].copyWith(index: keys[i]);
      indexUpdates.add(updated);
      indexed.add(updated);
    }

    final all = [...withIndex, ...indexed];
    all.sort((a, b) => a.index!.compareTo(b.index!));
    return (all, indexUpdates);
  }
}
