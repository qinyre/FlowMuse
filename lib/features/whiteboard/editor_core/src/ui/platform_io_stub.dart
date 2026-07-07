/// Web implementation — dart:io is not available on web.
///
/// File read/write by path is not supported; the app uses
/// file_picker bytes instead. Save uses a blob download.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Not supported on web — file_picker bytes not read by path.
Future<String> readStringFromFile(String path) =>
    throw UnsupportedError('File read by path not supported on web');

/// Not supported on web — file_picker bytes not written by path.
Future<void> writeStringToFile(String path, String content) =>
    throw UnsupportedError('File write by path not supported on web');

/// Not supported on web — file_picker bytes not written by path.
Future<void> writeBytesToFile(String path, Uint8List bytes) =>
    throw UnsupportedError('File write by path not supported on web');

/// Triggers a browser file download with the given filename and content.
void downloadFile(String filename, String content) {
  final bytes = utf8.encode(content);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/plain'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}

/// Triggers a browser file download with raw binary bytes.
void downloadBytes(
  String filename,
  List<int> bytes, {
  String mimeType = 'application/octet-stream',
}) {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
