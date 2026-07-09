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
  }) async {
    final payload = ref.read(pendingPdfImportProvider);
    if (payload == null) {
      return false;
    }
    ref.read(pendingPdfImportProvider.notifier).clear();

    try {
      await fileHandler.importPdfSource(
        PdfImportSource(name: payload.name, bytes: payload.bytes),
        canvasSize,
        asBackground: true,
      );
      final pageCount = controller.currentScene.activeElements
          .where((element) => element.isPdfBackground)
          .length;
      await ref
          .read(libraryIndexProvider.notifier)
          .renameSubtitle(noteId, '$pageCount 页 · ${payload.name}');
      return true;
    } catch (_) {
      await ref.read(libraryIndexProvider.notifier).deleteNotes([noteId]);
      return false;
    }
  }
}

final pdfNoteConsumerProvider = Provider<PdfNoteConsumer>(
  (ref) => const PdfNoteConsumer(),
);
