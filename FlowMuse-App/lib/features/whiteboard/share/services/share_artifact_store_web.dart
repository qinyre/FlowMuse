import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/src/ui/platform_io.dart';

import '../models/share_payload.dart';
import 'share_artifact_name.dart';

class ShareArtifactStore {
  ShareArtifactStore({String? rootPath});

  Future<ShareFilePayload> write({
    required String title,
    required ShareContentType contentType,
    required String extension,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final fileName = shareArtifactFileName(title, extension);
    return ShareFilePayload(
      title: title,
      contentType: contentType,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
    );
  }

  Future<void> cleanupExpired({required DateTime now}) async {}

  void download(ShareFilePayload payload) {
    downloadBytes(payload.fileName, payload.bytes!, mimeType: payload.mimeType);
  }
}
