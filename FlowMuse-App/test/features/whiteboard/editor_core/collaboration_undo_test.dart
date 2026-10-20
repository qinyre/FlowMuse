import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fullScene in [false, true]) {
    test('远端${fullScene ? '全场景' : '增量'}新增、修改、删除不被本地撤销重做覆盖', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      final original = Scene()
          .addElement(_rect('changed'))
          .addElement(_rect('deleted'));
      controller.loadScene(original);
      controller.applyScene(original.addElement(_rect('local')));
      final remote = [
        _rect('remote'),
        _rect('changed', version: 2, x: 70),
        _rect('deleted', version: 2).softDelete(),
      ];
      if (fullScene) {
        controller.applyRemoteScene(
          controller.currentScene.upsertRemoteElements(remote),
        );
      } else {
        controller.applyRemoteElements(remote);
      }

      controller.undo();
      expect(
        controller.currentScene.getElementById(const ElementId('local')),
        isNull,
      );
      _expectRemote(controller);
      controller.redo();
      expect(
        controller.currentScene.getElementById(const ElementId('local')),
        isNotNull,
      );
      _expectRemote(controller);
    });
  }

  test('撤销后收到远端更新，重做保留新远端版本', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyScene(Scene().addElement(_rect('local')));
    controller.undo();
    controller.applyRemoteElements([_rect('remote', version: 3, x: 90)]);
    controller.redo();
    expect(controller.currentScene.activeElements, hasLength(2));
    expect(
      controller.currentScene.getElementById(const ElementId('remote'))!.x,
      90,
    );
  });

  test('重复远端快照不把本地元素加入不可撤销集合', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyScene(Scene().addElement(_rect('local')));
    controller.applyRemoteScene(controller.currentScene);
    controller.undo();
    expect(controller.currentScene.activeElements, isEmpty);
  });

  test('远端旧版本不覆盖撤销目标里更新的本地版本', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyRemoteElements([_rect('shared', version: 2, x: 20)]);
    controller.applyScene(
      Scene().addElement(_rect('shared', version: 3, x: 30)),
    );
    controller.applyScene(controller.currentScene.addElement(_rect('local')));
    controller.undo();
    expect(
      controller.currentScene.getElementById(const ElementId('shared'))!.x,
      30,
    );
    controller.undo();
    expect(
      controller.currentScene.getElementById(const ElementId('shared'))!.x,
      20,
    );
  });

  test('本地撤销的版本规范化不阻止继续撤销，清空文档不残留远端元素', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyScene(Scene().addElement(_rect('first')));
    controller.applyScene(controller.currentScene.addElement(_rect('second')));
    controller.undo();
    controller.applyRemoteScene(
      controller.currentScene.upsertRemoteElements([
        _rect('first', version: 9),
      ]),
      recordRemoteChanges: false,
    );
    controller.undo();
    expect(controller.currentScene.activeElements, isEmpty);
    controller.applyRemoteElements([_rect('remote')]);
    controller.loadScene(Scene());
    controller.applyScene(Scene().addElement(_rect('new-local')));
    controller.undo();
    expect(controller.currentScene.activeElements, isEmpty);
  });
}

RectangleElement _rect(String id, {int version = 1, double x = 0}) =>
    RectangleElement(
      id: ElementId(id),
      x: x,
      y: 0,
      width: 40,
      height: 40,
      version: version,
      versionNonce: 10,
    );

void _expectRemote(MarkdrawController controller) {
  expect(
    controller.currentScene.getElementById(const ElementId('remote')),
    isNotNull,
  );
  expect(
    controller.currentScene.getElementById(const ElementId('changed'))!.x,
    70,
  );
  expect(
    controller.currentScene
        .getElementById(const ElementId('deleted'))!
        .isDeleted,
    isTrue,
  );
}
