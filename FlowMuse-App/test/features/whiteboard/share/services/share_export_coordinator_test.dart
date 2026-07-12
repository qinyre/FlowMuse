import 'dart:io';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/share/models/share_payload.dart';
import 'package:flow_muse/features/whiteboard/share/services/share_artifact_store.dart';
import 'package:flow_muse/features/whiteboard/share/services/share_export_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('文档导出使用正确后缀和内容类型', () async {
    final root = await Directory.systemTemp.createTemp('flowmuse-share-test-');
    addTearDown(() => root.delete(recursive: true));
    final controller = MarkdrawController()..renameDocument('课程草图');
    addTearDown(controller.dispose);
    final coordinator = ShareExportCoordinator(
      store: ShareArtifactStore(rootPath: root.path),
    );

    final markdraw = await coordinator.prepareDocument(
      controller,
      DocumentFormat.markdraw,
    );
    final excalidraw = await coordinator.prepareDocument(
      controller,
      DocumentFormat.excalidraw,
    );

    expect(markdraw.fileName, '课程草图.markdraw');
    expect(markdraw.contentType, ShareContentType.markdraw);
    expect(excalidraw.fileName, '课程草图.excalidraw');
    expect(excalidraw.contentType, ShareContentType.excalidraw);
  });
}
