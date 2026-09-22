import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

void main() {
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
