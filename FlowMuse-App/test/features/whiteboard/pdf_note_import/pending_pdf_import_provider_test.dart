import 'package:flow_muse/features/whiteboard/pdf_note_import/pdf_note_import_payload.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pending_pdf_import_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

void main() {
  test('pendingPdfImportProvider holds and clears payload', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(pendingPdfImportProvider), isNull);
    final payload = PdfNoteImportPayload(
      bytes: Uint8List.fromList([1, 2, 3]),
      name: 'doc.pdf',
    );
    container.read(pendingPdfImportProvider.notifier).set(payload);
    expect(container.read(pendingPdfImportProvider)?.name, 'doc.pdf');
    container.read(pendingPdfImportProvider.notifier).clear();
    expect(container.read(pendingPdfImportProvider), isNull);
  });
}
