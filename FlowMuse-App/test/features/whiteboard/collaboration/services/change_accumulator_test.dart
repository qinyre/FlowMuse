import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/change_accumulator.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';

void main() {
  testWidgets('慢发送跨窗口合并尾批，保留独立元素、nonce 胜者和墓碑', (tester) async {
    final accumulator = ChangeAccumulator();
    addTearDown(accumulator.dispose);
    final gate = Completer<void>();
    final batches = <List<Map<String, Object?>>>[];
    accumulator.onFlush = (elements, _) async {
      batches.add(elements);
      if (batches.length == 1) await gate.future;
    };
    accumulator.scheduleElements([
      _element(id: 'a', version: 1, versionNonce: 10),
    ]);
    await tester.pump(const Duration(milliseconds: 16));
    for (var version = 2; version <= 26; version++) {
      accumulator.scheduleElements([
        _element(id: 'a', version: version, versionNonce: 10),
        _element(
          id: 'b',
          version: version,
          versionNonce: 10,
          isDeleted: version == 26,
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 16));
    }
    accumulator.scheduleElements([
      _element(id: 'a', version: 26, versionNonce: 5),
      _element(id: 'a', version: 26, versionNonce: 8),
      _element(id: 'c', version: 1, versionNonce: 10),
    ]);
    await tester.pump(const Duration(milliseconds: 16));
    expect(batches, hasLength(1), reason: '等待期间不得不断封包');
    gate.complete();
    await tester.pump();
    expect(batches, hasLength(2));
    final last = {for (final e in batches.last) e['id']: e};
    expect(last.keys.toSet(), {'a', 'b', 'c'});
    expect(last['a']!['version'], 26);
    expect(last['a']!['versionNonce'], 5);
    expect(last['b']!['isDeleted'], isTrue);
  });

  testWidgets('发送完成不提前未到期尾批，旧完成不解锁新会话', (tester) async {
    final accumulator = ChangeAccumulator();
    addTearDown(accumulator.dispose);
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    final delivered = <int>[];
    accumulator.onFlush = (elements, _) async {
      final version = elements.single['version'] as int;
      delivered.add(version);
      if (version == 1) await oldGate.future;
      if (version == 2) await newGate.future;
    };
    void update(int version) => accumulator.scheduleElements([
      _element(id: 'a', version: version, versionNonce: 10),
    ]);
    update(1);
    await tester.pump(const Duration(milliseconds: 16));
    accumulator.dispose();
    update(2);
    await tester.pump(const Duration(milliseconds: 16));
    oldGate.complete();
    await tester.pump();
    update(3);
    await tester.pump(const Duration(milliseconds: 16));
    expect(delivered, [1, 2]);
    newGate.complete();
    await tester.pump();
    expect(delivered, [1, 2, 3]);
    update(4);
    await tester.pump(const Duration(milliseconds: 15));
    expect(delivered, [1, 2, 3]);
    await tester.pump(const Duration(milliseconds: 1));
    expect(delivered, [1, 2, 3, 4]);
  });

  testWidgets('连续高频输入仍在首个16ms窗口交付，尾批保留删除', (tester) async {
    final accumulator = ChangeAccumulator();
    addTearDown(accumulator.dispose);
    final delivered = <int>[];
    accumulator.onFlush = (elements, _) async {
      delivered.add((elements.single['version'] as num).toInt());
    };
    for (var version = 1; version <= 8; version++) {
      accumulator.scheduleElements([
        _element(
          id: 'a',
          version: version,
          versionNonce: 10,
          isDeleted: version == 8,
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 5));
      if (version == 4) expect(delivered, [4]);
    }
    expect(delivered, [4, 8]);
  });

  test('合并窗口内同一元素多次更新只保留最高version', () async {
    final accumulator = ChangeAccumulator(
      batchWindow: const Duration(milliseconds: 50),
    );

    final batches = <List<Map<String, Object?>>>[];
    accumulator.onFlush = (elements, _) async {
      batches.add(List.of(elements));
    };

    accumulator.schedule(
      _sceneWithElements([
        _element(id: 'a', version: 1, versionNonce: 10, x: 10),
      ]),
    );
    accumulator.schedule(
      _sceneWithElements([
        _element(id: 'a', version: 2, versionNonce: 20, x: 20),
      ]),
    );
    accumulator.schedule(
      _sceneWithElements([
        _element(id: 'a', version: 3, versionNonce: 30, x: 30),
      ]),
    );

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

    accumulator.schedule(
      _sceneWithElements([
        _element(id: 'a', version: 5, versionNonce: 10, x: 10),
      ]),
    );
    accumulator.schedule(
      _sceneWithElements([
        _element(id: 'a', version: 6, versionNonce: 20, isDeleted: true),
      ]),
    );

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

    accumulator.schedule(
      _sceneWithElements([
        _element(id: 'a', version: 5, versionNonce: 50, x: 10),
      ]),
    );
    accumulator.schedule(
      _sceneWithElements([
        _element(id: 'a', version: 5, versionNonce: 30, x: 20),
      ]),
    );

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

    accumulator.schedule(
      _sceneWithElements([
        _element(id: 'a', version: 1, versionNonce: 10, x: 10),
      ]),
    );
    accumulator.schedule(
      _sceneWithElements([
        _element(id: 'b', version: 1, versionNonce: 10, x: 20),
      ]),
      bypass: true,
    );

    expect(batches.length, 1);
    expect(batches.first.length, 1);
    expect(batches.first.first['id'], 'b');
  });

  test('窗口内无变更不触发flush', () async {
    final accumulator = ChangeAccumulator();
    var flushCount = 0;
    accumulator.onFlush = (_, _) async {
      flushCount++;
    };
    await Future.delayed(const Duration(milliseconds: 100));
    expect(flushCount, 0);
  });

  test('dispose 取消待发送批次且不再 tick', () async {
    final accumulator = ChangeAccumulator(
      batchWindow: const Duration(milliseconds: 20),
    );
    var flushCount = 0;
    accumulator.onFlush = (_, _) async => flushCount++;
    accumulator.schedule(
      _sceneWithElements([_element(id: 'a', version: 1, versionNonce: 10)]),
    );

    accumulator.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 40));

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
    // ignore: use_null_aware_elements
    if (x != null) 'x': x,
    'y': 0,
    'width': 100,
    'height': 100,
  };
}

ExcalidrawScene _sceneWithElements(List<Map<String, Object?>> elements) {
  return ExcalidrawScene.empty().copyWith(elements: elements);
}
