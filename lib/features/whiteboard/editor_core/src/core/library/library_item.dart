import '../elements/element.dart';
import '../elements/image_file.dart';

/// A reusable template of elements that can be placed on the canvas.
///
/// Library items store normalized element positions (relative to their
/// union bounds origin at 0,0) so they can be instantiated at any position.
class LibraryItem {
  final String id;
  final String name;
  final String status; // 'published' | 'unpublished'
  final int created; // epoch ms
  final List<Element> elements;
  final Map<String, ImageFile> files;

  LibraryItem({
    required this.id,
    required this.name,
    this.status = 'unpublished',
    this.created = 0,
    this.elements = const [],
    this.files = const {},
  });

  LibraryItem copyWith({
    String? id,
    String? name,
    String? status,
    int? created,
    List<Element>? elements,
    Map<String, ImageFile>? files,
  }) {
    return LibraryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      created: created ?? this.created,
      elements: elements ?? this.elements,
      files: files ?? this.files,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LibraryItem && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'LibraryItem($id, "$name", ${elements.length} elements)';
}
