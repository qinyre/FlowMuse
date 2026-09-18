import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/studio_rail_icon_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Finder railButton(String tooltip) => find.byWidgetPredicate(
    (widget) => widget is StudioRailIconButton && widget.tooltip == tooltip,
  );

  Future<MarkdrawController> pumpDesktopToolbar(
    WidgetTester tester, {
    ToolbarDock dock = ToolbarDock.top,
  }) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final isTop = dock == ToolbarDock.top;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: isTop ? 260 : 150,
              height: isTop ? 180 : 260,
              child: DesktopToolbar(controller: controller, dock: dock),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<MarkdrawController> pumpCompactToolbar(
    WidgetTester tester, {
    ToolbarDock dock = ToolbarDock.top,
  }) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final isTop = dock == ToolbarDock.top;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: isTop ? 300 : 160,
              height: isTop ? 180 : 280,
              child: CompactToolbar(controller: controller, dock: dock),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> tapWithKind(
    WidgetTester tester,
    Finder target,
    PointerDeviceKind kind, {
    Duration hold = const Duration(milliseconds: 80),
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: kind,
    );
    await tester.pump(hold);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> hoverThenTap(
    WidgetTester tester,
    Finder first,
    Finder second, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final gesture = await tester.createGesture(kind: kind);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(8, 8));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveTo(tester.getCenter(second));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.down(tester.getCenter(second));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  for (final dock in ToolbarDock.values) {
    testWidgets('DesktopToolbar $dock：悬停相邻按钮后触控笔一次点选', (tester) async {
      final controller = await pumpDesktopToolbar(tester, dock: dock);
      controller.switchTool(ToolType.text);
      await tester.pump();

      await hoverThenTap(tester, railButton('抓手 (H)'), railButton('选择 (1)'));

      expect(controller.editorState.activeToolType, ToolType.select);
    });
  }

  for (final dock in ToolbarDock.values) {
    testWidgets('CompactToolbar $dock：悬停相邻按钮后触控笔一次点选', (tester) async {
      final controller = await pumpCompactToolbar(tester, dock: dock);
      controller.switchTool(ToolType.text);
      await tester.pump();

      await hoverThenTap(tester, railButton('抓手'), railButton('选择'));

      expect(controller.editorState.activeToolType, ToolType.select);
    });
  }

  testWidgets('DesktopToolbar：触控笔长按、触摸和反向触控笔均只派发一次', (tester) async {
    final controller = await pumpDesktopToolbar(tester);
    final target = railButton('抓手 (H)');

    for (final kind in [
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.touch,
    ]) {
      controller.switchTool(ToolType.text);
      await tester.pump();
      await tapWithKind(
        tester,
        target,
        kind,
        hold: const Duration(milliseconds: 700),
      );
      expect(controller.editorState.activeToolType, ToolType.hand);
    }
  });

  testWidgets('DesktopToolbar：移出按钮后取消，不切换工具', (tester) async {
    final controller = await pumpDesktopToolbar(tester);
    controller.switchTool(ToolType.text);
    await tester.pump();
    final target = railButton('抓手 (H)');
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveTo(const Offset(790, 590));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.editorState.activeToolType, ToolType.text);
  });

  testWidgets('DesktopToolbar：真实滚动祖先中的拖动不切换工具', (tester) async {
    final controller = await pumpDesktopToolbar(tester);
    controller.switchTool(ToolType.text);
    await tester.pump();
    final target = railButton('抓手 (H)');
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveTo(
      Offset(tester.getCenter(target).dx + 220, tester.getCenter(target).dy),
    );
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.editorState.activeToolType, ToolType.text);
  });

  testWidgets('DesktopToolbar：真实笔盒和图形弹层一次选择成功', (tester) async {
    final controller = await pumpDesktopToolbar(tester);

    await tapWithKind(tester, railButton('笔型与压感'), PointerDeviceKind.stylus);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is StudioRailIconButton && widget.tooltip == '圆珠笔',
      ),
      findsOneWidget,
    );
    await tapWithKind(tester, railButton('圆珠笔'), PointerDeviceKind.stylus);
    expect(controller.activeBrushType, BrushType.ballpoint);
    expect(controller.editorState.activeToolType, ToolType.freedraw);

    await tapWithKind(tester, railButton('绘制图形'), PointerDeviceKind.stylus);
    await tester.pumpAndSettle();
    expect(railButton('矩形'), findsOneWidget);
    await tapWithKind(tester, railButton('矩形'), PointerDeviceKind.stylus);
    expect(controller.editorState.activeToolType, ToolType.rectangle);
  });
}
