import '../../../app/app_router.dart';
import '../../../shared/storage/local_settings_repository.dart';
import '../../library/models/note_item.dart';
import 'recent_whiteboard_snapshot.dart';

export 'recent_whiteboard_snapshot.dart';

class RecentWhiteboardStore {
  RecentWhiteboardStore({LocalSettingsRepository? settings})
    : _settings = settings ?? defaultLocalSettingsRepository;

  static const settingsKey = 'service_widget.lastWhiteboard';

  final LocalSettingsRepository _settings;

  Future<void> record({
    required String noteId,
    required String title,
    required DateTime updatedAt,
  }) {
    final snapshot = RecentWhiteboardSnapshot(
      noteId: noteId,
      title: title,
      updatedAt: updatedAt.millisecondsSinceEpoch,
    );
    return _settings.writeString(settingsKey, snapshot.toJsonString());
  }

  Future<RecentWhiteboardSnapshot?> read() async {
    final raw = await _settings.readString(settingsKey);
    return RecentWhiteboardSnapshot.tryParse(raw);
  }
}

String resolveRecentWhiteboardLocation(
  RecentWhiteboardSnapshot? snapshot,
  Iterable<NoteItem> notes, {
  String fallback = AppRoutes.library,
}) {
  if (snapshot == null) return fallback;
  for (final note in notes) {
    if (note.id == snapshot.noteId && !note.isDeleted) {
      return AppRoutes.whiteboardPath(noteId: note.id);
    }
  }
  return fallback;
}
