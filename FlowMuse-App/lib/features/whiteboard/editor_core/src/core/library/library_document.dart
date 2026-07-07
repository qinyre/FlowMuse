import 'library_item.dart';

/// A collection of reusable library items.
///
/// Immutable — use [addItem] and [removeItem] to create modified copies.
class LibraryDocument {
  final List<LibraryItem> items;

  LibraryDocument({this.items = const []});

  LibraryDocument copyWith({List<LibraryItem>? items}) {
    return LibraryDocument(items: items ?? this.items);
  }

  /// Returns a new document with [item] appended.
  LibraryDocument addItem(LibraryItem item) {
    return LibraryDocument(items: [...items, item]);
  }

  /// Returns a new document with the item matching [id] removed.
  LibraryDocument removeItem(String id) {
    return LibraryDocument(
      items: items.where((item) => item.id != id).toList(),
    );
  }

  @override
  String toString() => 'LibraryDocument(${items.length} items)';
}
