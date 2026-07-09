import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

  Future<void> touchNote(String noteId);

  Future<LibraryNotebook> createNotebook();

  Future<LibraryTag> createTag();

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
    final db = await _openDatabase();
    final noteRows = await db.query('notes', orderBy: 'updated_at DESC');
    final notebookRows = await db.query('notebooks', orderBy: 'sort_order ASC');
    final tagRows = await db.query('tags', orderBy: 'sort_order ASC');
    final noteTagRows = await db.query('note_tags');

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
    return note;
  }

  @override
  Future<void> ensureNote(String noteId) async {
    final db = await _openDatabase();
    final existing = await db.query(
      'notes',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
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
  Future<void> touchNote(String noteId) async {
    await ensureNote(noteId);
    final db = await _openDatabase();
    await db.update(
      'notes',
      {'updated_at': _timestamp(DateTime.now())},
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  @override
  Future<LibraryNotebook> createNotebook() async {
    final db = await _openDatabase();
    final now = DateTime.now();
    final notebookCount = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM notebooks',
    );
    final nextIndex = (notebookCount.first['count']! as int) + 1;
    final notebook = LibraryNotebook(
      id: 'notebook-${_uuid.v4()}',
      name: '新建笔记本 $nextIndex',
      coverColor: _notebookColors[(nextIndex - 1) % _notebookColors.length],
      createdAt: now,
      updatedAt: now,
      sortOrder: nextIndex - 1,
    );
    await db.insert('notebooks', _notebookToRow(notebook));
    return notebook;
  }

  @override
  Future<LibraryTag> createTag() async {
    final db = await _openDatabase();
    final now = DateTime.now();
    final tagCount = await db.rawQuery('SELECT COUNT(*) AS count FROM tags');
    final nextIndex = (tagCount.first['count']! as int) + 1;
    final tag = LibraryTag(
      id: 'tag-${_uuid.v4()}',
      name: '新建标签 $nextIndex',
      coverColor: _tagColors[(nextIndex - 1) % _tagColors.length],
      createdAt: now,
      updatedAt: now,
      sortOrder: nextIndex - 1,
    );
    await db.insert('tags', _tagToRow(tag));
    return tag;
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
    return note;
  }

  Future<void> ensureNote(String noteId) async {
    await _repository.ensureNote(noteId);
    await refresh();
  }

  Future<void> renameNote(String noteId, String title) async {
    await _repository.renameNote(noteId, title);
    await refresh();
  }

  Future<void> renameSubtitle(String noteId, String? subtitle) async {
    await _repository.renameSubtitle(noteId, subtitle);
    await refresh();
  }

  Future<void> touchNote(String noteId) async {
    await _repository.touchNote(noteId);
    await refresh();
  }

  Future<void> createNotebook() async {
    await _repository.createNotebook();
    await refresh();
  }

  Future<void> createTag() async {
    await _repository.createTag();
    await refresh();
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
    state = const AsyncLoading<LibraryIndex>();
    state = await AsyncValue.guard(_repository.loadIndex);
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
    'deleted_at': item.deletedAt == null ? null : _timestamp(item.deletedAt!),
  };
}

NoteItem _noteFromRow(Map<String, Object?> row, List<String> tagIds) {
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
  );
}

Map<String, Object?> _notebookToRow(LibraryNotebook notebook) {
  return {
    'id': notebook.id,
    'name': notebook.name,
    'cover_color': notebook.coverColor.toARGB32(),
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

const _notebookColors = [
  Color(0xFF8DB6C9),
  Color(0xFFD9B48F),
  Color(0xFF8CBDB5),
  Color(0xFF9CA2E6),
];

const _tagColors = [
  Color(0xFF8CBDB5),
  Color(0xFFE9993F),
  Color(0xFF9CA2E6),
  Color(0xFF2E5872),
];
