import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imports rendered PDF pages as stacked image elements', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final firstPageBytes = await _makePng(0xffff0000);
    final secondPageBytes = await _makePng(0xff000000);

    await controller.importPdfPages(
      [
        PdfRenderedPage(
          bytes: firstPageBytes,
          mimeType: 'image/png',
          width: 400,
          height: 300,
          pageNumber: 1,
        ),
        PdfRenderedPage(
          bytes: secondPageBytes,
          mimeType: 'image/png',
          width: 400,
          height: 200,
          pageNumber: 2,
        ),
      ],
      const Size(1000, 800),
      documentName: 'lecture.pdf',
    );

    final images = controller.editorState.scene.activeElements
        .whereType<ImageElement>()
        .toList();

    expect(images, hasLength(2));
    expect(controller.editorState.scene.files, hasLength(2));
    expect(images[0].width, 400);
    expect(images[0].height, 300);
    expect(images[1].width, 400);
    expect(images[1].height, 200);
    expect(images[1].y, greaterThan(images[0].y + images[0].height));
    expect(controller.editorState.selectedIds, isEmpty);
  });

  test('ignores empty rendered PDF page list', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);

    await controller.importPdfPages(
      const [],
      const Size(1000, 800),
      documentName: 'empty.pdf',
    );

    expect(controller.editorState.scene.activeElements, isEmpty);
    expect(controller.editorState.scene.files, isEmpty);
    expect(controller.editorState.selectedIds, isEmpty);
  });
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
