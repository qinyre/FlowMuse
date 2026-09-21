import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('静态缓存 miss/hit 与直绘逐像素相同，背景、叠色、视口和聚焦及时失效', () async {
    await PencilShader.init();
    addTearDown(PencilShader.resetForTesting);
    final adapter = RoughCanvasAdapter();
    final cache = StaticCanvasRenderCache();
    addTearDown(cache.dispose);
    final highlighter = FreedrawElement(
      id: ElementId('highlighter'),
      x: 25,
      y: 50,
      width: 120,
      height: 1,
      points: const [Point.zero, Point(120, 0)],
      pressures: const [0.7, 0.7],
      simulatePressure: false,
      strokeWidth: 12,
      strokeColor: '#ffee00',
      customData: customDataWithFreedrawRender(null, BrushType.highlighter),
    );
    final pencil = highlighter.copyWith(
      id: ElementId('pencil'),
      y: 60,
      strokeColor: '#121212',
      strokeWidth: 6,
      customData: customDataWithFreedrawRender(
        null,
        BrushType.pencil,
        renderVersion: BrushRenderVersion.naturalMediaV2,
      ),
    );
    final imageRecorder = ui.PictureRecorder();
    ui.Canvas(
      imageRecorder,
    ).drawColor(const ui.Color(0xff5684aa), ui.BlendMode.src);
    final imagePicture = imageRecorder.endRecording();
    final image = await imagePicture.toImage(180, 120);
    addTearDown(image.dispose);
    imagePicture.dispose();
    final images = {'page': image};
    final scene = Scene()
        .addElement(
          ImageElement(
            id: ElementId('image'),
            x: 0,
            y: 0,
            width: 180,
            height: 120,
            fileId: 'page',
          ),
        )
        .addElement(pencil)
        .addElement(
          pencil.copyWith(
            id: ElementId('classic-pencil'),
            y: 70,
            customData: customDataWithFreedrawRender(null, BrushType.pencil),
          ),
        )
        .addElement(highlighter);
    final updated = scene.removeElement(pencil.id);

    Future<Uint8List> raster(StaticCanvasPainter painter, ui.Size size) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xfff8f6ef), ui.BlendMode.src);
      canvas.translate(3, 7);
      canvas.scale(1.25, 1.5);
      canvas.rotate(0.1);
      painter.paint(canvas, size);
      // Same Canvas: active highlighter must darken static text/image/ink.
      ElementRenderer.render(canvas, highlighter.copyWith(y: 54), adapter);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final bytes = Uint8List.fromList(
        (await rendered.toByteData())!.buffer.asUint8List(),
      );
      rendered.dispose();
      picture.dispose();
      return bytes;
    }

    for (final currentScene in [scene, updated]) {
      for (final zoom in [0.25, 1.0, 4.0]) {
        for (final focus in [null, 'test-user']) {
          for (final size in [
            const ui.Size(200, 140),
            const ui.Size(220, 160),
          ]) {
            StaticCanvasPainter painter(
              StaticCanvasRenderCache? reuse, {
              Bounds? clip,
            }) => StaticCanvasPainter(
              scene: currentScene,
              adapter: adapter,
              viewport: ViewportState(
                zoom: zoom,
                offset: const ui.Offset(2, 3),
              ),
              resolvedImages: images,
              gridSize: 25,
              contentBounds: clip ?? Bounds.fromLTWH(10, 10, 170, 110),
              focusedCreatorKey: focus,
              renderCache: reuse,
            );
            final expected = await raster(painter(null), size);
            expect(
              await raster(painter(cache), size),
              expected,
              reason: 'cache miss',
            );
            expect(
              await raster(painter(cache), size),
              expected,
              reason: 'cache hit',
            );
            final clip = Bounds.fromLTWH(30, 30, 70, 60);
            expect(
              await raster(painter(cache, clip: clip), size),
              await raster(painter(null, clip: clip), size),
              reason: 'clip invalidation',
            );
          }
        }
      }
    }
  });
}
