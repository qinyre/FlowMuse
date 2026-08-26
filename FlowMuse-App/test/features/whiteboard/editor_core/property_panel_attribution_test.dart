import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/property_panel_state.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/property_panel_content.dart';
import 'package:flutter/material.dart' hide Element;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('单选元素且 resolver 返回动作时显示归属行；resolver 返回 null 不显示', (tester) async {
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
              controller: MarkdrawController(),
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
}
