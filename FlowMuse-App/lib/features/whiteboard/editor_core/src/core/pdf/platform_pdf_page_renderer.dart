import 'package:flutter/services.dart';

import 'pdf_import.dart';
import 'pdf_page_renderer.dart';

class PlatformPdfPageRenderer implements PdfPageRenderer {
  const PlatformPdfPageRenderer({
    MethodChannel channel = const MethodChannel('flow_muse/pdf_import'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<List<PdfRenderedPage>> render(
    PdfImportSource source,
    PdfRenderOptions options,
  ) async {
    final result = await _channel
        .invokeMethod<List<Object?>>('renderPdfPages', <String, Object?>{
          'name': source.name,
          'bytes': source.bytes,
          'path': source.path,
          'targetPageWidth': options.targetPageWidth,
          'maxPages': options.maxPages,
        });
    if (result == null) {
      return const [];
    }

    return [
      for (final item in result)
        if (item case final Map<Object?, Object?> page)
          PdfRenderedPage(
            bytes: page['bytes']! as Uint8List,
            mimeType: page['mimeType'] as String? ?? 'image/png',
            width: (page['width']! as num).toDouble(),
            height: (page['height']! as num).toDouble(),
            pageNumber: (page['pageNumber']! as num).toInt(),
          ),
    ];
  }
}
