import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_note_import_payload.dart';

class PendingPdfImportNotifier extends Notifier<PdfNoteImportPayload?> {
  @override
  PdfNoteImportPayload? build() => null;

  void set(PdfNoteImportPayload? payload) {
    state = payload;
  }

  void clear() {
    state = null;
  }
}

final pendingPdfImportProvider =
    NotifierProvider<PendingPdfImportNotifier, PdfNoteImportPayload?>(
      PendingPdfImportNotifier.new,
    );
