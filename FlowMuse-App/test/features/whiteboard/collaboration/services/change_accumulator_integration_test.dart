import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/change_accumulator.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/scene_reconciler.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';

void main() {
  test('accumulator flush 后 _changedElements 过滤不发送已广播元素', () async {
    final broadcasted = <String, int>{};
    final sentBatches = <List<Map<String, Object?>>>[];

    final accumulator = ChangeAccumulator();
    accumulator.onFlush = (elements, _) async {
      final changed = elements.where((e) {
        final id = e['id'] as String;
        final version = (e['version'] as num).toInt();
        final last = broadcasted[id];
        return last == null || version > last;
      }).toList();

      if (changed.isNotEmpty) {
        sentBatches.add(List.of(changed));
        for (final e in changed) {
          broadcasted[e['id'] as String] = (e['version'] as num).toInt();
        }
      }
    };

    accumulator.schedule(ExcalidrawScene.empty().copyWith(elements: [
      _makeElement('a', 1, 10),
    ]));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(sentBatches.length, 1);

    accumulator.schedule(ExcalidrawScene.empty().copyWith(elements: [
      _makeElement('a', 1, 10),
      _makeElement('b', 1, 20),
    ]));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(sentBatches.length, 2);
    final secondBatch = sentBatches.last;
    expect(secondBatch.length, 1);
    expect(secondBatch.first['id'], 'b');
  });

  test('大规模场景 accumulator 合并 + getSyncableElements 过滤', () async {
    final reconciler = SceneReconciler();
    final accumulator = ChangeAccumulator(reconciler: reconciler);
    final sentBatches = <List<Map<String, Object?>>>[];
    accumulator.onFlush = (elements, _) async {
      sentBatches.add(List.of(elements));
    };

    final elements = List.generate(200, (i) => _makeElement('e$i', 1, i));
    accumulator.schedule(ExcalidrawScene.empty().copyWith(elements: elements));
    await Future.delayed(const Duration(milliseconds: 100));

    expect(sentBatches.length, 1);
    expect(sentBatches.first.length, 200);
  });
}

Map<String, Object?> _makeElement(String id, int version, int nonce) {
  return {
    'id': id,
    'type': 'rectangle',
    'version': version,
    'versionNonce': nonce,
    'updated': DateTime.now().millisecondsSinceEpoch,
    'isDeleted': false,
    'index': 'a0',
    'x': 0,
    'y': 0,
    'width': 100,
    'height': 100,
  };
}
