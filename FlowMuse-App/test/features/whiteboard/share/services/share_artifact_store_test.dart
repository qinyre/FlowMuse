import 'dart:io';
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/share/models/share_payload.dart';
import 'package:flow_muse/features/whiteboard/share/services/share_artifact_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('只清理超过 24 小时的分享文件', () async {
    final root = await Directory.systemTemp.createTemp('flowmuse-share-test-');
    addTearDown(() => root.delete(recursive: true));
    final store = ShareArtifactStore(rootPath: root.path);
    final expired = File('${root.path}${Platform.pathSeparator}expired.png')
      ..writeAsBytesSync([1]);
    final fresh = File('${root.path}${Platform.pathSeparator}fresh.png')
      ..writeAsBytesSync([2]);
    await expired.setLastModified(DateTime(2026, 7, 9));
    await fresh.setLastModified(DateTime(2026, 7, 10, 12));

    await store.cleanupExpired(now: DateTime(2026, 7, 11, 0));

    expect(expired.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
  });

  test('写入文件时清理标题并保留内容类型', () async {
    final root = await Directory.systemTemp.createTemp('flowmuse-share-test-');
    addTearDown(() => root.delete(recursive: true));
    final store = ShareArtifactStore(rootPath: root.path);

    final payload = await store.write(
      title: '课堂/草图:*',
      contentType: ShareContentType.png,
      extension: 'png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(payload.fileName, '课堂_草图__.png');
    expect(payload.contentType, ShareContentType.png);
    expect(await File(payload.filePath!).readAsBytes(), [1, 2, 3]);
  });
}
