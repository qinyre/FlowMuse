import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('多页 PDF 序列化往返后 files 完整保留', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final renderer = _FakePdfPageRenderer([
      PdfRenderedPage(
        bytes: await _makePng(0xff0000ff),
        mimeType: 'image/png',
        width: 320,
        height: 240,
        pageNumber: 1,
      ),
      PdfRenderedPage(
        bytes: await _makePng(0xff00ff00),
        mimeType: 'image/png',
        width: 320,
        height: 240,
        pageNumber: 2,
      ),
      PdfRenderedPage(
        bytes: await _makePng(0xffff0000),
        mimeType: 'image/png',
        width: 320,
        height: 240,
        pageNumber: 3,
      ),
    ]);
    final importer = PdfImporter(renderer: renderer);
    await importer.importPdf(
      source: PdfImportSource(
        name: 'multi.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      controller: controller,
      canvasSize: const Size(900, 700),
    );

    final imageElements = controller.editorState.scene.activeElements
        .whereType<ImageElement>()
        .toList();
    expect(imageElements, hasLength(3), reason: '应导入 3 页');
    expect(
      controller.editorState.scene.files,
      hasLength(3),
      reason: '应有 3 个图片文件',
    );

    // 序列化
    final json = controller.serializeScene(format: DocumentFormat.excalidraw);

    // 反序列化
    final parsed = ExcalidrawJsonCodec.parse(json);

    final restoredScene = SceneDocumentConverter.documentToScene(parsed.value);
    final restoredImages = restoredScene.activeElements
        .whereType<ImageElement>()
        .toList();

    expect(parsed.value.files.length, 3, reason: '反序列化后应有 3 个文件');
    expect(restoredImages, hasLength(3), reason: '反序列化后应有 3 个图片元素');
    for (final img in restoredImages) {
      expect(
        restoredScene.files.containsKey(img.fileId),
        true,
        reason: 'fileId ${img.fileId} 在 files 中缺失',
      );
    }
  });
}

class _FakePdfPageRenderer implements PdfPageRenderer {
  _FakePdfPageRenderer(this.pages);
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
