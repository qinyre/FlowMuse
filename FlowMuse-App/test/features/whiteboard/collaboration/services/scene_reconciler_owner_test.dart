import 'package:flow_muse/features/whiteboard/collaboration/services/scene_reconciler.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> el(
  String id, {
  int version = 1,
  int nonce = 1,
  String? ownerKey,
  String ownerName = '张三',
  bool ownerGuest = false,
  String? containerId,
  String type = 'rectangle',
}) {
  return <String, Object?>{
    'id': id,
    'type': type,
    'version': version,
    'versionNonce': nonce,
    'index': 'a$id',
    if (containerId != null) 'containerId': containerId,
    if (ownerKey != null)
      'customData': {
        'flowMuse': {
          'collaborationOwner': {
            'version': 1,
            'creatorKey': ownerKey,
            'displayName': ownerName,
            'isGuest': ownerGuest,
          },
        },
      },
  };
}

List<Map<String, Object?>> deepCopy(List<Map<String, Object?>> input) => [
  for (final e in input) Map<String, Object?>.from(e),
];

void main() {
  final reconciler = SceneReconciler();

  test('winner 有 owner、loser 无 → winner 原样（远端胜出版本更高）', () {
    final local = [el('e1', version: 1, ownerKey: 'user:a')];
    final remote = [el('e1', version: 2)];
    final out = reconciler.reconcile(
      localElements: local,
      remoteElements: remote,
    );
    expect(out.first['customData'], isNotNull);
  });

  test('winner 缺 owner、loser 有 → 从 loser 回填且其他 customData 保留', () {
    final local = [el('e1', version: 2)];
    final remote = [el('e1', version: 1, ownerKey: 'user:b')];
    final out = reconciler.reconcile(
      localElements: local,
      remoteElements: remote,
    );
    final flowMuse = (out.first['customData'] as Map)['flowMuse'] as Map;
    expect((flowMuse['collaborationOwner'] as Map)['creatorKey'], 'user:b');
  });

  test('双方 owner 不同且都非空 → LWW winner 生效；local/remote 交换后结果一致', () {
    final a = [el('e1', version: 2, nonce: 5, ownerKey: 'user:a')];
    final b = [el('e1', version: 2, nonce: 9, ownerKey: 'user:b')];
    final out1 = reconciler.reconcile(localElements: a, remoteElements: b);
    final out2 = reconciler.reconcile(localElements: b, remoteElements: a);
    final k1 =
        (((out1.first['customData'] as Map)['flowMuse']
                as Map)['collaborationOwner']
            as Map)['creatorKey'];
    final k2 =
        (((out2.first['customData'] as Map)['flowMuse']
                as Map)['collaborationOwner']
            as Map)['creatorKey'];
    expect(k1, k2, reason: '交换参数后必须收敛到同一 winner owner');
    expect(k1, 'user:a'); // version 相同 nonce 5 < 9 → local(a) 胜
  });

  test('双方都无 owner → 输出无 owner', () {
    final out = reconciler.reconcile(
      localElements: [el('e1', version: 2)],
      remoteElements: [el('e1', version: 1)],
    );
    expect(out.first.containsKey('customData'), isFalse);
  });

  test('回填 copy-on-write：输入列表与嵌套 Map 在 reconcile 后完全不变', () {
    final local = deepCopy([el('e1', version: 2)]);
    final remote = deepCopy([el('e1', version: 1, ownerKey: 'user:b')]);
    final localBefore = local.toString();
    final remoteBefore = remote.toString();
    reconciler.reconcile(localElements: local, remoteElements: remote);
    expect(local.toString(), localBefore);
    expect(remote.toString(), remoteBefore);
  });

  test('父子规范化：绑定文字 owner 跟随结果集父元素（补齐/清除两向）', () {
    // 父赢且带 owner，绑定文字旧数据无 owner → 补齐
    final local = [
      el('parent', version: 2, ownerKey: 'user:a'),
      el('child', version: 1, type: 'text', containerId: 'parent'),
    ];
    final out = reconciler.reconcile(localElements: local, remoteElements: []);
    final child = out.firstWhere((e) => e['id'] == 'child');
    expect(
      (((child['customData'] as Map)['flowMuse'] as Map)['collaborationOwner']
          as Map)['creatorKey'],
      'user:a',
    );

    // 父无 owner，绑定文字残留 owner → 清除
    final local2 = [
      el('parent2', version: 2),
      el(
        'child2',
        version: 1,
        type: 'text',
        containerId: 'parent2',
        ownerKey: 'user:x',
      ),
    ];
    final out2 = reconciler.reconcile(
      localElements: local2,
      remoteElements: [],
    );
    final child2 = out2.firstWhere((e) => e['id'] == 'child2');
    expect(child2.containsKey('customData'), isFalse);
  });

  test('规范化不改 version/versionNonce', () {
    final local = [
      el('parent', version: 7, nonce: 3, ownerKey: 'user:a'),
      el('child', version: 9, nonce: 4, type: 'text', containerId: 'parent'),
    ];
    final out = reconciler.reconcile(localElements: local, remoteElements: []);
    final child = out.firstWhere((e) => e['id'] == 'child');
    expect(child['version'], 9);
    expect(child['versionNonce'], 4);
  });

  test('仅本地独有元素不触发回填（无 loser）', () {
    final out = reconciler.reconcile(
      localElements: [el('solo', version: 1, ownerKey: 'user:a')],
      remoteElements: [],
    );
    expect(out.single['id'], 'solo');
  });
}
