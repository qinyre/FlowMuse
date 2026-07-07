import '../../core/elements/elements.dart';
import '../../core/scene/scene_exports.dart';
import '../tool_result.dart';

/// Types that can contain bound text.
const _textContainerTypes = {'rectangle', 'ellipse', 'diamond'};

/// Stateless utilities for managing bound text (text inside shapes/arrows).
class BoundTextUtils {
  BoundTextUtils._();

  /// Returns true if [element] is a shape that can contain bound text.
  static bool isTextContainer(Element element) =>
      _textContainerTypes.contains(element.type);

  /// Find the bound text element for [parentId] in [scene].
  static TextElement? findBoundText(Scene scene, ElementId parentId) =>
      scene.findBoundText(parentId);

  /// Build [UpdateElementResult]s to sync bound text positions with their
  /// moved/resized parent elements.
  ///
  /// For each element in [movedElements] that has bound text, returns an
  /// update that positions the text to match the parent's bounds.
  static List<ToolResult> updateBoundTextPositions(
    Scene scene,
    List<Element> movedElements,
  ) {
    final results = <ToolResult>[];
    for (final parent in movedElements) {
      final boundText = scene.findBoundText(parent.id);
      if (boundText == null) continue;
      final updated = boundText.copyWith(
        x: parent.x,
        y: parent.y,
        width: parent.width,
        height: parent.height,
      );
      results.add(UpdateElementResult(updated));
    }
    return results;
  }
}
