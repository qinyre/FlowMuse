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

/// Saves raw bytes to the system temp directory and returns the saved path.
///
/// Used as a fallback when [FilePicker]'s saveFile is unavailable (e.g., on
/// HarmonyOS where the plugin is not auto-registered and no native channel
/// handler exists).
String saveBytesToTempFile(String filename, Uint8List bytes) {
  final path = '${Directory.systemTemp.path}/$filename';
  File(path).writeAsBytesSync(bytes);
  return path;
}
