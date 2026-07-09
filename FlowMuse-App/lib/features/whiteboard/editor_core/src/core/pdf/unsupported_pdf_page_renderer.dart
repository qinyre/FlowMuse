import 'pdf_import.dart';
import 'pdf_page_renderer.dart';

class UnsupportedPdfPageRenderer implements PdfPageRenderer {
  const UnsupportedPdfPageRenderer(this.platformName);

  final String platformName;

  @override
  Future<List<PdfRenderedPage>> render(
    PdfImportSource source,
    PdfRenderOptions options,
  ) {
    throw UnsupportedError('PDF 导入暂不支持 $platformName。');
  }
}
