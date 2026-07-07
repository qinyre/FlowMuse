import 'package:flutter/material.dart';

enum LibraryFilter { all, notes, pdf }

enum LibraryViewMode { grid, list }

class NotebookItem {
  const NotebookItem({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.kind,
    required this.coverColor,
    this.folderId,
    this.tagIds = const [],
    this.subtitle,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final LibraryFilter kind;
  final Color coverColor;
  final String? folderId;
  final List<String> tagIds;
  final String? subtitle;

  String get date {
    final year = updatedAt.year.toString().padLeft(4, '0');
    final month = updatedAt.month.toString().padLeft(2, '0');
    final day = updatedAt.day.toString().padLeft(2, '0');
    return '$year/$month/$day';
  }
}
