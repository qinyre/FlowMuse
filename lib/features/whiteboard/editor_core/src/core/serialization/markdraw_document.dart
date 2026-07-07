import '../elements/elements.dart';
import 'canvas_settings.dart';
import 'document_section.dart';

/// A complete .markdraw document with settings, sections, and alias mappings.
class MarkdrawDocument {
  final CanvasSettings settings;
  final List<DocumentSection> sections;
  final Map<String, String> aliases;
  final Map<String, ImageFile> files;

  MarkdrawDocument({
    CanvasSettings? settings,
    List<DocumentSection> sections = const [],
    Map<String, String> aliases = const {},
    Map<String, ImageFile> files = const {},
  }) : settings = settings ?? const CanvasSettings(),
       sections = List.unmodifiable(sections),
       aliases = Map.unmodifiable(aliases),
       files = Map.unmodifiable(files);

  /// All elements across all sketch sections, in document order.
  List<Element> get allElements {
    final result = <Element>[];
    for (final section in sections) {
      if (section is SketchSection) {
        result.addAll(section.elements);
      }
    }
    return result;
  }

  /// Looks up the element ID for the given alias.
  String? resolveAlias(String alias) => aliases[alias];

  /// Looks up the alias for the given element ID.
  String? aliasFor(String elementId) {
    for (final entry in aliases.entries) {
      if (entry.value == elementId) return entry.key;
    }
    return null;
  }

  MarkdrawDocument copyWith({
    CanvasSettings? settings,
    List<DocumentSection>? sections,
    Map<String, String>? aliases,
    Map<String, ImageFile>? files,
  }) {
    return MarkdrawDocument(
      settings: settings ?? this.settings,
      sections: sections ?? this.sections,
      aliases: aliases ?? this.aliases,
      files: files ?? this.files,
    );
  }
}
