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
    // int64 在鸿蒙 Flutter 桥被解码为 BigInt，BigInt 无法 JSON.stringify。
    // 改发 float64（double），桥侧解码为普通 JS number，ArkTS 可直接使用。
    'updatedAt': updatedAt.toDouble(),
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
      if (noteId is! String || title is! String || updatedAt is! num) {
        return null;
      }
      return RecentWhiteboardSnapshot(
        noteId: noteId,
        title: title,
        updatedAt: updatedAt.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
