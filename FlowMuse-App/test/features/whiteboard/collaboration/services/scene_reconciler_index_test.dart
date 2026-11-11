import 'package:flow_muse/features/whiteboard/collaboration/services/scene_reconciler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('缺失或空索引的新笔迹保留在已有字母索引之后，重复合并不再改变索引', () {
    final local = [
      _element('legacy', index: '00000001'),
      _element('pdf', index: 'VV'),
      _element('old', index: 'VVV'),
      _element('new-local'),
    ];
    final remote = [_element('new-remote', index: '')];
    final reconciler = SceneReconciler();

    // When: 一个对端新元素同时触发本机缺失索引的补齐。
    final merged = reconciler.reconcile(
      localElements: local,
      remoteElements: remote,
    );

    // Then: 保留既有索引/对象，新字仍位于底图与旧字之后，输入不变。
    expect(merged.map((e) => e['id']), [
      'legacy',
      'pdf',
      'old',
      'new-local',
      'new-remote',
    ]);
    _expectIncreasing(merged);
    for (var i = 0; i < 3; i++) {
      expect(identical(merged[i], local[i]), isTrue);
    }
    expect((merged[3]['index'] as String).compareTo('VVV'), greaterThan(0));
    expect(local.last.containsKey('index'), isFalse);
    expect(remote.single['index'], '');
    expect(
      merged.every((e) => e['version'] == 1 && e['versionNonce'] == 10),
      isTrue,
    );
    final repeated = reconciler.reconcile(
      localElements: merged,
      remoteElements: remote,
    );
    expect(repeated, merged);
    for (var i = 0; i < repeated.length; i++) {
      expect(identical(repeated[i], merged[i]), isTrue);
    }
  });

  test('连续重复与后继冲突修复保持相对顺序、严格唯一及双端确定性', () {
    final elements = [
      _element('a', index: 'V'),
      _element('b', index: 'V'),
      _element('c', index: 'V0'),
      _element('d', index: 'VV'),
      _element('e', index: 'VV'),
      _element('f', index: 'VVV'),
      _element('g', index: 'a'),
      _element('h'),
    ];
    final reconciler = SceneReconciler();
    final first = reconciler.reconcile(
      localElements: elements,
      remoteElements: [],
    );
    final reverse = reconciler.reconcile(
      localElements: elements.reversed.toList(),
      remoteElements: elements,
    );
    expect(first.map((e) => e['id']), elements.map((e) => e['id']));
    _expectIncreasing(first);
    expect(reverse, first);
    expect(first.last['index'], isNotNull);
    expect(elements[1]['index'], 'V');
    expect(elements.last.containsKey('index'), isFalse);
    expect(first[6]['index'], 'a');
  });
}

Map<String, Object?> _element(String id, {String? index}) => {
  'id': id,
  'type': 'freedraw',
  'version': 1,
  'versionNonce': 10,
  'index': ?index,
};

void _expectIncreasing(List<Map<String, Object?>> elements) {
  for (var i = 1; i < elements.length; i++) {
    expect(
      (elements[i - 1]['index'] as String).compareTo(
        elements[i]['index'] as String,
      ),
      lessThan(0),
    );
  }
}
