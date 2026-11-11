import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/page_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('历史错误索引的 PDF 始终在批注下方，普通插图仍在前景，存储顺序不变', () async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final scene = controller.currentScene;
    expect(scene.orderedElements.map((e) => e.id.value), [
      'illustration',
      'annotation',
      'pdf',
    ]);
    expect(scene.paintOrderedElements.map((e) => e.id.value), [
      'pdf',
      'annotation',
      'illustration',
    ]);
    expect(
      scene.getElementAtPoint(const Point(100, 90))?.id,
      const ElementId('annotation'),
    );
    expect(
      scene.getElementAtPoint(const Point(10, 10))?.id,
      const ElementId('illustration'),
    );
    final json = controller.serializeExcalidrawSceneJson();
    expect((json['elements'] as List).map((e) => (e as Map)['index']), [
      '00000000',
      '00000001',
      'VV',
    ]);

    final svg = SvgExporter.export(scene, embedMarkdraw: false);
    expect(svg.indexOf('<image '), lessThan(svg.indexOf('<path ')));
    expect(svg.lastIndexOf('<image '), greaterThan(svg.lastIndexOf('<path ')));
    final png = (await controller.exportRegionPng(
      const ui.Rect.fromLTWH(0, 0, 240, 180),
      maxLongestSide: 240,
    ))!;
    expect(await _pixel(png), (255, 0, 0));
    expect(await _pixel(png, xFraction: 10 / 240, yFraction: 10 / 180), (
      0,
      0,
      255,
    ));
  });

  test('错误索引笔迹在 PNG、封面、页面缩略图及 PDF 导出中保持可见', () async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    expect(
      await _pixel(
        (await controller.exportPng(scale: 1, selectedOnly: false))!,
      ),
      (255, 0, 0),
    );
    expect(
      await _pixel(
        (await controller.exportCoverThumbnail(
          outputSize: const ui.Size(240, 180),
        ))!,
      ),
      (255, 0, 0),
    );
    final thumbnail = (await renderPageThumbnail(
      scene: controller.currentScene,
      layout: controller.layout,
      page: controller.layout.pages.first,
      background: '#ffffff',
      shouldContinue: () => true,
      longestSide: 240,
    ))!;
    try {
      final rgba = (await thumbnail.image.toByteData())!;
      final at =
          ((thumbnail.image.height ~/ 2) * thumbnail.image.width +
              thumbnail.image.width ~/ 2) *
          4;
      expect(
        (rgba.getUint8(at), rgba.getUint8(at + 1), rgba.getUint8(at + 2)),
        (255, 0, 0),
      );
    } finally {
      thumbnail.dispose();
    }
    // PDF 每页嵌入 JPEG；解码实际导出图像检查批注像素，避免只检查 PDF 头。
    final pdf = (await controller.exportPdf())!;
    final start = _jpegMarker(pdf, 0xd8, 0);
    final end = _jpegMarker(pdf, 0xd9, start + 2);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final jpeg = img.decodeJpg(pdf.sublist(start, end + 2))!;
    final pixel = jpeg.getPixel(jpeg.width ~/ 2, jpeg.height ~/ 2);
    expect(pixel.r, greaterThan(200));
    expect(pixel.g, lessThan(40));
    expect(pixel.b, lessThan(40));
  });

  test('错误索引场景保存重开与新增内容撤销重做不会再次遮挡批注', () async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    controller.loadFromContent(
      controller.serializeScene(format: DocumentFormat.excalidraw),
      'note.excalidraw',
    );
    await controller.prewarmRegionImages(
      const ui.Rect.fromLTWH(0, 0, 240, 180),
    );
    Future<(int, int, int)> center() async => _pixel(
      (await controller.exportRegionPng(
        const ui.Rect.fromLTWH(0, 0, 240, 180),
        maxLongestSide: 240,
      ))!,
    );
    expect(await center(), (255, 0, 0));
    controller.pushHistory();
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('new'),
          x: 80,
          y: 60,
          width: 80,
          height: 60,
          backgroundColor: '#00ff00',
          strokeColor: '#00ff00',
          roughness: 0,
        ),
      ),
    );
    expect(await center(), (0, 255, 0));
    controller.undo();
    expect(await center(), (255, 0, 0));
    controller.redo();
    expect(await center(), (0, 255, 0));
  });
}

Future<MarkdrawController> _controller() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  final controller = MarkdrawController();
  controller.loadScene(
    Scene()
        .addFile('page', ImageFile(mimeType: 'image/png', bytes: bytes))
        .addElement(
          ImageElement(
            id: const ElementId('pdf'),
            x: 0,
            y: 0,
            width: 240,
            height: 180,
            fileId: 'page',
            index: 'VV',
            locked: true,
            customData: CanvasLayout.pdfBackgroundCustomData('page-1'),
          ),
        )
        .addElement(
          RectangleElement(
            id: const ElementId('annotation'),
            x: 40,
            y: 40,
            width: 160,
            height: 100,
            backgroundColor: '#ff0000',
            strokeColor: '#ff0000',
            roughness: 0,
            index: '00000001',
            customData: CanvasLayout.elementCustomData('page-1'),
          ),
        )
        .addElement(
          ImageElement(
            id: const ElementId('illustration'),
            x: 0,
            y: 0,
            width: 20,
            height: 20,
            fileId: 'blue',
            index: '00000000',
          ),
        ),
  );
  final blueRecorder = ui.PictureRecorder();
  ui.Canvas(
    blueRecorder,
  ).drawColor(const ui.Color(0xff0000ff), ui.BlendMode.src);
  final bluePicture = blueRecorder.endRecording();
  final blue = await bluePicture.toImage(4, 4);
  final blueBytes = (await blue.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  blue.dispose();
  bluePicture.dispose();
  controller.applyResult(
    AddFileResult(
      fileId: 'blue',
      file: ImageFile(mimeType: 'image/png', bytes: blueBytes),
    ),
  );
  await controller.prewarmRegionImages(const ui.Rect.fromLTWH(0, 0, 240, 180));
  return controller;
}

Future<(int, int, int)> _pixel(
  Uint8List png, {
  double xFraction = 0.5,
  double yFraction = 0.5,
}) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  try {
    final data = (await image.toByteData())!;
    final at =
        ((image.height * yFraction).floor() * image.width +
            (image.width * xFraction).floor()) *
        4;
    return (data.getUint8(at), data.getUint8(at + 1), data.getUint8(at + 2));
  } finally {
    image.dispose();
    codec.dispose();
  }
}

int _jpegMarker(Uint8List bytes, int marker, int start) {
  for (var i = start; i < bytes.length - 1; i++) {
    if (bytes[i] == 0xff && bytes[i + 1] == marker) return i;
  }
  return -1;
}
