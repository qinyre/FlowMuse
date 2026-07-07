import '../elements/elements.dart';

/// A section of a .markdraw document — either prose markdown or a sketch block.
sealed class DocumentSection {
  const DocumentSection();
}

/// A prose (markdown) section of the document.
class ProseSection extends DocumentSection {
  final String content;

  const ProseSection(this.content);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProseSection && content == other.content;

  @override
  int get hashCode => content.hashCode;

  @override
  String toString() => 'ProseSection(${content.length} chars)';
}

/// A sketch block section containing drawing elements.
class SketchSection extends DocumentSection {
  final List<Element> elements;

  SketchSection(List<Element> elements)
    : elements = List.unmodifiable(elements);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SketchSection) return false;
    if (elements.length != other.elements.length) return false;
    for (var i = 0; i < elements.length; i++) {
      if (elements[i] != other.elements[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(elements);

  @override
  String toString() => 'SketchSection(${elements.length} elements)';
}
