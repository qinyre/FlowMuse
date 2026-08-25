import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/text_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_split_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alice = CollaborationCreator(
    creatorKey: 'user:a',
    displayName: 'A',
    isGuest: false,
  );
  const bob = CollaborationCreator(
    creatorKey: 'user:b',
    displayName: 'B',
    isGuest: false,
  );

  test('alias 命中 sidecar → 恢复原 owner（元素类型改变也恢复，规则 4）', () {
    final parsed = [
      RectangleElement(
        id: const ElementId('new-1'),
        x: 0,
        y: 0,
        width: 1,
        height: 1,
      ),
    ];
    final out = applySidecarOwners(
      parsedElements: parsed,
      aliasToElementId: {'rect1': 'new-1'},
      sidecar: {'rect1': alice},
      localCreatorResolver: () => bob,
    );
    expect(readCreator(out.single)?.creatorKey, 'user:a');
  });

  test('alias 未命中（新行/改名/重加）→ 当前操作者', () {
    final parsed = [
      RectangleElement(
        id: const ElementId('new-2'),
        x: 0,
        y: 0,
        width: 1,
        height: 1,
      ),
    ];
    final out = applySidecarOwners(
      parsedElements: parsed,
      aliasToElementId: {'rect9': 'new-2'},
      sidecar: {'rect1': alice},
      localCreatorResolver: () => bob,
    );
    expect(readCreator(out.single)?.creatorKey, 'user:b');
  });

  test('localCreatorResolver 为 null → 新行无 owner（本地无协作上下文）', () {
    final parsed = [
      RectangleElement(
        id: const ElementId('new-3'),
        x: 0,
        y: 0,
        width: 1,
        height: 1,
      ),
    ];
    final out = applySidecarOwners(
      parsedElements: parsed,
      aliasToElementId: {'rect9': 'new-3'},
      sidecar: const {},
    );
    expect(readCreator(out.single), isNull);
  });

  test('绑定文字继承父元素（父在前在后都能正确处理）', () {
    final parsed = [
      TextElement(
        id: const ElementId('t'),
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        text: 'x',
        containerId: 'new-p',
      ),
      RectangleElement(
        id: const ElementId('new-p'),
        x: 0,
        y: 0,
        width: 1,
        height: 1,
      ),
    ];
    final out = applySidecarOwners(
      parsedElements: parsed,
      aliasToElementId: {'text1': 't', 'rect1': 'new-p'},
      sidecar: {'rect1': alice},
      localCreatorResolver: () => bob,
    );
    expect(
      readCreator(
        out.firstWhere((e) => e.id == const ElementId('new-p')),
      )!.creatorKey,
      'user:a',
    );
    expect(
      readCreator(
        out.firstWhere((e) => e.id == const ElementId('t')),
      )!.creatorKey,
      'user:a',
    );
  });

  test('系统元素清除 owner', () {
    final parsed = [
      RectangleElement(
        id: const ElementId('pg'),
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        customData: const {
          'flowMuse': {'role': 'page', 'pageId': 'p'},
        },
      ),
    ];
    final out = applySidecarOwners(
      parsedElements: [for (final e in parsed) withCreator(e, alice)],
      aliasToElementId: {},
      sidecar: const {},
      localCreatorResolver: () => bob,
    );
    expect(readCreator(out.single), isNull);
  });

  test('findDuplicateAliasIds：真重复报出，前缀别名（rect1 vs rect11）不误报', () {
    const aliases = {'rect1': 'e1', 'rect11': 'e2', 'text1': 'e3'};
    expect(
      findDuplicateAliasIds(
        '- rect | id=rect1\n- rect | id=rect11\n- text | id=text1',
        aliases,
      ),
      isEmpty,
      reason: 'rect1 不能因 rect11 的存在被误判重复',
    );
    expect(
      findDuplicateAliasIds('- rect | id=rect1\n- rect | id=rect1', aliases),
      ['rect1'],
    );
    expect(findDuplicateAliasIds('', aliases), isEmpty);
  });
}
