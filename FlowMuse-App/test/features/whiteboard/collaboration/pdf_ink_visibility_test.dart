import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/whiteboard_collaboration_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final pageCount in [1, 220]) {
    test('$pageCount 页 PDF 收到对端一笔后，本机四笔和对端笔迹均可见、可选且可继续写', () async {
      // Given: 正常本地恢复生成字母索引，两端继续在第一页协作。
      final local = MarkdrawController();
      final peer = MarkdrawController();
      addTearDown(local.dispose);
      addTearDown(peer.dispose);
      var scene = Scene();
      for (var i = 0; i < pageCount; i++) {
        scene = scene.addElement(
          ImageElement(
            id: ElementId('pdf-$i'),
            x: 0,
            y: i * 276.0,
            width: 240,
            height: 180,
            fileId: 'page',
            locked: true,
            customData: CanvasLayout.pdfBackgroundCustomData('page-$i'),
          ),
        );
      }
      local.loadScene(scene.addElement(_ink('old', 25)));
      local.loadFromContent(
        local.serializeScene(format: DocumentFormat.excalidraw),
        'note.excalidraw',
      );
      final localAdapter = WhiteboardCollaborationAdapter(local);
      final peerAdapter = WhiteboardCollaborationAdapter(peer);
      final baseline = localAdapter.currentScene();
      peerAdapter.applyRemoteScene(baseline);
      final room = CollaborationRoom.newRoom(crypto: CollaborationCrypto());
      final store = MemoryEncryptedSceneStore();
      await store.createRoom(
        room: room,
        scene: baseline,
        ownerKeyHash: 'fixture',
      );
      final repository = CollaborationRepository(
        sceneStore: store,
        transport: MemoryRealtimeTransport(
          hub: MemoryRealtimeRoomHub(),
          socketId: 'fixture',
        ),
      );
      addTearDown(repository.stop);
      await repository.joinRoom(room: room, localScene: baseline);
      final image = await _whitePage();
      addTearDown(image.dispose);
      for (var i = 0; i < 4; i++) {
        local.applyResult(AddElementResult(_ink('local-$i', 50 + i * 20.0)));
      }
      final localInk = local.currentScene.elements
          .whereType<FreedrawElement>()
          .where((e) => e.index == null)
          .toList();
      await repository.broadcastElements(
        room: room,
        elements: localAdapter.serializeElements(localInk),
      );
      final before = await _raster(local.currentScene, image);

      // When: 与页面实际入口一致，只接收一笔远端增量。
      peer.applyResult(AddElementResult(_ink('remote', 130)));
      final changes = repository.reconcileRemoteElements(
        remoteElements: peerAdapter.serializeElements([
          peer.currentScene.getElementById(const ElementId('remote'))!,
        ]),
      );
      localAdapter.applyRemoteElements(changes);
      peerAdapter.applyRemoteElements(changes);

      // Then: 本机四笔同时补号但不沉底，两端静态像素一致且可框选。
      expect(changes, hasLength(5));
      final pdfIndex = local.currentScene
          .getElementById(const ElementId('pdf-0'))!
          .index!;
      expect(
        changes.every((e) => (e['index'] as String).compareTo(pdfIndex) > 0),
        isTrue,
      );
      for (final controller in [local, peer]) {
        final pixels = await _raster(controller.currentScene, image);
        for (final y in [25, 50, 70, 90, 110, 130]) {
          expect(_blackPixels(pixels, y), greaterThan(100));
        }
        expect(_blackPixels(pixels, 50), _blackPixels(before, 50));
        controller.setViewport(const ViewportState());
        controller.switchTool(ToolType.select);
        controller.onPointerDown(
          const PointerDownEvent(
            position: ui.Offset(10, 40),
            kind: PointerDeviceKind.mouse,
          ),
        );
        controller.onPointerMove(
          const PointerMoveEvent(
            position: ui.Offset(220, 140),
            delta: ui.Offset(210, 100),
            kind: PointerDeviceKind.mouse,
          ),
        );
        controller.onPointerUp(
          const PointerUpEvent(
            position: ui.Offset(220, 140),
            kind: PointerDeviceKind.mouse,
          ),
        );
        expect(
          controller.editorState.selectedIds,
          containsAll([
            for (var i = 0; i < 4; i++) ElementId('local-$i'),
            const ElementId('remote'),
          ]),
        );
      }
      expect(
        await _raster(local.currentScene, image),
        await _raster(peer.currentScene, image),
      );
      local.applyResult(SetSelectionResult({}));
      local.applyResult(AddElementResult(_ink('next', 155)));
      await repository.broadcastElements(
        room: room,
        elements: localAdapter.serializeElements([
          local.currentScene.getElementById(const ElementId('next'))!,
        ]),
      );
      localAdapter.applyRemoteElements(
        repository.reconcileRemoteElements(remoteElements: []),
      );
      expect(
        _blackPixels(await _raster(local.currentScene, image), 155),
        greaterThan(100),
      );
      local.loadFromContent(
        local.serializeScene(format: DocumentFormat.excalidraw),
        'note.excalidraw',
      );
      expect(
        _blackPixels(await _raster(local.currentScene, image), 155),
        greaterThan(100),
      );
    });
  }
}

FreedrawElement _ink(String id, double y) => FreedrawElement(
  id: ElementId(id),
  x: 30,
  y: y,
  width: 160,
  height: 1,
  points: const [Point.zero, Point(160, 0)],
  strokeWidth: 6,
);

Future<ui.Image> _whitePage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  picture.dispose();
  return image;
}

Future<Uint8List> _raster(Scene scene, ui.Image image) async {
  final recorder = ui.PictureRecorder();
  StaticCanvasPainter(
    scene: scene,
    adapter: RoughCanvasAdapter(),
    viewport: const ViewportState(),
    resolvedImages: {'page': image},
  ).paint(ui.Canvas(recorder), const ui.Size(240, 180));
  final picture = recorder.endRecording();
  final raster = await picture.toImage(240, 180);
  final data = (await raster.toByteData())!;
  final pixels = Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  raster.dispose();
  picture.dispose();
  return pixels;
}

int _blackPixels(Uint8List pixels, int centerY) {
  var count = 0;
  for (var y = centerY - 5; y < centerY + 5; y++) {
    for (var x = 20; x < 210; x++) {
      final at = (y * 240 + x) * 4;
      if (pixels[at] < 80 &&
          pixels[at + 1] < 80 &&
          pixels[at + 2] < 80 &&
          pixels[at + 3] > 200) {
        count++;
      }
    }
  }
  return count;
}
