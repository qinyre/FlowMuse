import 'note_item.dart';

enum LibrarySortField { updatedAt, title }

enum LibrarySortDirection { ascending, descending }

class LibraryQuery {
  const LibraryQuery({
    this.queryText = '',
    this.filter = LibraryFilter.all,
    this.notebookId,
    this.tagIds = const [],
    this.onlyUnnotebooked = false,
    this.onlyUntagged = false,
    this.onlyDeleted = false,
    this.sortField = LibrarySortField.updatedAt,
    this.sortDirection = LibrarySortDirection.descending,
  });

  final String queryText;
  final LibraryFilter filter;
  final String? notebookId;
  final List<String> tagIds;
  final bool onlyUnnotebooked;
  final bool onlyUntagged;
  final bool onlyDeleted;
  final LibrarySortField sortField;
  final LibrarySortDirection sortDirection;
}
