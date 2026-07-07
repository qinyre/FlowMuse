import '../core/elements/elements.dart';
import '../core/scene/scene.dart';
import 'text_renderer.dart';

/// Validates and corrects text element bounds to match rendered text size.
///
/// When text elements are loaded from files or modified via the property panel,
/// their stored width/height may be smaller than the actual rendered text.
/// This makes the text unclickable because hit testing uses stored bounds.
class TextBoundsValidator {
  /// Returns a new [Scene] with text element bounds expanded to fit their
  /// rendered text.
  ///
  /// - Skips bound text (`containerId != null`) — their size is controlled
  ///   by the parent shape.
  /// - For `autoResize == true`: expands both width and height if too small.
  /// - For `autoResize == false`: keeps width fixed, expands height if too small.
  /// - Returns the same scene if no changes are needed.
  static Scene validateScene(Scene scene) {
    var changed = false;
    var result = scene;

    for (final element in scene.elements) {
      if (element is! TextElement) continue;
      if (element.containerId != null) continue;
      if (element.text.isEmpty) continue;
      if (element.isDeleted) continue;

      final validated = validateElement(element);
      if (!identical(validated, element)) {
        result = result.updateElement(validated);
        changed = true;
      }
    }

    return changed ? result : scene;
  }

  /// Returns a corrected copy of [element] if its bounds are too small,
  /// or the same instance if no change is needed.
  static TextElement validateElement(TextElement element) {
    if (element.text.isEmpty) return element;

    if (element.autoResize) {
      final (measuredW, measuredH) = TextRenderer.measure(element);
      final needsWidth = measuredW > element.width;
      final needsHeight = measuredH > element.height;

      if (!needsWidth && !needsHeight) return element;

      return element.copyWith(
        width: needsWidth ? measuredW.ceilToDouble() : null,
        height: needsHeight ? measuredH.ceilToDouble() : null,
      );
    } else {
      // Fixed width — only expand height
      final (_, measuredH) = TextRenderer.measure(
        element,
        maxWidth: element.width,
      );
      if (measuredH <= element.height) return element;

      return element.copyWith(height: measuredH.ceilToDouble());
    }
  }
}
