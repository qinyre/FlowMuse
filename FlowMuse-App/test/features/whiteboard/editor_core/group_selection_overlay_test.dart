import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const groupA = 'group-a';
  const groupB = 'group-b';
  const innerA = 'inner-a';
  const innerB = 'inner-b';

  RectangleElement rect(String id, {List<String> groupIds = const []}) =>
      RectangleElement(
        id: ElementId(id),
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        groupIds: groupIds,
      );

  Scene sceneWith(List<RectangleElement> elements) =>
      elements.fold<Scene>(Scene(), (s, e) => s.addElement(e));

  group('GroupUtils.isCompleteGroupSelection', () {
    test('单元素返回 false', () {
      // Given 一个未分组元素
      final scene = sceneWith([rect('a')]);
      // When 选中该元素
      final result = GroupUtils.isCompleteGroupSelection(scene, [
        scene.getElementById(ElementId('a'))!,
      ]);
      // Then 不视为组合选中
      expect(result, isFalse);
    });

    test('空列表返回 false', () {
      final scene = sceneWith([]);
      expect(GroupUtils.isCompleteGroupSelection(scene, const []), isFalse);
    });

    test('完整外层组合全选返回 true', () {
      // Given 3 个成员共同属于 group-a
      final scene = sceneWith([
        rect('a', groupIds: [groupA]),
        rect('b', groupIds: [groupA]),
        rect('c', groupIds: [groupA]),
      ]);
      // When 全部成员被选中
      final selected = [
        scene.getElementById(ElementId('a'))!,
        scene.getElementById(ElementId('b'))!,
        scene.getElementById(ElementId('c'))!,
      ];
      // Then 是组合选中
      expect(GroupUtils.isCompleteGroupSelection(scene, selected), isTrue);
    });

    test('组合的部分成员被选中返回 false', () {
      // Given 3 个成员同属 group-a，仅含 2 个
      final scene = sceneWith([
        rect('a', groupIds: [groupA]),
        rect('b', groupIds: [groupA]),
        rect('c', groupIds: [groupA]),
      ]);
      final selected = [
        scene.getElementById(ElementId('a'))!,
        scene.getElementById(ElementId('b'))!,
      ];
      // When 只选部分 → Then 不视为组合选中（陈旧/部分选中不误判）
      expect(GroupUtils.isCompleteGroupSelection(scene, selected), isFalse);
    });

    test('两个不同组合各取全成员返回 false', () {
      // Given 组 A 两个成员 + 组 B 两个成员
      final scene = sceneWith([
        rect('a', groupIds: [groupA]),
        rect('b', groupIds: [groupA]),
        rect('cx', groupIds: [groupB]),
        rect('dy', groupIds: [groupB]),
      ]);
      final selected = [
        scene.getElementById(ElementId('a'))!,
        scene.getElementById(ElementId('b'))!,
        scene.getElementById(ElementId('cx'))!,
        scene.getElementById(ElementId('dy'))!,
      ];
      expect(GroupUtils.isCompleteGroupSelection(scene, selected), isFalse);
    });

    test('一个组合加一个独立元素混选返回 false', () {
      final scene = sceneWith([
        rect('a', groupIds: [groupA]),
        rect('b', groupIds: [groupA]),
        rect('sol'),
      ]);
      final selected = [
        scene.getElementById(ElementId('a'))!,
        scene.getElementById(ElementId('b'))!,
        scene.getElementById(ElementId('sol'))!,
      ];
      expect(GroupUtils.isCompleteGroupSelection(scene, selected), isFalse);
    });

    test('嵌套：仅选内层子组的完整成员返回 true', () {
      // Given 外层组含 inner-a、inner-b 两个子组（4 个成员）
      final scene = sceneWith([
        rect('a1', groupIds: [innerA, groupA]),
        rect('a2', groupIds: [innerA, groupA]),
        rect('b1', groupIds: [innerB, groupA]),
        rect('b2', groupIds: [innerB, groupA]),
      ]);
      // When 只选 inner-a 的 2 个成员
      final selected = [
        scene.getElementById(ElementId('a1'))!,
        scene.getElementById(ElementId('a2'))!,
      ];
      // Then 视为内层组合选中（外层共享但成员全集更大，向下钻到内层命中）
      expect(GroupUtils.isCompleteGroupSelection(scene, selected), isTrue);
    });

    test('嵌套：外层全部成员被选中返回 true', () {
      final scene = sceneWith([
        rect('a1', groupIds: [innerA, groupA]),
        rect('a2', groupIds: [innerA, groupA]),
        rect('b1', groupIds: [innerB, groupA]),
        rect('b2', groupIds: [innerB, groupA]),
      ]);
      final selected = [
        scene.getElementById(ElementId('a1'))!,
        scene.getElementById(ElementId('a2'))!,
        scene.getElementById(ElementId('b1'))!,
        scene.getElementById(ElementId('b2'))!,
      ];
      expect(GroupUtils.isCompleteGroupSelection(scene, selected), isTrue);
    });
  });

  group('SelectionOverlay.isGroupUnit', () {
    test('fromElements 传 isGroupUnit 时置空 elementBounds', () {
      final elements = [
        rect('a', groupIds: [groupA]),
        rect('b', groupIds: [groupA]),
        rect('c', groupIds: [groupA]),
      ];
      // When 以组合单元方式构建
      final overlay = SelectionOverlay.fromElements(elements, isGroupUnit: true);
      // Then 不填充逐元素轮廓，且标记为组合单元，union bounds 与 9 个手柄保留
      expect(overlay!.elementBounds, isEmpty);
      expect(overlay.isGroupUnit, isTrue);
      expect(overlay.handles, hasLength(9));
      expect(overlay.bounds.left, 0);
      expect(overlay.bounds.size.width, 10);
      expect(overlay.bounds.size.height, 10);
    });

    test('多选的逐元素轮廓保留（默认 isGroupUnit=false）', () {
      final elements = [
        rect('a', groupIds: [groupA]),
        rect('b', groupIds: [groupA]),
      ];
      final overlay = SelectionOverlay.fromElements(elements);
      expect(overlay!.elementBounds, isNotEmpty);
      expect(overlay.isGroupUnit, isFalse);
    });

    test('isGroupUnit 参与相等性判断', () {
      final elements = [
        rect('a', groupIds: [groupA]),
        rect('b', groupIds: [groupA]),
      ];
      final a = SelectionOverlay.fromElements(elements, isGroupUnit: true);
      final b = SelectionOverlay.fromElements(elements, isGroupUnit: true);
      final c = SelectionOverlay.fromElements(elements, isGroupUnit: false);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
