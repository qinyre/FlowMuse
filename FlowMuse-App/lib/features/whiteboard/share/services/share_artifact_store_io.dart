import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/share_payload.dart';
import 'share_artifact_name.dart';

class ShareArtifactStore {
  ShareArtifactStore({this.rootPath});

  final String? rootPath;

  Future<ShareFilePayload> write({
    required String title,
    required ShareContentType contentType,
    required String extension,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    await cleanupExpired(now: DateTime.now());
    final root = await _root();
    final fileName = shareArtifactFileName(title, extension);
    final file = File(
      p.join(root.path, '${DateTime.now().microsecondsSinceEpoch}_$fileName'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return ShareFilePayload(
      title: title,
      contentType: contentType,
      filePath: file.path,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  Future<void> cleanupExpired({required DateTime now}) async {
    final root = await _root();
    await for (final entity in root.list()) {
      if (entity is File &&
          now.difference(await entity.lastModified()).inHours >= 24) {
        await entity.delete();
      }
    }
  }

  Future<Directory> _root() async {
    if (rootPath != null) {
      return Directory(rootPath!).create(recursive: true);
    }
    return Directory(
      p.join((await getTemporaryDirectory()).path, 'flowmuse-share'),
    ).create(recursive: true);
  }
}
