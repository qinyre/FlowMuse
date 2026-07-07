/// Native implementation using dart:io for desktop and mobile.
library;

import 'dart:io';
import 'dart:typed_data';

/// Reads a file as a UTF-8 string.
Future<String> readStringFromFile(String path) => File(path).readAsString();

/// Writes a UTF-8 string to a file.
Future<void> writeStringToFile(String path, String content) =>
    File(path).writeAsString(content);

/// Writes raw bytes to a file at the given path.
Future<void> writeBytesToFile(String path, Uint8List bytes) =>
    File(path).writeAsBytes(bytes);

/// Not used on native — file_picker handles save dialogs.
void downloadFile(String filename, String content) =>
    throw UnsupportedError('downloadFile is web-only');

/// Not used on native — file_picker handles save dialogs.
void downloadBytes(
  String filename,
  List<int> bytes, {
  String mimeType = 'application/octet-stream',
}) => throw UnsupportedError('downloadBytes is web-only');
