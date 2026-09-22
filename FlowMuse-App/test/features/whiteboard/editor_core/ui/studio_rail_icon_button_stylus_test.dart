import 'package:flow_muse/features/whiteboard/editor_core/src/ui/studio_rail_icon_button.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/toolbar_input_diagnostics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// issue #31 第三轮回归：触控笔工具栏点选必须"一次生效"，不依赖手势竞技场。
///
/// 既有事实（框架源码级）：
/// - InkWell 的 tap 由 TapGestureRecognizer 决定，onTapDOMDown 在竞技场判决或
///   kPressTimeout(100ms) 后才触发；按下期间任何 PointerCancel / move 越过
///   kTouchSlop(18px) 都会让这一次按压被取消（tap.dart / recognizer.dart）。
/// - 真机触控笔的事件流由 OHOS 引擎产生，本机 widget 测试无法覆盖引擎差异；
///   前两轮修复（Tooltip.triggerMode、HoverTooltip）都没有改变"点击动作依赖
///   竞技场判决"这一结构，因此真机仍可复现。
///
/// 本轮修复：为触控笔在原始指针层增加一条不经过竞技场的通道——按下落在按钮
/// 内、抬起时仍在按钮内且位移不超过 kTouchSlop 即生效。手指/鼠标保持原路径。
void main() {
  Future<void> pumpButton(
    WidgetTester tester,
    VoidCallback onPressed,
  ) async {
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

  Offset center(WidgetTester tester) =>
      tester.getCenter(find.byType(StudioRailIconButton));

  testWidgets('触控笔正常点按一次生效且不重复派发', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);

    final pen = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 80));
    await pen.up();
    await tester.pumpAndSettle();

    expect(taps, 1, reason: '触控笔一次点按应只派发一次，且不依赖竞技场');
  });

  testWidgets('触控笔长按显示工具名且不触发点击', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);

    final pen = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(kLongPressTimeout);

    expect(find.text('测试工具'), findsOneWidget);
    expect(taps, 0);

    await pen.up();
    await tester.pump();
    expect(taps, 1, reason: '长按显示工具名后仍应保留原有点击动作');
  });

  testWidgets('触控笔按下后引擎取消指针，抬手仍应生效（本轮核心场景）', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);
    final lines = <String>[];
    ToolbarInputDiagnostics.setTestSink(lines.add);
    addTearDown(ToolbarInputDiagnostics.resetTestSink);

    // 真机引擎若在按压期间发出 PointerCancel：竞技场里的 tap 必然被取消，
    // 只能靠原始指针通道救回这一下。
    const pointer = 9301;
    final down = tester.getCenter(find.byType(StudioRailIconButton));
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: down,
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.sendEventToBinding(
      PointerCancelEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: down,
      ),
    );
    await tester.pump();
    // 笔尖随后正常抬起：竞技场已死，只有原始指针通道能救回这一下。
    await tester.sendEventToBinding(
      PointerUpEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: down,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      taps,
      1,
      reason: 'PointerCancel 吞掉竞技场后，原始指针通道仍应让这次点选生效',
    );
    // 真机复验时靠这条日志判断"引擎是否用 cancel 代替了 up"。
    expect(
      lines.any((line) => line.contains('source=gesture stage=rawCancelTap')),
      isTrue,
      reason: '取消时刻的结算必须留下 rawCancelTap 诊断记录',
    );
  });

  testWidgets('触控笔按压期间小幅漂移（≤kTouchSlop）仍应生效', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);

    final pen = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await pen.moveBy(const Offset(0, 12));
    await tester.pump(const Duration(milliseconds: 20));
    await pen.up();
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('触控笔拖动后被引擎取消：不生效（取消结算也要守住位移容差）', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);

    const pointer = 9401;
    final start = tester.getCenter(find.byType(StudioRailIconButton));
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: start,
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.sendEventToBinding(
      PointerMoveEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: start + const Offset(0, 90),
      ),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      PointerCancelEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: start + const Offset(0, 90),
      ),
    );
    await tester.pumpAndSettle();

    expect(taps, 0, reason: '位移超过 kTouchSlop 的按压是拖动，取消也不能结算成点选');
  });

  testWidgets('触控笔按下后大幅拖走再抬手：不生效', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);

    final pen = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await pen.moveBy(const Offset(0, 80));
    await tester.pump();
    await pen.up();
    await tester.pumpAndSettle();

    expect(taps, 0, reason: '位移超过 kTouchSlop 视为拖动，不应触发电选');
  });

  testWidgets('触控笔在按钮外抬起：不生效', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);

    final pen = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await pen.moveTo(center(tester) + const Offset(0, 60));
    await tester.pump();
    await pen.up();
    await tester.pumpAndSettle();

    expect(taps, 0);
  });

  testWidgets('对照组：手指点击仍不重复派发', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);

    await tester.tap(find.byType(StudioRailIconButton));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('对照组：鼠标点击仍不重复派发', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: center(tester));
    await mouse.down(center(tester));
    await tester.pump(const Duration(milliseconds: 30));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('禁用按钮：触控笔点按不派发', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StudioRailIconButton(
              tooltip: '测试工具',
              onPressed: null,
              child: const Icon(Icons.edit_outlined),
            ),
          ),
        ),
      ),
    );

    final pen = await tester.startGesture(
      center(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 30));
    await pen.up();
    await tester.pumpAndSettle();

    expect(taps, 0);
  });
}
