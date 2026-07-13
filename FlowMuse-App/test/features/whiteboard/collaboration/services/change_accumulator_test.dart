import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/change_accumulator.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';

void main() {
  test('合并窗口内同一元素多次更新只保留最高version', () async {
    final accumulator = ChangeAccumulator(
      batchWindow: const Duration(milliseconds: 50),
    );

    final batches = <List<Map<String, Object?>>>[];
    accumulator.onFlush = (elements, _) async {
      batches.add(List.of(elements));
    };

    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 1, versionNonce: 10, x: 10),
    ]));
    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 2, versionNonce: 20, x: 20),
    ]));
    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 3, versionNonce: 30, x: 30),
    ]));

    await Future.delayed(const Duration(milliseconds: 100));

    expect(batches.length, 1);
    final sent = batches.first;
    expect(sent.length, 1);
    expect(sent.first['id'], 'a');
    expect(sent.first['version'], 3);
    expect(sent.first['x'], 30);
  });

  test('删除墓碑version更高时覆盖更新', () async {
    final accumulator = ChangeAccumulator();
    final batches = <List<Map<String, Object?>>>[];
    accumulator.onFlush = (elements, _) async {
      batches.add(List.of(elements));
    };

    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 5, versionNonce: 10, x: 10),
    ]));
    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 6, versionNonce: 20, isDeleted: true),
    ]));

    await Future.delayed(const Duration(milliseconds: 100));
    expect(batches.length, 1);
    expect(batches.first.first['isDeleted'], true);
    expect(batches.first.first['version'], 6);
  });

  test('version相同时nonce小的胜出 — 对齐_shouldKeepLocal', () async {
    final accumulator = ChangeAccumulator();
    final batches = <List<Map<String, Object?>>>[];
    accumulator.onFlush = (elements, _) async {
      batches.add(List.of(elements));
    };

    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 5, versionNonce: 50, x: 10),
    ]));
    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 5, versionNonce: 30, x: 20),
    ]));

    await Future.delayed(const Duration(milliseconds: 100));
    expect(batches.first.first['version'], 5);
    expect(batches.first.first['versionNonce'], 30);
    expect(batches.first.first['x'], 20);
  });

  test('bypass跳过批处理立即发送', () async {
    final accumulator = ChangeAccumulator();
    final batches = <List<Map<String, Object?>>>[];
    accumulator.onFlush = (elements, _) async {
      batches.add(List.of(elements));
    };

    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 1, versionNonce: 10, x: 10),
    ]));
    accumulator.schedule(_sceneWithElements([
      _element(id: 'b', version: 1, versionNonce: 10, x: 20),
    ]), bypass: true);

    expect(batches.length, 1);
    expect(batches.first.length, 1);
    expect(batches.first.first['id'], 'b');
  });

  test('窗口内无变更不触发flush', () async {
    final accumulator = ChangeAccumulator();
    var flushCount = 0;
    accumulator.onFlush = (_, __) async { flushCount++; };
    await Future.delayed(const Duration(milliseconds: 100));
    expect(flushCount, 0);
  });
}

Map<String, Object?> _element({
  required String id,
  required int version,
  required int versionNonce,
  int? x,
  bool isDeleted = false,
}) {
  return {
    'id': id,
    'type': 'rectangle',
    'version': version,
    'versionNonce': versionNonce,
    'updated': DateTime.now().millisecondsSinceEpoch,
    'isDeleted': isDeleted,
    'index': 'a0',
    if (x != null) 'x': x,
    'y': 0,
    'width': 100,
    'height': 100,
  };
}

ExcalidrawScene _sceneWithElements(List<Map<String, Object?>> elements) {
  return ExcalidrawScene.empty().copyWith(elements: elements);
}
