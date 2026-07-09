import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/note_item.dart';

@immutable
class LibraryNotebook {
  const LibraryNotebook({
    required this.id,
    required this.name,
    required this.coverColor,
  });

  final String id;
  final String name;
  final Color coverColor;

  Map<String, Object?> toJson() {
    return {'id': id, 'name': name, 'coverColor': coverColor.toARGB32()};
  }

  factory LibraryNotebook.fromJson(Map<String, Object?> json) {
    return LibraryNotebook(
      id: json['id']! as String,
      name: json['name']! as String,
      coverColor: Color(json['coverColor']! as int),
    );
  }
}

@immutable
class LibraryTag {
  const LibraryTag({
    required this.id,
    required this.name,
    required this.coverColor,
  });

  final String id;
  final String name;
  final Color coverColor;

  Map<String, Object?> toJson() {
    return {'id': id, 'name': name, 'coverColor': coverColor.toARGB32()};
  }

  factory LibraryTag.fromJson(Map<String, Object?> json) {
    return LibraryTag(
      id: json['id']! as String,
      name: json['name']! as String,
      coverColor: Color(json['coverColor']! as int),
    );
  }
}

@immutable
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

  Map<String, Object?> toJson() {
    return {
      'notes': notes.map(_noteToJson).toList(),
      'notebooks': notebooks.map((item) => item.toJson()).toList(),
      'tags': tags.map((item) => item.toJson()).toList(),
    };
  }

  factory LibraryIndex.fromJson(Map<String, Object?> json) {
    return LibraryIndex(
      notes: _decodeList(json['notes'], _noteFromJson),
      notebooks: _decodeList(json['notebooks'], LibraryNotebook.fromJson),
      tags: _decodeList(json['tags'], LibraryTag.fromJson),
    );
  }

  LibraryIndex copyWith({
    List<NoteItem>? notes,
    List<LibraryNotebook>? notebooks,
    List<LibraryTag>? tags,
  }) {
    return LibraryIndex(
      notes: notes ?? this.notes,
      notebooks: notebooks ?? this.notebooks,
      tags: tags ?? this.tags,
    );
  }

  static List<T> _decodeList<T>(
    Object? raw,
    T Function(Map<String, Object?> json) decode,
  ) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((item) => decode(Map<String, Object?>.from(item)))
        .toList();
  }
}

abstract interface class LibraryRepository {
  Future<LibraryIndex> loadIndex();

  Future<NoteItem> createNote({
    NoteType noteType = NoteType.unbounded,
    PageTemplate pageTemplate = PageTemplate.blank,
    String? title,
    String? notebookId,
    List<String> tagIds = const [],
  });

  Future<void> ensureNote(String noteId);

  Future<void> renameNote(String noteId, String title);

  Future<void> touchNote(String noteId);

  Future<LibraryNotebook> createNotebook({String? name, Color? coverColor});

  Future<LibraryTag> createTag({String? name, Color? coverColor});

  Future<void> deleteNotes(List<String> noteIds);

  Future<void> restoreNotes(List<String> noteIds);

  Future<void> deleteNotesForever(List<String> noteIds);

  Future<void> moveNotesToNotebook(List<String> noteIds, String? notebookId);

  Future<void> addTagsToNotes(List<String> noteIds, List<String> tagIds);

  Future<void> removeTagFromNotes(List<String> noteIds, String tagId);

  Future<void> renameNotebook(String notebookId, String name);

  Future<void> deleteNotebook(String notebookId);

  Future<void> renameTag(String tagId, String name);

  Future<void> deleteTag(String tagId);
}

class SharedPreferencesLibraryRepository implements LibraryRepository {
  SharedPreferencesLibraryRepository(
    Future<SharedPreferences> Function() preferences,
  ) : _preferences = preferences;

