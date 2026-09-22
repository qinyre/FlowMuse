import 'dart:typed_data';

import 'pdf_import.dart';

class PdfImportSource {
  const PdfImportSource({required this.name, this.bytes, this.path})
    : assert(bytes != null || path != null, 'bytes or path must be provided');

  final String name;
  final Uint8List? bytes;
  final String? path;
}

class PdfRenderOptions {
  const PdfRenderOptions({
    this.targetPageWidth = 1600,
    this.maxPages,
    this.onProgress,
    this.isCancelled,
  });

  final double targetPageWidth;
  final int? maxPages;
  final void Function(int completed, int total)? onProgress;
  final bool Function()? isCancelled;

  void checkCancelled() {
    if (isCancelled?.call() ?? false) {
      throw StateError('PDF import cancelled');
    }
  }
}

abstract interface class PdfPageRenderer {
  Future<List<PdfRenderedPage>> render(
    PdfImportSource source,
    PdfRenderOptions options,
  );
}
