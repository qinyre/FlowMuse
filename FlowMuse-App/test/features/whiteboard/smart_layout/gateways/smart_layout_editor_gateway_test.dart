import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MarkdrawController buildController() {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    return controller;
  }

  RectangleElement rect(String id) =>
      RectangleElement(id: ElementId(id), x: 10, y: 10, width: 40, height: 40);

  test('currentScene 透传控制器权威 Scene 实例', () {
    final controller = buildController();
    final gateway = SmartLayoutEditorGateway(controller);
    expect(identical(gateway.currentScene, controller.currentScene), isTrue);
  });

  test('changes 即控制器 Listenable', () {
    final controller = buildController();
    final gateway = SmartLayoutEditorGateway(controller);
    expect(identical(gateway.changes, controller), isTrue);
  });

  test('isDisposed 随控制器 dispose 翻转', () {
    final controller = MarkdrawController();
    final gateway = SmartLayoutEditorGateway(controller);
    expect(gateway.isDisposed, isFalse);
    controller.dispose();
    expect(gateway.isDisposed, isTrue);
  });

  test('serializeScene 透传格式与 includeDeleted 参数', () {
    final gateway = SmartLayoutEditorGateway(buildController());
    final text = gateway.serializeScene(
      format: DocumentFormat.markdraw,
      includeDeleted: false,
    );
    expect(text, isNotEmpty);
  });

  test('captureDraftBase 返回捕获时的不可变 Scene', () {
    final controller = buildController();
    final gateway = SmartLayoutEditorGateway(controller);
    controller.applyResult(AddElementResult(rect('r1')));
    final base = gateway.captureDraftBase();
    expect(base.elements.map((e) => e.id.value), contains('r1'));

    controller.applyResult(AddElementResult(rect('r2')));
    expect(
      base.elements.map((e) => e.id.value),
      isNot(contains('r2')),
      reason: '草稿基线必须不受后续编辑影响',
    );
    expect(
      gateway.currentScene.elements.map((e) => e.id.value),
      contains('r2'),
    );
  });

  test('addSceneChangeListener 收到 userEdit 通知且 remove 后不再收到', () {
    final controller = buildController();
    final gateway = SmartLayoutEditorGateway(controller);
    final events = <SceneChangeSource>[];
    void listener(Scene scene, SceneChangeSource source) => events.add(source);
    gateway.addSceneChangeListener(listener);
    controller.applyResult(AddElementResult(rect('r1')));
    gateway.removeSceneChangeListener(listener);
    controller.applyResult(AddElementResult(rect('r2')));
    expect(events, [SceneChangeSource.userEdit]);
  });

  test('sceneChangeListeners 不抢占 onSceneChanged 单槽', () {
    final controller = buildController();
    final gateway = SmartLayoutEditorGateway(controller);
    var slotCalls = 0;
    var listenerCalls = 0;
    controller.onSceneChanged = (_, _) => slotCalls++;
    gateway.addSceneChangeListener((_, _) => listenerCalls++);
    controller.applyResult(AddElementResult(rect('r1')));
    expect(slotCalls, greaterThanOrEqualTo(1));
    expect(listenerCalls, greaterThanOrEqualTo(1));
  });

  test('监听器内移除自身不破坏其余监听器', () {
    final controller = buildController();
    final gateway = SmartLayoutEditorGateway(controller);
    var secondCalls = 0;
    void selfRemoving(Scene scene, SceneChangeSource source) {
      gateway.removeSceneChangeListener(selfRemoving);
    }

    gateway.addSceneChangeListener(selfRemoving);
    gateway.addSceneChangeListener((_, _) => secondCalls++);
    controller.applyResult(AddElementResult(rect('r1')));
    expect(secondCalls, greaterThanOrEqualTo(1));
  });

  test('commitValidated 先存 undo 快照再应用结果', () {
    final controller = buildController();
    final gateway = SmartLayoutEditorGateway(controller);
    final before = controller.currentScene;
    gateway.commitValidated(AddElementResult(rect('committed-1')));
    expect(
      controller.currentScene.elements.map((e) => e.id.value),
      contains('committed-1'),
    );
    controller.undo();
    expect(
      controller.currentScene.elements.map((e) => e.id.value),
      isNot(contains('committed-1')),
      reason: '提交前场景应可经 undo 恢复',
    );
    expect(
      identical(controller.currentScene, before) ||
          controller.currentScene.elements.length == before.elements.length,
      isTrue,
    );
  });

  test('编辑器释放后 commitValidated 零副作用并抛 StateError', () {
    final controller = MarkdrawController();
    final gateway = SmartLayoutEditorGateway(controller);
    controller.dispose();
    expect(
      () => gateway.commitValidated(AddElementResult(rect('late'))),
      throwsStateError,
    );
    expect(
      controller.currentScene.elements.map((e) => e.id.value),
      isNot(contains('late')),
    );
  });
}
