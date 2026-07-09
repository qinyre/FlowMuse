import 'package:flutter/foundation.dart';

import 'pdf_page_renderer.dart';
import 'pdfx_pdf_page_renderer.dart';
import 'platform_pdf_page_renderer.dart';
import 'unsupported_pdf_page_renderer.dart';

PdfPageRenderer createDefaultPdfPageRenderer({TargetPlatform? platform}) {
  if (kIsWeb) {
    return const PdfxPdfPageRenderer();
  }
  final targetPlatform = platform ?? defaultTargetPlatform;
  if (targetPlatform == TargetPlatform.ohos) {
    return const PlatformPdfPageRenderer();
  }
  return switch (targetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => const PdfxPdfPageRenderer(),
    TargetPlatform.linux => const UnsupportedPdfPageRenderer('Linux'),
    TargetPlatform.fuchsia => const UnsupportedPdfPageRenderer('Fuchsia'),
    TargetPlatform.ohos => const PlatformPdfPageRenderer(),
  };
}
