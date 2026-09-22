import 'dart:typed_data';

class PdfNoteImportPayload {
  const PdfNoteImportPayload({
    required this.bytes,
    required this.name,
    this.noteId,
  });

  final Uint8List bytes;
  final String name;
  final String? noteId;
}
