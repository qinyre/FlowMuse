import 'package:flow_muse/app/adapters/ohos_keyboard_focus_recovery.dart';
import 'package:flow_muse/shared/widgets/keyboard_focus_recovery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('鸿蒙适配仅在鸿蒙端安装焦点恢复', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      MaterialApp(
        builder: wrapOhosKeyboardFocusRecovery,
        home: const Text('ok'),
      ),
    );
    expect(find.byType(KeyboardFocusRecovery), findsNothing);

    debugDefaultTargetPlatformOverride = TargetPlatform.ohos;
    await tester.pumpWidget(
      MaterialApp(
        builder: wrapOhosKeyboardFocusRecovery,
        home: const Text('ok'),
      ),
    );
    expect(find.byType(KeyboardFocusRecovery), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('普通输入框再次点击会重建焦点并保留文字', (tester) async {
    final focusNode = FocusNode();
    final controller = TextEditingController(text: '原文');
    addTearDown(focusNode.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardFocusRecovery(
          child: Scaffold(
            body: TextField(focusNode: focusNode, controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    tester.testTextInput.hide();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
    final selectionAfterTap = controller.selection;
    await tester.pump(const Duration(milliseconds: 50));
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(controller.text, '原文');
    expect(controller.selection, selectionAfterTap);
  });

  testWidgets('搜索框和底层 EditableText 也会重建焦点', (tester) async {
    for (final directEditable in [false, true]) {
      final focusNode = FocusNode();
      final controller = TextEditingController(text: '搜索');
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      var recovering = false;
      var commits = 0;
      focusNode.addListener(() {
        if (!focusNode.hasFocus && !recovering) commits++;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardFocusRecovery(
            child: Scaffold(
              body: KeyboardFocusRecoveryGuard(
                onRecoveryChanged: (value) => recovering = value,
                child: directEditable
                    ? EditableText(
                        controller: controller,
                        focusNode: focusNode,
                        style: const TextStyle(color: Colors.black),
                        cursorColor: Colors.black,
                        backgroundCursorColor: Colors.grey,
                      )
                    : SearchBar(controller: controller, focusNode: focusNode),
              ),
            ),
          ),
        ),
      );
      final input = directEditable
          ? find.byType(EditableText)
          : find.byType(SearchBar);
      focusNode.requestFocus();
      await tester.pump();
      tester.testTextInput.hide();
      await tester.pump();

      await tester.tap(input);
      await tester.pump();
      expect(recovering, isTrue);
      expect(commits, 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(focusNode.hasFocus, isTrue);
      expect(recovering, isFalse);
      expect(commits, 0);
    }
  });

  testWidgets('拖动和点击其他输入框不会抢回旧焦点', (tester) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardFocusRecovery(
          child: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: first),
                TextField(focusNode: second),
              ],
            ),
          ),
        ),
      ),
    );
    final fields = find.byType(TextField);
    await tester.tap(fields.first);
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(fields.first));
    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 60));
    expect(first.hasFocus, isTrue);

    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(fields.first);
    await tester.pump();
    expect(first.hasFocus, isFalse);
    await tester.tap(fields.last);
    await tester.pump(const Duration(milliseconds: 60));
    expect(second.hasFocus, isTrue);
    expect(first.hasFocus, isFalse);
  });

  testWidgets('长按和点击输入框外部不执行焦点恢复', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    var recoveryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardFocusRecovery(
          child: Scaffold(
            body: Column(
              children: [
                KeyboardFocusRecoveryGuard(
                  onRecoveryChanged: (_) => recoveryCount++,
                  child: TextField(focusNode: focusNode),
                ),
                const SizedBox(height: 80),
                TextButton(onPressed: () {}, child: const Text('其他控件')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    tester.testTextInput.hide();
    await tester.pump();

    await tester.longPress(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 60));
    expect(recoveryCount, 0);
    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.text('其他控件'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(recoveryCount, 0);
  });

  testWidgets('已有局部焦点修复的输入框不会再触发全局恢复', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    var recoveryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardFocusRecovery(
          child: Scaffold(
            body: KeyboardFocusRecoveryExclusion(
              child: KeyboardFocusRecoveryGuard(
                onRecoveryChanged: (_) => recoveryCount++,
                child: Builder(
                  builder: (context) => TextField(
                    focusNode: focusNode,
                    onTapAlwaysCalled: true,
                    onTap: () {
                      if (!focusNode.hasFocus) return;
                      focusNode.unfocus();
                      Future<void>.delayed(
                        const Duration(milliseconds: 50),
                        () {
                          if (context.mounted) focusNode.requestFocus();
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(focusNode.hasFocus, isTrue);
    expect(recoveryCount, 0);
  });
}
