import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imports a PDF source through the configured renderer', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final handler = MarkdrawFileHandler(
      controller: controller,
      pdfPageRenderer: _FakePdfPageRenderer([
        PdfRenderedPage(
          bytes: await _makePng(0xff00aa00),
          mimeType: 'image/png',
          width: 240,
          height: 320,
          pageNumber: 1,
        ),
      ]),
    );

    await handler.importPdfSource(
      PdfImportSource(name: 'paper.pdf', bytes: Uint8List.fromList([1, 2, 3])),
      const Size(800, 600),
    );

    expect(
      controller.editorState.scene.activeElements.whereType<ImageElement>(),
      hasLength(1),
    );
    expect(controller.editorState.scene.files, hasLength(1));
  });
}

class _FakePdfPageRenderer implements PdfPageRenderer {
  _FakePdfPageRenderer(this.pages);

  final List<PdfRenderedPage> pages;

  @override
  Future<List<PdfRenderedPage>> render(
    PdfImportSource source,
    PdfRenderOptions options,
  ) async {
    return pages;
  }
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
