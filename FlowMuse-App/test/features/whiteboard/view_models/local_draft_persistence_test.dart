import 'dart:async';

import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/whiteboard/repositories/whiteboard_scene_repository.dart';
import 'package:flow_muse/features/whiteboard/view_models/local_draft_persistence.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('封面生成失败仍保存正文，并保留已有封面', () async {
    // Given：已有封面，新封面渲染失败。
    final scenes = InMemoryWhiteboardSceneRepository();
    final oldCover = Uint8List.fromList([1, 2, 3]);
    final library = _Library()..cover = oldCover;

    // When：保存当前正文。
    await persistLocalDraft(
      noteId: 'test-note',
      content: 'test-content',
      scenes: scenes,
      library: library,
      previousSave: Future<void>.value(),
      thumbnail: Future<Uint8List?>.error(StateError('render failed')),
    );

    // Then：正文持久化成功，旧封面不会被误清空。
    expect(await scenes.loadScene('test-note'), 'test-content');
    expect(library.cover, same(oldCover));
    expect(library.touches, 1);
  });

  test('封面元数据写入失败不将已经落盘的正文判为失败', () async {
    final scenes = InMemoryWhiteboardSceneRepository();
    final library = _Library()..failure = StateError('metadata unavailable');
    await persistLocalDraft(
      noteId: 'test-note',
      content: 'saved-body',
      scenes: scenes,
      library: library,
      previousSave: Future<void>.value(),
      thumbnail: Future<Uint8List?>.value(Uint8List(1)),
    );
    expect(await scenes.loadScene('test-note'), 'saved-body');
  });

  test('正文写盘失败保留原异常，不被同时发生的封面错误掩盖', () async {
    final failure = StateError('storage unavailable');
    final library = _Library();
    await expectLater(
      persistLocalDraft(
        noteId: 'test-note',
        content: 'unsaved-body',
        scenes: _FailingScenes(failure),
        library: library,
        previousSave: Future<void>.value(),
        thumbnail: Future<Uint8List?>.error(StateError('render failed')),
      ),
      throwsA(same(failure)),
    );
    expect(library.touches, 0);
  });

  test('前次保存失败后，新保存仍等待其结束且可以成功', () async {
    final previous = Completer<void>();
    final scenes = InMemoryWhiteboardSceneRepository();
    final library = _Library();
    final saving = persistLocalDraft(
      noteId: 'test-note',
      content: 'latest-body',
      scenes: scenes,
      library: library,
      previousSave: previous.future,
      thumbnail: Future<Uint8List?>.error(StateError('render failed early')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(library.touches, 0);
    previous.completeError(StateError('previous failed'));
    await saving;
    expect(await scenes.loadScene('test-note'), 'latest-body');
  });

  test('正常空封面仍清除旧封面，错误日志不包含异常正文', () async {
    final messages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = originalDebugPrint);
    final library = _Library()..cover = Uint8List(1);
    await persistLocalDraft(
      noteId: 'test-note',
      content: 'test-body',
      scenes: InMemoryWhiteboardSceneRepository(),
      library: library,
      previousSave: Future<void>.error(StateError('private-error-content')),
      thumbnail: Future<Uint8List?>.value(),
    );
    expect(library.cover, isNull);
    expect(messages.join('\n'), contains('stage=previous'));
    expect(messages.join('\n'), isNot(contains('private-error-content')));
    expect(messages.join('\n'), isNot(contains('test-body')));
  });
}

class _Library extends Fake implements LibraryRepository {
  Uint8List? cover;
  Object? failure;
  int touches = 0;

  @override
  Future<void> touchNote(
    String noteId, {
    Uint8List? coverThumbnailBytes,
    bool clearCoverThumbnail = false,
  }) async {
    touches++;
    if (failure != null) throw failure!;
    if (clearCoverThumbnail) {
      cover = null;
    } else if (coverThumbnailBytes != null) {
      cover = coverThumbnailBytes;
    }
  }
}

class _FailingScenes extends Fake implements WhiteboardSceneRepository {
  _FailingScenes(this.failure);
  final Object failure;

  @override
  Future<void> saveScene(String noteId, String content) async => throw failure;
}
