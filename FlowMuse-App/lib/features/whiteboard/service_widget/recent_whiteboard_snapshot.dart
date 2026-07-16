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
    // updatedAt 以字符串传输，避开鸿蒙 MethodChannel 对 int64/double 的
    // BigInt 解码与精度问题（曾出现大数被解码为 0 导致卡片显示"1月1日"）。
    // 原生侧用 parseInt_ 还是 Number 还原。
    'updatedAt': updatedAt.toString(),
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
      if (noteId is! String || title is! String) {
        return null;
      }
      // updatedAt 兼容字符串（新格式）与数字（旧格式/测试）
      final parsedUpdatedAt = updatedAt is int
          ? updatedAt
          : updatedAt is double
              ? updatedAt.toInt()
              : updatedAt is String
                  ? int.tryParse(updatedAt)
                  : null;
      if (parsedUpdatedAt == null) return null;
      return RecentWhiteboardSnapshot(
        noteId: noteId,
        title: title,
        updatedAt: parsedUpdatedAt,
      );
    } catch (_) {
      return null;
    }
  }
}
