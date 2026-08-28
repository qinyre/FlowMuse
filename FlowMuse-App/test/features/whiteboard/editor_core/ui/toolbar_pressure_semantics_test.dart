import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/toolbar_palette_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 笔盒压力交互语义（Issue #5 T8 / A16）：
/// 圆珠笔/荧光笔恒定线宽（隐藏滑块+说明文案），压感笔型正常显示；
/// 各笔型颜色/宽度/压力偏好互不串扰。
void main() {
  Future<MarkdrawController> pumpPalette(WidgetTester tester) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BrushPaletteButton(
              controller: controller,
              dock: ToolbarDock.top,
              size: 40,
            ),
          ),
        ),
      ),
    );
    // 打开笔盒弹层（点击按钮）
    await tester.tap(find.byType(BrushPaletteButton));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('钢笔（默认）：显示压力滑块', (tester) async {
    final controller = await pumpPalette(tester);
    expect(controller.activeBrushType, BrushType.fountainPen);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('圆珠笔：隐藏滑块并显示恒定线宽说明', (tester) async {
    final controller = await pumpPalette(tester);
    // 切到圆珠笔（弹层随选择关闭）
    await tester.tap(find.byTooltip('圆珠笔'));
    await tester.pumpAndSettle();
    expect(controller.activeBrushType, BrushType.ballpoint);

    // 重新打开：滑块隐藏、文案出现
    await tester.tap(find.byType(BrushPaletteButton));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(find.text('恒定线宽'), findsOneWidget);
  });

  testWidgets('荧光笔：同圆珠笔语义', (tester) async {
    final controller = await pumpPalette(tester);
    await tester.tap(find.byTooltip('荧光笔'));
    await tester.pumpAndSettle();
    expect(controller.activeBrushType, BrushType.highlighter);

    await tester.tap(find.byType(BrushPaletteButton));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(find.text('恒定线宽'), findsOneWidget);
  });

  testWidgets('毛笔/铅笔：保留压力滑块', (tester) async {
    final controller = await pumpPalette(tester);
    await tester.tap(find.byTooltip('毛笔'));
    await tester.pumpAndSettle();
    expect(controller.activeBrushType, BrushType.brushPen);
    await tester.tap(find.byType(BrushPaletteButton));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('A16: 各笔型压力偏好互不串扰，切换不丢设置', (tester) async {
    final controller = await pumpPalette(tester);
    // 钢笔设 0.3
    await tester.drag(find.byType(Slider), const Offset(-120, 0));
    await tester.pumpAndSettle();
    final fountainValue = controller.pressureSensitivity;

    // 圆珠笔（无滑块）不改变任何偏好
    await tester.tap(find.byTooltip('圆珠笔'));
    await tester.pumpAndSettle();

    // 切回钢笔：偏好保留且滑块回到该值
    controller.activeBrushType = BrushType.fountainPen;
    await tester.pumpAndSettle();
    expect(controller.pressureSensitivity, fountainValue);
    expect(
      controller.pressureSensitivity,
      lessThan(0.5),
      reason: '拖动应改变了钢笔灵敏度',
    );

    // 毛笔默认 0.85，不受钢笔 0.3 影响
    controller.activeBrushType = BrushType.brushPen;
    await tester.pumpAndSettle();
    expect(
      controller.pressureSensitivity,
      BrushState.defaults[BrushType.brushPen]!.pressureSensitivity,
      reason: '毛笔独立偏好',
    );
  });
}
