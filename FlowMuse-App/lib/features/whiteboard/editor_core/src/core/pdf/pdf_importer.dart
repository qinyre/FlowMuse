import 'package:flutter/widgets.dart';

import '../../ui/markdraw_controller.dart';
import 'pdf_page_renderer.dart';

class PdfImporter {
  const PdfImporter({
    required this.renderer,
    this.defaultOptions = const PdfRenderOptions(),
  });

  final PdfPageRenderer renderer;
  final PdfRenderOptions defaultOptions;

  Future<void> importPdf({
    required PdfImportSource source,
    required MarkdrawController controller,
    required Size canvasSize,
    PdfRenderOptions? options,
    bool asBackground = false,
  }) async {
    final renderOptions = options ?? defaultOptions;
    final pages = await renderer.render(source, renderOptions);
    renderOptions.checkCancelled();
    if (controller.isDisposed) return;
    if (pages.isEmpty) {
      return;
    }
    await controller.importPdfPages(
      pages,
      canvasSize,
      documentName: source.name,
      asBackground: asBackground,
      isCancelled: renderOptions.isCancelled,
    );
  }
}
