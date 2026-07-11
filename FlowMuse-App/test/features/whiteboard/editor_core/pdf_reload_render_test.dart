import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('加载含 3 张图片的场景后图片缓存能解码', (tester) async {
    // 1. 先导入 3 页 PDF,拿到场景 JSON
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

    // 2. 模拟第二次打开:新建 controller,loadFromContent
    final controller2 = MarkdrawController();
    addTearDown(controller2.dispose);
    controller2.loadFromContent(json, 'test.excalidraw');

    // 3. 调 resolveImages 触发异步解码
    controller2.resolveImages();

    // 5. 等待异步解码完成
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(controller2.editorState.scene.files.length, 3);
    expect(
      controller2.imageCache.length,
      3,
      reason: '异步解码后图片缓存应有 3 张,实际 ${controller2.imageCache.length}',
    );
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
