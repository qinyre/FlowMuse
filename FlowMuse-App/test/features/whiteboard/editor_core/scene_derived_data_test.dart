import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

void main() {
  test('批量更新与逐项操作保持顺序、版本及不存在 ID 的语义', () {
    final a = RectangleElement(
      id: ElementId('a'),
      x: 0,
      y: 0,
      width: 20,
      height: 20,
    );
    final b = a.copyWith(id: ElementId('b'));
    final initial = EditorState(
      scene: Scene().upsertRemoteElements([a, b]),
      viewport: const ViewportState(),
      selectedIds: {},
      activeToolType: ToolType.select,
    );
    final results = <ToolResult>[
      UpdateElementResult(a.copyWith(x: 10)),
      UpdateElementResult(a.copyWith(x: 20, version: 8)),
      UpdateElementResult(a.copyWith(id: ElementId('missing'))),
      RemoveElementResult(b.id),
      UpdateElementResult(b.copyWith(y: 30)),
      AddElementResult(a.copyWith(id: ElementId('c'))),
      CompoundResult([
        UpdateElementResult(a.copyWith(id: ElementId('c'), x: 40)),
        UpdateElementResult(a.copyWith(x: 50)),
      ]),
      SetSelectionResult({a.id}),
    ];
    EditorState sequential(EditorState state, ToolResult result) =>
        result is CompoundResult
        ? result.results.fold(state, sequential)
        : state.applyResult(result);
    final expected = results.fold(initial, sequential);
    final actual = initial.applyResult(CompoundResult(results));
    expect(actual.selectedIds, expected.selectedIds);
    expect(
      actual.scene.elements.map((e) => e.id),
      expected.scene.elements.map((e) => e.id),
    );
    for (final element in expected.scene.elements) {
      final changed = actual.scene.getElementById(element.id)!;
      expect(
        (changed.x, changed.y, changed.version, changed.isDeleted),
        (element.x, element.y, element.version, element.isDeleted),
      );
    }
    expect(actual.scene.getElementById(ElementId('missing')), isNull);
    expect(initial.scene.getElementById(a.id), same(a));
  });

  test('绑定索引保留去重、删除和远端修改语义，查询副本不污染快照', () {
    final id = ElementId('target');
    final arrow = ArrowElement(
      id: ElementId('arrow'),
      x: 0,
      y: 0,
      width: 20,
      height: 20,
      points: const [Point(0, 0), Point(20, 20)],
      startBinding: PointBinding(
        elementId: id.value,
        fixedPoint: const Point(1, .5),
      ),
      endBinding: PointBinding(
        elementId: id.value,
        fixedPoint: const Point(0, .5),
      ),
    );
    final scene = Scene().addElement(arrow);
    expect(scene.findBoundArrows(id), [arrow]);
    scene.findBoundArrows(id).clear();
    expect(scene.findBoundArrows(id), [arrow]);
    final deleted = scene.softDeleteElement(arrow.id);
    expect(deleted.findBoundArrows(id), isEmpty);
    expect(scene.getElementById(arrow.id), same(arrow));
    final remote = deleted.upsertRemoteElements([
      arrow.copyWithArrow(clearStartBinding: true, clearEndBinding: true),
    ]);
    expect(remote.findBoundArrows(id), isEmpty);
    expect(scene.findBoundArrows(id), [arrow]);
  });

  test('场景排序副本、重复绑定优先级与编辑/远端更新均保持原语义', () {
    final parent = RectangleElement(
      id: ElementId('parent'),
      x: 0,
      y: 0,
      width: 100,
      height: 60,
      index: 'a1',
    );
    final first = TextElement(
      id: ElementId('first'),
      x: 0,
      y: 0,
      width: 50,
      height: 20,
      text: 'first',
      containerId: 'parent',
      index: 'a0',
    );
    final second = first
        .copyWith(id: ElementId('second'), index: 'a2')
        .copyWithText(text: 'second');
    final scene = Scene()
        .addElement(parent)
        .addElement(first)
        .addElement(second);
    expect(scene.orderedElements.map((e) => e.id.value), [
      'first',
      'parent',
      'second',
    ]);
    scene.orderedElements.clear();
    expect(scene.orderedElements, hasLength(3));
    expect(scene.findBoundText(parent.id), same(first));

    final deleted = scene.softDeleteElement(first.id);
    expect(deleted.findBoundText(parent.id), same(second));
    expect(scene.findBoundText(parent.id), same(first));
    final remote = deleted.upsertRemoteElements([
      first.copyWith(index: 'a3').copyWithText(text: 'restored'),
    ]);
    expect(remote.findBoundText(parent.id)!.text, 'restored');
    expect(remote.orderedElements.map((e) => e.id.value), [
      'parent',
      'second',
      'first',
    ]);
    final moved = remote.updateElement(
      first.copyWithText(containerId: 'other'),
    );
    expect(moved.findBoundText(parent.id), same(second));
    expect(moved.findBoundText(ElementId('other'))!.id, first.id);
    expect(moved.removeElement(second.id).findBoundText(parent.id), isNull);
  });
}
