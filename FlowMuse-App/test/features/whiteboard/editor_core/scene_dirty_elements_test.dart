import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('场景回调只暴露本次工具结果修改的元素', () {
    final controller = MarkdrawController();
    final unchanged = RectangleElement(
      id: ElementId('unchanged'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
    );
    final changed = RectangleElement(
      id: ElementId('changed'),
      x: 20,
      y: 20,
      width: 10,
      height: 10,
    );

    controller.applyResult(AddElementResult(unchanged));
    controller.applyResult(AddElementResult(changed));

    expect(controller.lastChangedElements?.map((element) => element.id.value), [
      'changed',
    ]);

    controller.applyResult(RemoveElementResult(changed.id));
    expect(controller.lastChangedElements, hasLength(1));
    expect(controller.lastChangedElements!.single.id, changed.id);
    expect(controller.lastChangedElements!.single.isDeleted, isTrue);
  });

  test('远端增量更新保留其他元素和协作版本', () {
    final controller = MarkdrawController();
    final unchanged = RectangleElement(
      id: const ElementId('unchanged'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
    );
    controller.applyResult(AddElementResult(unchanged));
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('changed'),
          x: 20,
          y: 20,
          width: 10,
          height: 10,
        ),
      ),
    );

    SceneChangeSource? source;
    controller.onSceneChanged = (_, value) => source = value;
    controller.applyRemoteElements([
      RectangleElement(
        id: const ElementId('changed'),
        x: 30,
        y: 30,
        width: 20,
        height: 20,
        version: 9,
        versionNonce: 7,
      ),
    ]);

    final scene = controller.editorState.scene;
    expect(scene.getElementById(const ElementId('unchanged')), same(unchanged));
    final changed = scene.getElementById(const ElementId('changed'))!;
    expect(changed.version, 9);
    expect(changed.versionNonce, 7);
    expect(changed.x, 30);
    expect(source, SceneChangeSource.remoteApply);
    expect(controller.lastChangedElements, isNull);
  });

  test('远端笔迹只刷新画布，选中笔迹的属性更新仍通知工具栏', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    var canvasChanges = 0;
    var chromeChanges = 0;
    controller.addListener(() => canvasChanges++);
    controller.chromeChanges.addListener(() => chromeChanges++);
    final stroke = FreedrawElement(
      id: const ElementId('remote-stroke'),
      x: 0,
      y: 0,
      width: 20,
      height: 10,
      points: const [Point(0, 0), Point(20, 10)],
    );

    controller.applyRemoteElements([stroke]);
    expect(canvasChanges, 1);
    expect(chromeChanges, 0);
    expect(controller.currentScene.getElementById(stroke.id), same(stroke));

    controller.applyResult(SetSelectionResult({stroke.id}));
    canvasChanges = chromeChanges = 0;
    final moved = stroke.copyWith(x: 30, version: 2);
    controller.applyRemoteElements([moved]);
    expect(canvasChanges, 1);
    expect(chromeChanges, 1);
    expect(controller.selectedElements.single.x, 30);
  });

  test('reset canvas reports a full-scene replacement', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('element'),
          x: 0,
          y: 0,
          width: 10,
          height: 10,
        ),
      ),
    );

    SceneChangeSource? source;
    controller.onSceneChanged = (_, value) => source = value;
    controller.resetCanvas();

    expect(source, SceneChangeSource.reset);
    expect(controller.editorState.scene.activeElements, isEmpty);
  });
}
