import 'dart:async';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import 'package:flow_muse/shared/widgets/anchored_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder panel(String text) => find
    .ancestor(of: find.text(text), matching: find.byType(DecoratedBox))
    .first;

void main() {
  testWidgets('减少动画设置和无障碍关闭提示生效', (tester) async {
    final semantics = tester.ensureSemantics();
    late BuildContext anchor;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              anchor = context;
              return TextButton(
                onPressed: () => unawaited(
                  showAnchoredPopupMenu<String>(
                    context: context,
                    items: const [
                      PopupMenuItem(value: 'a', child: Text('无障碍选项')),
                    ],
                  ),
                ),
                child: const Text('打开'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(of: panel('无障碍选项'), matching: find.byType(ScaleTransition)),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(
        MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('窄屏长菜单可滚动选择末项', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showAnchoredPopupMenu<int>(
                  context: context,
                  items: [
                    for (var i = 0; i < 40; i++)
                      PopupMenuItem(value: i, child: Text('长菜单选项$i')),
                  ],
                ).then((value) => selected = value),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(panel('长菜单选项0'));
    expect(rect.left, greaterThanOrEqualTo(10));
    expect(rect.right, lessThanOrEqualTo(310));
    expect(rect.bottom, lessThanOrEqualTo(470));
    await tester.ensureVisible(find.text('长菜单选项39'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('长菜单选项39'));
    await tester.pumpAndSettle();
    expect(selected, 39);
  });

  testWidgets('左侧面板的右边缘位于锚点左侧', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showAnchoredPopupMenu<String>(
                    context: context,
                    placement: AnchoredPopupPlacement.left,
                    items: const [
                      PopupMenuItem(value: 'a', child: Text('左侧选项')),
                    ],
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    final anchor = tester.getRect(find.byType(TextButton));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tester.getRect(panel('左侧选项')).right, lessThanOrEqualTo(anchor.left));
  });

  testWidgets('面板位置尊重安全区和软键盘且负坐标不越界', (tester) async {
    late BuildContext anchor;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.fromLTRB(30, 20, 40, 10),
            viewInsets: const EdgeInsets.only(bottom: 200),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              anchor = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    unawaited(
      showAnchoredPopupMenuAt<String>(
        context: anchor,
        position: const RelativeRect.fromLTRB(-20, -20, 0, 0),
        items: const [PopupMenuItem(value: 'a', child: Text('边界选项'))],
      ),
    );
    await tester.pumpAndSettle();
    var rect = tester.getRect(panel('边界选项'));
    expect(rect.left, greaterThanOrEqualTo(40));
    expect(rect.top, greaterThanOrEqualTo(30));
    Navigator.of(anchor).pop();
    await tester.pumpAndSettle();
    unawaited(
      showAnchoredPopupMenuAt<String>(
        context: anchor,
        position: const RelativeRect.fromLTRB(780, 550, 0, 0),
        items: const [PopupMenuItem(value: 'a', child: Text('边界选项'))],
      ),
    );
    await tester.pumpAndSettle();
    rect = tester.getRect(panel('边界选项'));
    expect(rect.right, lessThanOrEqualTo(750));
    expect(rect.bottom, lessThanOrEqualTo(390));
  });

  testWidgets('面板纸面颜色继承触发器的局部主题', (tester) async {
    final localTheme = ThemeData.dark();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Theme(
            data: localTheme,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showAnchoredPopupMenu<String>(
                    context: context,
                    items: const [
                      PopupMenuItem(value: 'a', child: Text('主题选项')),
                    ],
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final box = tester.widget<DecoratedBox>(panel('主题选项'));
    expect(
      (box.decoration as BoxDecoration).color,
      localTheme.colorScheme.surface,
    );
  });

  testWidgets('向下展开动画固定面板顶边而非缩放整个屏幕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showAnchoredPopupMenu<String>(
                    context: context,
                    placement: AnchoredPopupPlacement.below,
                    items: const [
                      PopupMenuItem(value: 'a', child: Text('动画选项')),
                    ],
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final during = tester.getRect(panel('动画选项'));
    await tester.pumpAndSettle();
    expect(during.top, closeTo(tester.getRect(panel('动画选项')).top, 0.01));
  });

  testWidgets('菜单可用方向键选择并由 Escape 关闭', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showAnchoredPopupMenu<String>(
                  context: context,
                  items: const [
                    PopupMenuItem<String>(enabled: false, child: Text('禁用')),
                    PopupMenuItem(value: 'a', child: Text('键盘选项')),
                  ],
                ).then((value) => selected = value),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'a');
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('键盘选项'), findsNothing);
  });

  testWidgets('下拉触发器销毁后选择不会回调旧页面', (tester) async {
    var showField = true;
    var callbacks = 0;
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return showField
                  ? AnchoredDropdownField<int>(
                      value: 1,
                      options: const [1, 2],
                      labelOf: (value) => '值$value',
                      onChanged: (_) => callbacks++,
                    )
                  : const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('值1'));
    await tester.pumpAndSettle();
    updateHost(() => showField = false);
    await tester.pump();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, '值2'));
    await tester.pumpAndSettle();
    expect(callbacks, 0);
    expect(find.byType(CheckedPopupMenuItem<int>), findsNothing);
  });

  testWidgets('没有变更回调的下拉框保持禁用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnchoredDropdownField<int>(
            value: 1,
            options: const [1, 2],
            labelOf: (value) => '值$value',
          ),
        ),
      ),
    );
    await tester.tap(find.text('值1'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckedPopupMenuItem<int>), findsNothing);
  });
}
