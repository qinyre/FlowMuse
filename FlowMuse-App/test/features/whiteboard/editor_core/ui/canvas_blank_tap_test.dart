import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Element;
import 'package:flutter_test/flutter_test.dart';

MarkdrawController _controller({
  ToolType tool = ToolType.freedraw,
  CanvasLayoutType layout = CanvasLayoutType.unbounded,
  bool fingerDrawing = false,
}) {
  final controller = MarkdrawController(
    config: MarkdrawEditorConfig(initialLayout: CanvasLayout(type: layout)),
  );
  controller.applyEditorPreferences(
    defaultTool: tool,
    defaultBrush: BrushType.ballpoint,
    brushStates: const {},
    pressureEnabled: true,
    pressureExponent: 1,
    palmRejectionEnabled: true,
    twoFingerZoomEnabled: true,
    singleFingerPanEnabled: true,
    fingerDrawingEnabled: fingerDrawing,
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _pumpEditor(
  WidgetTester tester,
  MarkdrawController controller,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: MarkdrawEditor(controller: controller)),
  );
  await tester.pumpAndSettle();
}

Offset _canvasPoint(
  WidgetTester tester, [
  Offset point = const Offset(750, 360),
]) => tester.getTopLeft(find.byType(EditorCanvas)) + point;

