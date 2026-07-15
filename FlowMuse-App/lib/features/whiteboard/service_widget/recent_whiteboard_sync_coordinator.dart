import '../../library/models/note_item.dart';
import 'recent_whiteboard_store.dart';
import 'service_widget_channel.dart';

class RecentWhiteboardSyncCoordinator {
  RecentWhiteboardSyncCoordinator({
    RecentWhiteboardStore? store,
    ServiceWidgetChannelOhos? channel,
  }) : store = store ?? RecentWhiteboardStore(),
       _channel = channel ?? const ServiceWidgetChannelOhos();

  final RecentWhiteboardStore store;
  final ServiceWidgetChannelOhos _channel;

  Future<void> syncFromNote(NoteItem note) async {
    await store.record(
      noteId: note.id,
      title: note.title,
      updatedAt: note.updatedAt,
    );
    final snapshot = await store.read();
    if (snapshot != null) {
      await _channel.updateLastWhiteboard(snapshot);
    }
  }

  Future<String?> takePendingResumeLocation(Iterable<NoteItem> notes) async {
    final action = await _channel.takePendingLaunchAction();
    if (action != ServiceWidgetLaunchAction.resumeLastWhiteboard) {
      return null;
    }
    return resolveRecentWhiteboardLocation(await store.read(), notes);
  }
}
