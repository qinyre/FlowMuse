import 'package:flutter/material.dart';

enum LibraryFilter { all, notes, pdf }

enum LibraryViewMode { grid, list }

enum NoteType { paged, unbounded }

enum PageTemplate { blank, narrowLine, wideLine, grid, dotGrid }

class NoteItem {
  const NoteItem({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.kind,
    required this.coverColor,
    this.noteType = NoteType.unbounded,
    this.pageTemplate = PageTemplate.blank,
    this.notebookId,
    this.tagIds = const [],
    this.subtitle,
    this.deletedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final LibraryFilter kind;
  final Color coverColor;
  final NoteType noteType;
  final PageTemplate pageTemplate;
  final String? notebookId;
  final List<String> tagIds;
  final String? subtitle;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  String get date {
    final year = updatedAt.year.toString().padLeft(4, '0');
    final month = updatedAt.month.toString().padLeft(2, '0');
    final day = updatedAt.day.toString().padLeft(2, '0');
    return '$year/$month/$day';
  }

  NoteItem copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    LibraryFilter? kind,
    Color? coverColor,
    NoteType? noteType,
    PageTemplate? pageTemplate,
    String? notebookId,
    List<String>? tagIds,
    String? subtitle,
    DateTime? deletedAt,
    bool clearNotebook = false,
    bool clearDeletedAt = false,
  }) {
    return NoteItem(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      kind: kind ?? this.kind,
      coverColor: coverColor ?? this.coverColor,
      noteType: noteType ?? this.noteType,
      pageTemplate: pageTemplate ?? this.pageTemplate,
      notebookId: clearNotebook ? null : notebookId ?? this.notebookId,
      tagIds: tagIds ?? this.tagIds,
      subtitle: subtitle ?? this.subtitle,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }
}
