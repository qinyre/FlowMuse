import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/app/social_overlay.dart';
import 'package:flow_muse/features/social/views/social_page.dart';
import 'package:flow_muse/features/social/widgets/invitation_actions.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/collaboration_config.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_receive_scheduler.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/whiteboard_collaboration_adapter.dart';
import 'package:flow_muse/features/whiteboard/collaboration/widgets/room_invite_qr.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/ink_recognition_repository.dart';
import 'package:flow_muse/features/whiteboard/models/editor_preferences.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pdf_note_import_payload.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pending_pdf_import_provider.dart';
import 'package:flow_muse/features/whiteboard/repositories/whiteboard_scene_repository.dart';
import 'package:flow_muse/features/whiteboard/view_models/editor_preferences_view_model.dart';
import 'package:flow_muse/features/whiteboard/view_models/whiteboard_view_model.dart';
import 'package:flow_muse/features/whiteboard/views/whiteboard_page.dart';
import 'package:flow_muse/shared/storage/local_database.dart';
import 'package:flow_muse/shared/storage/local_settings_repository.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Real page, controller and SQLite; no account/server/platform service calls.
// Run this file with FLOWMUSE_LAYERED_WET_INK=false and true.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late _TrackedLibraryRepository library;
  late SqliteWhiteboardSceneRepository scenes;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'flowmuse-writing-workflow-',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    await LocalDatabase.open();
    messenger.setMockMethodCallHandler(
      const MethodChannel('flow_muse/service_widget'),
      (_) async => null,
    );
    library = _TrackedLibraryRepository();
    scenes = SqliteWhiteboardSceneRepository(LocalDatabase.open);
  });

  tearDownAll(() async {
    await (await LocalDatabase.open()).close();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await directory.delete(recursive: true);
  });

  setUp(() async {
    await defaultLocalSettingsRepository.writeString(
      EditorPreferencesViewModel.settingsKey,
      '{}',
    );
  });

  testWidgets('自动保存失败保留草稿，退出失败不离页，手动重试可恢复', (tester) async {
    final note = await tester.runAsync(
      () => library.createNote(title: 'workflow-save-failure'),
    );
    final storage = _FaultySceneRepository(library)..failures = 1;
    final container = _container(library: library, sceneRepository: storage);
    final controller = await _open(tester, container, note!);
    controller.switchTool(ToolType.freedraw);
    await _stroke(tester, const Offset(650, 350));
    expect(
      container.read(whiteboardViewModelProvider).saveStatus,
      WhiteboardSaveStatus.idle,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await _drainIo(tester, container);
    expect(
      container.read(whiteboardViewModelProvider).saveStatus,
      WhiteboardSaveStatus.failed,
    );
    expect(
      tester
          .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
          .saveStatusLabel,
      '保存失败',
    );

    storage.failures = 1;
    tester.widget<MarkdrawEditor>(find.byType(MarkdrawEditor)).onBack!();
    await _drainIo(tester, container);
    expect(find.byType(WhiteboardPage), findsOneWidget);
    expect(
      container.read(whiteboardViewModelProvider).saveStatus,
      WhiteboardSaveStatus.failed,
    );
    expect(storage.attempts, 2, reason: '退出仍重试未保存的内容');

    tester.widget<MarkdrawEditor>(find.byType(MarkdrawEditor)).onSave!();
    await _drainIo(
      tester,
      container,
      until: () =>
          container.read(whiteboardViewModelProvider).saveStatus ==
          WhiteboardSaveStatus.saved,
    );
    expect(storage.attempts, 3);
    final content = await tester.runAsync(() => scenes.loadScene(note.id));
    final reopened = MarkdrawController()
      ..loadFromContent(content!, 'saved.excalidraw');
    addTearDown(reopened.dispose);
    expect(_ink(reopened), hasLength(1));
  });

  testWidgets('慢写盘时串行保存，旧保存完成不能把新草稿显示为已保存', (tester) async {
    final note = await tester.runAsync(
      () => library.createNote(title: 'workflow-serialized-save'),
    );
    final first = Completer<void>();
    final second = Completer<void>();
    final storage = _FaultySceneRepository(library)
      ..gates.addAll([first, second]);
    addTearDown(() {
      if (!first.isCompleted) first.complete();
      if (!second.isCompleted) second.complete();
    });
    final container = _container(library: library, sceneRepository: storage);
    final controller = await _open(tester, container, note!);
    controller.switchTool(ToolType.freedraw);
    await _stroke(tester, const Offset(650, 350));
    await tester.pump(const Duration(milliseconds: 600));
    await _waitForSave(tester, () => storage.attempts == 1);
    expect(
      container.read(whiteboardViewModelProvider).saveStatus,
      WhiteboardSaveStatus.saving,
    );
    await _stroke(tester, const Offset(650, 450));
    await tester.pump(const Duration(milliseconds: 600));
    expect(storage.attempts, 1, reason: '第二次写盘等待第一次结束');
    first.complete();
    await _waitForSave(tester, () => storage.attempts == 2);
    expect(storage.maxConcurrent, 1);
    expect(
      container.read(whiteboardViewModelProvider).saveStatus,
      isNot(WhiteboardSaveStatus.saved),
    );
    second.complete();
    await _drainIo(
      tester,
      container,
      until: () =>
          container.read(whiteboardViewModelProvider).saveStatus ==
          WhiteboardSaveStatus.saved,
    );
    final content = await tester.runAsync(() => scenes.loadScene(note.id));
    final reopened = MarkdrawController()
      ..loadFromContent(content!, 'latest.excalidraw');
    addTearDown(reopened.dispose);
    expect(_ink(reopened), hasLength(2));
  });

  testWidgets('保存失败重试成功后返回首页，重新打开仍有笔迹', (tester) async {
    // Given：白板是栈底路由，首次自动保存失败。
    final note = (await tester.runAsync(
      () => library.createNote(title: 'workflow-retry-and-exit'),
    ))!;
    final storage = _FaultySceneRepository(library)..failures = 1;
    final container = _container(library: library, sceneRepository: storage);
    final router = GoRouter(
      initialLocation: '/whiteboard',
      routes: [
        GoRoute(
          path: '/library',
          builder: (_, _) => const Scaffold(body: Text('测试资料库')),
        ),
        GoRoute(
          path: '/whiteboard',
          builder: (_, _) => WhiteboardPage(noteId: note.id),
        ),
      ],
    );
    addTearDown(router.dispose);
    final controller = await _open(tester, container, note, router: router);
    controller.switchTool(ToolType.freedraw);
    await _stroke(tester, const Offset(650, 350));
    await tester.pump(const Duration(milliseconds: 600));
    await _drainIo(tester, container);
    expect(find.text('保存失败，内容仍保留在当前页面'), findsOneWidget);

    // When：使用真正的提示重试按钮，然后点击返回。
    await tester.tap(find.widgetWithText(SnackBarAction, '重试'));
    await _drainIo(
      tester,
      container,
      until: () =>
          container.read(whiteboardViewModelProvider).saveStatus ==
          WhiteboardSaveStatus.saved,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('保存失败，内容仍保留在当前页面'), findsNothing);
    tester.widget<MarkdrawEditor>(find.byType(MarkdrawEditor)).onBack!();
    await _drainIo(tester, container);
    await tester.pump(const Duration(milliseconds: 400));

    // Then：真实路由离开白板，磁盘内容可以完整恢复。
    expect(find.text('测试资料库'), findsOneWidget);
    expect(find.byType(WhiteboardPage), findsNothing);
    final content = (await tester.runAsync(() => scenes.loadScene(note.id)))!;
    final reopened = MarkdrawController()
      ..loadFromContent(content, 'reopened.excalidraw');
    addTearDown(reopened.dispose);
    expect(_ink(reopened), hasLength(1));
  });

  testWidgets('列表刷新失败不应把已落盘正文标成保存失败', (tester) async {
    // Given：打开后模拟资料库列表查询失败，场景写盘仍正常。
    final faultyLibrary = _FailingIndexLibrary();
    final note = (await tester.runAsync(
      () => faultyLibrary.createNote(title: 'workflow-index-failure'),
    ))!;
    final container = _container(library: faultyLibrary);
    final controller = await _open(tester, container, note);
    faultyLibrary.failIndex = true;

    // When：书写触发自动保存和列表刷新。
    controller.switchTool(ToolType.freedraw);
    await _stroke(tester, const Offset(650, 350));
    await tester.pump(const Duration(milliseconds: 600));
    await _drainIo(tester, container);

    // Then：列表错误保留在自身状态中，正文保存成功且可重开。
    expect(container.read(libraryIndexProvider).hasError, isTrue);
    expect(
      container.read(whiteboardViewModelProvider).saveStatus,
      WhiteboardSaveStatus.saved,
    );
    final content = (await tester.runAsync(() => scenes.loadScene(note.id)))!;
    final reopened = MarkdrawController()
      ..loadFromContent(content, 'saved.excalidraw');
    addTearDown(reopened.dispose);
    expect(_ink(reopened), hasLength(1));
  });

  testWidgets('五笔经过真实画布：SQLite 自动保存、撤销重做、取消和重开', (tester) async {
    final note = await tester.runAsync(
      () => library.createNote(title: 'workflow-five-brushes'),
    );
    final container = _container(library: library);
    final controller = await _open(tester, container, note!);
    controller.switchTool(ToolType.freedraw);
    for (final brush in BrushType.values) {
      controller.activeBrushType = brush;
      await _stroke(tester, Offset(650, 300 + brush.index * 60));
    }
    expect(_ink(controller), hasLength(5));
    final expected = _elements(controller);
    await tester.pump(const Duration(milliseconds: 600));
    await _drainIo(tester, container);
    final content = await tester.runAsync(() => scenes.loadScene(note.id));
    final reopened = MarkdrawController();
    addTearDown(reopened.dispose);
    reopened.loadFromContent(content!, 'saved.excalidraw');
    expect(_elements(reopened), expected);

    controller.undo();
    expect(_ink(controller), hasLength(4));
    controller.redo();
    expect(_elements(controller), expected);
    final cancelled = await tester.startGesture(
      const Offset(700, 700),
      kind: PointerDeviceKind.stylus,
    );
    await cancelled.moveBy(const Offset(40, 20));
    await cancelled.cancel();
    await tester.pump();
    expect(_elements(controller), expected);

    await tester.pump(const Duration(milliseconds: 600));
    await _drainIo(tester, container);
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
    final next = await _open(tester, container, note);
    expect(_elements(next), expected);
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
  });

  testWidgets('关闭自动保存后，后台与退出仍保存已提交笔迹', (tester) async {
    final note = await tester.runAsync(
      () => library.createNote(title: 'workflow-flush'),
    );
    final container = _container(library: library);
    final controller = await _open(tester, container, note!);
    await tester.runAsync(
      () => container
          .read(editorPreferencesProvider.notifier)
          .setAutosaveInterval(AutosaveInterval.off),
    );
    await tester.pump();
    controller.switchTool(ToolType.freedraw);
    await _stroke(tester, const Offset(650, 400));
    await tester.pump(const Duration(seconds: 2));
    final savedBeforePause = await tester.runAsync(
      () => scenes.loadScene(note.id),
    );
    final check = MarkdrawController();
    addTearDown(check.dispose);
    check.loadFromContent(savedBeforePause!, 'before-pause.excalidraw');
    expect(_ink(check), isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _drainIo(tester, container);
    final savedAfterPause = await tester.runAsync(
      () => scenes.loadScene(note.id),
    );
    check.loadFromContent(savedAfterPause!, 'after-pause.excalidraw');
    expect(_ink(check), hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _stroke(tester, const Offset(650, 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
    final savedAfterExit = await tester.runAsync(
      () => scenes.loadScene(note.id),
    );
    check.loadFromContent(savedAfterExit!, 'after-exit.excalidraw');
    expect(_ink(check), hasLength(2));
  });

  testWidgets('页码跳转仅保存本机阅读位置，退出重开恢复页内位置与缩放', (tester) async {
    final note = (await tester.runAsync(
      () => library.createNote(title: 'workflow-reading-position'),
    ))!;
    final seed = MarkdrawController();
    seed.setLayout(const CanvasLayout(type: CanvasLayoutType.paged));
    seed.insertBlankPage();
    seed.insertBlankPage();
    await tester.runAsync(
      () => scenes.saveScene(
        note.id,
        seed.serializeScene(format: DocumentFormat.excalidraw),
      ),
    );
    seed.dispose();
    final container = _container(library: library);
    final controller = await _open(tester, container, note);
    final scene = controller.currentScene;
    final canvasSize = controller.canvasSize;
    final initialViewport = controller.editorState.viewport;
    final toolbar = tester.widget<DesktopToolbar>(find.byType(DesktopToolbar));
    for (var i = 0; i < 8; i++) {
      controller.scrollPagedViewportBy(10);
      await tester.pump();
    }
    expect(
      tester.widget<DesktopToolbar>(find.byType(DesktopToolbar)),
      same(toolbar),
      reason: '纯滚动不能重建整套工具栏',
    );
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is StaticCanvasPainter,
      ),
    );
    expect(
      (paint.painter! as StaticCanvasPainter).viewport,
      controller.editorState.viewport,
      reason: '外框不重建时画布仍跟随视口刷新',
    );
    controller.navigateToPage(controller.layout.pages.last.id);
    await tester.pump();
    expect(
      find.text(
        '${controller.pagedViewportMetrics!.currentPageIndex + 1} / ${controller.layout.pages.length}',
      ),
      findsOneWidget,
    );
    controller.zoomIn(canvasSize);
    await tester.pump();
    expect(
      find.text('${(controller.editorState.viewport.zoom * 100).round()}%'),
      findsOneWidget,
    );
    expect(
      tester.widget<DesktopToolbar>(find.byType(DesktopToolbar)),
      same(toolbar),
    );
    controller.setViewport(initialViewport);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pump();
    expect(find.text('页面预览'), findsOneWidget);
    expect(controller.canvasSize, canvasSize);
    expect(controller.editorState.viewport, initialViewport);
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is HoverTooltip && widget.message == '关闭预览',
        ),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pump();
    controller.navigateToPage(controller.layout.pages[1].id);
    controller.setViewport(
      ViewportState(
        offset: controller.editorState.viewport.offset + const Offset(0, 150),
        zoom: 0.8,
      ),
    );
    final viewport = controller.editorState.viewport;
    await tester.pump(const Duration(milliseconds: 750));
    await _drainIo(tester, container);
    expect(controller.currentScene, same(scene));
    expect(controller.historyManager.canUndo, isFalse);
    expect(
      await tester.runAsync(
        () => defaultLocalSettingsRepository.readString(
          'whiteboard.readingPosition.v1.${note.id}',
        ),
      ),
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
    final reopened = await _open(tester, container, note);
    expect(reopened.editorState.viewport.zoom, viewport.zoom);
    expect(
      reopened.editorState.viewport.offset.dx,
      closeTo(viewport.offset.dx, 0.001),
    );
    expect(
      reopened.editorState.viewport.offset.dy,
      closeTo(viewport.offset.dy, 0.001),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
  });

  testWidgets('PDF 底图上书写、撤销和重开保留图片、页边界与笔迹', (tester) async {
    final note = await tester.runAsync(
      () => library.createNote(title: 'workflow-pdf', kind: LibraryFilter.pdf),
    );
    final seed = MarkdrawController();
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 2, 2),
        Paint()..color = Colors.white,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      // Simulated PDF renderer output; decoding a PDF is covered separately.
      await seed.importPdfPages(
        [
          PdfRenderedPage(
            bytes: bytes!.buffer.asUint8List(),
            mimeType: 'image/png',
            width: 600,
            height: 800,
            pageNumber: 1,
          ),
        ],
        const Size(1200, 900),
        asBackground: true,
      );
      await scenes.saveScene(
        note!.id,
        seed.serializeScene(format: DocumentFormat.excalidraw),
      );
    });
    final background = _elements(seed).singleWhere((e) => e['type'] == 'image');
    seed.dispose();
    final container = _container(library: library);
    final controller = await _open(tester, container, note!);
    expect(controller.contentBounds, isNotNull);
    expect(controller.resolveImages(), hasLength(1));
    controller.switchTool(ToolType.freedraw);
    await _stroke(tester, const Offset(650, 400));
    expect(_ink(controller), hasLength(1));
    expect(
      _elements(controller).singleWhere((e) => e['type'] == 'image'),
      background,
    );
    controller.undo();
    expect(_ink(controller), isEmpty);
    expect(
      _elements(controller).singleWhere((e) => e['type'] == 'image'),
      background,
    );
    controller.redo();
    final expected = _elements(controller);
    await tester.pump(const Duration(milliseconds: 600));
    await _drainIo(tester, container);
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
    final reopened = await _open(tester, container, note);
    expect(_elements(reopened), expected);
    expect(reopened.resolveImages(), hasLength(1));
    expect(reopened.contentBounds, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
  });

  for (final outcome in ['success', 'failure', 'leave']) {
    testWidgets(
      'PDF 导入显示进度并正确收尾：$outcome',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const channel = MethodChannel('flow_muse/pdf_import');
        const codec = StandardMethodCodec();
        final rendered = Completer<List<Object?>>();
        String? progressName;
        messenger.setMockMethodCallHandler(channel, (call) {
          progressName = (call.arguments as Map)['progressChannel'] as String;
          return rendered.future;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final note = (await tester.runAsync(
          () => library.createNote(
            title: 'pdf-$outcome',
            kind: LibraryFilter.pdf,
          ),
        ))!;
        final container = _container(library: library);
        container
            .read(pendingPdfImportProvider.notifier)
            .set(
              PdfNoteImportPayload(
                bytes: Uint8List(1),
                name: 'large.pdf',
                noteId: note.id,
              ),
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: WhiteboardPage(noteId: note.id)),
          ),
        );
        await _drainIo(tester, container, until: () => progressName != null);
        expect(find.text('正在导入 PDF…'), findsOneWidget);
        expect(progressName, isNotNull);
        final controller = tester
            .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
            .controller!;
        await messenger.handlePlatformMessage(
          progressName!,
          codec.encodeMethodCall(
            const MethodCall('progress', {'completed': 7, 'total': 200}),
          ),
          (reply) => expect(codec.decodeEnvelope(reply!), isTrue),
        );
        await tester.pump();
        expect(find.text('正在导入 PDF：7 / 200 页'), findsOneWidget);
        controller.switchTool(ToolType.freedraw);
        await _stroke(tester, const Offset(650, 400));
        expect(_ink(controller), isEmpty, reason: '加载覆盖层拦住未就绪画布的输入');

        if (outcome == 'success') {
          final bytes = (await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawColor(Colors.white, BlendMode.src);
            final picture = recorder.endRecording();
            final image = await picture.toImage(4, 4);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            picture.dispose();
            return data!.buffer.asUint8List();
          }))!;
          rendered.complete([
            for (var page = 1; page <= 2; page++)
              {
                'bytes': bytes,
                'width': 600.0,
                'height': 800.0,
                'pageNumber': page,
              },
          ]);
        } else {
          if (outcome == 'leave') {
            await tester.pumpWidget(const SizedBox.shrink());
            await messenger.handlePlatformMessage(
              progressName!,
              codec.encodeMethodCall(
                const MethodCall('progress', {'completed': 8, 'total': 200}),
              ),
              (reply) => expect(codec.decodeEnvelope(reply!), isFalse),
            );
          }
          rendered.completeError(PlatformException(code: 'PDF_IMPORT_FAILED'));
        }
        await _drainIo(
          tester,
          container,
          until: () => outcome == 'leave'
              ? library.deletedNotes.contains(note.id)
              : find.byType(CircularProgressIndicator).evaluate().isEmpty,
        );
        if (outcome == 'success') {
          expect(find.textContaining('正在导入 PDF'), findsNothing);
          expect(controller.contentBounds, isNotNull);
          expect(controller.resolveImages(), isNotEmpty);
          final saved = (await tester.runAsync(
            () => scenes.loadScene(note.id),
          ))!;
          final restored = MarkdrawController();
          addTearDown(restored.dispose);
          restored.loadFromContent(saved, 'saved.excalidraw');
          expect(
            restored.currentScene.activeElements.whereType<ImageElement>(),
            hasLength(2),
          );
        } else {
          if (outcome == 'failure') {
            expect(find.text('PDF 导入失败，请返回后重试'), findsOneWidget);
          }
          final index = (await tester.runAsync(library.loadIndex))!;
          expect(
            index.notes.singleWhere((n) => n.id == note.id).deletedAt,
            isNotNull,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await _drainIo(tester, container);
      },
      variant: TargetPlatformVariant({TargetPlatform.ohos}),
    );
  }

  testWidgets('识别等待期间仍可落笔，延迟结果只替换所属笔画且可撤销', (tester) async {
    final note = await tester.runAsync(
      () => library.createNote(title: 'workflow-recognition'),
    );
    final recognition = _PendingRecognition();
    final container = _container(library: library, recognition: recognition);
    final controller = await _open(tester, container, note!);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    controller.switchTool(ToolType.freedraw);
    controller.inkRecognitionMode = true;
    await _stroke(tester, const Offset(650, 350));
    await tester.pump(const Duration(seconds: 1));
    expect(recognition.requests, hasLength(1));
    await _stroke(tester, const Offset(650, 450));
    expect(_ink(controller), hasLength(2));
    final second = _ink(controller).last;
    recognition.result.complete(
      const InkRecognitionResult(
        elements: [
          InkRecognizedElement(
            type: 'text',
            text: '测试',
            x: 100,
            y: 100,
            width: 100,
            height: 40,
          ),
        ],
      ),
    );
    await tester.pump();
    expect(_ink(controller).single.id, second.id);
    expect(_ink(controller).single.points, second.points);
    expect(
      controller.currentScene.activeElements
          .whereType<TextElement>()
          .single
          .text,
      '测试',
    );
    controller.undo();
    expect(_ink(controller), hasLength(2));
    expect(
      controller.currentScene.activeElements.whereType<TextElement>(),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
    final content = await tester.runAsync(() => scenes.loadScene(note.id));
    final reopened = MarkdrawController()
      ..loadFromContent(content!, 'recognition.excalidraw');
    expect(_ink(reopened), hasLength(2));
    reopened.dispose();
  });

  testWidgets('创建房间后可直接邀请好友，窄屏可滚动且关闭列表不退出协作', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final note = (await tester.runAsync(
      () => library.createNote(title: 'workflow-invite-after-create'),
    ))!;
    final local = CollaborationRepository(
      transport: MemoryRealtimeTransport(
        hub: MemoryRealtimeRoomHub(),
        socketId: 'create-room-page',
      ),
      sceneStore: MemoryEncryptedSceneStore(),
    );
    addTearDown(local.stop);
    final container = _container(library: library, collaboration: local);
    final controller = await _open(tester, container, note);
    final creating = tester
        .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
        .onStartCollaboration!();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '创建房间'),
      ),
    );
    await _drainIo(
      tester,
      container,
      until: () => find.text('分享协作房间').evaluate().isNotEmpty,
    );
    final room = container.read(whiteboardViewModelProvider).activeRoom;
    expect(room != null, isTrue);
    expect(find.byType(RoomInviteQr), findsOneWidget);
    expect(container.read(whiteboardViewModelProvider).isRoomOwner, isTrue);
    await tester.binding.setSurfaceSize(const Size(390, 500));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('邀请好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请好友'));
    await tester.pumpAndSettle();
    expect(find.text('分享协作房间'), findsNothing);
    expect(
      tester.widget<SocialPage>(find.byType(SocialPage)).inviteFriends,
      isTrue,
    );
    expect(container.read(whiteboardViewModelProvider).collaborating, isTrue);
    await tester.tap(find.byTooltip('关闭好友列表'));
    await tester.pump(const Duration(milliseconds: 400));
    await creating;
    expect(
      identical(container.read(whiteboardViewModelProvider).activeRoom, room),
      isTrue,
    );
    expect(container.read(whiteboardViewModelProvider).collaborating, isTrue);
    expect(
      tester.widget<MarkdrawEditor>(find.byType(MarkdrawEditor)).controller,
      same(controller),
    );
    final sharing = tester
        .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
        .onShareCollaboration!();
    await tester.pumpAndSettle();
    expect(find.byType(RoomInviteQr), findsOneWidget);
    expect(find.text('分享协作房间'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await sharing;
    expect(
      identical(container.read(whiteboardViewModelProvider).activeRoom, room),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
  });

  for (final saveRemoved in [false, true]) {
    testWidgets('被移出后${saveRemoved ? '保存本地' : '直接返回'}，其他笔记可重新创建房间', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      final nextNote = (await tester.runAsync(
        () => library.createNote(title: 'after-room-removal'),
      ))!;
      final before = (await tester.runAsync(
        library.loadIndex,
      ))!.notes.map((note) => note.id).toSet();
      final hub = MemoryRealtimeRoomHub();
      final store = _MemberJoinSceneStore();
      final host = CollaborationRepository(
        transport: MemoryRealtimeTransport(hub: hub, socketId: 'removal-host'),
        sceneStore: store,
      );
      final transport = _RemovableRealtimeTransport(
        hub: hub,
        socketId: 'removal-guest',
      );
      final local = CollaborationRepository(
        transport: transport,
        sceneStore: store,
      );
      addTearDown(host.stop);
      addTearDown(local.stop);
      addTearDown(transport.close);
      final room = (await tester.runAsync(
        () => host.startNewRoom(initialScene: ExcalidrawScene.empty()),
      ))!;
      final container = _container(library: library, collaboration: local);
      final router = GoRouter(
        initialLocation: '/room',
        routes: [
          GoRoute(path: '/library', builder: (_, _) => const SizedBox.shrink()),
          GoRoute(
            path: '/room',
            builder: (_, _) =>
                WhiteboardPage.collaborationRoom(initialRoom: room),
          ),
          GoRoute(
            path: '/next',
            builder: (_, _) => WhiteboardPage(noteId: nextNote.id),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await _drainIo(
        tester,
        container,
        until: () =>
            container.read(whiteboardViewModelProvider).collaborationStatus ==
            WhiteboardCollaborationStatus.connected,
      );
      final controller = tester
          .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
          .controller!;
      controller.applyRemoteElements([
        RectangleElement(
          id: const ElementId('retained-after-removal'),
          x: 200,
          y: 200,
          width: 100,
          height: 80,
        ),
      ]);
      transport.removed.add(room.roomId);
      transport.statuses.add(RealtimeConnectionStatus.disconnected);
      await _drainIo(
        tester,
        container,
        until: () => find.text('已被移出房间').evaluate().isNotEmpty,
      );
      await tester.tap(find.text(saveRemoved ? '保存到本地' : '直接返回'));
      await _drainIo(
        tester,
        container,
        until: () =>
            router.routeInformationProvider.value.uri.path == '/library',
      );
      if (saveRemoved) {
        final saved = (await tester.runAsync(
          library.loadIndex,
        ))!.notes.where((note) => !before.contains(note.id)).single;
        final content = await tester.runAsync(() => scenes.loadScene(saved.id));
        expect(content, contains('retained-after-removal'));
      }
      router.go('/next');
      await _drainIo(
        tester,
        container,
        until: () =>
            container.read(whiteboardViewModelProvider).noteId == nextNote.id &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(find.text('创建房间'), findsOneWidget);
      expect(
        container.read(whiteboardViewModelProvider).collaborationStatus,
        WhiteboardCollaborationStatus.idle,
      );
      expect(
        container.read(whiteboardViewModelProvider).exitReason,
        WhiteboardCollaborationExitReason.none,
      );
      final creating = tester
          .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
          .onStartCollaboration!();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '创建房间'),
        ),
      );
      await _drainIo(
        tester,
        container,
        until: () => find.text('分享协作房间').evaluate().isNotEmpty,
      );
      final newRoom = container.read(whiteboardViewModelProvider).activeRoom!;
      expect(newRoom.roomId == room.roomId, isFalse);
      expect(container.read(whiteboardViewModelProvider).isRoomOwner, isTrue);
      await tester.tap(find.text('知道了'));
      await tester.pump(const Duration(milliseconds: 400));
      await creating;
      transport.statuses.add(RealtimeConnectionStatus.reconnecting);
      await tester.pump();
      expect(
        container.read(whiteboardViewModelProvider).collaborationStatus,
        WhiteboardCollaborationStatus.reconnecting,
      );
      transport.statuses.add(RealtimeConnectionStatus.joined);
      await _drainIo(
        tester,
        container,
        until: () =>
            container.read(whiteboardViewModelProvider).collaborationStatus ==
            WhiteboardCollaborationStatus.connected,
      );
      expect(
        container.read(whiteboardViewModelProvider).activeRoom,
        same(newRoom),
      );
      var queued = false;
      tester.binding.addPostFrameCallback((_) {
        queued = true;
        transport.statuses.add(RealtimeConnectionStatus.disconnected);
        unawaited(
          container
              .read(whiteboardViewModelProvider.notifier)
              .openNote(noteId: nextNote.id),
        );
      });
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(queued, isTrue);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(
        container.read(whiteboardViewModelProvider).collaborationStatus,
        WhiteboardCollaborationStatus.idle,
        reason: '旧会话已排队的断线回调不能覆盖重新进入笔记后的状态',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _drainIo(tester, container);
    });
  }

  for (final template in [
    CanvasPageTemplate.blank,
    CanvasPageTemplate.grid,
    CanvasPageTemplate.ancientBook,
  ]) {
    testWidgets('有限协作 ${template.name} 加入、续页和保存重开保持房主版式', (tester) async {
      // Given: 房主已有两页，加入方通过临时协作入口进入。
      FlutterSecureStorage.setMockInitialValues({});
      final flow = template == CanvasPageTemplate.ancientBook
          ? CanvasPageFlow.rightToLeft
          : CanvasPageFlow.topToBottom;
      final hostController = MarkdrawController()
        ..setLayout(
          CanvasLayout(
            type: CanvasLayoutType.paged,
            template: template,
            pageFlow: flow,
          ),
        )
        ..insertBlankPage();
      addTearDown(hostController.dispose);
      final store = _MemberJoinSceneStore();
      final hub = MemoryRealtimeRoomHub();
      final host = CollaborationRepository(
        transport: MemoryRealtimeTransport(hub: hub, socketId: 'layout-host'),
        sceneStore: store,
      );
      final local = CollaborationRepository(
        transport: MemoryRealtimeTransport(hub: hub, socketId: 'layout-guest'),
        sceneStore: store,
      );
      addTearDown(host.stop);
      addTearDown(local.stop);
      final room = (await tester.runAsync(
        () => host.startNewRoom(
          initialScene: WhiteboardCollaborationAdapter(
            hostController,
          ).currentScene(),
        ),
      ))!;
      final before = (await tester.runAsync(
        library.loadIndex,
      ))!.notes.map((note) => note.id).toSet();
      final container = _container(library: library, collaboration: local);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        initialLocation: '/room',
        routes: [
          GoRoute(path: '/library', builder: (_, _) => const SizedBox.shrink()),
          GoRoute(
            path: '/room',
            builder: (_, _) =>
                WhiteboardPage.collaborationRoom(initialRoom: room),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await _drainIo(
        tester,
        container,
        until: () =>
            container.read(whiteboardViewModelProvider).collaborationStatus ==
            WhiteboardCollaborationStatus.connected,
      );
      final controller = tester
          .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
          .controller!;

      // When/Then: 页面标记和默认版式一致，新增页面也不能退回空白模板。
      expect(controller.layout.type, CanvasLayoutType.paged);
      expect(
        controller.layout.pages.map((p) => p.bounds),
        hostController.layout.pages.map((p) => p.bounds),
      );
      expect(controller.layout.template, template);
      expect(controller.layout.pageFlow, flow);
      final visible = controller.editorState.viewport.visibleRect(
        controller.canvasSize,
      );
      expect(
        visible.contains(controller.layout.pages.first.bounds.topLeft),
        isTrue,
        reason: '平板加入后应看得到首张纸的边界，而不是只看见纸内局部',
      );
      expect(
        visible.contains(controller.layout.pages.first.bounds.bottomRight),
        isTrue,
      );
      controller.zoomIn(controller.canvasSize);
      await tester.pump();
      final zoom = controller.editorState.viewport.zoom;
      final firstMarker = WhiteboardCollaborationAdapter(
        hostController,
      ).currentScene().elements.first;
      await tester.runAsync(
        () => host.broadcastElements(
          room: room,
          elements: [
            {...firstMarker, 'version': (firstMarker['version']! as int) + 1},
          ],
        ),
      );
      await _drainIo(tester, container);
      expect(
        controller.editorState.viewport.zoom,
        zoom,
        reason: '后续远端页面更新不得反复重置本机缩放',
      );
      controller.insertBlankPage();
      await tester.pump();
      expect(controller.layout.pages.last.template, template);
      expect(controller.layout.pages.last.pageFlow, flow);

      // When: 加入方退出时保存临时协作。
      tester.widget<MarkdrawEditor>(find.byType(MarkdrawEditor)).onBack!();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('保存到本地'));
      await _drainIo(
        tester,
        container,
        until: () => !container.read(whiteboardViewModelProvider).collaborating,
      );
      final saved = (await tester.runAsync(
        library.loadIndex,
      ))!.notes.singleWhere((note) => !before.contains(note.id));
      expect(saved.noteType, NoteType.paged);
      expect(saved.pageTemplate.name, template.name);
      expect(saved.pageFlow.name, flow.name);

      // Then: 重开后继续插页仍沿用同一模板和方向。
      await tester.pumpWidget(const SizedBox.shrink());
      await _drainIo(tester, container);
      final reopened = await _open(tester, container, saved);
      expect(reopened.layout.pages, hasLength(3));
      expect(reopened.layout.template, template);
      expect(reopened.layout.pageFlow, flow);
      reopened.insertBlankPage();
      expect(reopened.layout.pages.last.template, template);
      await tester.pumpWidget(const SizedBox.shrink());
      await _drainIo(tester, container);
    });
  }

  testWidgets('本机有限笔记加入空白无限房间后不残留本机页面', (tester) async {
    final note = (await tester.runAsync(
      () => library.createNote(
        title: 'workflow-join-empty-room',
        noteType: NoteType.paged,
        pageTemplate: PageTemplate.grid,
      ),
    ))!;
    final store = MemoryEncryptedSceneStore();
    final room = CollaborationRoom.newRoom(crypto: CollaborationCrypto());
    await tester.runAsync(
      () => store.createRoom(
        room: room,
        scene: ExcalidrawScene.empty(),
        ownerKeyHash: 'fixture',
      ),
    );
    final local = CollaborationRepository(
      transport: MemoryRealtimeTransport(
        hub: MemoryRealtimeRoomHub(),
        socketId: 'empty-guest',
      ),
      sceneStore: store,
    );
    addTearDown(local.stop);
    final container = _container(library: library, collaboration: local);
    final controller = await _open(tester, container, note);
    expect(controller.layout.isPaged, isTrue);

    final joining = tester
        .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
        .onJoinCollaboration!();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), room.toRoomValue());
    await tester.tap(find.text('加入'));
    await _drainIo(
      tester,
      container,
      until: () =>
          container.read(whiteboardViewModelProvider).collaborationStatus ==
          WhiteboardCollaborationStatus.connected,
    );
    await joining;

    expect(controller.layout.type, CanvasLayoutType.unbounded);
    expect(controller.layout.pages, isEmpty);
    expect(controller.currentScene.elements, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
  });

  testWidgets('F1 加密协作：查看、跟随、主动操作、位置邀请和离线清理', (tester) async {
    final room = CollaborationRoom.newRoom(crypto: CollaborationCrypto());
    final store = MemoryEncryptedSceneStore();
    final hub = MemoryRealtimeRoomHub();
    final peer = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'f1-peer'),
      sceneStore: store,
    );
    final local = _TrackedCollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'f1-local'),
      sceneStore: store,
    );
    addTearDown(peer.stop);
    await tester.runAsync(() async {
      await store.createRoom(
        room: room,
        scene: ExcalidrawScene.empty(),
        ownerKeyHash: 'test',
      );
      await peer.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    });
    final received = <CollaborationMessage>[];
    final subscription = peer.encryptedMessages(room).listen(received.add);
    addTearDown(subscription.cancel);
    final container = _container(library: library, collaboration: local);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: WhiteboardPage.collaborationRoom(initialRoom: room),
        ),
      ),
    );
    await _drainIo(
      tester,
      container,
      until: () =>
          container.read(whiteboardViewModelProvider).collaborationStatus ==
          WhiteboardCollaborationStatus.connected,
    );
    final controller = tester
        .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
        .controller!;
    Future<void> bounds(
      double x, {
      String? following,
      String? attention,
    }) async {
      await tester.runAsync(
        () => peer.broadcastVisibleSceneBounds(
          room: room,
          username: '同伴',
          followingSocketId: following,
          attentionId: attention,
          sceneBounds: {'x': x, 'y': 2000, 'width': 800, 'height': 600},
        ),
      );
      await _drainIo(tester, container);
    }

    Future<void> action(String label) async {
      await tester.tap(find.text('同'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await _drainIo(tester, container);
    }

    final originalScene = controller.currentScene;
    final originalView = controller.editorState.viewport;
    expect(
      container.read(whiteboardViewModelProvider).collaborators.keys,
      contains('f1-peer'),
      reason: '页面订阅前到达的初始成员列表仍须展示',
    );
    await bounds(1000);
    expect(controller.editorState.viewport, originalView, reason: '接收视口不会自动跳转');
    await action('查看位置');
    expect(
      controller.editorState.viewport.screenToScene(
        controller.canvasSize.center(Offset.zero),
      ),
      const Offset(1400, 2300),
    );
    final oneShot = controller.editorState.viewport;
    await bounds(2000);
    expect(controller.editorState.viewport, oneShot);
    await action('跟随视角');
    expect(find.textContaining('正在跟随 同伴'), findsOneWidget);
    final editor = tester.widget<MarkdrawEditor>(find.byType(MarkdrawEditor));
    await bounds(3000);
    expect(
      controller.editorState.viewport.screenToScene(
        controller.canvasSize.center(Offset.zero),
      ),
      const Offset(3400, 2300),
    );
    expect(
      tester.widget<MarkdrawEditor>(find.byType(MarkdrawEditor)),
      same(editor),
      reason: '跟随移动不重建整个编辑器和工具栏',
    );
    expect(controller.currentScene, same(originalScene));
    expect(
      received.any((m) => m.payload['followingSocketId'] == 'f1-peer'),
      isTrue,
    );

    controller.setViewport(
      controller.editorState.viewport.pan(const Offset(30, 20)),
    );
    await tester.pump();
    expect(find.textContaining('正在跟随'), findsNothing);
    final manual = controller.editorState.viewport;
    await bounds(4000);
    expect(controller.editorState.viewport, manual);
    await action('跟随视角');
    controller.switchTool(ToolType.freedraw);
    await _stroke(tester, const Offset(600, 450));
    expect(find.textContaining('正在跟随'), findsNothing);
    expect(_ink(controller), hasLength(1));
    final afterWriting = controller.editorState.viewport;
    await bounds(5000, attention: 'request-1');
    expect(find.text('同伴 邀请你看这里'), findsOneWidget);
    expect(controller.editorState.viewport, afterWriting);
    await tester.tap(find.text('查看位置'));
    await tester.pumpAndSettle();
    expect(find.text('同伴 邀请你看这里'), findsNothing);
    expect(
      controller.editorState.viewport.screenToScene(
        controller.canvasSize.center(Offset.zero),
      ),
      const Offset(5400, 2300),
    );
    await bounds(6000, attention: 'request-1');
    expect(find.text('同伴 邀请你看这里'), findsNothing, reason: '重复提示不再次打断用户');
    await action('跟随视角');
    await bounds(6000, following: local.socketId);
    expect(find.textContaining('正在跟随'), findsNothing, reason: '互相跟随时自动解除循环');
    await bounds(6000);
    await action('跟随视角');
    await tester.runAsync(peer.stop);
    await _drainIo(tester, container);
    expect(find.textContaining('正在跟随'), findsNothing);
    expect(_ink(controller), hasLength(1));
  });

  testWidgets('内存加密协作：落笔中接收远端元素，终笔与撤销仍广播', (tester) async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final hub = MemoryRealtimeRoomHub();
    final peerTransport = MemoryRealtimeTransport(
      hub: hub,
      socketId: 'workflow-peer',
    );
    final peer = CollaborationRepository(
      transport: peerTransport,
      sceneStore: store,
    );
    final local = _TrackedCollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'workflow-page'),
      sceneStore: store,
    );
    addTearDown(peer.stop);
    await tester.runAsync(() async {
      await store.createRoom(
        room: room,
        scene: ExcalidrawScene.empty(),
        ownerKeyHash: 'test',
      );
      await peer.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    });
    final received = <CollaborationMessage>[];
    final subscription = peer.encryptedMessages(room).listen(received.add);
    addTearDown(subscription.cancel);
    final container = _container(library: library, collaboration: local);
    var joinedCallbacks = 0;
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: WhiteboardPage.collaborationRoom(
            initialRoom: room,
            onInitialRoomJoined: () async {
              expect(
                container.read(whiteboardViewModelProvider).collaborationStatus,
                WhiteboardCollaborationStatus.connected,
              );
              joinedCallbacks++;
            },
          ),
        ),
      ),
    );
    await _drainIo(
      tester,
      container,
      until: () =>
          container.read(whiteboardViewModelProvider).collaborationStatus ==
          WhiteboardCollaborationStatus.connected,
    );
    expect(container.read(whiteboardViewModelProvider).collaborating, isTrue);
    expect(joinedCallbacks, 1);
    final controller = tester
        .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
        .controller!;
    // Establish the participant once, then pointer updates must stay in the
    // cursor layer while participant identity/status still updates the header.
    Future<void> pointer(int x, {String username = 'fixture-peer'}) async {
      await tester.runAsync(
        () => peer.broadcastMouseLocation(
          room: room,
          pointer: {'x': x, 'y': 140},
          button: 'down',
          selectedElementIds: {'workflow-remote': true},
          username: username,
        ),
      );
      await _drainIo(tester, container);
    }

    await pointer(100);
    // Reading messages must not replace/dispose the collaborating route.
    await tester.tap(find.byType(SocialMessagesAction));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('登录后，与好友交流新的想法'), findsOneWidget);
    expect(container.read(whiteboardViewModelProvider).collaborating, isTrue);
    final elementCount = controller.currentScene.elements.length;
    await tester.tapAt(const Offset(600, 400));
    expect(controller.currentScene.elements.length, elementCount);
    final openingInvitation = InvitationActions.of(
      tester.element(find.byType(SocialPage)),
    )!.open('test-invite');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('退出协作房间'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 400));
    await openingInvitation;
    expect(container.read(whiteboardViewModelProvider).collaborating, isTrue);
    await tester.tap(find.byTooltip('关闭消息'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(whiteboardViewModelProvider).collaborating, isTrue);
    expect(
      tester.widget<MarkdrawEditor>(find.byType(MarkdrawEditor)).controller,
      same(controller),
    );
    final pageEditor = tester.widget<MarkdrawEditor>(
      find.byType(MarkdrawEditor),
    );
    final presenceToolbar = tester.widget<DesktopToolbar>(
      find.byType(DesktopToolbar),
    );
    for (var x = 101; x <= 104; x++) {
      await pointer(x);
      expect(
        identical(
          tester.widget<MarkdrawEditor>(find.byType(MarkdrawEditor)),
          pageEditor,
        ),
        isTrue,
      );
      expect(
        identical(
          tester.widget<DesktopToolbar>(find.byType(DesktopToolbar)),
          presenceToolbar,
        ),
        isTrue,
      );
      final cursor = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<InteractiveCanvasPainter>()
          .expand((paint) => paint.remoteCollaborators)
          .single;
      expect(cursor.pointer!.x, x);
    }
    await pointer(105, username: 'fixture-renamed');
    expect(
      tester
          .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
          .collaborationParticipants
          .any((badge) => badge.username == 'fixture-renamed'),
      isTrue,
    );
    final viewport = controller.editorState.viewport;
    controller.setViewport(viewport.pan(const Offset(20, 10)));
    await tester.pump();
    final presencePaint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<InteractiveCanvasPainter>()
        .singleWhere((paint) => paint.remoteCollaborators.isNotEmpty);
    expect(presencePaint.viewport, controller.editorState.viewport);
    controller.setViewport(viewport);
    await tester.pump();
    controller.switchTool(ToolType.freedraw);
    final gesture = await tester.startGesture(
      const Offset(650, 400),
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveBy(const Offset(40, 20));
    await tester.pump();
    final remote = MarkdrawController()
      ..loadScene(
        Scene().addElement(
          RectangleElement(
            id: const ElementId('workflow-remote'),
            x: 100,
            y: 100,
            width: 40,
            height: 40,
          ),
        ),
      );
    final elements = List<Map<String, Object?>>.from(
      remote.serializeExcalidrawSceneJson()['elements']! as List,
    );
    remote.dispose();
    await tester.runAsync(
      () => peer.broadcastElements(room: room, elements: elements),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await _drainIo(tester, container);
    expect(
      controller.currentScene.activeElements.whereType<RectangleElement>(),
      hasLength(1),
    );
    expect(_ink(controller), isEmpty, reason: '本地活动笔迹不能被远端合并提前提交');
    // Deliver pre-encrypted packets under the widget clock: a continuous
    // 5ms stream must become visible before the sender stops.
    final burst = (await tester.runAsync(
      () async => [
        for (var version = 2; version <= 7; version++)
          await crypto.encrypt(
            roomKey: room.roomKey,
            plainBytes: CollaborationMessage.sceneUpdate(
              elements: [
                {...elements.single, 'version': version, 'versionNonce': 10},
              ],
            ).toBytes(),
          ),
      ],
    ))!;
    for (var i = 0; i < burst.length; i++) {
      hub.broadcast(
        roomId: room.roomId,
        sender: peerTransport,
        payload: burst[i],
      );
      await tester.pump(const Duration(milliseconds: 5));
      if (i == 4) {
        expect(
          controller.currentScene
              .getElementById(const ElementId('workflow-remote'))!
              .version,
          greaterThan(1),
          reason: '连续入站消息不能不断推迟第一批画布更新',
        );
      }
    }
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      controller.currentScene
          .getElementById(const ElementId('workflow-remote'))!
          .version,
      7,
    );
    final selection = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<InteractiveCanvasPainter>()
        .expand((paint) => paint.remoteCollaborators)
        .single
        .selectionBounds;
    expect(selection.single.bounds, Bounds.fromLTWH(100, 100, 40, 40));
    final wetInk = tester
        .widget<EditorCanvas>(find.byType(EditorCanvas))
        .remoteWetInkStore!;
    const chunk = DecodedLiveInkChunk(
      senderSocketId: 'workflow-peer',
      chunk: LiveInkChunk(
        strokeId: 'workflow-long-remote',
        startIndex: 0,
        points: [LiveInkPoint(x: 100, y: 200), LiveInkPoint(x: 120, y: 220)],
        style: LiveInkStyle(
          brushType: 'ballpoint',
          strokeColor: '#000000',
          strokeWidth: 2,
          opacity: 100,
        ),
      ),
    );
    wetInk.apply(chunk);
    expect(wetInk.strokeCount, 1);
    void verifyHandoff() {
      if (wetInk.strokeCount == 0) {
        expect(
          controller.currentScene.getElementById(
            const ElementId('workflow-long-remote'),
          ),
          isNotNull,
          reason: '正式笔迹进入画布后才清除远端湿墨',
        );
      }
    }

    wetInk.addListener(verifyHandoff);
    final longToolbar = tester.widget<DesktopToolbar>(
      find.byType(DesktopToolbar),
    );
    final imageChecks = local.imageChecks;
    for (final count in [256, 512, 1024, 2048]) {
      final longStroke = FreedrawElement(
        id: const ElementId('workflow-long-remote'),
        x: 100,
        y: 200,
        width: 120,
        height: 40,
        points: [
          for (var i = 0; i < count; i++)
            Point(i * 120 / count, (i % 40).toDouble()),
        ],
        version: count,
        index: 'b1',
      );
      await tester.runAsync(
        () => peer.broadcastElements(
          room: room,
          elements: [
            Map<String, Object?>.from(
              ExcalidrawJsonCodec.elementToJson(longStroke),
            ),
          ],
          latestOnly: true,
        ),
      );
      await _drainIo(tester, container);
      expect(_ink(controller).single.points.length, count);
      expect(
        identical(
          tester.widget<DesktopToolbar>(find.byType(DesktopToolbar)),
          longToolbar,
        ),
        isTrue,
      );
      expect(local.imageChecks, imageChecks);
    }
    expect(wetInk.strokeCount, 0);
    expect(wetInk.apply(chunk).accepted, isFalse, reason: '迟到分片不能复活已完成笔迹');
    wetInk.removeListener(verifyHandoff);
    await gesture.moveBy(const Offset(30, -20));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    await _drainIo(tester, container);
    final stroke = _ink(
      controller,
    ).singleWhere((stroke) => stroke.id.value != 'workflow-long-remote');
    expect(
      received
          .expand((message) => message.elements)
          .any(
            (element) =>
                element['id'] == stroke.id.value &&
                element['isDeleted'] != true,
          ),
      isTrue,
    );
    controller.undo();
    await tester.pump(const Duration(milliseconds: 200));
    await _drainIo(tester, container);
    expect(_ink(controller).single.id.value, 'workflow-long-remote');
    expect(
      received
          .expand((message) => message.elements)
          .any(
            (element) =>
                element['id'] == stroke.id.value &&
                element['isDeleted'] == true,
          ),
      isTrue,
    );
    expect(
      received
          .expand((message) => message.elements)
          .any(
            (element) =>
                element['id'] == 'workflow-long-remote' &&
                element['isDeleted'] == true,
          ),
      isFalse,
    );
    controller.redo();
    await tester.pump(const Duration(milliseconds: 200));
    await _drainIo(tester, container);
    expect(_ink(controller), hasLength(2));
    final localUpdates = received
        .expand((message) => message.elements)
        .where((element) => element['id'] == stroke.id.value)
        .toList();
    final deletion = localUpdates.lastWhere(
      (element) => element['isDeleted'] == true,
    );
    expect(localUpdates.last['isDeleted'], isFalse);
    expect(
      localUpdates.last['version'] as int,
      greaterThan(deletion['version'] as int),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
  });

  test('known_remote_undo_preserves_new_elements', () {
    final controller = MarkdrawController()..switchTool(ToolType.freedraw);
    addTearDown(controller.dispose);
    controller.onPointerDown(
      const PointerDownEvent(
        position: Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        position: Offset(150, 150),
        kind: PointerDeviceKind.stylus,
      ),
    );
    controller.applyRemoteElements([
      RectangleElement(
        id: const ElementId('remote-during-stroke'),
        x: 300,
        y: 300,
        width: 40,
        height: 40,
      ),
    ]);
    controller.onPointerUp(
      const PointerUpEvent(
        position: Offset(150, 150),
        kind: PointerDeviceKind.stylus,
      ),
    );
    controller.undo();
    expect(
      controller.currentScene.activeElements.whereType<RectangleElement>(),
      hasLength(1),
    );
  });
}

