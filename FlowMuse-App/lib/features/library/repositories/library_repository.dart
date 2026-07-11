import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/storage/local_database.dart';
import '../models/library_collection.dart';
import '../models/library_index.dart';
import '../models/note_item.dart';

export '../models/library_collection.dart';
export '../models/library_index.dart';
export '../models/library_query.dart';

abstract interface class LibraryRepository {
  Future<LibraryIndex> loadIndex();

  Future<NoteItem> createNote({
    LibraryFilter kind = LibraryFilter.notes,
    NoteType noteType = NoteType.unbounded,
    PageTemplate pageTemplate = PageTemplate.blank,
    String? title,
    String? subtitle,
    String? notebookId,
    List<String> tagIds = const [],
  });

  Future<void> ensureNote(String noteId);

  Future<void> renameNote(String noteId, String title);

  Future<void> renameSubtitle(String noteId, String? subtitle);

  Future<void> touchNote(
    String noteId, {
    Uint8List? coverThumbnailBytes,
    bool clearCoverThumbnail = false,
  });

  Future<LibraryNotebook> createNotebook({
    String? name,
    Color? coverColor,
    String? coverImage,
  });

  Future<LibraryTag> createTag({
    String? name,
    Color? coverColor,
    String? coverImage,
  });

  Future<void> deleteNotes(List<String> noteIds);

  Future<void> restoreNotes(List<String> noteIds);

  Future<void> deleteNotesForever(List<String> noteIds);

  Future<void> moveNotesToNotebook(List<String> noteIds, String? notebookId);

  Future<void> addTagsToNotes(List<String> noteIds, List<String> tagIds);

  Future<void> removeTagFromNotes(List<String> noteIds, String tagId);

  Future<void> setNoteTags(String noteId, List<String> tagIds);

  Future<void> renameNotebook(String notebookId, String name);

  Future<void> recolorNotebook(String notebookId, Color color);

  Future<void> deleteNotebook(String notebookId);

  Future<void> renameTag(String tagId, String name);

  Future<void> recolorTag(String tagId, Color color);

  Future<void> deleteTag(String tagId);
}

class SqliteLibraryRepository implements LibraryRepository {
  SqliteLibraryRepository(this._openDatabase);

  static const _uuid = Uuid();
  static const _defaultNoteTitle = '未命名笔记';

  final Future<Database> Function() _openDatabase;

  @override
  Future<LibraryIndex> loadIndex() async {
    debugPrint('[FlowMuseCreateNote] LibraryRepository.loadIndex start');
    final db = await _openDatabase();
    final noteRows = await db.query('notes', orderBy: 'updated_at DESC');
    final notebookRows = await db.query('notebooks', orderBy: 'sort_order ASC');
    final tagRows = await db.query('tags', orderBy: 'sort_order ASC');
    final noteTagRows = await db.query('note_tags');
    debugPrint(
      '[FlowMuseCreateNote] LibraryRepository.loadIndex rows '
      'notes=${noteRows.length} notebooks=${notebookRows.length} '
      'tags=${tagRows.length} noteTags=${noteTagRows.length}',
    );

    final tagsByNoteId = <String, List<String>>{};
    for (final row in noteTagRows) {
      final noteId = row['note_id']! as String;
      final tagId = row['tag_id']! as String;
      tagsByNoteId.putIfAbsent(noteId, () => []).add(tagId);
    }

    return LibraryIndex(
      notes: [
        for (final row in noteRows)
          _noteFromRow(row, tagsByNoteId[row['id'] as String] ?? const []),
      ],
      notebooks: [for (final row in notebookRows) _notebookFromRow(row)],
      tags: [for (final row in tagRows) _tagFromRow(row)],
    );
  }

