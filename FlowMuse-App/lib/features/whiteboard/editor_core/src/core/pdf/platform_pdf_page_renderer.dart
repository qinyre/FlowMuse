import 'package:flutter/services.dart';

import 'pdf_import.dart';
import 'pdf_page_renderer.dart';

class PlatformPdfPageRenderer implements PdfPageRenderer {
  const PlatformPdfPageRenderer({
    MethodChannel channel = const MethodChannel('flow_muse/pdf_import'),
  }) : _channel = channel;

  final MethodChannel _channel;
  static int _nextProgressId = 0;

  @override
  Future<List<PdfRenderedPage>> render(
    PdfImportSource source,
    PdfRenderOptions options,
  ) async {
    options.checkCancelled();
    final progress = MethodChannel(
      'flow_muse/pdf_import/progress/${_nextProgressId++}',
    );
    progress.setMethodCallHandler((call) async {
      if (options.isCancelled?.call() ?? false) return false;
      if (call.method == 'progress') {
        final data = Map<Object?, Object?>.from(call.arguments as Map);
        options.onProgress?.call(
          (data['completed']! as num).toInt(),
          (data['total']! as num).toInt(),
        );
      }
      return true;
    });
    try {
      final result = await _channel
          .invokeMethod<List<Object?>>('renderPdfPages', <String, Object?>{
            'name': source.name,
            'bytes': source.bytes,
            'path': source.path,
            'targetPageWidth': options.targetPageWidth,
            'maxPages': options.maxPages,
            'progressChannel': progress.name,
          });
      options.checkCancelled();
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
    } finally {
      progress.setMethodCallHandler(null);
    }
  }
}
