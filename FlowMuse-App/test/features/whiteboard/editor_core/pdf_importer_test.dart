import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'renders a PDF source and imports its pages into the controller',
    () async {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      final renderer = _FakePdfPageRenderer([
        PdfRenderedPage(
          bytes: await _makePng(0xff0055ff),
          mimeType: 'image/png',
          width: 320,
          height: 240,
          pageNumber: 1,
        ),
      ]);
      final importer = PdfImporter(renderer: renderer);
      final source = PdfImportSource(
        name: 'slides.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await importer.importPdf(
        source: source,
        controller: controller,
        canvasSize: const Size(900, 700),
      );

      expect(renderer.sources, [source]);
      expect(
        controller.editorState.scene.activeElements.whereType<ImageElement>(),
        hasLength(1),
      );
      expect(controller.editorState.scene.files, hasLength(1));
    },
  );

  test(
    'does not mutate the controller when renderer returns no pages',
    () async {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      final importer = PdfImporter(renderer: _FakePdfPageRenderer(const []));

      await importer.importPdf(
        source: PdfImportSource(
          name: 'empty.pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        controller: controller,
        canvasSize: const Size(900, 700),
      );

      expect(controller.editorState.scene.activeElements, isEmpty);
      expect(controller.editorState.scene.files, isEmpty);
    },
  );
}

class _FakePdfPageRenderer implements PdfPageRenderer {
  _FakePdfPageRenderer(this.pages);

  final List<PdfRenderedPage> pages;
  final sources = <PdfImportSource>[];

  @override
  Future<List<PdfRenderedPage>> render(
    PdfImportSource source,
    PdfRenderOptions options,
  ) async {
    sources.add(source);
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
