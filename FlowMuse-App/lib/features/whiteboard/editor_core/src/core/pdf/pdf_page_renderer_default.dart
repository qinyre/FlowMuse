import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'pdf_page_renderer.dart';
import 'pdfx_pdf_page_renderer.dart';
import 'platform_pdf_page_renderer.dart';
import 'unsupported_pdf_page_renderer.dart';

PdfPageRenderer createDefaultPdfPageRenderer() {
  if (kIsWeb) {
    return const UnsupportedPdfPageRenderer('Web');
  }
  if (Platform.operatingSystem == 'ohos') {
    return const PlatformPdfPageRenderer();
  }
  return const PdfxPdfPageRenderer();
}
