import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadFromContent 后 imageCache 异步解码能完成', () async {
    // 1. 构造含 3 张图片的场景 JSON
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final renderer = _FakeRenderer([
      PdfRenderedPage(
        bytes: await _makePng(0xff0000ff),
        mimeType: 'image/png',
        width: 100,
        height: 100,
        pageNumber: 1,
      ),
      PdfRenderedPage(
        bytes: await _makePng(0xff00ff00),
        mimeType: 'image/png',
        width: 100,
        height: 100,
        pageNumber: 2,
      ),
      PdfRenderedPage(
        bytes: await _makePng(0xffff0000),
        mimeType: 'image/png',
        width: 100,
        height: 100,
        pageNumber: 3,
      ),
    ]);
    await PdfImporter(renderer: renderer).importPdf(
      source: PdfImportSource(name: 't.pdf', bytes: Uint8List.fromList([1])),
      controller: controller,
      canvasSize: const Size(800, 600),
    );
    final json = controller.serializeScene(format: DocumentFormat.excalidraw);

    // 2. 新 controller 加载
    final controller2 = MarkdrawController();
    addTearDown(controller2.dispose);
    controller2.loadFromContent(json, 'test.excalidraw');

    // 3. 手动触发 resolveImages（启动异步解码）
    controller2.resolveImages();

    // 4. 轮询等待解码完成（不用 pumpAndSettle）
    var decoded = 0;
    for (var i = 0; i < 100; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      // 触发微任务/事件循环
      decoded = controller2.imageCache.length;
      if (decoded >= 3) break;
    }
    // 5. 再次 resolveImages 看结果
    controller2.resolveImages();

    expect(decoded, 3, reason: '3 张图片应全部解码完成,实际 $decoded');
  });
}

class _FakeRenderer implements PdfPageRenderer {
  _FakeRenderer(this.pages);
  final List<PdfRenderedPage> pages;
  @override
  Future<List<PdfRenderedPage>> render(
    PdfImportSource source,
    PdfRenderOptions options,
  ) async => pages;
}

Future<Uint8List> _makePng(int argbColor) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = Color(argbColor),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}
