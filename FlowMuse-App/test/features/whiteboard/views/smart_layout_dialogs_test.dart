import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/views/smart_layout_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SmartLayoutPlan fakePlan() => SmartLayoutPlan(
  pageId: 'p-1',
  style: SmartLayoutStyle.mindmap,
  confidence: 0.9,
  description: '检测到头脑风暴内容',
  addElements: const [],
  moveDeltas: const {},
  removeIds: const [],
  selectIds: const {},
  previewRects: const [],
  removalRects: const [],
  failureRects: const [],
);

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('确认对话框展示描述与四种风格，点确定回调 apply', (tester) async {
    SmartLayoutPlan? applied;
    await tester.pumpWidget(
      wrap(
        SmartLayoutConfirmDialog(
          plan: fakePlan(),
          onSelectStyle: (style) async => fakePlan(),
          onApply: (plan) => applied = plan,
          onApplyAndDrop: (plan) {},
          onSkip: () {},
          onCancel: () {},
        ),
      ),
    );
    expect(find.text('检测到头脑风暴内容'), findsOneWidget);
    expect(find.text('思维导图'), findsWidgets);
    expect(find.text('PPT 式排版'), findsOneWidget);
    expect(find.text('文章式阅读流'), findsOneWidget);
    expect(find.text('仅转机器字体'), findsOneWidget);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(applied, isNotNull);
  });

  testWidgets('存在失败块时展示"删除未识别笔迹后应用"按钮', (tester) async {
    final plan = fakePlan();
    final failed = SmartLayoutPlan(
      pageId: plan.pageId,
      style: plan.style,
      confidence: plan.confidence,
      description: plan.description,
      addElements: plan.addElements,
      moveDeltas: plan.moveDeltas,
      removeIds: plan.removeIds,
      failedStrokeIds: const [ElementId('stroke-1')],
      selectIds: plan.selectIds,
      previewRects: plan.previewRects,
      removalRects: plan.removalRects,
      failureRects: const [Rect.fromLTWH(0, 0, 10, 10)],
    );
    await tester.pumpWidget(
      wrap(
        SmartLayoutConfirmDialog(
          plan: failed,
          onSelectStyle: (style) async => failed,
          onApply: (plan) {},
          onApplyAndDrop: (plan) {},
          onSkip: () {},
          onCancel: () {},
        ),
      ),
    );
    expect(find.text('删除未识别笔迹后应用'), findsOneWidget);
  });

  testWidgets('失败对话框列出失败项并可重试', (tester) async {
    bool? retried;
    await tester.pumpWidget(
      wrap(
        SmartLayoutFailureDialog(
          failures: const [
            SmartLayoutFailureInfo(
              blockId: 'b1',
              bounds: Rect.fromLTWH(0, 0, 10, 10),
              snippet: '潦草笔迹',
              error: '识别失败',
            ),
          ],
          onRetry: () => retried = true,
          onCancel: () {},
        ),
      ),
    );
    expect(find.textContaining('潦草笔迹'), findsOneWidget);
    await tester.tap(find.text('重新识别'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
  });

  testWidgets('页面多选：勾选两页后确定按钮可用', (tester) async {
    await tester.pumpWidget(
      wrap(
        SmartLayoutPagePickerDialog(
          pages: const [
            CanvasPage(
              id: 'p-1',
              index: 0,
              bounds: Rect.fromLTWH(0, 0, 100, 100),
              template: CanvasPageTemplate.blank,
            ),
            CanvasPage(
              id: 'p-2',
              index: 1,
              bounds: Rect.fromLTWH(200, 0, 100, 100),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    final confirmButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(confirmButton.onPressed, isNull); // 未勾选时禁用
    await tester.tap(find.text('第 1 页'));
    await tester.tap(find.text('第 2 页'));
    await tester.pumpAndSettle();
    final enabled = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(enabled.onPressed, isNotNull); // 勾选后可用
  });
}