class _RemovableRealtimeTransport extends MemoryRealtimeTransport {
  _RemovableRealtimeTransport({required super.hub, required super.socketId});
  final removed = StreamController<String>.broadcast(sync: true);
  final statuses = StreamController<RealtimeConnectionStatus>.broadcast(
    sync: true,
  );
  @override
  Stream<String> get roomRemoved => removed.stream;
  @override
  Stream<RealtimeConnectionStatus> get connectionStatus => statuses.stream;
  Future<void> close() async {
    await removed.close();
    await statuses.close();
  }
}

class _MemberJoinSceneStore extends MemoryEncryptedSceneStore {
  @override
  Future<CollaborationRoomMetadata> joinRoom(CollaborationRoom room) async =>
      CollaborationRoomMetadata(
        roomId: room.roomId,
        role: CollaborationRoomRole.editor,
        ended: false,
      );
}

class _TrackedCollaborationRepository extends CollaborationRepository {
  _TrackedCollaborationRepository({
    required super.transport,
    required super.sceneStore,
  });
  int imageChecks = 0;

  @override
  Future<CollaborationLoadedFilesResult> loadMissingFiles({
    required CollaborationRoom room,
    required Iterable<String> fileIds,
    required Set<String> existingFileIds,
  }) {
    imageChecks++;
    return super.loadMissingFiles(
      room: room,
      fileIds: fileIds,
      existingFileIds: existingFileIds,
    );
  }
}

