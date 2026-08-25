import 'dart:io';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const creator = CollaborationCreator(
    creatorKey: 'user:abc',
    displayName: '张三',
    isGuest: false,
  );

  test('withCreator 后 readCreator 往返一致', () {
    final element = RectangleElement(
      id: const ElementId('r1'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
    );
    final stamped = withCreator(element, creator);
    expect(readCreator(stamped)?.creatorKey, 'user:abc');
    expect(readCreator(stamped)?.displayName, '张三');
    expect(readCreator(stamped)?.isGuest, false);
  });

  test(
    'withCreator 深合并保留既有 flowMuse 键（brushType/pageId/pdfBackground/mindmap role/smart-layout）',
    () {
      final element = RectangleElement(
        id: const ElementId('r2'),
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        customData: const {
          'flowMuse': {
            'brushType': 'brush',
            'pageId': 'page-1',
            'pdfBackground': true,
            'role': 'mindmap-node',
            'smartLayoutPlan': {'rows': 2},
          },
          'other': {'keep': true},
        },
      );
      final stamped = withCreator(element, creator);
      final flowMuse = stamped.customData!['flowMuse'] as Map;
      expect(flowMuse['brushType'], 'brush');
      expect(flowMuse['pageId'], 'page-1');
      expect(flowMuse['pdfBackground'], true);
      expect(flowMuse['role'], 'mindmap-node');
      expect((flowMuse['smartLayoutPlan'] as Map)['rows'], 2);
      expect(flowMuse['collaborationOwner'], isNotNull);
      expect((stamped.customData!['other'] as Map)['keep'], true);
    },
  );

  test('withCreator 不修改输入元素（copy-on-write）', () {
    final element = RectangleElement(
      id: const ElementId('r3'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      customData: const {
        'flowMuse': {'brushType': 'marker'},
      },
    );
    final before = element.customData.toString();
    withCreator(element, creator);
    expect(element.customData.toString(), before);
    expect(
      (element.customData!['flowMuse'] as Map)['collaborationOwner'],
      isNull,
    );
  });

  test('withoutCreator 只删 collaborationOwner，保留其他键；无 owner 时原样返回', () {
    final element = withCreator(
      RectangleElement(
        id: const ElementId('r4'),
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        customData: const {
          'flowMuse': {'pageId': 'page-2'},
        },
      ),
      creator,
    );
    final cleared = withoutCreator(element);
    expect(readCreator(cleared), isNull);
    expect((cleared.customData!['flowMuse'] as Map)['pageId'], 'page-2');

    final untouched = RectangleElement(
      id: const ElementId('r5'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
    );
    expect(identical(withoutCreator(untouched), untouched), isTrue);
  });

  test('customData 为 null 时 withCreator 创建完整路径', () {
    final element = RectangleElement(
      id: const ElementId('r6'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
    );
    expect(element.customData, isNull);
    final stamped = withCreator(element, creator);
    expect(readCreator(stamped)?.creatorKey, 'user:abc');
  });

  test('畸形数据安全降级：readCreator 返回 null 而不抛异常', () {
    Element buildWith(Object? owner) => RectangleElement(
      id: const ElementId('r7'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      customData: {
        'flowMuse': {'collaborationOwner': owner},
      },
    );
    expect(readCreator(buildWith('not-a-map')), isNull);
    expect(readCreator(buildWith({'creatorKey': 42})), isNull);
    expect(
      readCreator(
        buildWith({
          'creatorKey': 'k',
          'displayName': 1,
          'isGuest': false,
          'version': 1,
        }),
      ),
      isNull,
    );
    expect(readCreator(buildWith(null)), isNull);
    expect(
      readCreator(
        RectangleElement(
          id: const ElementId('r8'),
          x: 0,
          y: 0,
          width: 10,
          height: 10,
          customData: const {'flowMuse': 'not-a-map'},
        ),
      ),
      isNull,
    );
  });

  test('未知更高 version 仍可读取合法公共字段', () {
    final element = RectangleElement(
      id: const ElementId('r9'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      customData: const {
        'flowMuse': {
          'collaborationOwner': {
            'version': 99,
            'creatorKey': 'guest:room:u',
            'displayName': '游客',
            'isGuest': true,
            'futureField': 'x',
          },
        },
      },
    );
    expect(readCreator(element)?.creatorKey, 'guest:room:u');
  });

  test('raw JSON 版本行为与 Element 版本一致且不改输入 map', () {
    final raw = <String, Object?>{
      'id': 'e1',
      'type': 'rectangle',
      'version': 3,
      'versionNonce': 7,
      'customData': {
        'flowMuse': {'pageId': 'page-3'},
      },
    };
    final stamped = withCreatorInJson(raw, creator);
    expect(readCreatorFromJson(stamped)?.creatorKey, 'user:abc');
    expect(
      ((stamped['customData'] as Map)['flowMuse'] as Map)['pageId'],
      'page-3',
    );
    // 输入不被修改
    expect(
      ((raw['customData'] as Map)['flowMuse'] as Map).containsKey(
        'collaborationOwner',
      ),
      isFalse,
    );
    final cleared = withoutCreatorInJson(stamped);
    expect(readCreatorFromJson(cleared), isNull);
    expect(
      ((cleared['customData'] as Map)['flowMuse'] as Map)['pageId'],
      'page-3',
    );
    // 无 owner 时 withoutCreatorInJson 原样返回同一实例
    expect(identical(withoutCreatorInJson(raw), raw), isTrue);
  });

  test('owner codec 不 import collaboration/account（依赖边界）', () {
    final file = File(
      'lib/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart',
    );
    final source = file.readAsStringSync();
    expect(
      source.contains('features/whiteboard/collaboration'),
      isFalse,
      reason: 'editor_core owner 模块不得依赖 collaboration',
    );
    expect(
      source.contains('features/account'),
      isFalse,
      reason: 'editor_core owner 模块不得依赖 account',
    );
  });
}
