import 'dart:convert';

import '../elements/elements.dart';
import 'document_section.dart';
import 'markdraw_document.dart';
import 'sketch_line_serializer.dart';

/// Serializes a MarkdrawDocument to a .markdraw format string.
class DocumentSerializer {
  /// Serialize a complete document to .markdraw format.
  static String serialize(MarkdrawDocument doc) {
    final buffer = StringBuffer();
    final hasContent = doc.sections.isNotEmpty;

    // Frontmatter
    if (!doc.settings.isDefault) {
      buffer.writeln('---');
      buffer.writeln('markdraw: ${doc.settings.formatVersion}');
      buffer.writeln('background: "${doc.settings.background}"');
      if (doc.settings.grid != null) {
        buffer.writeln('grid: ${doc.settings.grid}');
      }
      buffer.writeln('---');
      if (hasContent) {
        buffer.writeln();
      }
    }

    // Sections
    for (var i = 0; i < doc.sections.length; i++) {
      final section = doc.sections[i];
      switch (section) {
        case ProseSection():
          buffer.write(section.content);
        case SketchSection():
          _serializeSketch(buffer, section, doc);
      }

      // Add separator between sections
      if (i < doc.sections.length - 1) {
        buffer.writeln();
        buffer.writeln();
      }
    }

    // Files block
    if (doc.files.isNotEmpty) {
      if (hasContent) {
        buffer.writeln();
        buffer.writeln();
      }
      _serializeFiles(buffer, doc);
    }

    return buffer.toString();
  }

  static void _serializeSketch(
    StringBuffer buffer,
    SketchSection section,
    MarkdrawDocument doc,
  ) {
    // Build reverse alias map: element ID → alias
    final reverseAliases = <String, String>{};
    for (final entry in doc.aliases.entries) {
      reverseAliases[entry.value] = entry.key;
    }

    // Build element lookup map for arrow binding pixel conversion
    final elementMap = <String, Element>{
      for (final element in section.elements) element.id.value: element,
    };

    // Find bound text elements (those with containerId)
    final boundTextMap = <String, TextElement>{};
    for (final element in section.elements) {
      if (element is TextElement && element.containerId != null) {
        boundTextMap[element.containerId!] = element;
      }
    }

    final serializer = SketchLineSerializer();
    buffer.writeln('```markdraw');
    if (doc.settings.name != null) {
      buffer.writeln('@name "${doc.settings.name}"');
    }

    for (final element in section.elements) {
      // Skip bound text — it's inlined on the parent shape
      if (element is TextElement && element.containerId != null) {
        continue;
      }

      final alias = reverseAliases[element.id.value];
      final boundText = boundTextMap[element.id.value];

      if (boundText != null) {
        // Serialize shape with label inlined
        final line = serializer.serializeWithLabel(
          element,
          boundText,
          alias: alias,
          aliasMap: reverseAliases,
          elementMap: elementMap,
        );
        buffer.writeln(line);
      } else {
        final line = serializer.serialize(
          element,
          alias: alias,
          aliasMap: reverseAliases,
          elementMap: elementMap,
        );
        buffer.writeln(line);
      }
    }

    buffer.write('```');
  }

  static void _serializeFiles(StringBuffer buffer, MarkdrawDocument doc) {
    buffer.writeln('```files');
    for (final entry in doc.files.entries) {
      final b64 = base64Encode(entry.value.bytes);
      buffer.writeln('${entry.key} ${entry.value.mimeType} $b64');
    }
    buffer.write('```');
  }
}
