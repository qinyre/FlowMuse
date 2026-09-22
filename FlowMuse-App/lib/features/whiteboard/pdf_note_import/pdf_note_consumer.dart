import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/repositories/library_repository.dart';
import '../editor_core/flow_muse_whiteboard_editor.dart'
    hide Element, SelectionOverlay, TextAlign;
import 'pending_pdf_import_provider.dart';

class PdfNoteConsumer {
  const PdfNoteConsumer();

  Future<bool> consume(
    WidgetRef ref, {
    required MarkdrawController controller,
    required MarkdrawFileHandler fileHandler,
    required String noteId,
    required Size canvasSize,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final payload = ref.read(pendingPdfImportProvider);
    if (payload == null ||
        (payload.noteId != null && payload.noteId != noteId)) {
      return false;
    }
    ref.read(pendingPdfImportProvider.notifier).clear();
    final repository = ref.read(libraryRepositoryProvider);
    final index = ref.read(libraryIndexProvider.notifier);
    final options = PdfRenderOptions(
      onProgress: onProgress,
      isCancelled: () =>
          controller.isDisposed || (isCancelled?.call() ?? false),
    );

    try {
      await fileHandler.importPdfSource(
        PdfImportSource(name: payload.name, bytes: payload.bytes),
        canvasSize,
        asBackground: true,
        options: options,
      );
      options.checkCancelled();
      final effectiveCanvasSize =
          controller.canvasSize.width > 0 && controller.canvasSize.height > 0
          ? controller.canvasSize
          : canvasSize;
      controller.canvasSize = effectiveCanvasSize;
      final bounds = pdfBackgroundBounds(controller.currentScene);
      if (bounds == null) {
        throw StateError('PDF import produced no background pages');
      }
      controller.contentBounds = bounds;
      controller.setViewport(
        fitFirstPageViewport(controller.currentScene, effectiveCanvasSize),
      );
      final pageCount = pdfBackgroundPages(controller.currentScene).length;
      await index.renameSubtitle(noteId, '$pageCount 页 · ${payload.name}');
      return true;
    } catch (_) {
      await repository.deleteNotes([noteId]);
      if (!controller.isDisposed && !(isCancelled?.call() ?? false)) {
        await index.refresh();
      }
      rethrow;
    }
  }

  static List<ImageElement> pdfBackgroundPages(Scene scene) {
    final pages = scene.activeElements
        .whereType<ImageElement>()
        .where((element) => element.isPdfBackground)
        .toList();
    pages.sort((a, b) {
      final pageOrder = _pageOrder(a).compareTo(_pageOrder(b));
      if (pageOrder != 0) return pageOrder;
      final y = a.y.compareTo(b.y);
      return y != 0 ? y : a.x.compareTo(b.x);
    });
    return pages;
  }

  static Bounds? pdfBackgroundBounds(Scene scene) {
    Bounds? result;
    for (final page in pdfBackgroundPages(scene)) {
      final bounds = Bounds.fromLTWH(page.x, page.y, page.width, page.height);
      result = result == null ? bounds : result.union(bounds);
    }
    return result;
  }

  static ViewportState fitFirstPageViewport(Scene scene, Size canvasSize) {
    final pages = pdfBackgroundPages(scene);
    if (pages.isEmpty || canvasSize.width <= 0 || canvasSize.height <= 0) {
      return const ViewportState();
    }
    final first = pages.first;
    final widthZoom = first.width <= 0 ? 1.0 : canvasSize.width / first.width;
    final heightZoom = first.height <= 0
        ? 1.0
        : canvasSize.height / first.height;
    final zoom = widthZoom > heightZoom ? widthZoom : heightZoom;
    return ViewportState(offset: Offset(first.x, first.y), zoom: zoom);
  }

  static int _pageOrder(ImageElement element) {
    final pageId = element.pageId;
    if (pageId == null) {
      return 1 << 30;
    }
    final match = RegExp(r'^page-(\d+)$').firstMatch(pageId);
    if (match == null) {
      return 1 << 30;
    }
    return int.tryParse(match.group(1)!) ?? 1 << 30;
  }
}

final pdfNoteConsumerProvider = Provider<PdfNoteConsumer>(
  (ref) => const PdfNoteConsumer(),
);
