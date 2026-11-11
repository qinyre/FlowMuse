import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('多页 PDF 导出保留阅读顺序、混合方向和已提交批注', () async {
    final controller = MarkdrawController()
      ..setLayout(
        const CanvasLayout(
          type: CanvasLayoutType.paged,
          pageFlow: CanvasPageFlow.rightToLeft,
        ),
      );
    addTearDown(controller.dispose);
    await controller.importPdfPages(
      [
        PdfRenderedPage(
          bytes: await _background(const ui.Color(0xffffd6a5)),
          mimeType: 'image/png',
          width: 600,
          height: 800,
          pageNumber: 1,
        ),
        PdfRenderedPage(
          bytes: await _background(const ui.Color(0xffa0c4ff)),
          mimeType: 'image/png',
          width: 1000,
          height: 500,
          pageNumber: 2,
        ),
      ],
      const ui.Size(1000, 800),
      asBackground: true,
    );
    final second = controller.layout.pages.last;
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('annotation'),
          x: second.bounds.left + 200,
          y: second.bounds.top + 100,
          width: 300,
          height: 200,
          backgroundColor: '#20603a',
          strokeColor: '#20603a',
          fillStyle: FillStyle.solid,
          roughness: 0,
          customData: CanvasLayout.elementCustomData(second.id),
        ),
      ),
    );
    final progress = <(int, int)>[];
    final bytes = await controller.exportPdf(
      onProgress: (completed, total) => progress.add((completed, total)),
    );
    final pdf = latin1.decode(bytes!);
    expect(pdf, startsWith('%PDF-'));
    expect(progress, [(0, 2), (1, 2), (2, 2)]);
    final sizes = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)')
        .allMatches(pdf)
        .map((m) => (double.parse(m[1]!), double.parse(m[2]!)))
        .toList();
    expect(sizes, hasLength(2));
    expect(sizes.first.$1 / sizes.first.$2, closeTo(0.75, 0.001));
    expect(sizes.last.$1 / sizes.last.$2, closeTo(2, 0.001));
    expect(RegExp(r'/DCTDecode').allMatches(pdf), hasLength(2));
  });

  test('无限画布只在有内容时导出，取消后不生成 PDF', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    expect(await controller.exportPdf(), isNull);
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('shape'),
          x: -500,
          y: 500,
          width: 300,
          height: 50,
        ),
      ),
    );
    final bytes = await controller.exportPdf();
    final pdf = latin1.decode(bytes!);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf), hasLength(1));
    expect(await controller.exportPdf(isCancelled: () => true), isNull);
  });
}

Future<Uint8List> _background(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
