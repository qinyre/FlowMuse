import 'dart:async';

import 'package:flow_muse/features/whiteboard/ai_assistant/views/region_capture_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpOverlay(
    WidgetTester tester, {
    required Future<void> Function(Rect screenRect) onCommit,
    required VoidCallback onCancel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RegionCaptureOverlay(
            onCommit: onCommit,
            onCancel: onCancel,
          ),
        ),
      ),
    );
  }

  testWidgets('拖动产生矩形并提交', (tester) async {
    // Given：onCommit 记录调用；默认 800×600 表面，覆盖层中心 ≈ (400,300)
    final committed = <Rect>[];
    await pumpOverlay(
      tester,
      onCommit: (rect) async => committed.add(rect),
      onCancel: () {},
    );

    // When：自覆盖层中心向右下拖动 (100,80)
    await tester.drag(find.byType(RegionCaptureOverlay), const Offset(100, 80));
    await tester.pump();

    // Then：onCommit 调用 1 次，矩形起点为中心、尺寸 ≈ (100,80)
    expect(committed, hasLength(1));
    final rect = committed.single;
    expect(rect.left, closeTo(400, 2));
    expect(rect.top, closeTo(300, 2));
    expect(rect.width, closeTo(100, 2));
    expect(rect.height, closeTo(80, 2));
  });

  testWidgets('反向拖拽归一化', (tester) async {
    // Given：onCommit 记录调用
    final committed = <Rect>[];
    await pumpOverlay(
      tester,
      onCommit: (rect) async => committed.add(rect),
      onCancel: () {},
    );

    // When：自 (500,380) 向左上拖动 (-100,-80)，终点 (400,300)
    await tester.dragFrom(const Offset(500, 380), const Offset(-100, -80));
    await tester.pump();

    // Then：Rect.fromPoints 归一化 → Rect.fromLTWH(400,300,100,80)
    expect(committed, hasLength(1));
    final rect = committed.single;
    expect(rect.left, closeTo(400, 2));
    expect(rect.top, closeTo(300, 2));
    expect(rect.width, closeTo(100, 2));
    expect(rect.height, closeTo(80, 2));
  });

  testWidgets('过小矩形不提交并提示', (tester) async {
    // Given：onCommit 记录调用
    final committed = <Rect>[];
    await pumpOverlay(
      tester,
      onCommit: (rect) async => committed.add(rect),
      onCancel: () {},
    );

    // When：拖动 8×8（宽高均 <16 守卫）
    await tester.drag(find.byType(RegionCaptureOverlay), const Offset(8, 8));
    await tester.pump();

    // Then：不提交，且显示内联提示
    expect(committed, isEmpty);
    expect(find.text('矩形太小，请重新框选'), findsOneWidget);
  });

  testWidgets('取消按钮触发 onCancel', (tester) async {
    // Given：onCancel 计数
    var cancelled = 0;
    await pumpOverlay(
      tester,
      onCommit: (_) async {},
      onCancel: () => cancelled++,
    );

    // When：点击「✕ 取消」
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    // Then：onCancel 调用 1 次
    expect(cancelled, 1);
  });

  testWidgets('提交期间屏蔽重复提交与取消', (tester) async {
    // Given：onCommit 返回永不完成的挂起 Future
    final completer = Completer<void>();
    final committed = <Rect>[];
    await pumpOverlay(
      tester,
      onCommit: (rect) async {
        committed.add(rect);
        await completer.future;
      },
      onCancel: () {},
    );

    // When：第一次拖动触发提交，随后再次拖动重试
    await tester.drag(find.byType(RegionCaptureOverlay), const Offset(100, 80));
    await tester.pump();
    await tester.drag(find.byType(RegionCaptureOverlay), const Offset(50, 40));
    await tester.pump();

    // Then：onCommit 仍只 1 次；取消按钮禁用（onPressed == null）
    expect(committed, hasLength(1));
    final closeButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.close),
    );
    expect(closeButton.onPressed, isNull);
  });

  testWidgets('无输入时无任何回调', (tester) async {
    // Given：无任何手势操作直接挂载
    var commits = 0;
    var cancels = 0;
    await pumpOverlay(
      tester,
      onCommit: (_) async => commits++,
      onCancel: () => cancels++,
    );

    // When：仅初始 pump
    await tester.pump();

    // Then：onCommit/onCancel 均为 0 次
    expect(commits, 0);
    expect(cancels, 0);
  });
}