  @override
  Future<NoteItem> createNote({
    LibraryFilter kind = LibraryFilter.notes,
    NoteType noteType = NoteType.unbounded,
    PageTemplate pageTemplate = PageTemplate.blank,
    String? title,
    String? subtitle,
    String? notebookId,
    List<String> tagIds = const [],
  }) async {
    debugPrint(
      '[FlowMuseCreateNote] LibraryRepository.createNote start '
      'kind=${kind.name} noteType=${noteType.name} '
      'pageTemplate=${pageTemplate.name} title="$title" '
      'notebookId=$notebookId tagIds=${tagIds.join(',')}',
    );
    final now = DateTime.now();
    final trimmedTitle = title?.trim();
    final db = await _openDatabase();
    late final NoteItem note;
    await db.transaction((txn) async {
      final validNotebookId = await _validNotebookId(txn, notebookId);
      final validTagIds = await _validTagIds(txn, tagIds);
      note = NoteItem(
        id: 'note-${_uuid.v4()}',
        title: trimmedTitle == null || trimmedTitle.isEmpty
            ? _defaultNoteTitle
            : trimmedTitle,
        updatedAt: now,
        kind: kind,
        coverColor:
            _noteColors[now.millisecondsSinceEpoch % _noteColors.length],
        noteType: noteType,
        pageTemplate: pageTemplate,
        subtitle: subtitle,
        notebookId: validNotebookId,
        tagIds: validTagIds,
      );
      await txn.insert('notes', _noteToRow(note));
      for (final tagId in validTagIds) {
        await txn.insert('note_tags', {'note_id': note.id, 'tag_id': tagId});
      }
    });
    debugPrint(
      '[FlowMuseCreateNote] LibraryRepository.createNote inserted '
      'noteId=${note.id} title="${note.title}" '
      'noteType=${note.noteType.name} pageTemplate=${note.pageTemplate.name}',
    );
    return note;
  }

  @override
  Future<void> ensureNote(String noteId) async {
    debugPrint(
      '[FlowMuseCreateNote] LibraryRepository.ensureNote start $noteId',
    );
    final db = await _openDatabase();
    final existing = await db.query(
      'notes',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      debugPrint(
        '[FlowMuseCreateNote] LibraryRepository.ensureNote exists $noteId',
      );
      return;
    }
    final now = DateTime.now();
    await db.insert(
      'notes',
      _noteToRow(
        NoteItem(
          id: noteId,
          title: _defaultNoteTitle,
          updatedAt: now,
          kind: LibraryFilter.notes,
          coverColor:
              _noteColors[now.millisecondsSinceEpoch % _noteColors.length],
        ),
      ),
    );
    debugPrint(
      '[FlowMuseCreateNote] LibraryRepository.ensureNote inserted $noteId',
    );
  }

