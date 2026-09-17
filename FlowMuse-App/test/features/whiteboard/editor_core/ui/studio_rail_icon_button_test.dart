import 'package:flow_muse/features/whiteboard/editor_core/src/ui/studio_rail_icon_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// issue #31 回归测试：用触控笔/手指点工具栏按钮，按压时长不应影响 onTap。
/// 根因：按钮外层 Tooltip 默认 triggerMode=longPress，按压 ≥500ms 时长按
/// 识别器赢得手势竞技场，InkWell.onTap 被取消（表现为需点两遍）。
/// 修复：Tooltip 改为 TooltipTriggerMode.manual（仅悬停/无障碍提示）。
void main() {
  Future<void> pumpButton(WidgetTester tester, VoidCallback onPressed) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StudioRailIconButton(
              tooltip: '测试工具',
              onPressed: onPressed,
              child: const Icon(Icons.edit_outlined),
            ),
          ),
        ),
      ),
    );
  }

  Offset buttonCenter(WidgetTester tester) =>
      tester.getCenter(find.byType(StudioRailIconButton));

  group('StudioRailIconButton 点击链路（issue #31）', () {
    testWidgets('stylus 快速点击 → onTap 触发（对照组）', (tester) async {
      // Given
      var taps = 0;
      await pumpButton(tester, () => taps++);

      // When: 触控笔快速按下并抬起（100ms）
      final gesture = await tester.startGesture(
        buttonCenter(tester),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      // Then
      expect(taps, 1);
    });

    testWidgets('stylus 按压超过长按阈值(500ms)再抬起 → onTap 应触发', (tester) async {
      // Given
      var taps = 0;
      await pumpButton(tester, () => taps++);

      // When: 触控笔按住 700ms（超过 kLongPressTimeout）后抬起
      final gesture = await tester.startGesture(
        buttonCenter(tester),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 200));

      // Then(机制签名): 按压期间不应弹出提示气泡。
      // 若此处找到气泡，说明 Tooltip 长按识别器已赢得手势竞技场
      //（真机上表现为：按住约 0.5s 弹出提示气泡，且这次点击被吞掉）。
      expect(
        find.text('测试工具'),
        findsNothing,
        reason: '按住超过 500ms 时 Tooltip 气泡不应弹出（弹出即长按识别器竞争获胜）',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Then: 若实际为 0，则"按压稍久即被吞掉"，与 issue 症状一致
      expect(taps, 1, reason: '按压超过 Tooltip 长按阈值后 onTap 疑似被取消');
    });

    testWidgets('touch 按压超过长按阈值(500ms)再抬起（对照：验证是否仅笔受影响）', (tester) async {
      // Given
      var taps = 0;
      await pumpButton(tester, () => taps++);

      // When: 手指按住 600ms 后抬起
      final gesture = await tester.startGesture(
        buttonCenter(tester),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Then
      expect(taps, 1, reason: '若同为 0，说明该机制与设备类型无关（对照真机观察）');
    });

    testWidgets('stylus "点两遍"场景：第一下按压600ms、第二下快速点击', (tester) async {
      // Given
      var taps = 0;
      await pumpButton(tester, () => taps++);

      // When: 第一下（按压较久）+ 第二下（快速点击）
      final first = await tester.startGesture(
        buttonCenter(tester),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await first.up();
      await tester.pumpAndSettle();

      final second = await tester.startGesture(
        buttonCenter(tester),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await second.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Then: 期望两下都生效；若实际为 1，即"第一下被吞、第二下才生效"
      expect(taps, 2, reason: '实际为 1 时即复现 issue 的"需要点两遍"');
    });
  });
}
