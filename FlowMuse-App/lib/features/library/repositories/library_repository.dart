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
    return notes.where((item) => item.notebookId == null).length;
  }

  int get untaggedCount {
    return notes.where((item) => item.tagIds.isEmpty).length;
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
    String? notebookId,
    List<String> tagIds = const [],
  });

  Future<void> ensureNote(String noteId);

  Future<void> renameNote(String noteId, String title);

  Future<void> touchNote(String noteId);

  Future<LibraryNotebook> createNotebook();

  Future<LibraryTag> createTag();
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
    String? notebookId,
    List<String> tagIds = const [],
  }) async {
    final now = DateTime.now();
    final note = NoteItem(
      id: 'note-${_uuid.v4()}',
      title: _defaultNoteTitle,
      updatedAt: now,
      kind: LibraryFilter.notes,
      coverColor: _noteColors[now.millisecondsSinceEpoch % _noteColors.length],
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
      (item) => NoteItem(
        id: item.id,
        title: trimmed,
        updatedAt: DateTime.now(),
        kind: item.kind,
        coverColor: item.coverColor,
        notebookId: item.notebookId,
        tagIds: item.tagIds,
        subtitle: item.subtitle,
      ),
    );
  }

  @override
  Future<void> touchNote(String noteId) async {
    await _updateNote(
      noteId,
      (item) => NoteItem(
        id: item.id,
        title: item.title,
        updatedAt: DateTime.now(),
        kind: item.kind,
        coverColor: item.coverColor,
        notebookId: item.notebookId,
        tagIds: item.tagIds,
        subtitle: item.subtitle,
      ),
    );
  }

  @override
  Future<LibraryNotebook> createNotebook() async {
    final index = await loadIndex();
    final nextIndex = index.notebooks.length + 1;
    final notebook = LibraryNotebook(
      id: 'notebook-${_uuid.v4()}',
      name: '新建笔记本 $nextIndex',
      coverColor: _notebookColors[(nextIndex - 1) % _notebookColors.length],
    );
    await _saveIndex(index.copyWith(notebooks: [...index.notebooks, notebook]));
    return notebook;
  }

  @override
  Future<LibraryTag> createTag() async {
    final index = await loadIndex();
    final nextIndex = index.tags.length + 1;
    final tag = LibraryTag(
      id: 'tag-${_uuid.v4()}',
      name: '新建标签 $nextIndex',
      coverColor: _tagColors[(nextIndex - 1) % _tagColors.length],
    );
    await _saveIndex(index.copyWith(tags: [...index.tags, tag]));
    return tag;
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
    String? notebookId,
    List<String> tagIds = const [],
  }) async {
    final note = await _repository.createNote(
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

  Future<void> createNotebook() async {
    await _repository.createNotebook();
    await refresh();
  }

  Future<void> createTag() async {
    await _repository.createTag();
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
    'notebookId': item.notebookId,
    'tagIds': item.tagIds,
    'subtitle': item.subtitle,
  };
}

NoteItem _noteFromJson(Map<String, Object?> json) {
  return NoteItem(
    id: json['id']! as String,
    title: json['title']! as String,
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    kind: LibraryFilter.values.byName(json['kind']! as String),
    coverColor: Color(json['coverColor']! as int),
    notebookId: json['notebookId'] as String?,
    tagIds: (json['tagIds'] as List? ?? const []).whereType<String>().toList(),
    subtitle: json['subtitle'] as String?,
  );
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