ProviderContainer _container({
  required _TrackedLibraryRepository library,
  InkRecognitionRepository? recognition,
  CollaborationRepository? collaboration,
  WhiteboardSceneRepository? sceneRepository,
}) {
  final container = ProviderContainer(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(library),
      whiteboardSceneRepositoryProvider.overrideWithValue(
        sceneRepository ?? _TrackedSceneRepository(library),
      ),
      accountViewModelProvider.overrideWith(_GuestAccount.new),
      collaborationRepositoryProvider.overrideWithValue(
        collaboration ?? CollaborationRepository(),
      ),
      if (recognition != null)
        inkRecognitionRepositoryProvider.overrideWithValue(recognition),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<MarkdrawController> _open(
  WidgetTester tester,
  ProviderContainer container,
  NoteItem note, {
  GoRouter? router,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: router == null
          ? MaterialApp(home: WhiteboardPage(noteId: note.id))
          : MaterialApp.router(routerConfig: router),
    ),
  );
  await _drainIo(
    tester,
    container,
    until: () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  expect(find.text('笔记打开失败，请返回后重试'), findsNothing);
  final controller = tester
      .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
      .controller!;
  // Loading the title precedes restoring PDF bounds and decoding its images.
  // Wait for the state being asserted, rather than a fixed wall-clock delay.
  if (note.kind == LibraryFilter.pdf) {
    await _drainIo(
      tester,
      container,
      until: () =>
          controller.contentBounds != null &&
          controller.resolveImages()?.isNotEmpty == true,
    );
  }
  expect(controller.documentName, note.title);
  return controller;
}

Future<void> _drainIo(
  WidgetTester tester,
  ProviderContainer container, {
  bool Function()? until,
}) async {
  final library =
      container.read(libraryRepositoryProvider) as _TrackedLibraryRepository;
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
    // Keep pumping fake microtasks while real SQLite I/O finishes. Awaiting
    // its Future inside runAsync would block those fake-zone continuations.
    if (i >= 9 &&
        library.pendingWrites == 0 &&
        library.pendingSceneUpdates == 0 &&
        (until?.call() ?? true)) {
      return;
    }
  }
  fail(
    '异步流程未完成：metadata=${library.pendingWrites}, '
    'scene=${library.pendingSceneUpdates}, ready=${until?.call() ?? true}',
  );
}

Future<void> _stroke(WidgetTester tester, Offset start) async {
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.stylus,
  );
  await tester.pump(const Duration(milliseconds: 8));
  await gesture.moveBy(const Offset(30, -15));
  await tester.pump(const Duration(milliseconds: 8));
  await gesture.moveBy(const Offset(30, 25));
  await gesture.up();
  await tester.pump();
}

