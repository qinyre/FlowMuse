import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' hide TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

import 'math_text_utils.dart';

class PageThumbnail {
  PageThumbnail(this.image, this.mathElements);
  final ui.Image image;
  // Only formula elements survive the job, never a historic full scene.
  final List<TextElement> mathElements;
  int get bytes => image.width * image.height * 4;
  void dispose() => image.dispose();
}

/// Independent from the editor image/brush caches. At most one caller job runs.
Future<PageThumbnail?> renderPageThumbnail({
  required Scene scene,
  required CanvasLayout layout,
  required CanvasPage page,
  required String background,
  required bool Function() shouldContinue,
  int? gridSize,
  int longestSide = 384,
}) async {
  if (!shouldContinue()) return null;
  final scale =
      longestSide.clamp(1, 512) /
      math.max(page.bounds.width, page.bounds.height);
  final size = Size(
    (page.bounds.width * scale).ceilToDouble(),
    (page.bounds.height * scale).ceilToDouble(),
  );
  final images = <String, ImageElement>{};
  final formulas = <TextElement>[];
  for (final element in scene.elements) {
    if (element.isDeleted) continue;
    final bounds = AlignmentUtils.visualBounds(element);
    if (!Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.size.width,
      bounds.size.height,
    ).overlaps(page.bounds)) {
      continue;
    }
    if (element is ImageElement) {
      final previous = images[element.fileId];
      if (previous == null ||
          previous.width * previous.height < element.width * element.height) {
        images[element.fileId] = element;
      }
    }
    if (element is TextElement && MathTextUtils.isMathText(element)) {
      formulas.add(element);
    }
  }
  final decoded = <String, ui.Image>{};
  ui.Picture? picture;
  try {
    // Bound retained source pixels as well as output pixels. Codec transient
    // memory can still depend on the original file size, hence serial decoding.
    final pixelsPerImage = (8 * 1024 * 1024 / 4 / math.max(1, images.length))
        .floor();
    for (final entry in images.entries) {
      if (!shouldContinue()) return null;
      final file = scene.files[entry.key];
      if (file == null) continue;
      final element = entry.value;
      final targetScale = math.min(
        scale,
        math.sqrt(pixelsPerImage / math.max(1, element.width * element.height)),
      );
      ui.Codec? codec;
      try {
        codec = await ui.instantiateImageCodec(
          file.bytes,
          targetWidth: (element.width * targetScale).floor().clamp(1, 512),
          targetHeight: (element.height * targetScale).floor().clamp(1, 512),
          allowUpscaling: false,
        );
        decoded[entry.key] = (await codec.getNextFrame()).image;
      } catch (_) {
        // Match the editor's broken-image placeholder; keep other page content.
      } finally {
        codec?.dispose();
      }
    }
    if (!shouldContinue()) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(parseColor(background), BlendMode.src);
    StaticCanvasPainter(
      scene: scene,
      adapter: RoughCanvasAdapter(),
      viewport: ViewportState(offset: page.bounds.topLeft, zoom: scale),
      layout: layout.copyWith(pages: [page]),
      resolvedImages: decoded,
      gridSize: gridSize,
      isDarkBackground: parseColor(background).computeLuminance() < 0.5,
      renderPageShadows: false,
      skipMathText: true,
      cacheNaturalMedia: false,
    ).paint(canvas, size);
    picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    if (!shouldContinue()) {
      image.dispose();
      return null;
    }
    return PageThumbnail(image, formulas);
  } finally {
    picture?.dispose();
    for (final image in decoded.values) {
      image.dispose();
    }
  }
}
