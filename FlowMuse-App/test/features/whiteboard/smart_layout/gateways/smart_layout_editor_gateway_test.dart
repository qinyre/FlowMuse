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

  for (final tool in [ToolType.freedraw, ToolType.text, ToolType.select]) {
    test('V3 应用保持预览样式并支持撤销重做：${tool.name}', () {
      final controller = buildController();
      controller.switchTool(tool);
      controller.applyStyleChange(
        const ElementStyle(
          strokeColor: '#ff0000',
          fontSize: 64,
          fontFamily: 'Excalifont',
        ),
      );
      final text = TextElement(
        id: ElementId('composed-text'),
        x: 48,
        y: 80,
        width: 240,
        height: 64,
        text: '排版后的文字',
        fontSize: 24,
        fontFamily: 'Helvetica',
        lineHeight: 1.35,
        strokeColor: '#222222',
        autoResize: false,
      );
      final picture = ImageElement(
        id: ElementId('composed-image'),
        x: 320,
        y: 80,
        width: 120,
        height: 90,
        fileId: 'image-file',
        crop: const ImageCrop(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
      );
      void expectPreviewAttributes() {
        final actual = controller.currentScene.activeElements;
        final applied = actual.whereType<TextElement>().single;
        expect(applied.text, text.text);
        expect(applied.fontSize, text.fontSize);
        expect(applied.fontFamily, text.fontFamily);
        expect(applied.lineHeight, text.lineHeight);
        expect(applied.strokeColor, text.strokeColor);
        expect(
          [applied.x, applied.y, applied.width, applied.height],
          [text.x, text.y, text.width, text.height],
        );
        final image = actual.whereType<ImageElement>().single;
        expect(image.crop, picture.crop);
        expect(image.fileId, picture.fileId);
        expect(
          [image.x, image.y, image.width, image.height],
          [picture.x, picture.y, picture.width, picture.height],
        );
      }

      SmartLayoutEditorGateway(controller).commitValidated(
        CompoundResult([AddElementResult(text), AddElementResult(picture)]),
      );
      expectPreviewAttributes();
      controller.undo();
      expect(controller.currentScene.activeElements, isEmpty);
      controller.redo();
      expectPreviewAttributes();
    });
  }
}
