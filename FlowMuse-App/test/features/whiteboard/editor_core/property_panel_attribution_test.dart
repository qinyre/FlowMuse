import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/material.dart' hide Element;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('混合选区默认紧凑，详细样式与排列操作独立展开', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rectangle = RectangleElement(
      id: const ElementId('rectangle'),
      x: 420,
      y: 250,
      width: 120,
      height: 80,
    );
    final text = TextElement(
      id: const ElementId('text'),
      x: 460,
      y: 330,
      width: 90,
      height: 36,
      text: '混合选区',
    );
    final stroke = FreedrawElement(
      id: const ElementId('stroke'),
      x: 480,
      y: 390,
      width: 120,
      height: 20,
      points: const [Point(0, 0), Point(120, 20)],
    );
    final controller = MarkdrawController()
      ..loadScene(
        Scene().addElement(rectangle).addElement(text).addElement(stroke),
      )
      ..applyResult(SetSelectionResult({rectangle.id, text.id, stroke.id}));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdrawEditor(
          controller: controller,
          selectionActions: {'解释这段': () {}},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byType(PropertyPanel);
    expect(find.text('已选 3 项'), findsOneWidget);
    expect(tester.getSize(panel).height, greaterThanOrEqualTo(480));
    expect(find.text('描边宽度'), findsOneWidget);
    expect(find.text('透明度'), findsOneWidget);
    expect(
      tester.getCenter(find.text('AI 助手')).dy,
      tester.getCenter(find.text('更多')).dy,
    );
    for (final label in ['背景', '填充样式', '字体', '图层顺序', '对齐']) {
      expect(find.text(label), findsNothing);
    }

    Future<void> openDetails(String label) async {
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('详细样式'), findsNothing);
    expect(find.text('字体'), findsNothing);

    await openDetails('详细样式');
    expect(find.text('填充样式'), findsOneWidget);
    expect(find.text('字体'), findsOneWidget);
    expect(find.text('图层顺序'), findsNothing);
    await tester.tap(find.text('收起详情'));
    await tester.pumpAndSettle();

    await openDetails('排列与操作');
    expect(find.text('图层顺序'), findsOneWidget);
    expect(find.text('对齐'), findsOneWidget);
    expect(find.text('字体'), findsNothing);

    controller.applyResult(SetSelectionResult({text.id}));
    await tester.pumpAndSettle();
    expect(find.text('选区属性'), findsOneWidget);
    expect(find.text('字号'), findsOneWidget);
    expect(find.text('图层顺序'), findsNothing);
    controller.requestColorPicker(ColorPickerTarget.font);
    await tester.pumpAndSettle();
    expect(controller.fontPickerOpen, isTrue);
    expect(find.text('文字对齐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中笔迹和自由绘制的属性面板保持上沿与基础高度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final stroke = FreedrawElement(
      id: const ElementId('ink'),
      x: 420,
      y: 320,
      width: 120,
      height: 20,
      points: const [Point(0, 0), Point(120, 20)],
    );
    final controller = MarkdrawController()
      ..loadScene(Scene().addElement(stroke))
      ..applyResult(SetSelectionResult({stroke.id}));
    addTearDown(controller.dispose);
    var invoked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdrawEditor(
          controller: controller,
          selectionActions: {'解释这段': () => invoked = true},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byType(PropertyPanel);
    final top = tester.getTopLeft(panel).dy;

    final collapsedHeight = tester.getSize(panel).height;
    expect(top, lessThan(180));
    expect(collapsedHeight, greaterThanOrEqualTo(480));
    expect(find.text('笔迹粗细'), findsOneWidget);
    expect(find.text('透明度'), findsOneWidget);
    expect(find.text('填充样式'), findsNothing);
    expect(find.text('图层顺序'), findsNothing);
    expect(find.text('解释这段'), findsNothing);

    await tester.tap(find.text('AI 助手'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解释这段'));
    await tester.pumpAndSettle();
    expect(invoked, isTrue);

    await tester.tap(find.text('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('图层顺序'), findsOneWidget);
    expect(tester.getSize(panel).height, greaterThanOrEqualTo(collapsedHeight));
    expect(tester.getTopLeft(panel).dy, top);
    await tester.tap(find.text('收起操作'));
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, collapsedHeight);

    controller.applyResult(SetSelectionResult({}));
    controller.switchTool(ToolType.freedraw);
    await tester.pumpAndSettle();
    expect(find.text('自由绘制'), findsOneWidget);
    expect(tester.getTopLeft(panel).dy, top);
    expect(tester.getSize(panel).height, greaterThanOrEqualTo(360));

    await tester.binding.setSurfaceSize(const Size(1200, 360));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(panel).dy, lessThanOrEqualTo(360));
    await tester.scrollUntilVisible(
      find.byType(Slider),
      100,
      scrollable: find.descendant(of: panel, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Slider).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单选元素显示归属与聚焦入口', (tester) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    var pressed = 0;
    var explained = false;
    ({String attributionLabel, String actionLabel, VoidCallback onPressed})?
    resolver(Element element) {
      return element.id == const ElementId('has-owner')
          ? (
              attributionLabel: '由 张三 创建',
              actionLabel: '查看张三的内容',
              onPressed: () => pressed++,
            )
          : null;
    }

    final element = RectangleElement(
      id: const ElementId('has-owner'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PropertyPanelContent(
              controller: controller,
              style: PropertyPanelState.fromElements([element]),
              elements: [element],
              isLocked: false,
              showFullTextProps: false,
              isEditingText: false,
              attributionActionResolver: resolver,
              selectionActions: {'解释这段': () => explained = true},
            ),
          ),
        ),
      ),
    );
    expect(find.text('由 张三 创建'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('查看张三的内容')), findsOneWidget);
    } finally {
      semantics.dispose();
    }
    expect(find.text('查看张三的内容'), findsNothing);
    await tester.tap(find.text('由 张三 创建'));
    await tester.pump();
    expect(pressed, 1);
    expect(find.text('解释这段'), findsNothing);
    await tester.tap(find.text('AI 助手'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解释这段'));
    await tester.pumpAndSettle();
    expect(explained, isTrue);
  });

  testWidgets('长创建者归属在桌面窄面板和紧凑面板中可读且可聚焦', (tester) async {
    final stroke = FreedrawElement(
      id: const ElementId('stroke'),
      x: 0,
      y: 0,
      width: 100,
      height: 10,
      points: const [Point(0, 0), Point(100, 10)],
    );
    final controller = MarkdrawController()
      ..loadScene(Scene().addElement(stroke))
      ..applyResult(SetSelectionResult({stroke.id}));
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const name = '测试协作者名字比较长#ABCD（历史会话）';
    const attribution = '由 $name 创建';
    const action = '查看$name的内容';
    var pressed = 0;
    ({String attributionLabel, String actionLabel, VoidCallback onPressed})
    resolver(Element element) => (
      attributionLabel: attribution,
      actionLabel: action,
      onPressed: () => pressed++,
    );

    for (final compact in [false, true]) {
      await tester.binding.setSurfaceSize(
        compact ? const Size(360, 800) : const Size(1200, 900),
      );
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: compact
                  ? Builder(
                      builder: (context) => TextButton(
                        onPressed: () => showCompactPropertyPanel(
                          context,
                          controller,
                          attributionActionResolver: resolver,
                        ),
                        child: const Text('属性'),
                      ),
                    )
                  : Align(
                      alignment: Alignment.topLeft,
                      child: PropertyPanel(
                        controller: controller,
                        attributionActionResolver: resolver,
                      ),
                    ),
            ),
          ),
        );
        if (compact) await tester.tap(find.text('属性'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final labelRect = tester.getRect(find.text(attribution));
        final card = find.widgetWithText(InkWell, attribution);
        final icon = find.descendant(
          of: card,
          matching: find.byIcon(Icons.center_focus_strong),
        );
        expect(tester.getSize(card).height, greaterThanOrEqualTo(44));
        expect(labelRect.width, greaterThanOrEqualTo(120));
        expect(labelRect.right, lessThan(tester.getRect(icon).left));
        expect(labelRect.height, lessThan(80));
        await tester.tap(card);
        await tester.pump();
        expect(pressed, greaterThan(0));
      }
    }
    expect(pressed, 4);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
