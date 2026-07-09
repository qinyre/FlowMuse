import 'dart:typed_data';

class PdfNoteImportPayload {
  const PdfNoteImportPayload({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}
