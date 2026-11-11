import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

typedef _RgbaPage = ({Uint8List pixels, int width, int height});

Uint8List _encodePageJpeg(_RgbaPage page) => img.encodeJpg(
  img.Image.fromBytes(
    width: page.width,
    height: page.height,
    bytes: page.pixels.buffer,
    bytesOffset: page.pixels.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  ),
  quality: 92,
  chroma: img.JpegChroma.yuv444,
);

Future<Uint8List?> renderNotePdf({
  required List<ui.Rect> pages,
  required bool paged,
  required Future<ui.Image?> Function(ui.Rect) renderPage,
  required bool Function() isCancelled,
  void Function(int completed, int total)? onProgress,
}) async {
  if (pages.isEmpty) return null;
  final document = pw.Document();
  onProgress?.call(0, pages.length);
  for (var index = 0; index < pages.length; index++) {
    // Let progress, cancellation and canvas events run between pages on Web.
    await Future<void>.delayed(Duration.zero);
    if (isCancelled()) return null;
    final bounds = pages[index];
    final raster = await renderPage(bounds);
    if (raster == null) {
      if (isCancelled()) return null;
      throw StateError('无法渲染第 ${index + 1} 页');
    }
    final Uint8List jpeg;
    try {
      if (isCancelled()) return null;
      final pixels = await raster.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (pixels == null) throw StateError('无法读取页面图像');
      jpeg = await compute(_encodePageJpeg, (
        pixels: pixels.buffer.asUint8List(
          pixels.offsetInBytes,
          pixels.lengthInBytes,
        ),
        width: raster.width,
        height: raster.height,
      ));
    } finally {
      raster.dispose();
    }
    if (isCancelled()) return null;
    final landscape = bounds.width > bounds.height;
    final scale = PdfPageFormat.a4.height / bounds.longestSide;
    final format = paged
        ? PdfPageFormat(
            math.max(1, bounds.width * scale),
            math.max(1, bounds.height * scale),
          )
        : landscape
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
    final image = pw.MemoryImage(jpeg);
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
    onProgress?.call(index + 1, pages.length);
  }
  return isCancelled() ? null : document.save();
}
