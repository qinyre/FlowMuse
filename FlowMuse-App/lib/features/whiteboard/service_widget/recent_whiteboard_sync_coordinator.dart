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
      debugPrint('[ServiceWidget] syncFromNote: noteId=${note.id} title=${note.title} updatedAt=${note.updatedAt.millisecondsSinceEpoch}');
      await store.record(
        noteId: note.id,
        title: note.title,
        updatedAt: note.updatedAt,
      );
      final snapshot = await store.read();
      debugPrint('[ServiceWidget] syncFromNote store read: snapshot=${snapshot?.noteId}/${snapshot?.title}/${snapshot?.updatedAt}');
      if (snapshot != null) {
        await _channel.updateLastWhiteboard(snapshot);
        debugPrint('[ServiceWidget] syncFromNote updateLastWhiteboard sent');
      }
    } on PlatformException catch (e, st) {
      debugPrint('[ServiceWidget] syncFromNote PlatformException: $e\n$st');
    } on MissingPluginException catch (e, st) {
      debugPrint('[ServiceWidget] syncFromNote MissingPluginException: $e\n$st');
    } catch (e, st) {
      debugPrint('[ServiceWidget] syncFromNote unexpected error: $e\n$st');
    }
  }

  /// 将已存储的最近白板快照重新推给服务卡片，不写入新数据。
  ///
  /// 用于 App 启动时刷新卡片：卡片所在进程可能与主进程不同，冷启动后
  /// 卡片仍停留在占位文案，这里主动同步一次让其尽快显示真实内容。
  /// 若 store 中无快照（从未打开过白板），则不做任何操作。
  Future<void> syncFromStore() async {
    try {
      final snapshot = await store.read();
      debugPrint('[ServiceWidget] syncFromStore: snapshot=${snapshot?.noteId}/${snapshot?.title}/${snapshot?.updatedAt}');
      if (snapshot != null) {
        await _channel.updateLastWhiteboard(snapshot);
        debugPrint('[ServiceWidget] syncFromStore updateLastWhiteboard sent');
      }
    } on PlatformException catch (e, st) {
      debugPrint('[ServiceWidget] syncFromStore PlatformException: $e\n$st');
    } on MissingPluginException catch (e, st) {
      debugPrint('[ServiceWidget] syncFromStore MissingPluginException: $e\n$st');
    } catch (e, st) {
      debugPrint('[ServiceWidget] syncFromStore unexpected error: $e\n$st');
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
