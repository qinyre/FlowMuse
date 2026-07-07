import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/notebook_item.dart';

@immutable
class LibraryFolder {
  const LibraryFolder({
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

  factory LibraryFolder.fromJson(Map<String, Object?> json) {
    return LibraryFolder(
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
    this.notebooks = const [],
    this.folders = const [],
    this.tags = const [],
  });

  final List<NotebookItem> notebooks;
  final List<LibraryFolder> folders;
  final List<LibraryTag> tags;

  int get unfiledCount {
    return notebooks.where((item) => item.folderId == null).length;
  }

  int get untaggedCount {
    return notebooks.where((item) => item.tagIds.isEmpty).length;
  }

  Map<String, Object?> toJson() {
    return {
      'notebooks': notebooks.map(_notebookToJson).toList(),
      'folders': folders.map((item) => item.toJson()).toList(),
      'tags': tags.map((item) => item.toJson()).toList(),
    };
  }

  factory LibraryIndex.fromJson(Map<String, Object?> json) {
    return LibraryIndex(
      notebooks: _decodeList(json['notebooks'], _notebookFromJson),
      folders: _decodeList(json['folders'], LibraryFolder.fromJson),
      tags: _decodeList(json['tags'], LibraryTag.fromJson),
    );
  }

  LibraryIndex copyWith({
    List<NotebookItem>? notebooks,
    List<LibraryFolder>? folders,
    List<LibraryTag>? tags,
  }) {
    return LibraryIndex(
      notebooks: notebooks ?? this.notebooks,
      folders: folders ?? this.folders,
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

  Future<NotebookItem> createNotebook({
    String? folderId,
    List<String> tagIds = const [],
  });

  Future<void> ensureNotebook(String notebookId);

  Future<void> renameNotebook(String notebookId, String title);

  Future<void> touchNotebook(String notebookId);

  Future<LibraryFolder> createFolder();

  Future<LibraryTag> createTag();
}

class SharedPreferencesLibraryRepository implements LibraryRepository {
  SharedPreferencesLibraryRepository(
    Future<SharedPreferences> Function() preferences,
  ) : _preferences = preferences;

  static const _key = 'flowmuse.library.index.v1';
  static const _uuid = Uuid();
  static const _defaultNotebookTitle = '未命名笔记';

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
  Future<NotebookItem> createNotebook({
    String? folderId,
    List<String> tagIds = const [],
  }) async {
    final now = DateTime.now();
    final notebook = NotebookItem(
      id: 'whiteboard-${_uuid.v4()}',
      title: _defaultNotebookTitle,
      updatedAt: now,
      kind: LibraryFilter.notes,
      coverColor:
          _notebookColors[now.millisecondsSinceEpoch % _notebookColors.length],
      folderId: folderId,
      tagIds: tagIds,
    );
    final index = await loadIndex();
    await _saveIndex(index.copyWith(notebooks: [notebook, ...index.notebooks]));
    return notebook;
  }

  @override
  Future<void> ensureNotebook(String notebookId) async {
    final index = await loadIndex();
    if (index.notebooks.any((item) => item.id == notebookId)) {
      return;
    }
    final now = DateTime.now();
    final notebook = NotebookItem(
      id: notebookId,
      title: _defaultNotebookTitle,
      updatedAt: now,
      kind: LibraryFilter.notes,
      coverColor:
          _notebookColors[now.millisecondsSinceEpoch % _notebookColors.length],
    );
    await _saveIndex(index.copyWith(notebooks: [notebook, ...index.notebooks]));
  }

  @override
  Future<void> renameNotebook(String notebookId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _updateNotebook(
      notebookId,
      (item) => NotebookItem(
        id: item.id,
        title: trimmed,
        updatedAt: DateTime.now(),
        kind: item.kind,
        coverColor: item.coverColor,
        folderId: item.folderId,
        tagIds: item.tagIds,
        subtitle: item.subtitle,
      ),
    );
  }

  @override
  Future<void> touchNotebook(String notebookId) async {
    await _updateNotebook(
      notebookId,
      (item) => NotebookItem(
        id: item.id,
        title: item.title,
        updatedAt: DateTime.now(),
        kind: item.kind,
        coverColor: item.coverColor,
        folderId: item.folderId,
        tagIds: item.tagIds,
        subtitle: item.subtitle,
      ),
    );
  }

  @override
  Future<LibraryFolder> createFolder() async {
    final index = await loadIndex();
    final nextIndex = index.folders.length + 1;
    final folder = LibraryFolder(
      id: 'folder-${_uuid.v4()}',
      name: '新建文件夹 $nextIndex',
      coverColor: _folderColors[(nextIndex - 1) % _folderColors.length],
    );
    await _saveIndex(index.copyWith(folders: [...index.folders, folder]));
    return folder;
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

  Future<void> _updateNotebook(
    String notebookId,
    NotebookItem Function(NotebookItem item) update,
  ) async {
    await ensureNotebook(notebookId);
    final index = await loadIndex();
    await _saveIndex(
      index.copyWith(
        notebooks: [
          for (final item in index.notebooks)
            if (item.id == notebookId) update(item) else item,
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

  Future<NotebookItem> createNotebook({
    String? folderId,
    List<String> tagIds = const [],
  }) async {
    final notebook = await _repository.createNotebook(
      folderId: folderId,
      tagIds: tagIds,
    );
    await refresh();
    return notebook;
  }

  Future<void> ensureNotebook(String notebookId) async {
    await _repository.ensureNotebook(notebookId);
    await refresh();
  }

  Future<void> renameNotebook(String notebookId, String title) async {
    await _repository.renameNotebook(notebookId, title);
    await refresh();
  }

  Future<void> touchNotebook(String notebookId) async {
    await _repository.touchNotebook(notebookId);
    await refresh();
  }

  Future<void> createFolder() async {
    await _repository.createFolder();
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

Map<String, Object?> _notebookToJson(NotebookItem item) {
  return {
    'id': item.id,
    'title': item.title,
    'updatedAt': item.updatedAt.toIso8601String(),
    'kind': item.kind.name,
    'coverColor': item.coverColor.toARGB32(),
    'folderId': item.folderId,
    'tagIds': item.tagIds,
    'subtitle': item.subtitle,
  };
}

NotebookItem _notebookFromJson(Map<String, Object?> json) {
  return NotebookItem(
    id: json['id']! as String,
    title: json['title']! as String,
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    kind: LibraryFilter.values.byName(json['kind']! as String),
    coverColor: Color(json['coverColor']! as int),
    folderId: json['folderId'] as String?,
    tagIds: (json['tagIds'] as List? ?? const []).whereType<String>().toList(),
    subtitle: json['subtitle'] as String?,
  );
}

const _notebookColors = [
  Color(0xFF8DB6C9),
  Color(0xFFD9B48F),
  Color(0xFF2E5872),
  Color(0xFF8CBDB5),
  Color(0xFFD6D6D0),
  Color(0xFFE9993F),
  Color(0xFF9CA2E6),
];

const _folderColors = [
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
