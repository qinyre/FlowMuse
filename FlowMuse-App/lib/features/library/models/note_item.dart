import 'dart:typed_data';

import 'package:flutter/material.dart';

enum LibraryFilter { all, notes, pdf }

enum LibraryViewMode { grid, list }

enum NoteType { paged, unbounded }

enum PageFlow { topToBottom, rightToLeft }

enum PageTemplate {
  blank,
  narrowLine,
  wideLine,
  grid,
  dotGrid,
  tianGrid,
  miGrid,
  narrowVerticalLine,
  wideVerticalLine,
  fourLineGrid,
  ancientBook,
}

extension PageTemplateLabel on PageTemplate {
  String get displayName {
    return switch (this) {
      PageTemplate.blank => '空白',
      PageTemplate.narrowLine => '窄线格',
      PageTemplate.wideLine => '宽线格',
      PageTemplate.grid => '方格',
      PageTemplate.dotGrid => '点阵',
      PageTemplate.tianGrid => '田字格',
      PageTemplate.miGrid => '米字格',
      PageTemplate.narrowVerticalLine => '窄竖线格',
      PageTemplate.wideVerticalLine => '宽竖线格',
      PageTemplate.fourLineGrid => '四线三格',
      PageTemplate.ancientBook => '古籍版式',
    };
  }
}

class NoteItem {
  const NoteItem({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.kind,
    required this.coverColor,
    this.noteType = NoteType.unbounded,
    this.pageTemplate = PageTemplate.blank,
    this.pageFlow = PageFlow.topToBottom,
    this.notebookId,
    this.tagIds = const [],
    this.subtitle,
    this.deletedAt,
    this.coverThumbnailBytes,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final LibraryFilter kind;
  final Color coverColor;
  final NoteType noteType;
  final PageTemplate pageTemplate;
  final PageFlow pageFlow;
  final String? notebookId;
  final List<String> tagIds;
  final String? subtitle;
  final DateTime? deletedAt;
  final Uint8List? coverThumbnailBytes;

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
    PageFlow? pageFlow,
    String? notebookId,
    List<String>? tagIds,
    String? subtitle,
    DateTime? deletedAt,
    Uint8List? coverThumbnailBytes,
    bool clearNotebook = false,
    bool clearDeletedAt = false,
    bool clearCoverThumbnail = false,
  }) {
    return NoteItem(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      kind: kind ?? this.kind,
      coverColor: coverColor ?? this.coverColor,
      noteType: noteType ?? this.noteType,
      pageTemplate: pageTemplate ?? this.pageTemplate,
      pageFlow: pageFlow ?? this.pageFlow,
      notebookId: clearNotebook ? null : notebookId ?? this.notebookId,
      tagIds: tagIds ?? this.tagIds,
      subtitle: subtitle ?? this.subtitle,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      coverThumbnailBytes: clearCoverThumbnail
          ? null
          : coverThumbnailBytes ?? this.coverThumbnailBytes,
    );
  }
}
