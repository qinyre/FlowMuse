import 'dart:math' as math;

import 'package:pdfx/pdfx.dart' as pdfx;

import 'pdf_import.dart';
import 'pdf_page_renderer.dart';

class PdfxPdfPageRenderer implements PdfPageRenderer {
  const PdfxPdfPageRenderer();

  @override
  Future<List<PdfRenderedPage>> render(
    PdfImportSource source,
    PdfRenderOptions options,
  ) async {
    options.checkCancelled();
    final document = source.bytes != null
        ? await pdfx.PdfDocument.openData(source.bytes!)
        : await pdfx.PdfDocument.openFile(source.path!);

    try {
      final pageCount = options.maxPages == null
          ? document.pagesCount
          : math.min(document.pagesCount, options.maxPages!);
      final pages = <PdfRenderedPage>[];
      options.onProgress?.call(0, pageCount);
      for (var pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
        options.checkCancelled();
        final page = await document.getPage(pageNumber);
        try {
          final scale = options.targetPageWidth / page.width;
          final width = math.max(1.0, options.targetPageWidth);
          final height = math.max(1.0, page.height * scale);
          final image = await page.render(
            width: width,
            height: height,
            format: pdfx.PdfPageImageFormat.png,
            backgroundColor: '#ffffff',
          );
          if (image == null || image.bytes.isEmpty) {
            throw StateError('PDF page $pageNumber could not be rendered');
          }
          pages.add(
            PdfRenderedPage(
              bytes: image.bytes,
              mimeType: 'image/png',
              width: image.width?.toDouble() ?? width,
              height: image.height?.toDouble() ?? height,
              pageNumber: pageNumber,
            ),
          );
        } finally {
          await page.close();
        }
        options.onProgress?.call(pageNumber, pageCount);
      }
      options.checkCancelled();
      return pages;
    } finally {
      await document.close();
    }
  }
}
