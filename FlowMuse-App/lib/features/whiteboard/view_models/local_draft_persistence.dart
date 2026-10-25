import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../library/repositories/library_repository.dart';
import '../repositories/whiteboard_scene_repository.dart';

/// 场景正文决定保存是否成功，封面和列表元数据失败不应困住已保存的白板。
Future<void> persistLocalDraft({
  required String noteId,
  required FutureOr<String> content,
  required WhiteboardSceneRepository scenes,
  required LibraryRepository library,
  required Future<void> previousSave,
  required Future<Uint8List?> thumbnail,
}) async {
  // 立即接管封面异常；等待前一次写盘时，渲染也可能已经失败。
  final cover = thumbnail.then<(Uint8List?, bool)>(
    (bytes) => (bytes, true),
    onError: (Object error, StackTrace stackTrace) {
      _reportFailure('thumbnail', error, stackTrace);
      return (null, false);
    },
  );
  final previous = previousSave.catchError((
    Object error,
    StackTrace stackTrace,
  ) {
    _reportFailure('previous', error, stackTrace);
  });
  try {
    final preparedContent = await content;
    await previous;
    await scenes.saveScene(noteId, preparedContent);
  } catch (error, stackTrace) {
    _reportFailure('scene', error, stackTrace);
    rethrow;
  }
  final (bytes, rendered) = await cover;
  try {
    await library.touchNote(
      noteId,
      coverThumbnailBytes: bytes,
      // 渲染异常保留旧封面；正常返回 null 才清空。
      clearCoverThumbnail: rendered && bytes == null,
    );
  } catch (error, stackTrace) {
    _reportFailure('metadata', error, stackTrace);
  }
}

void _reportFailure(String stage, Object error, StackTrace stackTrace) {
  debugPrint(
    '[FlowMuseCreateNote] draft stage=$stage '
    'error=${error.runtimeType} '
    'sqliteCode=${error is DatabaseException ? error.getResultCode() : null}\n'
    '$stackTrace',
  );
}
