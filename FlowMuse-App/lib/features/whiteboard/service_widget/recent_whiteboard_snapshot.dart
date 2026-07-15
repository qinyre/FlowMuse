import 'dart:convert';

class RecentWhiteboardSnapshot {
  const RecentWhiteboardSnapshot({
    required this.noteId,
    required this.title,
    required this.updatedAt,
  });

  final String noteId;
  final String title;
  final int updatedAt;

  Map<String, Object?> toJson() => {
    'noteId': noteId,
    'title': title,
    'updatedAt': updatedAt,
  };

  String toJsonString() => jsonEncode(toJson());

  static RecentWhiteboardSnapshot? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, Object?>) return null;
      final noteId = value['noteId'];
      final title = value['title'];
      final updatedAt = value['updatedAt'];
      if (noteId is! String || title is! String || updatedAt is! int) {
        return null;
      }
      return RecentWhiteboardSnapshot(
        noteId: noteId,
        title: title,
        updatedAt: updatedAt,
      );
    } catch (_) {
      return null;
    }
  }
}
