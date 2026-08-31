import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/deterministic_hash.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/stable_element_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RectangleElement rect(String id, {double x = 10}) => RectangleElement(
    id: ElementId(id),
    x: x,
    y: 10,
    width: 40,
    height: 40,
    // 钉定会随进程漂移的字段，保证用例只考察目标差异
    seed: 7,
    versionNonce: 11,
    updated: 1000,
  );

  group('deterministic_hash（公开规范向量）', () {
    test('fnv1a32 空串=偏移基，"abc"=0x1a47e90b', () {
      expect(fnv1a32([]), 0x811c9dc5);
      expect(fnv1a32('abc'.codeUnits), 0x1a47e90b);
    });

    test('fingerprint64 确定性且域分隔', () {
      final a = fingerprint64('payload-x');
      expect(a, fingerprint64('payload-x'));
      expect(a, isNot(fingerprint64('payload-y')));
      expect(a, hasLength(16));
      expect(a, matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('canonical 数字/值归一（跨端一致前提）', () {
    test('整值 double 与 int 同形态；0/-0.0 归一', () {
      expect(canonicalNum(1.0), canonicalNum(1));
      expect(canonicalNum(1.0), '1');
      expect(canonicalNum(0), '0');
      expect(canonicalNum(-0.0), '0');
      expect(canonicalNum(2.5), '2.5');
      expect(canonicalNum(-2.5), '-2.5');
      expect(canonicalNum(123456789012345.0), '123456789012345');
    });

    test('Map 键序无关；字符串经 JSON 转义不可注入分隔符', () {
      expect(
        canonicalValue({'b': 1, 'a': 2.0}),
        canonicalValue({'a': 2, 'b': 1}),
      );
      expect(canonicalValue('a|b~c{d}'), isNot(canonicalValue('a')));
      expect(canonicalValue(null), 'null');
      expect(canonicalValue(true), 'true');
      expect(
        canonicalValue([
          1,
          1.0,
          'x',
          null,
          {'k': 'v'},
        ]),
        '[1,1,"x",null,{"k":"v"}]',
      );
    });
  });

  group('StableElementIdentity', () {
    test('取元素 id；按 id 排序与列表顺序无关', () {
      final a = StableElementIdentity.of(rect('a-id'));
      final b = StableElementIdentity.of(rect('b-id'));
      expect(a.value, 'a-id');
      expect(a.compareTo(b), lessThan(0));
      expect(a, StableElementIdentity('a-id'));
    });
  });

  group('SceneFingerprint', () {
    test('元素列表顺序无关：不同合入顺序同指纹', () {
      final s1 = Scene().addElement(rect('r1')).addElement(rect('r2'));
      final s2 = Scene().addElement(rect('r2')).addElement(rect('r1'));
      expect(SceneFingerprint.of(s1), SceneFingerprint.of(s2));
    });

    test('重复计算稳定', () {
      final s = Scene().addElement(rect('r1'));
      expect(SceneFingerprint.of(s), SceneFingerprint.of(s));
    });

    test('内容变化（位移/软删/类型字段）改变指纹', () {
      final base = Scene().addElement(rect('r1'));
      final baseFp = SceneFingerprint.of(base);
      expect(
        SceneFingerprint.of(Scene().addElement(rect('r1', x: 99))),
        isNot(baseFp),
      );
      expect(
        SceneFingerprint.of(
          Scene().addElement(rect('r1').copyWith(isDeleted: true)),
        ),
        isNot(baseFp),
      );
    });

    test('id 不同则指纹不同', () {
      expect(
        SceneFingerprint.of(Scene().addElement(rect('r1'))),
        isNot(SceneFingerprint.of(Scene().addElement(rect('other')))),
      );
    });

    test('files：内容/类型/长度任一变化改变指纹；相同内容稳定', () {
      ImageFile file(String mime, List<int> bytes) =>
          ImageFile(mimeType: mime, bytes: Uint8List.fromList(bytes));
      final base = Scene().addFile('f1', file('image/png', [1, 2, 3]));
      final baseFp = SceneFingerprint.of(base);
      expect(SceneFingerprint.of(base), baseFp);
      expect(
        SceneFingerprint.of(
          Scene().addFile('f1', file('image/png', [1, 2, 4])),
        ),
        isNot(baseFp),
      );
      expect(
        SceneFingerprint.of(
          Scene().addFile('f1', file('image/jpeg', [1, 2, 3])),
        ),
        isNot(baseFp),
      );
      expect(
        SceneFingerprint.of(
          Scene().addFile('f1', file('image/png', [1, 2, 3, 4])),
        ),
        isNot(baseFp),
      );
      // Expando 缓存命中路径不改变结果
      expect(SceneFingerprint.of(base), baseFp);
    });

    test('smartLayout 文档参与指纹', () {
      final scene = Scene().addElement(rect('r1'));
      final plain = SceneFingerprint.of(scene);
      final doc = SmartLayoutDocument(
        version: 1,
        generatedAt: 42,
        blocks: const [SmartLayoutBlock(id: 'b1', type: 'text', text: '标题')],
      );
      final withDoc = SceneFingerprint.of(scene.withSmartLayout(doc));
      expect(withDoc, isNot(plain));
      expect(withDoc, SceneFingerprint.of(scene.withSmartLayout(doc)));
    });

    test('canonicalScenePayload 域分隔完整（元素/文件/文档三段）', () {
      final payload = canonicalScenePayload(
        Scene()
            .addElement(rect('r1'))
            .addFile(
              'f1',
              ImageFile(mimeType: 'image/png', bytes: Uint8List.fromList([1])),
            )
            .withSmartLayout(
              const SmartLayoutDocument(version: 1, generatedAt: 1, blocks: []),
            ),
      );
      expect(payload.startsWith('flowmuse-scene-v1|elements=1|'), isTrue);
      expect(payload.contains('|files=1|'), isTrue);
      expect(payload.contains('|doc={'), isTrue);
      expect(
        canonicalScenePayload(Scene()).contains('|files=0||doc=-'),
        isTrue,
      );
    });
  });
}
