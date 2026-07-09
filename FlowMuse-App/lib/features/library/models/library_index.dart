import 'library_collection.dart';
import 'library_query.dart';
import 'note_item.dart';

class LibraryIndex {
  const LibraryIndex({
    this.notes = const [],
    this.notebooks = const [],
    this.tags = const [],
  });

  final List<NoteItem> notes;
  final List<LibraryNotebook> notebooks;
  final List<LibraryTag> tags;

  int get unnotebookedCount {
    return notes
        .where((item) => !item.isDeleted && item.notebookId == null)
        .length;
  }

  int get untaggedCount {
    return notes.where((item) => !item.isDeleted && item.tagIds.isEmpty).length;
  }

  List<NoteItem> get activeNotes {
    return notes.where((item) => !item.isDeleted).toList();
  }

  List<NoteItem> get deletedNotes {
    return notes.where((item) => item.isDeleted).toList();
  }

  List<NoteItem> notesForQuery(LibraryQuery query) {
    final normalizedQuery = query.queryText.trim().toLowerCase();
    final requiredTags = query.tagIds.toSet();
    final result = notes.where((item) {
      if (query.onlyDeleted != item.isDeleted) {
        return false;
      }
      if (query.filter != LibraryFilter.all && item.kind != query.filter) {
        return false;
      }
      if (query.notebookId != null && item.notebookId != query.notebookId) {
        return false;
      }
      if (query.onlyUnnotebooked && item.notebookId != null) {
        return false;
      }
      if (query.onlyUntagged && item.tagIds.isNotEmpty) {
        return false;
      }
      if (requiredTags.isNotEmpty &&
          !requiredTags.every(item.tagIds.contains)) {
        return false;
      }
      if (normalizedQuery.isNotEmpty &&
          !item.title.toLowerCase().contains(normalizedQuery) &&
          !(item.subtitle?.toLowerCase().contains(normalizedQuery) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    result.sort((a, b) {
      final compared = switch (query.sortField) {
        LibrarySortField.updatedAt => a.updatedAt.compareTo(b.updatedAt),
        LibrarySortField.title => a.title.compareTo(b.title),
      };
      return query.sortDirection == LibrarySortDirection.ascending
          ? compared
          : -compared;
    });
    return result;
  }

  int countNotesInNotebook(String notebookId) {
    return notes
        .where((item) => !item.isDeleted && item.notebookId == notebookId)
        .length;
  }

  int countNotesWithTag(String tagId) {
    return notes
        .where((item) => !item.isDeleted && item.tagIds.contains(tagId))
        .length;
  }

  String? notebookNameOf(String? notebookId) {
    if (notebookId == null) {
      return null;
    }
    for (final notebook in notebooks) {
      if (notebook.id == notebookId) {
        return notebook.name;
      }
    }
    return null;
  }

  List<LibraryTag> tagsOfNote(NoteItem note) {
    final ids = note.tagIds.toSet();
    return [
      for (final tag in tags)
        if (ids.contains(tag.id)) tag,
    ];
  }
}
