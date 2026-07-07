import '../elements/elements.dart';
import '../library/library.dart';
import 'document_parser.dart';
import 'document_section.dart';
import 'document_serializer.dart';
import 'markdraw_document.dart';
import 'parse_result.dart';

/// Codec for the .markdrawlib library format.
///
/// Items are separated by `---` dividers with metadata headers.
/// Element data reuses the existing .markdraw sketch block format.
class LibraryCodec {
  /// Parses a .markdrawlib string into a [LibraryDocument].
  static ParseResult<LibraryDocument> parse(String content) {
    final warnings = <ParseWarning>[];

    if (content.trim().isEmpty) {
      return ParseResult(value: LibraryDocument(), warnings: warnings);
    }

    final items = <LibraryItem>[];
    final blocks = _splitItems(content);

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final header = _parseHeader(block.header);
      final id = header['library-item'] ?? 'item-$i';
      final name = _unquote(header['name'] ?? '');
      final status = header['status'] ?? 'unpublished';
      final created = int.tryParse(header['created'] ?? '0') ?? 0;

      // Parse the sketch content as a markdraw document
      final elements = <Element>[];
      final files = <String, ImageFile>{};

      if (block.body.trim().isNotEmpty) {
        final docResult = DocumentParser.parse(block.body);
        warnings.addAll(docResult.warnings);
        elements.addAll(docResult.value.allElements);
        files.addAll(docResult.value.files);
      }

      items.add(
        LibraryItem(
          id: id,
          name: name,
          status: status,
          created: created,
          elements: elements,
          files: files,
        ),
      );
    }

    return ParseResult(
      value: LibraryDocument(items: items),
      warnings: warnings,
    );
  }

  /// Serializes a [LibraryDocument] to .markdrawlib format.
  static String serialize(LibraryDocument doc) {
    final buffer = StringBuffer();

    for (var i = 0; i < doc.items.length; i++) {
      final item = doc.items[i];

      // Item header
      buffer.writeln('---');
      buffer.writeln('library-item: ${item.id}');
      buffer.writeln('name: "${item.name}"');
      buffer.writeln('status: ${item.status}');
      buffer.writeln('created: ${item.created}');
      buffer.writeln('---');
      buffer.writeln();

      // Serialize elements as a markdraw document
      final mdDoc = MarkdrawDocument(
        sections: [SketchSection(item.elements)],
        files: item.files,
      );
      buffer.write(DocumentSerializer.serialize(mdDoc));

      if (i < doc.items.length - 1) {
        buffer.writeln();
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Splits raw content into item blocks by `---` dividers.
  static List<_ItemBlock> _splitItems(String content) {
    final blocks = <_ItemBlock>[];
    final lines = content.split('\n');
    var i = 0;

    while (i < lines.length) {
      // Look for --- divider starting a header
      if (lines[i].trim() == '---') {
        i++;
        // Read header lines until next ---
        final headerLines = <String>[];
        while (i < lines.length && lines[i].trim() != '---') {
          headerLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // skip closing ---

        // Check if this looks like a library-item header
        final headerText = headerLines.join('\n');
        if (headerText.contains('library-item:')) {
          // Read body until next --- divider (or EOF)
          final bodyLines = <String>[];
          while (i < lines.length) {
            if (lines[i].trim() == '---') {
              // Peek ahead to check if this is a new library-item header
              var j = i + 1;
              while (j < lines.length && lines[j].trim() != '---') {
                if (lines[j].contains('library-item:')) {
                  break;
                }
                j++;
              }
              if (j < lines.length && lines[j].contains('library-item:')) {
                // This --- starts a new item
                break;
              }
              // Check if the --- itself is followed by library-item
              if (i + 1 < lines.length &&
                  lines[i + 1].contains('library-item:')) {
                break;
              }
            }
            bodyLines.add(lines[i]);
            i++;
          }
          blocks.add(
            _ItemBlock(header: headerText, body: bodyLines.join('\n').trim()),
          );
        }
      } else {
        i++;
      }
    }

    return blocks;
  }

  static Map<String, String> _parseHeader(String header) {
    final result = <String, String>{};
    for (final line in header.split('\n')) {
      final colonIdx = line.indexOf(':');
      if (colonIdx > 0) {
        final key = line.substring(0, colonIdx).trim();
        final value = line.substring(colonIdx + 1).trim();
        result[key] = value;
      }
    }
    return result;
  }

  static String _unquote(String s) {
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }
}

class _ItemBlock {
  final String header;
  final String body;
  _ItemBlock({required this.header, required this.body});
}
