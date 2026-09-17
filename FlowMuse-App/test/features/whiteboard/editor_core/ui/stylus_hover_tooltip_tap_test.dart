import 'package:flow_muse/features/whiteboard/editor_core/src/ui/studio_rail_icon_button.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/toggle_chips.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// issue #31 回归测试：触控笔"悬停"引发的提示气泡不得吞掉点击。
///
/// 事实链（均已核实）：
/// 1. 框架把 stylus 当作可悬停指针追踪（mouse_tracker.dart 接受 mouse + stylus；
///    框架自带测试 mouse_region_test.dart 'stylus input works' 断言 onEnter/onHover）。
/// 2. Tooltip 的悬停弹出与 triggerMode 无关（文档："Setting triggerMode to manual
///    will not prevent the tooltip from showing when the mouse cursor hovers over it"），
///    所以上一轮改 manual 只杀掉了长按识别器，笔悬停仍会弹气泡。
/// 3. Material Tooltip 的气泡是命中不透明的（raw_tooltip.dart `_ExclusiveMouseRegion`
///    默认 HitTestBehavior.opaque），落在气泡矩形内的按下事件不会再传给下层按钮。
/// 4. 气泡定位 = 目标中心 + verticalOffset(24px)（material tooltip.dart
///    `_defaultVerticalOffset` + painting/geometry.dart positionDependentBox），
///    即气泡紧贴在被悬停按钮的下方。
///
/// 修复（本文件守护的行为）：编辑器内全部悬停提示站点改用自绘 `HoverTooltip`
/// （editor_core/src/ui/hover_tooltip.dart）——工具栏/笔盒与图形弹层（经
/// StudioRailIconButton）、属性面板 chips（经 IconToggleChip）、撤销重做缩放、
/// 菜单、素材库、查找/链接浮层、帮助等；气泡包 IgnorePointer 永不拦截
/// 指针事件。提示照常显示，但任何排布下点击都直达目标控件。
void main() {
  Future<void> pumpVerticalPair(WidgetTester tester, List<String> taps) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: StudioRailIconButton(
                    tooltip: '按钮A',
                    onPressed: () => taps.add('A'),
                    child: const Icon(Icons.lock),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: StudioRailIconButton(
                    tooltip: '按钮B',
                    onPressed: () => taps.add('B'),
                    child: const Icon(Icons.lock_open),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Finder railButton(String tooltip) => find.byWidgetPredicate(
    (widget) => widget is StudioRailIconButton && widget.tooltip == tooltip,
  );

  /// 悬停指针（笔在屏幕上方移动）——与真机一致：同一个笔指针先悬停、后按下。
  Future<TestGesture> hoverOver(
    WidgetTester tester,
    Finder finder, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final gesture = await tester.createGesture(kind: kind);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(5, 5));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(finder));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return gesture;
  }

  testWidgets('触控笔悬停 → 提示气泡照常显示', (tester) async {
    final taps = <String>[];
    await pumpVerticalPair(tester, taps);

    await hoverOver(tester, railButton('按钮A'));

    expect(find.text('按钮A'), findsOneWidget, reason: '悬停提示是保留的交互反馈');
    await tester.pumpAndSettle();
  });

  testWidgets('气泡几何不变：悬停 A 时气泡矩形仍盖住下方按钮 B 的中心', (tester) async {
    final taps = <String>[];
    await pumpVerticalPair(tester, taps);

    await hoverOver(tester, railButton('按钮A'));

    final bubbleRect = tester.getRect(find.text('按钮A'));
    final bCenter = tester.getCenter(railButton('按钮B'));
    expect(
      bubbleRect.contains(bCenter),
      isTrue,
      reason: '气泡贴在 A 下方 24px 起，纵向堆叠时本就会盖住 B 的中心'
          '（bubble=$bubbleRect, Bcenter=$bCenter）——所以气泡必须不参与命中测试',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('鼠标悬停同样弹出气泡（桌面端行为保留）', (tester) async {
    final taps = <String>[];
    await pumpVerticalPair(tester, taps);

    await hoverOver(tester, railButton('按钮A'), kind: PointerDeviceKind.mouse);

    expect(find.text('按钮A'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('悬停 A 时点 A 生效', (tester) async {
    final taps = <String>[];
    await pumpVerticalPair(tester, taps);

    final pen = await hoverOver(tester, railButton('按钮A'));
    await pen.down(tester.getCenter(railButton('按钮A')));
    await tester.pump(const Duration(milliseconds: 80));
    await pen.up();
    await tester.pumpAndSettle();

    expect(taps, ['A']);
    await tester.pumpAndSettle();
  });

  testWidgets('悬停 A 后移向 B：第一下点击即生效（issue #31 已修复）', (tester) async {
    final taps = <String>[];
    await pumpVerticalPair(tester, taps);

    final pen = await hoverOver(tester, railButton('按钮A'));
    final bCenter = tester.getCenter(railButton('按钮B'));

    // 笔移向 B：A 的气泡不再拦截指针，B 自身正常获得悬停并弹出自己的气泡
    await pen.moveTo(bCenter);
    await tester.pump();
    expect(find.text('按钮B'), findsOneWidget, reason: 'B 应收到悬停（气泡透传指针）');
    expect(find.text('按钮A'), findsNothing, reason: '离开 A 后其气泡收起');

    // 第一下即生效
    await pen.down(bCenter);
    await tester.pump(const Duration(milliseconds: 80));
    await pen.up();
    await tester.pumpAndSettle();
    expect(taps, ['B'], reason: '气泡不参与命中测试，第一下就应点到 B');

    // 按下事件收起气泡（与 Material Tooltip 一致）
    expect(find.text('按钮B'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('对照组：笔悬停在 B 自身 → 点 B 第一下即生效', (tester) async {
    final taps = <String>[];
    await pumpVerticalPair(tester, taps);

    final pen = await hoverOver(tester, railButton('按钮B'));
    final bCenter = tester.getCenter(railButton('按钮B'));
    await pen.down(bCenter);
    await tester.pump(const Duration(milliseconds: 80));
    await pen.up();
    await tester.pumpAndSettle();

    expect(taps, ['B']);
    await tester.pumpAndSettle();
  });

  testWidgets('不变量：编辑器控件不再内嵌框架 Tooltip（回归守卫）', (tester) async {
    // 框架 Tooltip 气泡命中不透明，一旦回退，issue #31 立即复发。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StudioRailIconButton(
                tooltip: '轨道按钮',
                onPressed: () {},
                child: const Icon(Icons.edit_outlined),
              ),
              IconToggleChip(
                tooltip: '面板 chip',
                isSelected: false,
                onTap: () {},
                child: const Icon(Icons.format_align_left, size: 18),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byType(Tooltip),
      findsNothing,
      reason: '控件内部应使用 HoverTooltip，框架 Tooltip 的悬停气泡会吞点击',
    );
  });
}
