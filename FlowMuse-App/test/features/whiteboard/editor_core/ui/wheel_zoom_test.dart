import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Element;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Web 缩放信号围绕指针放大和缩小，不改变场景', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.setViewport(
      const ViewportState(offset: Offset(30, 40), zoom: 1),
    );
    final scene = controller.currentScene;
    const anchor = Offset(200, 150);
    final scenePoint = controller.toScenePrecise(anchor);

    controller.onPointerSignal(
      const PointerScaleEvent(position: anchor, scale: 1.25),
    );
    expect(controller.editorState.viewport.zoom, 1.25);
    expect(controller.toScenePrecise(anchor), scenePoint);
    controller.onPointerSignal(
      const PointerScaleEvent(position: anchor, scale: 0.8),
    );
    expect(controller.editorState.viewport.zoom, closeTo(1, 1e-10));
    expect(controller.toScenePrecise(anchor), scenePoint);
    expect(controller.currentScene, same(scene));
  });

  test('缩放信号沿用配置上下限，忽略单位及非法倍率', () {
    final controller = MarkdrawController(
      config: const MarkdrawEditorConfig(minZoom: 0.5, maxZoom: 2),
    );
    addTearDown(controller.dispose);
    controller.onPointerSignal(const PointerScaleEvent(scale: 100));
    expect(controller.editorState.viewport.zoom, 2);
    controller.onPointerSignal(const PointerScaleEvent(scale: 0.001));
    expect(controller.editorState.viewport.zoom, 0.5);

    final before = controller.editorState.viewport;
    for (final scale in [0.0, -1.0, double.nan, double.infinity, 1.0]) {
      controller.onPointerSignal(PointerScaleEvent(scale: scale));
      expect(controller.editorState.viewport, same(before));
    }
  });

  test('零垂直滚轮不缩放，无限画布普通滚轮保持原有行为', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final before = controller.editorState.viewport;
    controller.onPointerSignal(
      const PointerScrollEvent(scrollDelta: Offset(100, 0)),
    );
    expect(controller.editorState.viewport, same(before));
    controller.onPointerSignal(
      const PointerScrollEvent(scrollDelta: Offset(0, -100)),
    );
    expect(controller.editorState.viewport.zoom, closeTo(1.1, 1e-10));
  });

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets('分页普通滚轮翻页，${modifier.keyLabel}＋滚轮仍缩放', (tester) async {
      final controller = MarkdrawController(
        config: const MarkdrawEditorConfig(
          initialLayout: CanvasLayout(type: CanvasLayoutType.paged),
        ),
      )..canvasSize = const Size(400, 400);
      addTearDown(controller.dispose);
      final before = controller.editorState.viewport;
      controller.onPointerSignal(
        const PointerScrollEvent(scrollDelta: Offset(0, 100)),
      );
      expect(controller.editorState.viewport.zoom, before.zoom);
      expect(
        controller.editorState.viewport.offset.dy,
        greaterThan(before.offset.dy),
      );

      await tester.sendKeyDownEvent(modifier);
      try {
        controller.onPointerSignal(
          const PointerScrollEvent(scrollDelta: Offset(0, -100)),
        );
        expect(controller.editorState.viewport.zoom, greaterThan(before.zoom));
      } finally {
        await tester.sendKeyUpEvent(modifier);
      }
    });
  }

  testWidgets('Canvas 转发缩放信号并使用画布局部坐标', (tester) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    var interactions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: EditorCanvas(
              controller: controller,
              onUserInteraction: () => interactions++,
            ),
          ),
        ),
      ),
    );
    controller.setViewport(const ViewportState(offset: Offset(10, 20)));
    const localAnchor = Offset(180, 130);
    final scenePoint = controller.toScenePrecise(localAnchor);
    await tester.sendEventToBinding(
      PointerScaleEvent(
        position: tester.getTopLeft(find.byType(EditorCanvas)) + localAnchor,
        scale: 1.5,
      ),
    );
    expect(controller.editorState.viewport.zoom, 1.5);
    expect(controller.toScenePrecise(localAnchor), scenePoint);
    expect(interactions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets('快捷键帮助按 $platform 显示滚轮修饰键', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHelpDialog(context),
              child: const Text('帮助'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('帮助'));
      await tester.pumpAndSettle();
      final mod = platform == TargetPlatform.macOS ? 'Cmd' : 'Ctrl';
      expect(find.text('$mod + 滚轮上 / 下'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
