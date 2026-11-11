import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MarkdrawController> _openCanvas(
  WidgetTester tester, {
  CanvasPageFlow flow = CanvasPageFlow.topToBottom,
}) async {
  final controller = MarkdrawController(
    config: MarkdrawEditorConfig(
      initialLayout: CanvasLayout(type: CanvasLayoutType.paged, pageFlow: flow),
    ),
  )..switchTool(ToolType.hand);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: EditorCanvas(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
  controller.scrollPagedViewportBy(100000);
  return controller;
}

Future<void> _wheel(WidgetTester tester, double delta) =>
    tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(EditorCanvas)),
        scrollDelta: Offset(0, delta),
      ),
    );

void main() {
  for (final flow in CanvasPageFlow.values) {
    testWidgets('${flow.name} 抓手拖过末页边界后松开新增一页，可撤销重做', (tester) async {
      final controller = await _openCanvas(tester, flow: flow);
      final before = controller.layout.pages.length;
      final canvas = tester.getRect(find.byType(EditorCanvas));
      final start = flow == CanvasPageFlow.topToBottom
          ? canvas.bottomCenter - const Offset(0, 10)
          : canvas.centerLeft + const Offset(10, 0);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(
        flow == CanvasPageFlow.topToBottom
            ? const Offset(0, -380)
            : const Offset(380, 0),
      );
      expect(controller.layout.pages.length, before);
      await gesture.up();
      await tester.pump();
      expect(controller.layout.pages.length, before + 1);
      expect(controller.editorState.activeToolType, ToolType.hand);
      controller.undo();
      expect(controller.layout.pages.length, before);
      controller.redo();
      expect(controller.layout.pages.length, before + 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${flow.name} 末页继续滚动，停下后只新增一页', (tester) async {
      final controller = await _openCanvas(tester, flow: flow);
      final before = controller.layout.pages.length;
      await _wheel(tester, 600);
      expect(controller.layout.pages.length, before);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.layout.pages.length, before + 1);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.layout.pages.length, before + 1);
      expect(controller.layout.pages.last.pageFlow, flow);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('滚轮未到阈值或反向撤回不会新增页面', (tester) async {
    final controller = await _openCanvas(tester);
    final before = controller.layout.pages.length;
    await _wheel(tester, 60);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controller.layout.pages.length, before);
    await _wheel(tester, 600);
    await _wheel(tester, -600);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controller.layout.pages.length, before);
  });

  testWidgets('抓手取消、回拉或只读拖动不会新增页面', (tester) async {
    final controller = await _openCanvas(tester);
    final before = controller.layout.pages.length;
    for (final action in ['取消', '回拉', '只读']) {
      if (action == '只读') controller.toggleViewMode();
      final gesture = await tester.startGesture(
        tester.getRect(find.byType(EditorCanvas)).bottomCenter -
            const Offset(0, 10),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -380));
      if (action == '取消') {
        await gesture.cancel();
      } else {
        if (action == '回拉') await gesture.moveBy(const Offset(0, 380));
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(controller.layout.pages.length, before, reason: action);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('只读和缩放不会提交待执行的滚轮新增', (tester) async {
    final controller = await _openCanvas(tester);
    final before = controller.layout.pages.length;
    await _wheel(tester, 600);
    controller.toggleViewMode();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controller.layout.pages.length, before);
    await _wheel(tester, 600);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.layout.pages.length, before);
    controller.toggleViewMode();

    await _wheel(tester, 600);
    final zoom = controller.editorState.viewport.zoom;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      await _wheel(tester, -100);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controller.editorState.viewport.zoom, greaterThan(zoom));
    expect(controller.layout.pages.length, before);
  });

  testWidgets('切换笔记或销毁画布会取消待执行的滚轮新增', (tester) async {
    final previous = await _openCanvas(tester);
    await _wheel(tester, 600);
    previous.insertBlankPage();
    final previousCount = previous.layout.pages.length;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(previous.layout.pages.length, previousCount);
    previous.scrollPagedViewportBy(100000);
    await _wheel(tester, 600);
    final current = await _openCanvas(tester);
    final currentCount = current.layout.pages.length;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(previous.layout.pages.length, previousCount);
    expect(current.layout.pages.length, currentCount);
    await _wheel(tester, 600);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(current.layout.pages.length, currentCount);
    expect(tester.takeException(), isNull);
  });
}
