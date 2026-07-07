import '../elements/elements.dart';
import '../scene/scene_exports.dart';

/// Stateless utility methods for frame containment logic.
///
/// Frames are named containers. An element belongs to a frame when its
/// [Element.frameId] matches the frame's [ElementId.value].
class FrameUtils {
  FrameUtils._();

  /// Returns all active elements in [scene] whose [frameId] matches
  /// [frameId]'s value.
  static List<Element> findFrameChildren(Scene scene, ElementId frameId) {
    return scene.activeElements
        .where((e) => e.frameId == frameId.value)
        .toList();
  }

  /// Returns true if [element]'s bounding box is fully within [frame]'s bounds.
  static bool isInsideFrame(Element element, FrameElement frame) {
    return element.x >= frame.x &&
        element.y >= frame.y &&
        element.x + element.width <= frame.x + frame.width &&
        element.y + element.height <= frame.y + frame.height;
  }

  /// Returns copies of [elements] with [frameId] set.
  static List<Element> assignToFrame(
    List<Element> elements,
    ElementId frameId,
  ) {
    return elements.map((e) => e.copyWith(frameId: frameId.value)).toList();
  }

  /// Returns copies of [elements] with [frameId] cleared.
  static List<Element> removeFromFrame(List<Element> elements) {
    return elements.map((e) => e.copyWith(clearFrameId: true)).toList();
  }

  /// Finds the smallest [FrameElement] in [scene] whose bounds fully contain
  /// [element], or null if the element is not inside any frame.
  ///
  /// Skips the element itself (a frame is not its own container).
  static FrameElement? findContainingFrame(Scene scene, Element element) {
    FrameElement? best;
    double bestArea = double.infinity;

    for (final e in scene.activeElements) {
      if (e is! FrameElement) continue;
      if (e.id == element.id) continue;
      if (!isInsideFrame(element, e)) continue;

      final area = e.width * e.height;
      if (area < bestArea) {
        best = e;
        bestArea = area;
      }
    }
    return best;
  }

  /// Returns copies of all children of [frameId] with their frameId cleared.
  static List<Element> releaseFrameChildren(Scene scene, ElementId frameId) {
    final children = findFrameChildren(scene, frameId);
    return removeFromFrame(children);
  }
}