  static const _key = 'flowmuse.library.index.v2';
  static const _uuid = Uuid();
  static const _defaultNoteTitle = '未命名笔记';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<LibraryIndex> loadIndex() async {
    final preferences = await _preferences();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const LibraryIndex();
    }
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    return LibraryIndex.fromJson(decoded);
  }

  @override
  Future<NoteItem> createNote({
    NoteType noteType = NoteType.unbounded,
    PageTemplate pageTemplate = PageTemplate.blank,
    String? title,
    String? notebookId,
    List<String> tagIds = const [],
  }) async {
    final now = DateTime.now();
    final trimmedTitle = title?.trim();
    final note = NoteItem(
      id: 'note-${_uuid.v4()}',
      title: trimmedTitle == null || trimmedTitle.isEmpty
          ? _defaultNoteTitle
          : trimmedTitle,
      updatedAt: now,
      kind: LibraryFilter.notes,
      coverColor: _noteColors[now.millisecondsSinceEpoch % _noteColors.length],
      noteType: noteType,
      pageTemplate: pageTemplate,
      notebookId: notebookId,
      tagIds: tagIds,
    );
    final index = await loadIndex();
    await _saveIndex(index.copyWith(notes: [note, ...index.notes]));
    return note;
  }

  @override
  Future<void> ensureNote(String noteId) async {
    final index = await loadIndex();
    if (index.notes.any((item) => item.id == noteId)) {
      return;
    }
    final now = DateTime.now();
    final note = NoteItem(
      id: noteId,
      title: _defaultNoteTitle,
      updatedAt: now,
      kind: LibraryFilter.notes,
      coverColor: _noteColors[now.millisecondsSinceEpoch % _noteColors.length],
    );
    await _saveIndex(index.copyWith(notes: [note, ...index.notes]));
  }

  @override
  Future<void> renameNote(String noteId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _updateNote(
      noteId,
      (item) => item.copyWith(
        title: trimmed,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> touchNote(String noteId) async {
    await _updateNote(
      noteId,
      (item) => item.copyWith(
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<LibraryNotebook> createNotebook({
    String? name,
    Color? coverColor,
  }) async {
    final index = await loadIndex();
    final nextIndex = index.notebooks.length + 1;
    final trimmedName = name?.trim();
    final notebook = LibraryNotebook(
      id: 'notebook-${_uuid.v4()}',
      name: trimmedName == null || trimmedName.isEmpty
          ? '新建笔记本 $nextIndex'
          : trimmedName,
      coverColor: coverColor ??
          libraryNotebookColors[
              (nextIndex - 1) % libraryNotebookColors.length],
    );
    await _saveIndex(index.copyWith(notebooks: [...index.notebooks, notebook]));
    return notebook;
  }

  @override
  Future<LibraryTag> createTag({
    String? name,
    Color? coverColor,
  }) async {
    final index = await loadIndex();
    final nextIndex = index.tags.length + 1;
    final trimmedName = name?.trim();
    final tag = LibraryTag(
      id: 'tag-${_uuid.v4()}',
      name: trimmedName == null || trimmedName.isEmpty
          ? '新建标签 $nextIndex'
          : trimmedName,
      coverColor: coverColor ??
          libraryTagColors[(nextIndex - 1) % libraryTagColors.length],
    );
    await _saveIndex(index.copyWith(tags: [...index.tags, tag]));
    return tag;
  }

  @override
  Future<void> deleteNotes(List<String> noteIds) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final now = DateTime.now();
    await _updateNotes(
      (item) => ids.contains(item.id)
          ? item.copyWith(updatedAt: now, deletedAt: now)
          : item,
    );
  }

  @override
  Future<void> restoreNotes(List<String> noteIds) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    await _updateNotes(
      (item) => ids.contains(item.id)
          ? item.copyWith(updatedAt: DateTime.now(), clearDeletedAt: true)
          : item,
    );
  }

  @override
  Future<void> deleteNotesForever(List<String> noteIds) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final index = await loadIndex();
    await _saveIndex(
      index.copyWith(
        notes: [for (final item in index.notes) if (!ids.contains(item.id)) item],
      ),
    );
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
    await _updateNotes(
      (item) => ids.contains(item.id)
          ? item.copyWith(
              notebookId: notebookId,
              clearNotebook: notebookId == null,
              updatedAt: DateTime.now(),
            )
          : item,
    );
  }

  @override
  Future<void> addTagsToNotes(List<String> noteIds, List<String> tagIds) async {
    final ids = noteIds.toSet();
    final tags = tagIds.toSet();
    if (ids.isEmpty || tags.isEmpty) {
      return;
    }
    await _updateNotes(
      (item) => ids.contains(item.id)
          ? item.copyWith(
              tagIds: {...item.tagIds, ...tags}.toList(),
              updatedAt: DateTime.now(),
            )
          : item,
    );
  }

  @override
  Future<void> removeTagFromNotes(List<String> noteIds, String tagId) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    await _updateNotes(
      (item) => ids.contains(item.id)
          ? item.copyWith(
              tagIds: [
                for (final id in item.tagIds)
                  if (id != tagId) id,
              ],
              updatedAt: DateTime.now(),
            )
          : item,
    );
  }

  @override
  Future<void> renameNotebook(String notebookId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final index = await loadIndex();
    await _saveIndex(
      index.copyWith(
        notebooks: [
          for (final notebook in index.notebooks)
            notebook.id == notebookId
                ? LibraryNotebook(
                    id: notebook.id,
                    name: trimmed,
                    coverColor: notebook.coverColor,
                  )
                : notebook,
        ],
      ),
    );
  }

  @override
  Future<void> deleteNotebook(String notebookId) async {
    final index = await loadIndex();
    await _saveIndex(
      index.copyWith(
        notebooks: [
          for (final notebook in index.notebooks)
            if (notebook.id != notebookId) notebook,
        ],
        notes: [
          for (final note in index.notes)
            note.notebookId == notebookId
                ? note.copyWith(clearNotebook: true, updatedAt: DateTime.now())
                : note,
        ],
      ),
    );
  }

  @override
  Future<void> renameTag(String tagId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final index = await loadIndex();
    await _saveIndex(
      index.copyWith(
        tags: [
          for (final tag in index.tags)
            tag.id == tagId
                ? LibraryTag(id: tag.id, name: trimmed, coverColor: tag.coverColor)
                : tag,
        ],
      ),
    );
  }

  @override
  Future<void> deleteTag(String tagId) async {
    final index = await loadIndex();
    await _saveIndex(
      index.copyWith(
        tags: [
          for (final tag in index.tags)
            if (tag.id != tagId) tag,
        ],
        notes: [
          for (final note in index.notes)
            note.tagIds.contains(tagId)
                ? note.copyWith(
                    tagIds: [
                      for (final id in note.tagIds)
                        if (id != tagId) id,
                    ],
                    updatedAt: DateTime.now(),
                  )
                : note,
        ],
      ),
    );
  }

  Future<void> _updateNote(
    String noteId,
    NoteItem Function(NoteItem item) update,
  ) async {
    await ensureNote(noteId);
    final index = await loadIndex();
    await _saveIndex(
      index.copyWith(
        notes: [
          for (final item in index.notes)
            if (item.id == noteId) update(item) else item,
        ],
      ),
    );
  }

  Future<void> _updateNotes(NoteItem Function(NoteItem item) update) async {
    final index = await loadIndex();
    await _saveIndex(
      index.copyWith(notes: [for (final item in index.notes) update(item)]),
    );
  }

  Future<void> _saveIndex(LibraryIndex index) async {
    final preferences = await _preferences();
    await preferences.setString(_key, jsonEncode(index.toJson()));
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
    NoteType noteType = NoteType.unbounded,
    PageTemplate pageTemplate = PageTemplate.blank,
    String? title,
    String? notebookId,
    List<String> tagIds = const [],
  }) async {
    final note = await _repository.createNote(
      noteType: noteType,
      pageTemplate: pageTemplate,
      title: title,
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

  Future<void> touchNote(String noteId) async {
    await _repository.touchNote(noteId);
    await refresh();
  }

  Future<void> createNotebook({String? name, Color? coverColor}) async {
    await _repository.createNotebook(name: name, coverColor: coverColor);
    await refresh();
  }

  Future<void> createTag({String? name, Color? coverColor}) async {
    await _repository.createTag(name: name, coverColor: coverColor);
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

  Future<void> renameNotebook(String notebookId, String name) async {
    await _repository.renameNotebook(notebookId, name);
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
  return SharedPreferencesLibraryRepository(SharedPreferences.getInstance);
});

final libraryIndexProvider =
    AsyncNotifierProvider<LibraryIndexNotifier, LibraryIndex>(
      LibraryIndexNotifier.new,
    );

Map<String, Object?> _noteToJson(NoteItem item) {
  return {
    'id': item.id,
    'title': item.title,
    'updatedAt': item.updatedAt.toIso8601String(),
    'kind': item.kind.name,
    'coverColor': item.coverColor.toARGB32(),
    'noteType': item.noteType.name,
    'pageTemplate': item.pageTemplate.name,
    'notebookId': item.notebookId,
    'tagIds': item.tagIds,
    'subtitle': item.subtitle,
    'deletedAt': item.deletedAt?.toIso8601String(),
  };
}

NoteItem _noteFromJson(Map<String, Object?> json) {
  return NoteItem(
    id: json['id']! as String,
    title: json['title']! as String,
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    kind: LibraryFilter.values.byName(json['kind']! as String),
    coverColor: Color(json['coverColor']! as int),
    noteType: _enumByName(
      NoteType.values,
      json['noteType'],
      NoteType.unbounded,
    ),
    pageTemplate: _enumByName(
      PageTemplate.values,
      json['pageTemplate'],
      PageTemplate.blank,
    ),
    notebookId: json['notebookId'] as String?,
    tagIds: (json['tagIds'] as List? ?? const []).whereType<String>().toList(),
    subtitle: json['subtitle'] as String?,
    deletedAt: json['deletedAt'] is String
        ? DateTime.parse(json['deletedAt']! as String)
        : null,
  );
}

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
