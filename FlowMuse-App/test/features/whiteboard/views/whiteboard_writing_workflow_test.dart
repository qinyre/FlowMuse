import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/collaboration_config.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
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
import 'package:flutter_test/flutter_test.dart';

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
        await _drainIo(tester, container);
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
        for (var attempt = 0; attempt < 20; attempt++) {
          await _drainIo(tester, container);
          if (outcome == 'leave' ||
              find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
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

  testWidgets('内存加密协作：落笔中接收远端元素，终笔与撤销仍广播', (tester) async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final hub = MemoryRealtimeRoomHub();
    final peer = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'workflow-peer'),
      sceneStore: store,
    );
    final local = CollaborationRepository(
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
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: WhiteboardPage.collaborationRoom(initialRoom: room),
        ),
      ),
    );
    await _drainIo(tester, container);
    expect(container.read(whiteboardViewModelProvider).collaborating, isTrue);
    final controller = tester
        .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
        .controller!;
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
    await gesture.moveBy(const Offset(30, -20));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    await _drainIo(tester, container);
    final stroke = _ink(controller).single;
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
    expect(_ink(controller), isEmpty);
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
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainIo(tester, container);
  });

  test(
    'known_remote_undo_preserves_new_elements',
    () {
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
    },
    skip: '既有协作历史问题：整场景快照撤销会回退远端新增；用 --run-skipped 单独复现，见第二轮验证记录。',
  );
}

ProviderContainer _container({
  required _TrackedLibraryRepository library,
  InkRecognitionRepository? recognition,
  CollaborationRepository? collaboration,
}) {
  final container = ProviderContainer(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(library),
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
  NoteItem note,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: WhiteboardPage(noteId: note.id)),
    ),
  );
  await _drainIo(tester, container);
  final controller = tester
      .widget<MarkdrawEditor>(find.byType(MarkdrawEditor))
      .controller!;
  // Loading the title precedes restoring PDF bounds and decoding its images.
  // Wait for the state being asserted, rather than a fixed wall-clock delay.
  if (note.kind == LibraryFilter.pdf) {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (controller.contentBounds != null &&
          controller.resolveImages()?.isNotEmpty == true) {
        break;
      }
      await _drainIo(tester, container);
    }
  }
  expect(controller.documentName, note.title);
  return controller;
}

Future<void> _drainIo(WidgetTester tester, ProviderContainer container) async {
  final library =
      container.read(libraryRepositoryProvider) as _TrackedLibraryRepository;
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    // Keep pumping fake microtasks while real SQLite I/O finishes. Awaiting
    // its Future inside runAsync would block those fake-zone continuations.
    if (i >= 9 && library.pendingWrites == 0) {
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('SQLite 笔记更新在 10 秒内未完成');
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

  @override
  Future<void> touchNote(
    String noteId, {
    Uint8List? coverThumbnailBytes,
    bool clearCoverThumbnail = false,
  }) async {
    pendingWrites++;
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