  @override
  Future<void> renameNote(String noteId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await ensureNote(noteId);
    final db = await _openDatabase();
    await db.update(
      'notes',
      {'title': trimmed, 'updated_at': _timestamp(DateTime.now())},
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  @override
  Future<void> renameSubtitle(String noteId, String? subtitle) async {
    await ensureNote(noteId);
    final db = await _openDatabase();
    await db.update(
      'notes',
      {'subtitle': subtitle?.trim(), 'updated_at': _timestamp(DateTime.now())},
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  @override
  Future<void> touchNote(
    String noteId, {
    Uint8List? coverThumbnailBytes,
    bool clearCoverThumbnail = false,
  }) async {
    await ensureNote(noteId);
    final db = await _openDatabase();
    await db.update(
      'notes',
      {
        'updated_at': _timestamp(DateTime.now()),
        if (clearCoverThumbnail) 'cover_thumbnail': null,
        if (!clearCoverThumbnail && coverThumbnailBytes != null)
          'cover_thumbnail': coverThumbnailBytes,
      },
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  @override
  Future<LibraryNotebook> createNotebook({
    String? name,
    Color? coverColor,
    String? coverImage,
  }) async {
    final createdAt = DateTime.now();
    final normalizedName = name?.trim();
    final database = await _openDatabase();
    late final LibraryNotebook createdNotebook;
    await database.transaction((txn) async {
      final nextSortOrder = await _nextSortOrder(txn, 'notebooks');
      final defaultNameIndex = nextSortOrder + 1;
      createdNotebook = LibraryNotebook(
        id: 'notebook-${_uuid.v4()}',
        name: normalizedName == null || normalizedName.isEmpty
            ? '\u65b0\u5efa\u7b14\u8bb0\u672c $defaultNameIndex'
            : normalizedName,
        coverColor:
            coverColor ??
            libraryNotebookColors[nextSortOrder % libraryNotebookColors.length],
        coverImage: coverImage,
        createdAt: createdAt,
        updatedAt: createdAt,
        sortOrder: nextSortOrder,
      );
      await txn.insert('notebooks', _notebookToRow(createdNotebook));
    });
    return createdNotebook;
  }

  @override
  Future<LibraryTag> createTag({
    String? name,
    Color? coverColor,
    String? coverImage,
  }) async {
    final createdAt = DateTime.now();
    final normalizedName = name?.trim();
    final database = await _openDatabase();
    late final LibraryTag createdTag;
    await database.transaction((txn) async {
      final nextSortOrder = await _nextSortOrder(txn, 'tags');
      final defaultNameIndex = nextSortOrder + 1;
      createdTag = LibraryTag(
        id: 'tag-${_uuid.v4()}',
        name: normalizedName == null || normalizedName.isEmpty
            ? '\u65b0\u5efa\u6807\u7b7e $defaultNameIndex'
            : normalizedName,
        coverColor:
            coverColor ??
            libraryTagColors[nextSortOrder % libraryTagColors.length],
        coverImage: coverImage,
        createdAt: createdAt,
        updatedAt: createdAt,
        sortOrder: nextSortOrder,
      );
      await txn.insert('tags', _tagToRow(createdTag));
    });
    return createdTag;
  }

  @override
  Future<void> deleteNotes(List<String> noteIds) async {
    await _updateNotes(noteIds, {
      'updated_at': _timestamp(DateTime.now()),
      'deleted_at': _timestamp(DateTime.now()),
    });
  }

  @override
  Future<void> restoreNotes(List<String> noteIds) async {
    await _updateNotes(noteIds, {
      'updated_at': _timestamp(DateTime.now()),
      'deleted_at': null,
    });
  }

  @override
  Future<void> deleteNotesForever(List<String> noteIds) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final db = await _openDatabase();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete('notes', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  @override
  Future<void> moveNotesToNotebook(
    List<String> noteIds,
    String? notebookId,
  ) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final db = await _openDatabase();
    await db.transaction((txn) async {
      final validNotebookId = await _validNotebookId(txn, notebookId);
      for (final noteId in ids) {
        await txn.update(
          'notes',
          {
            'notebook_id': validNotebookId,
            'updated_at': _timestamp(DateTime.now()),
          },
          where: 'id = ?',
          whereArgs: [noteId],
        );
      }
    });
  }

  @override
  Future<void> addTagsToNotes(List<String> noteIds, List<String> tagIds) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty || tagIds.isEmpty) {
      return;
    }
    final db = await _openDatabase();
    await db.transaction((txn) async {
      final validTagIds = await _validTagIds(txn, tagIds);
      if (validTagIds.isEmpty) {
        return;
      }
      for (final noteId in ids) {
        for (final tagId in validTagIds) {
          await txn.insert('note_tags', {
            'note_id': noteId,
            'tag_id': tagId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await txn.update(
          'notes',
          {'updated_at': _timestamp(DateTime.now())},
          where: 'id = ?',
          whereArgs: [noteId],
        );
      }
    });
  }

  @override
  Future<void> removeTagFromNotes(List<String> noteIds, String tagId) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final db = await _openDatabase();
    await db.transaction((txn) async {
      for (final noteId in ids) {
        await txn.delete(
          'note_tags',
          where: 'note_id = ? AND tag_id = ?',
          whereArgs: [noteId, tagId],
        );
        await txn.update(
          'notes',
          {'updated_at': _timestamp(DateTime.now())},
          where: 'id = ?',
          whereArgs: [noteId],
        );
      }
    });
  }

  @override
  Future<void> setNoteTags(String noteId, List<String> tagIds) async {
    await ensureNote(noteId);
    final db = await _openDatabase();
    await db.transaction((txn) async {
      final validTagIds = await _validTagIds(txn, tagIds);
      await txn.delete('note_tags', where: 'note_id = ?', whereArgs: [noteId]);
      for (final tagId in validTagIds) {
        await txn.insert('note_tags', {'note_id': noteId, 'tag_id': tagId});
      }
      await txn.update(
        'notes',
        {'updated_at': _timestamp(DateTime.now())},
        where: 'id = ?',
        whereArgs: [noteId],
      );
    });
  }

  @override
  Future<void> renameNotebook(String notebookId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final db = await _openDatabase();
    await db.update(
      'notebooks',
      {'name': trimmed, 'updated_at': _timestamp(DateTime.now())},
      where: 'id = ?',
      whereArgs: [notebookId],
    );
  }

  @override
  Future<void> recolorNotebook(String notebookId, Color color) async {
    final db = await _openDatabase();
    await db.update(
      'notebooks',
      {
        'cover_color': color.toARGB32(),
        'updated_at': _timestamp(DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: [notebookId],
    );
  }

  @override
  Future<void> deleteNotebook(String notebookId) async {
    final db = await _openDatabase();
    await db.delete('notebooks', where: 'id = ?', whereArgs: [notebookId]);
  }

  @override
  Future<void> renameTag(String tagId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final db = await _openDatabase();
    await db.update(
      'tags',
      {'name': trimmed, 'updated_at': _timestamp(DateTime.now())},
      where: 'id = ?',
      whereArgs: [tagId],
    );
  }

  @override
  Future<void> recolorTag(String tagId, Color color) async {
    final db = await _openDatabase();
    await db.update(
      'tags',
      {
        'cover_color': color.toARGB32(),
        'updated_at': _timestamp(DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: [tagId],
    );
  }

  @override
  Future<void> deleteTag(String tagId) async {
    final db = await _openDatabase();
    await db.delete('tags', where: 'id = ?', whereArgs: [tagId]);
  }

  Future<void> _updateNotes(
    List<String> noteIds,
    Map<String, Object?> values,
  ) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final db = await _openDatabase();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update('notes', values, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<String?> _validNotebookId(Transaction txn, String? notebookId) async {
    if (notebookId == null) {
      return null;
    }
    final existing = await txn.query(
      'notebooks',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [notebookId],
      limit: 1,
    );
    return existing.isEmpty ? null : notebookId;
  }

  Future<List<String>> _validTagIds(
    Transaction txn,
    List<String> tagIds,
  ) async {
    final unique = tagIds.toSet();
    if (unique.isEmpty) {
      return const [];
    }
    final result = <String>[];
    for (final tagId in unique) {
      final existing = await txn.query(
        'tags',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [tagId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        result.add(tagId);
      }
    }
    return result;
  }

  Future<int> _nextSortOrder(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) AS max_sort_order FROM $table',
    );
    return (rows.first['max_sort_order']! as int) + 1;
  }
}

class LibraryIndexNotifier extends AsyncNotifier<LibraryIndex> {
  late final LibraryRepository _repository;

  @override
  Future<LibraryIndex> build() async {
    _repository = ref.watch(libraryRepositoryProvider);
    return _repository.loadIndex();
  }

  Future<NoteItem> createNote({
    LibraryFilter kind = LibraryFilter.notes,
    NoteType noteType = NoteType.unbounded,
    PageTemplate pageTemplate = PageTemplate.blank,
    String? title,
    String? subtitle,
    String? notebookId,
    List<String> tagIds = const [],
  }) async {
    debugPrint('[FlowMuseCreateNote] LibraryIndexNotifier.createNote start');
    final note = await _repository.createNote(
      kind: kind,
      noteType: noteType,
      pageTemplate: pageTemplate,
      title: title,
      subtitle: subtitle,
      notebookId: notebookId,
      tagIds: tagIds,
    );
    await refresh();
    debugPrint(
      '[FlowMuseCreateNote] LibraryIndexNotifier.createNote refreshed '
      'noteId=${note.id} stateHasError=${state.hasError}',
    );
    return note;
  }

  Future<void> ensureNote(String noteId) async {
    debugPrint(
      '[FlowMuseCreateNote] LibraryIndexNotifier.ensureNote start $noteId',
    );
    await _repository.ensureNote(noteId);
    await refresh();
    debugPrint(
      '[FlowMuseCreateNote] LibraryIndexNotifier.ensureNote refreshed '
      '$noteId stateHasError=${state.hasError}',
    );
  }

  Future<void> renameNote(String noteId, String title) async {
    await _repository.renameNote(noteId, title);
    await refresh();
  }

  Future<void> renameSubtitle(String noteId, String? subtitle) async {
    await _repository.renameSubtitle(noteId, subtitle);
    await refresh();
  }

  Future<void> touchNote(
    String noteId, {
    Uint8List? coverThumbnailBytes,
    bool clearCoverThumbnail = false,
  }) async {
    await _repository.touchNote(
      noteId,
      coverThumbnailBytes: coverThumbnailBytes,
      clearCoverThumbnail: clearCoverThumbnail,
    );
    await refresh();
  }

  Future<LibraryNotebook> createNotebook({
    String? name,
    Color? coverColor,
    String? coverImage,
  }) async {
    final notebook = await _repository.createNotebook(
      name: name,
      coverColor: coverColor,
      coverImage: coverImage,
    );
    await refresh();
    if (state.hasError) {
      throw state.error ?? StateError('Failed to refresh notebooks');
    }
    return notebook;
  }

  Future<LibraryTag> createTag({
    String? name,
    Color? coverColor,
    String? coverImage,
  }) async {
    final tag = await _repository.createTag(
      name: name,
      coverColor: coverColor,
      coverImage: coverImage,
    );
    await refresh();
    if (state.hasError) {
      throw state.error ?? StateError('Failed to refresh tags');
    }
    return tag;
  }

  Future<void> deleteNotes(List<String> noteIds) async {
    await _repository.deleteNotes(noteIds);
    await refresh();
  }

  Future<void> restoreNotes(List<String> noteIds) async {
    await _repository.restoreNotes(noteIds);
    await refresh();
  }

  Future<void> deleteNotesForever(List<String> noteIds) async {
    await _repository.deleteNotesForever(noteIds);
    await refresh();
  }

  Future<void> moveNotesToNotebook(
    List<String> noteIds,
    String? notebookId,
  ) async {
    await _repository.moveNotesToNotebook(noteIds, notebookId);
    await refresh();
  }

  Future<void> addTagsToNotes(List<String> noteIds, List<String> tagIds) async {
    await _repository.addTagsToNotes(noteIds, tagIds);
    await refresh();
  }

  Future<void> removeTagFromNotes(List<String> noteIds, String tagId) async {
    await _repository.removeTagFromNotes(noteIds, tagId);
    await refresh();
  }

  Future<void> setNoteTags(String noteId, List<String> tagIds) async {
    await _repository.setNoteTags(noteId, tagIds);
    await refresh();
  }

  Future<void> renameNotebook(String notebookId, String name) async {
    await _repository.renameNotebook(notebookId, name);
    await refresh();
  }

  Future<void> recolorNotebook(String notebookId, Color color) async {
    await _repository.recolorNotebook(notebookId, color);
    await refresh();
  }

  Future<void> deleteNotebook(String notebookId) async {
    await _repository.deleteNotebook(notebookId);
    await refresh();
  }

  Future<void> renameTag(String tagId, String name) async {
    await _repository.renameTag(tagId, name);
    await refresh();
  }

  Future<void> recolorTag(String tagId, Color color) async {
    await _repository.recolorTag(tagId, color);
    await refresh();
  }

  Future<void> deleteTag(String tagId) async {
    await _repository.deleteTag(tagId);
    await refresh();
  }

  Future<void> refresh() async {
    debugPrint('[FlowMuseCreateNote] LibraryIndexNotifier.refresh start');
    state = const AsyncLoading<LibraryIndex>();
    state = await AsyncValue.guard(_repository.loadIndex);
    debugPrint(
      '[FlowMuseCreateNote] LibraryIndexNotifier.refresh done '
      'hasValue=${state.hasValue} hasError=${state.hasError} '
      'error=${state.error}',
    );
  }
}

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return SqliteLibraryRepository(LocalDatabase.open);
});

final libraryIndexProvider =
    AsyncNotifierProvider<LibraryIndexNotifier, LibraryIndex>(
      LibraryIndexNotifier.new,
    );

Map<String, Object?> _noteToRow(NoteItem item) {
  return {
    'id': item.id,
    'title': item.title,
    'updated_at': _timestamp(item.updatedAt),
    'kind': item.kind.name,
    'cover_color': item.coverColor.toARGB32(),
    'note_type': item.noteType.name,
    'page_template': item.pageTemplate.name,
    'notebook_id': item.notebookId,
    'subtitle': item.subtitle,
    'cover_thumbnail': item.coverThumbnailBytes,
    'deleted_at': item.deletedAt == null ? null : _timestamp(item.deletedAt!),
  };
}

NoteItem _noteFromRow(Map<String, Object?> row, List<String> tagIds) {
  final coverThumbnail = row['cover_thumbnail'];
  return NoteItem(
    id: row['id']! as String,
    title: row['title']! as String,
    updatedAt: _date(row['updated_at']! as int),
    kind: LibraryFilter.values.byName(row['kind']! as String),
    coverColor: Color(row['cover_color']! as int),
    noteType: _enumByName(
      NoteType.values,
      row['note_type'],
      NoteType.unbounded,
    ),
    pageTemplate: _enumByName(
      PageTemplate.values,
      row['page_template'],
      PageTemplate.blank,
    ),
    notebookId: row['notebook_id'] as String?,
    tagIds: tagIds,
    subtitle: row['subtitle'] as String?,
    deletedAt: row['deleted_at'] is int
        ? _date(row['deleted_at']! as int)
        : null,
    coverThumbnailBytes: coverThumbnail is Uint8List ? coverThumbnail : null,
  );
}

Map<String, Object?> _notebookToRow(LibraryNotebook notebook) {
  return {
    'id': notebook.id,
    'name': notebook.name,
    'cover_color': notebook.coverColor.toARGB32(),
    'cover_image': notebook.coverImage,
    'created_at': _timestamp(notebook.createdAt),
    'updated_at': _timestamp(notebook.updatedAt),
    'sort_order': notebook.sortOrder,
  };
}

LibraryNotebook _notebookFromRow(Map<String, Object?> row) {
  return LibraryNotebook(
    id: row['id']! as String,
    name: row['name']! as String,
    coverColor: Color(row['cover_color']! as int),
    coverImage: row['cover_image'] as String?,
    createdAt: _date(row['created_at']! as int),
    updatedAt: _date(row['updated_at']! as int),
    sortOrder: row['sort_order']! as int,
  );
}

Map<String, Object?> _tagToRow(LibraryTag tag) {
  return {
    'id': tag.id,
    'name': tag.name,
    'cover_color': tag.coverColor.toARGB32(),
    'cover_image': tag.coverImage,
    'created_at': _timestamp(tag.createdAt),
    'updated_at': _timestamp(tag.updatedAt),
    'sort_order': tag.sortOrder,
  };
}

LibraryTag _tagFromRow(Map<String, Object?> row) {
  return LibraryTag(
    id: row['id']! as String,
    name: row['name']! as String,
    coverColor: Color(row['cover_color']! as int),
    coverImage: row['cover_image'] as String?,
    createdAt: _date(row['created_at']! as int),
    updatedAt: _date(row['updated_at']! as int),
    sortOrder: row['sort_order']! as int,
  );
}

int _timestamp(DateTime date) => date.millisecondsSinceEpoch;

DateTime _date(int timestamp) => DateTime.fromMillisecondsSinceEpoch(timestamp);

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is String) {
    for (final value in values) {
      if (value.name == raw) {
        return value;
      }
    }
  }
  return fallback;
}

const _noteColors = [
  Color(0xFF8DB6C9),
  Color(0xFFD9B48F),
  Color(0xFF2E5872),
  Color(0xFF8CBDB5),
  Color(0xFFD6D6D0),
  Color(0xFFE9993F),
  Color(0xFF9CA2E6),
];

const libraryNotebookColors = [
  Color(0xFF8DB6C9),
  Color(0xFFD9B48F),
  Color(0xFF8CBDB5),
  Color(0xFF9CA2E6),
];

const libraryTagColors = [
  Color(0xFF8CBDB5),
  Color(0xFFE9993F),
  Color(0xFF9CA2E6),
  Color(0xFF2E5872),
];
