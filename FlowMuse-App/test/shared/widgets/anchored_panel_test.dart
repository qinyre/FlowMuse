import 'dart:async';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 面板容器：菜单文本向上找到的第一个 DecoratedBox 即纸面容器。
Finder _panelContainerOf(String itemText) {
  return find
      .ancestor(of: find.text(itemText), matching: find.byType(DecoratedBox))
      .first;
}

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required void Function(BuildContext) onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('panel-anchor'),
              onPressed: () => onOpen(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('panel-anchor')));
    await tester.pumpAndSettle();
  }

  testWidgets('选中菜单项返回结果并关闭面板', (tester) async {
    String? selected;
    await pumpHost(
      tester,
      onOpen: (context) => unawaited(
        showAnchoredPopupMenu<String>(
          context: context,
          items: const [
            PopupMenuItem(value: 'a', child: Text('选项A')),
            PopupMenuItem(value: 'b', child: Text('选项B')),
          ],
        ).then((value) => selected = value),
      ),
    );

    expect(find.text('选项A'), findsOneWidget);

    await tester.tap(find.text('选项B'));
    await tester.pumpAndSettle();

    expect(selected, 'b');
    expect(find.text('选项B'), findsNothing);
  });

  testWidgets('点击屏障关闭且不产生选择结果', (tester) async {
    String? selected;
    var dismissed = false;
    await pumpHost(
      tester,
      onOpen: (context) => unawaited(
        showAnchoredPopupMenu<String>(
          context: context,
          items: const [PopupMenuItem(value: 'a', child: Text('选项A'))],
        ).then((value) {
          selected = value;
          dismissed = value == null;
        }),
      ),
    );

    // 面板外的空白区域（屏幕右下角）触发 barrier 关闭。
    await tester.tapAt(const Offset(780, 580));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(dismissed, isTrue);
    expect(find.text('选项A'), findsNothing);
  });

  testWidgets('面板容器使用纸面样式：亮底、12 圆角、细边框', (tester) async {
    await pumpHost(
      tester,
      onOpen: (context) => unawaited(
        showAnchoredPopupMenu<String>(
          context: context,
          placement: AnchoredPopupPlacement.below,
          items: const [PopupMenuItem(value: 'a', child: Text('选项A'))],
        ),
      ),
    );

    final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    final container = tester.widget<DecoratedBox>(_panelContainerOf('选项A'));
    final decoration = container.decoration as BoxDecoration;

    expect(decoration.color, theme.colorScheme.surface);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(decoration.boxShadow, hasLength(3));
  });

  testWidgets('按坐标弹出的变体可显示与选择', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('panel-anchor'),
              onPressed: () => unawaited(
                showAnchoredPopupMenuAt<String>(
                  context: context,
                  position: RelativeRect.fromLTRB(40, 80, 40, 300),
                  items: const [
                    PopupMenuItem(value: 'x', child: Text('坐标选项')),
                  ],
                ).then((value) => selected = value),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('panel-anchor')));
    await tester.pumpAndSettle();

    final itemRect = tester.getRect(find.text('坐标选项'));
    expect(itemRect.top, greaterThanOrEqualTo(10));

    await tester.tap(find.text('坐标选项'));
    await tester.pumpAndSettle();
    expect(selected, 'x');
  });
}
