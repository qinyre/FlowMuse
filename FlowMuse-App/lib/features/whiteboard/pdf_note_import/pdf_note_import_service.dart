import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';
import 'pdf_note_import_payload.dart';
import 'pending_pdf_import_provider.dart';

class PdfNoteImportService {
  const PdfNoteImportService();

  Future<NoteItem?> pickAndStageImport(
    T Function<T>(ProviderListenable<T>) read, {
    required Future<PdfNoteImportPayload?> Function() picker,
    required NoteType noteType,
    required PageTemplate pageTemplate,
    required PageFlow pageFlow,
    String? notebookId,
    List<String> tagIds = const [],
  }) async {
    final payload = await picker();
    if (payload == null) {
      return null;
    }

    final note = await read(libraryIndexProvider.notifier).createNote(
      kind: LibraryFilter.pdf,
      noteType: noteType,
      pageTemplate: pageTemplate,
      pageFlow: pageFlow,
      title: _titleFromFileName(payload.name),
      subtitle: payload.name,
      notebookId: notebookId,
      tagIds: tagIds,
    );
    read(pendingPdfImportProvider.notifier).set(payload);
    return note;
  }

  String _titleFromFileName(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

final pdfNoteImportServiceProvider = Provider<PdfNoteImportService>(
  (ref) => const PdfNoteImportService(),
);
