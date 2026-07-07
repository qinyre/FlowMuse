import '../elements/elements.dart';
import 'document_parser.dart';
import 'document_section.dart';
import 'document_serializer.dart';
import 'markdraw_document.dart';

/// Serializes/deserializes elements to/from .markdraw clipboard text.
///
/// The clipboard format is a sketch block without frontmatter, reusing
/// [DocumentSerializer] and [DocumentParser] internally.
class ClipboardCodec {
  /// Serializes [elements] to a .markdraw sketch block string.
  static String serialize(List<Element> elements) {
    final doc = MarkdrawDocument(sections: [SketchSection(elements)]);
    return DocumentSerializer.serialize(doc);
  }

  /// Parses [text] as a .markdraw sketch block and returns the elements.
  ///
  /// Returns null if the text is not a valid markdraw sketch block.
  static List<Element>? parse(String text) {
    if (!isMarkdrawText(text)) return null;

    final result = DocumentParser.parse(text);
    final elements = result.value.allElements;
    if (elements.isEmpty) return null;
    return elements;
  }

  /// Returns true if [text] looks like it contains markdraw sketch blocks.
  static bool isMarkdrawText(String text) {
    return text.contains('```markdraw') || text.contains('```sketch');
  }
}
