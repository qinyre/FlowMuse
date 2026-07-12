import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'local_database_path.dart';

class SceneContentStore {
  SceneContentStore({this.rootPath});

  static const referencePrefix = '@scene-file:';

  final String? rootPath;

  bool isReference(String value) => value.startsWith(referencePrefix);

  Future<String> write(String noteId, String content) async {
    final fileName =
        '${base64Url.encode(utf8.encode(noteId)).replaceAll('=', '')}.scene';
    await File(
      path.join((await _root()).path, fileName),
    ).writeAsString(content, flush: true);
    return '$referencePrefix$fileName';
  }

  Future<String?> read(String reference) async {
    final fileName = reference.substring(referencePrefix.length);
    if (!RegExp(r'^[A-Za-z0-9_-]+\.scene$').hasMatch(fileName)) return null;
    final file = File(path.join((await _root()).path, fileName));
    return await file.exists() ? file.readAsString() : null;
  }

  Future<Directory> _root() async {
    final pathValue =
        rootPath ?? path.join(await localDatabaseDirectory(), 'scenes');
    return Directory(pathValue).create(recursive: true);
  }
}