void main() {
  for (final layout in CanvasLayoutType.values) {
    testWidgets('$layout：画笔下手指轻点空白抬手后收起，可展开及切工具恢复', (tester) async {
      // Given: a visible creation-tool panel and finger drawing disabled.
      final controller = _controller(layout: layout);
      await _pumpEditor(tester, controller);
      final scene = controller.currentScene;
      final viewport = controller.editorState.viewport;
      final gesture = await tester.startGesture(_canvasPoint(tester));
      await tester.pump();
      expect(find.byType(PropertyPanel), findsOneWidget);

      // When: the finger lifts without editing or panning.
      await gesture.up();
      await tester.pumpAndSettle();

      // Then: only the property panel collapses.
      expect(find.byType(PropertyPanel), findsNothing);
      expect(controller.currentScene, same(scene));
      expect(controller.editorState.viewport, viewport);
      expect(controller.editorState.activeToolType, ToolType.freedraw);
      await tester.tap(find.byIcon(Icons.tune).hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(PropertyPanel), findsOneWidget);
      await tester.tapAt(_canvasPoint(tester));
      await tester.pumpAndSettle();
      controller.switchTool(ToolType.rectangle);
      await tester.pumpAndSettle();
      expect(find.byType(PropertyPanel), findsOneWidget);
    });
  }

  for (final kind in [
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  ]) {
    testWidgets('${kind.name}：选择工具空白轻点取消选择，点元素仍显示属性', (tester) async {
      final controller = _controller(tool: ToolType.select);
      final element = RectangleElement(
        id: const ElementId('rectangle'),
        x: 500,
        y: 200,
        width: 120,
        height: 100,
      );
      controller.loadScene(Scene().addElement(element));
      controller.applyResult(SetSelectionResult({element.id}));
      await _pumpEditor(tester, controller);
      await tester.tapAt(_canvasPoint(tester), kind: kind);
      await tester.pumpAndSettle();
      expect(controller.editorState.selectedIds, isEmpty);
      expect(find.byType(PropertyPanel), findsNothing);

      await tester.tapAt(
        _canvasPoint(tester, const Offset(560, 250)),
        kind: kind,
      );
      await tester.pumpAndSettle();
      expect(controller.editorState.selectedIds, {element.id});
      expect(find.byType(PropertyPanel), findsOneWidget);
    });

    testWidgets('${kind.name}：拖动对象及撤销正常，属性面板保持展开', (tester) async {
      final controller = _controller(tool: ToolType.select);
      final element = RectangleElement(
        id: const ElementId('rectangle'),
        x: 500,
        y: 200,
        width: 120,
        height: 100,
      );
      controller.loadScene(Scene().addElement(element));
      controller.applyResult(SetSelectionResult({element.id}));
      await _pumpEditor(tester, controller);
      final gesture = await tester.startGesture(
        _canvasPoint(tester, const Offset(560, 250)),
        kind: kind,
      );
      await gesture.moveBy(const Offset(60, 40));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.currentScene.getElementById(element.id)!.x, 560);
      expect(find.byType(PropertyPanel), findsOneWidget);
      controller.undo();
      expect(controller.currentScene.getElementById(element.id)!.x, 500);
    });

    testWidgets('${kind.name}：画笔轻点仍产生墨点，连续绘制及图形拖动正常', (tester) async {
      final controller = _controller(fingerDrawing: true);
      await _pumpEditor(tester, controller);
      final point = _canvasPoint(tester);
      await tester.tapAt(point, kind: kind);
      await tester.pumpAndSettle();
      expect(
        controller.currentScene.activeElements.whereType<FreedrawElement>(),
        hasLength(1),
      );
      expect(find.byType(PropertyPanel), findsOneWidget);

      var gesture = await tester.startGesture(
        point + const Offset(0, 50),
        kind: kind,
      );
      await gesture.moveBy(const Offset(35, 25));
      await gesture.moveBy(const Offset(35, -25));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.currentScene.activeElements.whereType<FreedrawElement>(),
        hasLength(2),
      );
      expect(find.byType(PropertyPanel), findsOneWidget);

      controller.switchTool(ToolType.rectangle);
      await tester.pumpAndSettle();
      gesture = await tester.startGesture(
        point + const Offset(0, 120),
        kind: kind,
      );
      await gesture.moveBy(const Offset(100, 60));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.currentScene.activeElements.whereType<RectangleElement>(),
        hasLength(1),
      );
      expect(find.byType(PropertyPanel), findsOneWidget);
    });
  }

  testWidgets('画笔下点已有对象、长按、取消及右键不收起', (tester) async {
    final controller = _controller();
    final element = RectangleElement(
      id: const ElementId('rectangle'),
      x: 500,
      y: 200,
      width: 120,
      height: 100,
    );
    controller.loadScene(Scene().addElement(element));
    await _pumpEditor(tester, controller);
    await tester.tapAt(_canvasPoint(tester, const Offset(560, 250)));
    await tester.pumpAndSettle();
    expect(controller.editorState.selectedIds, {element.id});
    expect(find.byType(PropertyPanel), findsOneWidget);
    controller.applyResult(SetSelectionResult({}));
    await tester.pumpAndSettle();

    var gesture = await tester.startGesture(_canvasPoint(tester));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    await gesture.up(
      timeStamp: kLongPressTimeout + const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PropertyPanel), findsOneWidget);
    gesture = await tester.startGesture(_canvasPoint(tester));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.byType(PropertyPanel), findsOneWidget);
    await tester.tapAt(
      _canvasPoint(tester),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byType(PropertyPanel), findsOneWidget);
  });

  for (final layout in CanvasLayoutType.values) {
    testWidgets('$layout：单指平移、双指轻点和缩放均不误收起', (tester) async {
      final controller = _controller(layout: layout);
      await _pumpEditor(tester, controller);
      final point = _canvasPoint(tester);
      final before = controller.editorState.viewport;
      var first = await tester.startGesture(point, pointer: 1);
      await first.moveBy(const Offset(0, -80));
      await first.up();
      await tester.pumpAndSettle();
      expect(controller.editorState.viewport, isNot(before));
      expect(find.byType(PropertyPanel), findsOneWidget);

      first = await tester.startGesture(point, pointer: 2);
      var second = await tester.startGesture(
        point + const Offset(100, 0),
        pointer: 3,
      );
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(find.byType(PropertyPanel), findsOneWidget);

      final zoom = controller.editorState.viewport.zoom;
      first = await tester.startGesture(point, pointer: 4);
      second = await tester.startGesture(
        point + const Offset(100, 0),
        pointer: 5,
      );
      await first.moveBy(const Offset(-30, 0));
      await second.moveBy(const Offset(30, 0));
      await second.moveBy(const Offset(30, 0));
      await second.up();
      await first.up();
      await tester.pumpAndSettle();
      expect(controller.editorState.viewport.zoom, greaterThan(zoom));
      expect(find.byType(PropertyPanel), findsOneWidget);
    });
  }
}
