import 'package:flutter/material.dart';

@immutable
class LibraryNotebook {
  const LibraryNotebook({
    required this.id,
    required this.name,
    required this.coverColor,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final Color coverColor;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sortOrder;

  LibraryNotebook copyWith({
    String? id,
    String? name,
    Color? coverColor,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sortOrder,
  }) {
    return LibraryNotebook(
      id: id ?? this.id,
      name: name ?? this.name,
      coverColor: coverColor ?? this.coverColor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

@immutable
class LibraryTag {
  const LibraryTag({
    required this.id,
    required this.name,
    required this.coverColor,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final Color coverColor;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sortOrder;

  LibraryTag copyWith({
    String? id,
    String? name,
    Color? coverColor,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sortOrder,
  }) {
    return LibraryTag(
      id: id ?? this.id,
      name: name ?? this.name,
      coverColor: coverColor ?? this.coverColor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
