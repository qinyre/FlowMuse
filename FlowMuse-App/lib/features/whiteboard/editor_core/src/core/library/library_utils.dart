import '../../editor/editor.dart';
import '../elements/elements.dart';
import '../math/math.dart';
import 'library_item.dart';

/// Stateless utility methods for creating and instantiating library items.
///
/// Follows the GroupUtils/BindingUtils/FrameUtils pattern.
class LibraryUtils {
  LibraryUtils._();

  /// Creates a [LibraryItem] from a list of elements.
  ///
  /// Normalizes positions so elements are relative to their union bounds
  /// origin (0,0). Includes bound text elements and referenced image files.
  static LibraryItem createFromElements({
    required List<Element> elements,
    required String name,
    List<Element> allSceneElements = const [],
    Map<String, ImageFile> sceneFiles = const {},
  }) {
    if (elements.isEmpty) {
      return LibraryItem(
        id: ElementId.generate().value,
        name: name,
        created: DateTime.now().millisecondsSinceEpoch,
      );
    }

    // Collect bound text elements not already in the list
    final elementIds = elements.map((e) => e.id.value).toSet();
    final withBoundText = <Element>[...elements];
    for (final e in elements) {
      for (final sceneEl in allSceneElements) {
        if (sceneEl is TextElement &&
            sceneEl.containerId == e.id.value &&
            !elementIds.contains(sceneEl.id.value)) {
          withBoundText.add(sceneEl);
          elementIds.add(sceneEl.id.value);
        }
      }
    }

    // Compute union bounds
    final minX = withBoundText.map((e) => e.x).reduce((a, b) => a < b ? a : b);
    final minY = withBoundText.map((e) => e.y).reduce((a, b) => a < b ? a : b);

    // Normalize positions to origin
    final normalized = withBoundText
        .map((e) => e.copyWith(x: e.x - minX, y: e.y - minY))
        .toList();

    // Collect referenced image files
    final files = <String, ImageFile>{};
    for (final e in normalized) {
      if (e is ImageElement && sceneFiles.containsKey(e.fileId)) {
        files[e.fileId] = sceneFiles[e.fileId]!;
      }
    }

    return LibraryItem(
      id: ElementId.generate().value,
      name: name,
      created: DateTime.now().millisecondsSinceEpoch,
      elements: normalized,
      files: files,
    );
  }

  /// Instantiates a [LibraryItem] onto the canvas at the given [position].
  ///
  /// Generates fresh IDs, remaps groupIds/frameIds/boundElements/bindings.
  /// Returns a [CompoundResult] with AddElementResults, AddFileResults,
  /// and a SetSelectionResult.
  static ToolResult instantiate({
    required LibraryItem item,
    required Point position,
  }) {
    if (item.elements.isEmpty) {
      return CompoundResult([SetSelectionResult({})]);
    }

    final results = <ToolResult>[];
    final newIds = <ElementId>{};
    final idMap = <String, ElementId>{};
    final groupIdMap = <String, String>{};

    // Build groupId remap
    for (final e in item.elements) {
      for (final gid in e.groupIds) {
        groupIdMap.putIfAbsent(gid, () => ElementId.generate().value);
      }
    }

    // Generate new IDs for all elements
    for (final e in item.elements) {
      idMap[e.id.value] = ElementId.generate();
    }

    // Compute item bounds for centering
    final maxX = item.elements
        .map((e) => e.x + e.width)
        .reduce((a, b) => a > b ? a : b);
    final maxY = item.elements
        .map((e) => e.y + e.height)
        .reduce((a, b) => a > b ? a : b);
    final offsetX = position.x - maxX / 2;
    final offsetY = position.y - maxY / 2;

    // Create remapped elements
    for (final e in item.elements) {
      final newId = idMap[e.id.value]!;

      // Only add non-bound-text elements to selection
      if (e is! TextElement || e.containerId == null) {
        newIds.add(newId);
      }

      final remappedGroupIds = e.groupIds
          .map((gid) => groupIdMap[gid]!)
          .toList();

      // Remap frameId
      String? remappedFrameId = e.frameId;
      if (e.frameId != null && idMap.containsKey(e.frameId)) {
        remappedFrameId = idMap[e.frameId]!.value;
      }

      // Remap boundElements
      final remappedBoundElements = e.boundElements.map((be) {
        final newBeId = idMap[be.id];
        return BoundElement(id: newBeId?.value ?? be.id, type: be.type);
      }).toList();

      var newElement = e.copyWith(
        id: newId,
        x: e.x + offsetX,
        y: e.y + offsetY,
        groupIds: remappedGroupIds,
        frameId: remappedFrameId,
        boundElements: remappedBoundElements,
      );

      // Remap text containerId
      if (newElement is TextElement && newElement.containerId != null) {
        final newParentId = idMap[newElement.containerId];
        if (newParentId != null) {
          newElement = newElement.copyWithText(containerId: newParentId.value);
        }
      }

      // Remap arrow bindings
      if (newElement is ArrowElement) {
        PointBinding? newStart = newElement.startBinding;
        PointBinding? newEnd = newElement.endBinding;
        if (newStart != null && idMap.containsKey(newStart.elementId)) {
          newStart = PointBinding(
            elementId: idMap[newStart.elementId]!.value,
            fixedPoint: newStart.fixedPoint,
          );
        }
        if (newEnd != null && idMap.containsKey(newEnd.elementId)) {
          newEnd = PointBinding(
            elementId: idMap[newEnd.elementId]!.value,
            fixedPoint: newEnd.fixedPoint,
          );
        }
        if (newStart != newElement.startBinding ||
            newEnd != newElement.endBinding) {
          newElement = newElement.copyWithArrow(
            startBinding: newStart,
            clearStartBinding: newStart == null,
            endBinding: newEnd,
            clearEndBinding: newEnd == null,
          );
        }
      }

      results.add(AddElementResult(newElement));
    }

    // Add file results
    for (final entry in item.files.entries) {
      results.add(AddFileResult(fileId: entry.key, file: entry.value));
    }

    results.add(SetSelectionResult(newIds));
    return CompoundResult(results);
  }
}