Iterable<FreedrawElement> _ink(MarkdrawController controller) =>
    controller.currentScene.activeElements.whereType<FreedrawElement>();

// Import fills fractional ordering indices; geometry/style/data must survive.
List<Map<Object?, Object?>> _elements(MarkdrawController controller) => [
  for (final element
      in controller.serializeExcalidrawSceneJson()['elements']! as List)
    {
      for (final entry in (element as Map).entries)
        if (entry.key != 'index') entry.key: entry.value,
    },
];

class _GuestAccount extends AccountViewModel {
  @override
  AccountState build() => const AccountState(status: AccountStatus.guest);
}

class _TrackedLibraryRepository extends SqliteLibraryRepository {
  _TrackedLibraryRepository() : super(LocalDatabase.open);

  int pendingWrites = 0;
  int pendingSceneUpdates = 0;
  final deletedNotes = <String>{};

  @override
  Future<void> deleteNotes(List<String> noteIds) async {
    await super.deleteNotes(noteIds);
    deletedNotes.addAll(noteIds);
  }

  @override
  Future<void> touchNote(
    String noteId, {
    Uint8List? coverThumbnailBytes,
    bool clearCoverThumbnail = false,
  }) async {
    pendingWrites++;
    if (pendingSceneUpdates > 0) pendingSceneUpdates--;
    try {
      await super.touchNote(
        noteId,
        coverThumbnailBytes: coverThumbnailBytes,
        clearCoverThumbnail: clearCoverThumbnail,
      );
    } finally {
      pendingWrites--;
    }
  }
}

