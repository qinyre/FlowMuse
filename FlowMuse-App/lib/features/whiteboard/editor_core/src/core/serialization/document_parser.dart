import 'dart:convert';
import 'dart:typed_data';

import '../elements/elements.dart';
import 'color_names.dart';
import 'document_section.dart';
import 'frontmatter_parser.dart';
import 'markdraw_document.dart';
import 'parse_result.dart';
import 'sketch_line_parser.dart';

/// Keywords that can have inline labels (e.g., rect "Label" ...).
const _labelableKeywords = {'rect', 'ellipse', 'diamond', 'arrow'};

/// Font category aliases for shorthand font names (bound text).
const _fontAliases = {
  'hand-drawn': 'Excalifont',
  'normal': 'Nunito',
  'code': 'Source Code Pro',
};

/// Resolves a font alias to its actual font name, or returns the value as-is.
String _resolveFontAlias(String value) => _fontAliases[value] ?? value;

/// Named font size aliases (bound text).
const _namedFontSizes = {
  'small': 16.0,
  's': 16.0,
  'medium': 20.0,
  'm': 20.0,
  'large': 28.0,
  'l': 28.0,
  'extra-large': 36.0,
  'xl': 36.0,
};

/// Parses a .markdraw format string into a MarkdrawDocument.
class DocumentParser {
  static ParseResult<MarkdrawDocument> parse(String input) {
    if (input.isEmpty) {
      return ParseResult(value: MarkdrawDocument());
    }

    final allWarnings = <ParseWarning>[];

    // Parse frontmatter
    final fmResult = FrontmatterParser.parse(input);
    allWarnings.addAll(fmResult.warnings);
    final settings = fmResult.value.settings;
    final remaining = fmResult.value.remaining;

    if (remaining.trim().isEmpty) {
      return ParseResult(
        value: MarkdrawDocument(settings: settings),
        warnings: allWarnings,
      );
    }

    // Split into sections (prose vs sketch blocks)
    final sections = <DocumentSection>[];
    final parser = SketchLineParser();
    final lines = remaining.split('\n');

    var i = 0;
    var proseBuffer = StringBuffer();
    final files = <String, ImageFile>{};
    String? sketchName;

    while (i < lines.length) {
      if (lines[i].trim() == '```markdraw' || lines[i].trim() == '```sketch') {
        // Flush prose
        _flushProse(proseBuffer, sections);
        proseBuffer = StringBuffer();

        // Parse sketch block
        i++;
        final sketchLines = <String>[];
        while (i < lines.length && lines[i].trim() != '```') {
          sketchLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // skip closing ```

        // Extract @name directive
        sketchName ??= _extractDirective(sketchLines, 'name');

        final sketchResult = _parseSketchBlock(
          sketchLines,
          parser,
          allWarnings,
        );
        sections.add(SketchSection(sketchResult));
      } else if (lines[i].trim() == '```files') {
        // Flush prose
        _flushProse(proseBuffer, sections);
        proseBuffer = StringBuffer();

        // Parse files block
        i++;
        while (i < lines.length && lines[i].trim() != '```') {
          final fileLine = lines[i].trim();
          if (fileLine.isNotEmpty) {
            final spaceIdx = fileLine.indexOf(' ');
            if (spaceIdx > 0) {
              final fileId = fileLine.substring(0, spaceIdx);
              final rest = fileLine.substring(spaceIdx + 1);
              final spaceIdx2 = rest.indexOf(' ');
              if (spaceIdx2 > 0) {
                final mimeType = rest.substring(0, spaceIdx2);
                final b64Data = rest.substring(spaceIdx2 + 1);
                try {
                  final bytes = base64Decode(b64Data);
                  files[fileId] = ImageFile(
                    mimeType: mimeType,
                    bytes: Uint8List.fromList(bytes),
                  );
                } catch (_) {
                  allWarnings.add(
                    ParseWarning(
                      line: i + 1,
                      message: 'Invalid base64 data for file $fileId',
                    ),
                  );
                }
              }
            }
          }
          i++;
        }
        if (i < lines.length) i++; // skip closing ```
      } else {
        if (proseBuffer.isNotEmpty) proseBuffer.write('\n');
        proseBuffer.write(lines[i]);
        i++;
      }
    }

    _flushProse(proseBuffer, sections);

    // Resolve arrow bindings
    final allElements = <Element>[];
    for (final section in sections) {
      if (section is SketchSection) {
        allElements.addAll(section.elements);
      }
    }

    if (parser.pendingBindings.isNotEmpty) {
      final bindingResult = parser.resolveBindings(allElements);
      allWarnings.addAll(bindingResult.warnings);

      // Replace arrow elements with resolved versions
      final resolvedMap = <String, Element>{};
      for (final resolved in bindingResult.value) {
        resolvedMap[resolved.id.value] = resolved;
      }

      if (resolvedMap.isNotEmpty) {
        final updatedSections = sections.map((section) {
          if (section is SketchSection) {
            final updatedElements = section.elements.map((e) {
              return resolvedMap[e.id.value] ?? e;
            }).toList();
            return SketchSection(updatedElements);
          }
          return section;
        }).toList();
        sections
          ..clear()
          ..addAll(updatedSections);
      }
    }

    final finalSettings = sketchName != null
        ? settings.copyWith(name: sketchName)
        : settings;

    return ParseResult(
      value: MarkdrawDocument(
        settings: finalSettings,
        sections: sections,
        aliases: Map.from(parser.aliases),
        files: files,
      ),
      warnings: allWarnings,
    );
  }

  /// Extracts a `@directive "value"` from sketch block lines.
  static String? _extractDirective(List<String> lines, String directive) {
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('@$directive ')) {
        final rest = trimmed.substring(directive.length + 2).trim();
        if (rest.startsWith('"') && rest.endsWith('"') && rest.length >= 2) {
          return rest.substring(1, rest.length - 1);
        }
        return rest;
      }
    }
    return null;
  }

  static void _flushProse(StringBuffer buffer, List<DocumentSection> sections) {
    final content = buffer.toString();
    if (content.isNotEmpty) {
      sections.add(ProseSection(content));
    }
  }

  static List<Element> _parseSketchBlock(
    List<String> lines,
    SketchLineParser parser,
    List<ParseWarning> warnings,
  ) {
    final elements = <Element>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('@')) {
        continue;
      }

      // Check for inline label on shapes: keyword [props] "Label" ...
      // Only applies to shape types (not text, which naturally has quotes)
      // The quoted string may appear immediately after keyword or after
      // properties like id=... (e.g. rect id=rect1 "Label" at 0,0 100x50).
      final labelMatch = RegExp(
        r'^(\w+)\s+(.*?)(?<!=)"([^"]+)"\s*(.*)',
      ).firstMatch(line);

      if (labelMatch != null &&
          _labelableKeywords.contains(labelMatch.group(1)!.toLowerCase())) {
        final keyword = labelMatch.group(1)!;
        final before = labelMatch.group(
          2,
        )!; // props before the label (may be empty)
        final label = labelMatch.group(3)!;
        final after = labelMatch.group(4)!; // props after the label

        // Parse the shape without the label
        final shapeLine = '$keyword $before$after';
        final result = parser.parseLine(shapeLine, i + 1);
        warnings.addAll(result.warnings);

        if (result.value != null) {
          elements.add(result.value!);

          // Extract text-* properties from the original line
          final textFontSize =
              _namedFontSizes[_parseNamedString(line, 'text-size')] ??
              _namedFontSizes[_parseNamedString(line, 'font-size')] ??
              _parseNamedDouble(line, 'text-size') ??
              20.0;
          final textFontFamily = _resolveFontAlias(
            _parseNamedString(line, 'text-font') ?? 'Excalifont',
          );
          final textAlignStr = _parseNamedString(line, 'text-align');
          final textAlign = switch (textAlignStr) {
            'left' => TextAlign.left,
            'right' => TextAlign.right,
            _ => TextAlign.center,
          };
          final textValignStr = _parseNamedString(line, 'text-valign');
          final textVerticalAlign = switch (textValignStr) {
            'top' => VerticalAlign.top,
            'bottom' => VerticalAlign.bottom,
            _ => VerticalAlign.middle,
          };
          final textColorStr = _parseNamedString(line, 'text-color');
          final textColor = textColorStr != null
              ? normalizeColor(textColorStr)
              : '#000000';

          // Create bound text element
          final textElement = TextElement(
            id: ElementId.generate(),
            x: result.value!.x,
            y: result.value!.y,
            width: result.value!.width,
            height: 20,
            text: label,
            fontSize: textFontSize,
            fontFamily: textFontFamily,
            textAlign: textAlign,
            verticalAlign: textVerticalAlign,
            strokeColor: textColor,
            containerId: result.value!.id.value,
            seed: result.value!.seed + 1,
          );
          elements.add(textElement);
        }
      } else {
        final result = parser.parseLine(line, i + 1);
        warnings.addAll(result.warnings);
        if (result.value != null) {
          elements.add(result.value!);
        }
      }
    }

    return elements;
  }

  /// Extracts a named string property (e.g., "text-font=Nunito") from a line.
  /// Supports quoted values: text-font="Lilita One".
  static String? _parseNamedString(String line, String name) {
    // Try quoted value first: name="value with spaces"
    final quoted = RegExp('(?:^|\\s)$name="([^"]*)"').firstMatch(line);
    if (quoted != null) return quoted.group(1);
    // Fall back to unquoted: name=value
    final match = RegExp('(?:^|\\s)$name=(\\S+)').firstMatch(line);
    return match?.group(1);
  }

  /// Extracts a named double property (e.g., "text-size=24") from a line.
  static double? _parseNamedDouble(String line, String name) {
    final str = _parseNamedString(line, name);
    if (str == null) return null;
    return double.tryParse(str);
  }
}
