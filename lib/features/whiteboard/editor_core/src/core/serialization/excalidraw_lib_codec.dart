import 'dart:convert';

import '../elements/elements.dart';
import '../library/library.dart';
import 'excalidraw_json_codec.dart';
import 'parse_result.dart';

/// Codec for importing/exporting Excalidraw library (.excalidrawlib) files.
///
/// Supports both v1 (legacy array-of-arrays) and v2 (libraryItems array)
/// formats on import. Always serializes to v2 format.
class ExcalidrawLibCodec {
  /// Parses a .excalidrawlib JSON string into a [LibraryDocument].
  ///
  /// Supports both v1 and v2 Excalidraw library formats.
  static ParseResult<LibraryDocument> parse(String json) {
    final warnings = <ParseWarning>[];

    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (e) {
      warnings.add(ParseWarning(line: 0, message: 'Invalid JSON: $e'));
      return ParseResult(value: LibraryDocument(), warnings: warnings);
    }

    if (decoded is! Map<String, dynamic>) {
      warnings.add(
        const ParseWarning(line: 0, message: 'Expected JSON object at root'),
      );
      return ParseResult(value: LibraryDocument(), warnings: warnings);
    }

    // v2 format: { libraryItems: [...] }
    final libraryItems = decoded['libraryItems'];
    if (libraryItems is List) {
      return _parseV2(libraryItems, decoded, warnings);
    }

    // v1 format: { library: [[elements], [elements], ...] }
    final library = decoded['library'];
    if (library is List) {
      return _parseV1(library, warnings);
    }

    warnings.add(
      const ParseWarning(
        line: 0,
        message: 'No "libraryItems" or "library" array found',
      ),
    );
    return ParseResult(value: LibraryDocument(), warnings: warnings);
  }

  static ParseResult<LibraryDocument> _parseV2(
    List<dynamic> libraryItems,
    Map<String, dynamic> root,
    List<ParseWarning> warnings,
  ) {
    final items = <LibraryItem>[];

    for (var i = 0; i < libraryItems.length; i++) {
      final raw = libraryItems[i];
      if (raw is! Map<String, dynamic>) {
        warnings.add(
          ParseWarning(
            line: i,
            message: 'Library item $i is not a JSON object',
          ),
        );
        continue;
      }

      final id = raw['id'] as String? ?? 'item-$i';
      final name = raw['name'] as String? ?? '';
      final status = raw['status'] as String? ?? 'unpublished';
      final created = (raw['created'] as num?)?.toInt() ?? 0;

      final elementsJson = raw['elements'];
      final elements = <Element>[];
      if (elementsJson is List) {
        for (var j = 0; j < elementsJson.length; j++) {
          final elRaw = elementsJson[j];
          if (elRaw is! Map<String, dynamic>) continue;
          final type = elRaw['type'] as String?;
          if (type == null) continue;
          final element = ExcalidrawJsonCodec.parseElement(
            elRaw,
            type,
            j,
            warnings,
          );
          if (element != null) elements.add(element);
        }
      }

      // Parse files from the item or root level
      final itemFiles = <String, ImageFile>{};
      final itemFilesJson = raw['files'];
      if (itemFilesJson != null) {
        itemFiles.addAll(
          ExcalidrawJsonCodec.parseFilesJson(itemFilesJson, warnings),
        );
      }
      // Also check root-level files
      final rootFilesJson = root['files'];
      if (rootFilesJson != null) {
        final rootFiles = ExcalidrawJsonCodec.parseFilesJson(
          rootFilesJson,
          warnings,
        );
        // Only include files referenced by this item's elements
        for (final el in elements) {
          if (el is ImageElement && rootFiles.containsKey(el.fileId)) {
            itemFiles.putIfAbsent(el.fileId, () => rootFiles[el.fileId]!);
          }
        }
      }

      items.add(
        LibraryItem(
          id: id,
          name: name,
          status: status,
          created: created,
          elements: elements,
          files: itemFiles,
        ),
      );
    }

    return ParseResult(
      value: LibraryDocument(items: items),
      warnings: warnings,
    );
  }

  static ParseResult<LibraryDocument> _parseV1(
    List<dynamic> library,
    List<ParseWarning> warnings,
  ) {
    final items = <LibraryItem>[];

    for (var i = 0; i < library.length; i++) {
      final group = library[i];
      if (group is! List) {
        warnings.add(
          ParseWarning(line: i, message: 'Library entry $i is not an array'),
        );
        continue;
      }

      final elements = <Element>[];
      for (var j = 0; j < group.length; j++) {
        final elRaw = group[j];
        if (elRaw is! Map<String, dynamic>) continue;
        final type = elRaw['type'] as String?;
        if (type == null) continue;
        final element = ExcalidrawJsonCodec.parseElement(
          elRaw,
          type,
          j,
          warnings,
        );
        if (element != null) elements.add(element);
      }

      items.add(
        LibraryItem(
          id: 'v1-item-$i',
          name: '',
          status: 'unpublished',
          created: 0,
          elements: elements,
        ),
      );
    }

    return ParseResult(
      value: LibraryDocument(items: items),
      warnings: warnings,
    );
  }

  /// Serializes a [LibraryDocument] to .excalidrawlib JSON (v2 format).
  static String serialize(LibraryDocument doc) {
    final libraryItems = doc.items.map((item) {
      final elementsJson = item.elements
          .map(ExcalidrawJsonCodec.elementToJson)
          .toList();
      final result = <String, dynamic>{
        'id': item.id,
        'status': item.status,
        'name': item.name,
        'created': item.created,
        'elements': elementsJson,
      };
      if (item.files.isNotEmpty) {
        result['files'] = ExcalidrawJsonCodec.filesToJson(item.files);
      }
      return result;
    }).toList();

    final result = {
      'type': 'excalidrawlib',
      'version': 2,
      'source': 'markdraw',
      'libraryItems': libraryItems,
    };
    return jsonEncode(result);
  }
}
