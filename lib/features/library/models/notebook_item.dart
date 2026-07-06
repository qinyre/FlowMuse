import 'package:flutter/material.dart';

enum LibraryFilter { all, notes, pdf }

class NotebookItem {
  const NotebookItem({
    required this.title,
    required this.date,
    required this.kind,
    required this.coverColor,
    this.subtitle,
  });

  final String title;
  final String date;
  final LibraryFilter kind;
  final Color coverColor;
  final String? subtitle;
}