class _FailingIndexLibrary extends _TrackedLibraryRepository {
  bool failIndex = false;

  @override
  Future<LibraryIndex> loadIndex() async {
    if (failIndex) throw StateError('fixture index unavailable');
    return super.loadIndex();
  }
}

class _TrackedSceneRepository extends SqliteWhiteboardSceneRepository {
  _TrackedSceneRepository(this.library) : super(LocalDatabase.open);

  final _TrackedLibraryRepository library;

  @override
  Future<String> loadScene(String noteId) async {
    // Exceed the old 200 ms idle guess deterministically, even on a fast host.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return super.loadScene(noteId);
  }

  @override
  Future<void> saveScene(String noteId, String content) async {
    // Page saves finish with touchNote after scene I/O and cover encoding.
    // Keep that whole chain pending, including the gap between repositories.
    library.pendingSceneUpdates++;
    try {
      await super.saveScene(noteId, content);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } catch (_) {
      library.pendingSceneUpdates--;
      rethrow;
    }
  }
}

class _FaultySceneRepository extends _TrackedSceneRepository {
  _FaultySceneRepository(super.library);
  int failures = 0;
  int attempts = 0;
  int concurrent = 0;
  int maxConcurrent = 0;
  final gates = <Completer<void>>[];

  @override
  Future<void> saveScene(String noteId, String content) async {
    attempts++;
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    try {
      if (failures > 0) {
        failures--;
        throw StateError('fixture storage unavailable');
      }
      if (gates.isNotEmpty) await gates.removeAt(0).future;
      await super.saveScene(noteId, content);
    } finally {
      concurrent--;
    }
  }
}

Future<void> _waitForSave(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
  }
  expect(ready(), isTrue);
}

class _PendingRecognition extends InkRecognitionRepository {
  _PendingRecognition()
    : super(
        config: const CollaborationConfig(
          serverUrl: 'http://127.0.0.1',
          shareOrigin: 'https://example.invalid',
        ),
      );
  final requests = <InkRecognitionRequest>[];
  final result = Completer<InkRecognitionResult>();

  @override
  Future<InkRecognitionResult> recognize(InkRecognitionRequest request) {
    requests.add(request);
    return result.future;
  }
}
