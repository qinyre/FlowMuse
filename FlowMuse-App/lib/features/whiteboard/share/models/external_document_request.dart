import 'package:flutter/foundation.dart';

@immutable
class ExternalDocumentRequest {
  const ExternalDocumentRequest({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}
