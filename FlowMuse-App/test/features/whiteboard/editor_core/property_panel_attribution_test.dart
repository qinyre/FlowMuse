import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/material.dart' hide Element;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('单选元素显示归属与聚焦入口', (tester) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    var pressed = 0;
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
            ),
          ),
        ),
      ),
    );
    expect(find.text('由 张三 创建'), findsOneWidget);
    expect(find.text('查看张三的内容'), findsOneWidget);
    await tester.tap(find.text('查看张三的内容'));
    await tester.pump();
    expect(pressed, 1);
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
        final buttonRect = tester.getRect(
          find.widgetWithText(TextButton, action),
        );
        // 两段内容各有完整的横向空间，按钮不能再挤压创建者说明。
        expect(labelRect.width, greaterThanOrEqualTo(170));
        expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.top));
        expect(labelRect.height, lessThan(80));
        await tester.tap(find.text(action));
        await tester.pump();
        expect(pressed, greaterThan(0));
      }
    }
    expect(pressed, 4);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
