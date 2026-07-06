import 'package:flutter/material.dart';

enum LibraryFilter { all, notes, pdf }

enum LibraryViewMode { grid, list }

class NotebookItem {
  const NotebookItem({
    required this.id,
    required this.title,
    required this.date,
    required this.kind,
    required this.coverColor,
    this.subtitle,
  });

  final String id;
  final String title;
  final String date;
  final LibraryFilter kind;
  final Color coverColor;
  final String? subtitle;
}
