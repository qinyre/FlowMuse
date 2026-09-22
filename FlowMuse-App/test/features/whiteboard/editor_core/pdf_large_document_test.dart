import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rendering/canvas_spy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('区域预热复核最终缓存，超容量时报告缺图', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final file = ImageFile(mimeType: 'image/png', bytes: await _png());
    for (var i = 0; i < 52; i++) {
      controller.applyResult(
        CompoundResult([
          AddFileResult(fileId: '$i', file: file),
          AddElementResult(
            ImageElement(
              id: ElementId('$i'),
              x: 0,
              y: 0,
              width: 10,
              height: 10,
              fileId: '$i',
              mimeType: 'image/png',
            ),
          ),
        ]),
      );
    }
    expect(
      await controller.prewarmRegionImages(
        const ui.Rect.fromLTWH(0, 0, 20, 20),
      ),
      2,
    );
  });

  test('快速跳页丢弃未开始请求，可见集合超过条目预算也不频闪', () async {
    final cache = ImageElementCache(maxSize: 1);
    addTearDown(cache.dispose);
    final file = ImageFile(mimeType: 'image/png', bytes: await _png());
    cache.resolveVisible({for (var i = 0; i < 100; i++) '$i': file});
    cache.resolveVisible({'98': file, '99': file});
    for (var i = 0; i < 100 && !cache.contains('99'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(cache.length, 2);
    expect(cache.contains('0'), isFalse);
    expect(cache.contains('50'), isFalse);
    final first = cache.peek('98');
    final second = cache.peek('99');
    for (var i = 0; i < 10; i++) {
      expect(cache.resolveVisible({'98': file, '99': file}), {
        '98': same(first),
        '99': same(second),
      });
    }
    cache.resolveVisible({'99': file});
    expect(cache.length, 1);
    expect(cache.peek('99'), same(second));
  });

  test('按字节驱逐离屏图片，同 ID 替换不泄漏图片或重复 LRU', () async {
    final cache = ImageElementCache(maxBytes: 128);
    addTearDown(cache.dispose);
    final file = ImageFile(mimeType: 'image/png', bytes: await _png());
    await cache.decodeAndWait('a', file);
    cache.resolveVisible({'a': file});
    final first = cache.peek('a')!;
    await cache.decodeAndWait('b', file);
    await cache.decodeAndWait('c', file);
    expect(cache.sizeBytes, 128);
    expect(cache.contains('b'), isFalse);
    expect(cache.peek('a'), same(first));
    final replacement = first.clone();
    cache.putImage('a', replacement);
    expect(first.debugDisposed, isTrue);
    expect(cache.length, 2);
    expect(cache.sizeBytes, 128);
    cache.putImage('a', replacement);
    expect(cache.sizeBytes, 128);
    cache.dispose();
    expect(replacement.debugDisposed, isTrue);
    expect(cache.resolveVisible({'a': file}), isNull);
  });

  test('200 页文档只解码首屏附近图片，重复重绘不触发缓存轮换', () async {
    final controller = MarkdrawController()
      ..canvasSize = const ui.Size(800, 600);
    addTearDown(controller.dispose);
    final file = ImageFile(mimeType: 'image/png', bytes: await _png());
    var scene = Scene();
    for (var i = 0; i < 200; i++) {
      scene = scene
          .addFile('pdf-$i', file)
          .addElement(
            ImageElement(
              id: ElementId('image-$i'),
              x: 0,
              y: i * 2096.0,
              width: 1400,
              height: 2000,
              fileId: 'pdf-$i',
              mimeType: 'image/png',
            ),
          );
    }
    controller.loadScene(scene);
    for (var frame = 0; frame < 40; frame++) {
      controller.resolveImages();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.imageCache.length, lessThanOrEqualTo(3));
    final first = controller.imageCache.peek('pdf-0');
    expect(first, isNotNull);
    for (var frame = 0; frame < 20; frame++) {
      expect(controller.resolveImages()?['pdf-0'], same(first));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    controller.setViewport(const ViewportState(offset: ui.Offset(0, 209600)));
    for (var frame = 0; frame < 40; frame++) {
      controller.resolveImages();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.imageCache.contains('pdf-100'), isTrue);
    expect(controller.imageCache.contains('pdf-50'), isFalse);
    expect(controller.imageCache.length, lessThanOrEqualTo(6));
    expect(controller.resolveImages(), isNot(contains('pdf-0')));
  });

  for (final flow in CanvasPageFlow.values) {
    test('200 页 ${flow.name} 首屏绘制量与像素等同单页', () async {
      Future<(int, Uint8List)> paint(int count) async {
        final layout = CanvasLayout(
          type: CanvasLayoutType.paged,
          pageFlow: flow,
          pages: List.generate(
            count,
            (i) => CanvasPage(
              id: 'page-$i',
              index: i,
              bounds: CanvasLayout.pageBoundsForIndex(
                index: i,
                pageSize: const ui.Size(800, 1000),
                pageFlow: flow,
              ),
              template: CanvasPageTemplate.grid,
            ),
          ),
        );
        final recorder = ui.PictureRecorder();
        final canvas = SpyCanvas(ui.Canvas(recorder));
        StaticCanvasPainter(
          scene: Scene(),
          layout: layout,
          adapter: RoughCanvasAdapter(),
          viewport: const ViewportState(),
        ).paint(canvas, const ui.Size(400, 300));
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 300);
        final bytes = (await image.toByteData())!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        return (canvas.drawCallCount, bytes);
      }

      final single = await paint(1);
      final large = await paint(200);
      expect(large.$1, single.$1, reason: '屏幕外页面不应产生绘制指令');
      expect(large.$2, orderedEquals(single.$2));
    });
  }
}

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff225588), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}
