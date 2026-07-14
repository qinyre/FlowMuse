import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TestLibraryIndexNotifier extends LibraryIndexNotifier {
  static final _now = DateTime(2026, 7, 14);

  @override
  Future<LibraryIndex> build() async => LibraryIndex(
    notes: [
      NoteItem(
        id: 'whiteboard-os',
        title: '操作系统',
        updatedAt: _now,
        kind: LibraryFilter.notes,
        coverColor: Colors.blue,
      ),
      NoteItem(
        id: 'lecture-notes',
        title: 'LectureNotes',
        updatedAt: _now,
        kind: LibraryFilter.pdf,
        coverColor: Colors.orange,
      ),
    ],
  );

  @override
  Future<NoteItem> createNote({
    LibraryFilter kind = LibraryFilter.notes,
    NoteType noteType = NoteType.unbounded,
    PageTemplate pageTemplate = PageTemplate.blank,
    PageFlow pageFlow = PageFlow.topToBottom,
    String? title,
    String? subtitle,
    String? notebookId,
    List<String> tagIds = const [],
  }) async {
    final note = NoteItem(
      id: 'created-note',
      title: title ?? '未命名白板',
      updatedAt: _now,
      kind: kind,
      coverColor: Colors.teal,
      noteType: noteType,
      pageTemplate: pageTemplate,
      pageFlow: pageFlow,
      subtitle: subtitle,
      notebookId: notebookId,
      tagIds: tagIds,
    );
    final current = state.requireValue;
    state = AsyncData(
      LibraryIndex(
        notes: [...current.notes, note],
        notebooks: current.notebooks,
        tags: current.tags,
      ),
    );
    return note;
  }

  @override
  Future<void> ensureNote(String noteId) async {}

  @override
  Future<LibraryNotebook> createNotebook({
    String? name,
    Color? coverColor,
    String? coverImage,
  }) async {
    final current = state.requireValue;
    final notebook = LibraryNotebook(
      id: 'notebook-${current.notebooks.length + 1}',
      name: name ?? '新建文件夹 ${current.notebooks.length + 1}',
      coverColor: coverColor ?? Colors.blue,
      coverImage: coverImage,
      createdAt: _now,
      updatedAt: _now,
      sortOrder: current.notebooks.length,
    );
    state = AsyncData(
      LibraryIndex(
        notes: current.notes,
        notebooks: [...current.notebooks, notebook],
        tags: current.tags,
      ),
    );
    return notebook;
  }

  @override
  Future<LibraryTag> createTag({
    String? name,
    Color? coverColor,
    String? coverImage,
  }) async {
    final current = state.requireValue;
    final tag = LibraryTag(
      id: 'tag-${current.tags.length + 1}',
      name: name ?? '新建标签 ${current.tags.length + 1}',
      coverColor: coverColor ?? Colors.green,
      coverImage: coverImage,
      createdAt: _now,
      updatedAt: _now,
      sortOrder: current.tags.length,
    );
    state = AsyncData(
      LibraryIndex(
        notes: current.notes,
        notebooks: current.notebooks,
        tags: [...current.tags, tag],
      ),
    );
    return tag;
  }
}
