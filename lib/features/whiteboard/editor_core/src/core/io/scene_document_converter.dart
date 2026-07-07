import '../../editor/bindings/binding_utils.dart';
import '../elements/elements.dart';
import '../math/fractional_index.dart';
import '../scene/scene_exports.dart';
import '../serialization/serialization.dart';

/// Bridges [Scene] and [MarkdrawDocument] for file I/O integration.
class SceneDocumentConverter {
  SceneDocumentConverter._();

  /// Converts a [Scene] to a [MarkdrawDocument] containing its active elements.
  ///
  /// Auto-generates human-friendly aliases (`rect1`, `arrow1`, etc.) for
  /// elements that don't already have one, so the serialized output is
  /// readable rather than full of UUIDs.
  ///
  /// Optionally pass [settings] to include canvas-level settings such as
  /// the background color.
  static MarkdrawDocument sceneToDocument(
    Scene scene, {
    CanvasSettings? settings,
  }) {
    final elements = scene.orderedElements.where((e) => !e.isDeleted).toList();
    final aliases = _generateAliases(elements);

    return MarkdrawDocument(
      sections: [SketchSection(elements)],
      files: scene.files,
      aliases: aliases,
      settings: settings,
    );
  }

  /// Generates `{keyword}{N}` aliases for every element.
  ///
  /// Counter is per-keyword, starting at 1: rect1, rect2, ellipse1, arrow1…
  static Map<String, String> _generateAliases(List<Element> elements) {
    final counters = <String, int>{};
    final aliases = <String, String>{};

    for (final element in elements) {
      final keyword = _elementKeyword(element);
      final count = (counters[keyword] ?? 0) + 1;
      counters[keyword] = count;
      aliases['$keyword$count'] = element.id.value;
    }

    return aliases;
  }

  /// Maps an Element subclass to its .markdraw keyword.
  static String _elementKeyword(Element element) {
    return switch (element) {
      ArrowElement() => 'arrow',
      LineElement() => 'line',
      FrameElement() => 'frame',
      ImageElement() => 'image',
      RectangleElement() => 'rect',
      EllipseElement() => 'ellipse',
      DiamondElement() => 'diamond',
      TextElement() => 'text',
      FreedrawElement() => 'freedraw',
      _ => element.type,
    };
  }

  /// Converts a [MarkdrawDocument] to a [Scene] containing all its elements.
  ///
  /// Bound arrows are updated so their endpoints match the current positions
  /// of their binding targets — the parser stores placeholder points that
  /// must be resolved once all elements are present.
  static Scene documentToScene(MarkdrawDocument doc) {
    var scene = Scene();
    final allElements = doc.allElements;
    final keys = FractionalIndex.generateNKeys(allElements.length);
    for (var i = 0; i < allElements.length; i++) {
      scene = scene.addElement(allElements[i].copyWith(index: keys[i]));
    }
    for (final entry in doc.files.entries) {
      scene = scene.addFile(entry.key, entry.value);
    }

    // Resolve bound arrow endpoints now that all targets are in the scene.
    for (final element in scene.activeElements) {
      if (element is ArrowElement &&
          (element.startBinding != null || element.endBinding != null)) {
        final updated = BindingUtils.updateBoundArrowEndpoints(element, scene);
        if (!identical(updated, element)) {
          scene = scene.updateElement(updated);
        }
      }
    }

    return scene;
  }
}
