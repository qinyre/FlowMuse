import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pdf_note_consumer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scene = Scene()
      .addElement(
        ImageElement(
          id: const ElementId('page-2-image'),
          x: 10,
          y: 824,
          width: 400,
          height: 800,
          fileId: 'page-2',
          mimeType: 'image/png',
          customData: CanvasLayout.pdfBackgroundCustomData('page-2'),
        ),
      )
      .addElement(
        ImageElement(
          id: const ElementId('page-1-image'),
          x: 10,
          y: 0,
          width: 400,
          height: 800,
          fileId: 'page-1',
          mimeType: 'image/png',
          customData: CanvasLayout.pdfBackgroundCustomData('page-1'),
        ),
      );

  test('computes ordered PDF pages and their union bounds', () {
    final pages = PdfNoteConsumer.pdfBackgroundPages(scene);
    final bounds = PdfNoteConsumer.pdfBackgroundBounds(scene);

    expect(pages.map((page) => page.fileId), ['page-1', 'page-2']);
    expect(bounds?.left, 10);
    expect(bounds?.top, 0);
    expect(bounds?.right, 410);
    expect(bounds?.bottom, 1624);
  });

  test('fits the first PDF page to the viewport', () {
    final viewport = PdfNoteConsumer.fitFirstPageViewport(
      scene,
      const Size(400, 600),
    );

    expect(viewport.offset, const Offset(10, 0));
    expect(viewport.zoom, closeTo(1, 0.001));
  });
}
