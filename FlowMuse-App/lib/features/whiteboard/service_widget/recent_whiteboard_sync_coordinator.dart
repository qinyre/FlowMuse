import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../library/models/note_item.dart';
import 'recent_whiteboard_store.dart';
import 'service_widget_channel.dart';

class RecentWhiteboardSyncCoordinator {
  RecentWhiteboardSyncCoordinator({
    RecentWhiteboardStore? store,
    ServiceWidgetChannelOhos? channel,
  }) : store = store ?? RecentWhiteboardStore(),
       _channel = channel ?? const ServiceWidgetChannelOhos();

  @visibleForTesting
  final RecentWhiteboardStore store;
  final ServiceWidgetChannelOhos _channel;

  /// 将笔记快照写入存储并通知服务卡片频道。
  ///
  /// 内部捕获 [PlatformException] 与 [MissingPluginException]，静默降级，
  /// 不向调用方抛异常，以保证 [whiteboard_page.dart] 中的保存流程不被中断。
  Future<void> syncFromNote(NoteItem note) async {
    try {
      await store.record(
        noteId: note.id,
        title: note.title,
        updatedAt: note.updatedAt,
      );
      final snapshot = await store.read();
      if (snapshot != null) {
        await _channel.updateLastWhiteboard(snapshot);
      }
    } on PlatformException catch (e, st) {
      debugPrint('[RecentWhiteboardSyncCoordinator] syncFromNote PlatformException: $e\n$st');
    } on MissingPluginException catch (e, st) {
      debugPrint('[RecentWhiteboardSyncCoordinator] syncFromNote MissingPluginException: $e\n$st');
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
