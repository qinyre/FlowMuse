import 'dart:typed_data';

class PdfRenderedPage {
  const PdfRenderedPage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.pageNumber,
  });

  final Uint8List bytes;
  final String mimeType;
  final double width;
  final double height;
  final int pageNumber;
}
