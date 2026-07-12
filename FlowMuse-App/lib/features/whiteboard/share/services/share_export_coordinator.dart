import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../models/share_payload.dart';
import 'share_artifact_store.dart';

class ShareExportCoordinator {
  ShareExportCoordinator({ShareArtifactStore? store})
    : _store = store ?? ShareArtifactStore();

  final ShareArtifactStore _store;

  Future<ShareFilePayload> preparePng(MarkdrawController controller) async {
    final bytes = await controller.exportPng(selectedOnly: false);
    if (bytes == null) {
      throw StateError('无法导出当前画布');
    }
    return _store.write(
      title: _title(controller),
      contentType: ShareContentType.png,
      extension: 'png',
      mimeType: 'image/png',
      bytes: bytes,
    );
  }

  Future<ShareFilePayload> prepareDocument(
    MarkdrawController controller,
    DocumentFormat format,
  ) {
    final (type, extension, mimeType) = switch (format) {
      DocumentFormat.markdraw => (
        ShareContentType.markdraw,
        'markdraw',
        'application/x-markdraw',
      ),
      DocumentFormat.excalidraw => (
        ShareContentType.excalidraw,
        'excalidraw',
        'application/vnd.excalidraw+json',
      ),
      _ => throw ArgumentError.value(format, 'format', '不支持的分享格式'),
    };
    return _store.write(
      title: _title(controller),
      contentType: type,
      extension: extension,
      mimeType: mimeType,
      bytes: Uint8List.fromList(
        utf8.encode(controller.serializeScene(format: format)),
      ),
    );
  }

  String _title(MarkdrawController controller) {
    return controller.documentName?.trim().isNotEmpty == true
        ? controller.documentName!.trim()
        : '白板';
  }
}
