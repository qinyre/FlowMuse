import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/library/repositories/library_repository.dart';
import '../features/whiteboard/share/models/external_document_request.dart';
import '../features/whiteboard/share/services/external_document_channel.dart';
import '../features/whiteboard/share/services/imported_document_coordinator.dart';
import '../features/whiteboard/view_models/whiteboard_view_model.dart';
import '../features/whiteboard/service_widget/recent_whiteboard_sync_coordinator.dart';
import '../features/whiteboard/service_widget/service_widget_channel.dart';
import 'app_router.dart';
import 'app_theme.dart';
import 'app_theme_preset.dart';
import 'view_models/theme_view_model.dart';

class FlowMuseApp extends ConsumerStatefulWidget {
  FlowMuseApp({super.key}) : _router = createAppRouter();

  final GoRouter _router;

  @override
  ConsumerState<FlowMuseApp> createState() => _FlowMuseAppState();
}

class _FlowMuseAppState extends ConsumerState<FlowMuseApp> {
  bool _consuming = false;
  bool _consumingServiceWidget = false;
  final _recentWhiteboardSync = RecentWhiteboardSyncCoordinator();

  @override
  void initState() {
    super.initState();
    const ExternalDocumentChannelOhos().setEnqueueListener(
      _drainPendingDocuments,
    );
    const ServiceWidgetChannelOhos().setLaunchListener(
      _drainPendingServiceWidgetActions,
    );
    Future.microtask(_drainPendingDocuments);
    Future.microtask(_drainPendingServiceWidgetActions);
  }

  /// 持续消费待处理文档,直到队列清空。重入时跳过,由入队通知或启动触发。
  Future<void> _drainPendingDocuments() async {
    if (_consuming) return;
    _consuming = true;
    try {
      while (true) {
        final request = await const ExternalDocumentChannelOhos().takeNext();
        if (request == null) break;
        await _consumeOne(request);
      }
    } finally {
      _consuming = false;
    }
  }

  Future<void> _drainPendingServiceWidgetActions() async {
    if (_consumingServiceWidget) return;
    _consumingServiceWidget = true;
    try {
      while (true) {
        final libraryIndex = await ref.read(libraryIndexProvider.future);
        final location = await _recentWhiteboardSync.takePendingResumeLocation(
          libraryIndex.notes,
        );
        if (location == null) break;
        widget._router.go(location);
      }
    } finally {
      _consumingServiceWidget = false;
    }
  }

  Future<void> _consumeOne(ExternalDocumentRequest request) async {
    final routerContext =
        widget._router.routerDelegate.navigatorKey.currentContext;
    if (routerContext == null) return;
    try {
      final preview = ImportedDocumentCoordinator().preview(request);
      // routerContext 来自 navigatorKey,是 router 级别全局 context,
      // 不随某个 widget 的 dispose 失效,在 async gap 后使用是安全的。
      final accepted = await showDialog<bool>(
        // ignore: use_build_context_synchronously
        context: routerContext,
        builder: (context) => AlertDialog(
          title: const Text('打开外部绘图文件'),
          content: Text('将“${preview.fileName}”创建为新的本地笔记副本。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('创建新笔记并打开'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      final noteTitle = _titleFromFileName(preview.fileName);
      final note = await ref
          .read(libraryIndexProvider.notifier)
          .createNote(title: noteTitle);
      await ref
          .read(whiteboardSceneRepositoryProvider)
          .saveScene(note.id, preview.content);
      widget._router.push(
        AppRoutes.whiteboardPath(noteId: note.id, discardIfUnchanged: false),
      );
    } catch (_) {
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        routerContext,
      ).showSnackBar(const SnackBar(content: Text('无法打开该绘图文件')));
    }
  }

  /// 从文件名提取笔记标题:去掉扩展名,空则回退默认。
  String? _titleFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    return base.trim().isEmpty ? null : base.trim();
  }

  @override
  Widget build(BuildContext context) {
    final themePreset = ref.watch(themeViewModelProvider);
    final darkThemePreset = effectiveAppThemePreset(
      themePreset,
      Brightness.dark,
    );

    return MaterialApp.router(
      title: 'FlowMuse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPreset(themePreset),
      darkTheme: AppTheme.fromPreset(darkThemePreset),
      themeMode: themePreset.themeMode,
      routerConfig: widget._router,
    );
  }
}
