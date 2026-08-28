import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/views/smart_layout_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SmartLayoutPlan fakePlan({bool hasFailures = false}) => SmartLayoutPlan(
  pageId: 'p-1',
  style: SmartLayoutTemplateKind.handout,
  confidence: 0.9,
  description: '检测到头脑风暴内容',
  addElements: const [],
  moveDeltas: const {},
  removeIds: const [],
  failedStrokeIds: hasFailures ? const [ElementId('stroke-1')] : const [],
  selectIds: const {},
  previewRects: const [],
  removalRects: const [],
  failureRects: hasFailures ? const [Rect.fromLTWH(0, 0, 10, 10)] : const [],
);

List<CanvasPage> _pages(int count) => [
  for (var i = 0; i < count; i++)
    CanvasPage(
      id: 'p-$i',
      index: i,
      bounds: Rect.fromLTWH(0, i * 896.0, 800, 800),
      template: CanvasPageTemplate.blank,
    ),
];

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SmartLayoutScopeDialog', () {
    testWidgets('默认当前页，确定可直接确定', (tester) async {
      SmartLayoutScopeSelection? selection;
      await tester.pumpWidget(wrap(SmartLayoutScopeDialog(
        pages: _pages(3),
        currentPageId: 'p-1',
      )));
      expect(find.text('当前页'), findsOneWidget);
      expect(find.text('全部页'), findsOneWidget);
      expect(find.text('选页'), findsOneWidget);
      // 选页时才有复选框列表与输入框
      expect(find.text('第 1 页'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed, isNotNull);
      // 点确定：当前页返回（这里只验证可确定）
      expect(selection, isNull);
    });

    testWidgets('切入选页：出现勾选列表与输入框；勾选只更新勾选并清空输入', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutScopeDialog(
        pages: _pages(3),
        currentPageId: 'p-0',
      )));
      await tester.tap(find.text('选页'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 页'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // 先输入再勾选：勾选后输入框清空
      await tester.enterText(find.byType(TextField), '2');
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 1 页'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 页'), findsOneWidget); // 列表仍在
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, isEmpty);
    });

    testWidgets('输入合法范围自动勾选对应页', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutScopeDialog(
        pages: _pages(5),
        currentPageId: 'p-0',
      )));
      await tester.tap(find.text('选页'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3-4');
      await tester.pumpAndSettle();
      final tile3 = tester.widget<Checkbox>(
        find.descendant(
          of: find.ancestor(
            of: find.text('第 3 页'),
            matching: find.byType(InkWell),
          ),
          matching: find.byType(Checkbox),
        ),
      );
      final tile4 = tester.widget<Checkbox>(
        find.descendant(
          of: find.ancestor(
            of: find.text('第 4 页'),
            matching: find.byType(InkWell),
          ),
          matching: find.byType(Checkbox),
        ),
      );
      expect(tile3.value, isTrue);
      expect(tile4.value, isTrue);
      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('输入非法格式：提示错误并禁用确定', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutScopeDialog(
        pages: _pages(5),
        currentPageId: 'p-0',
      )));
      await tester.tap(find.text('选页'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '6-8');
      await tester.pumpAndSettle();
      expect(find.textContaining('页码超出范围'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed, isNull);
    });
  });

  group('SmartLayoutConfirmBar', () {
    testWidgets('多页 + 无失败：显示 应用/重新识别/跳过本页/取消整个流程', (tester) async {
      SmartLayoutBarAction? tapped;
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(),
        isMultiPage: true,
        onAction: (action) => tapped = action,
      )));
      expect(find.textContaining('图文讲义'), findsOneWidget);
      expect(find.text('应用'), findsOneWidget);
      expect(find.text('重新识别'), findsOneWidget);
      expect(find.text('跳过本页'), findsOneWidget);
      expect(find.text('取消整个流程'), findsOneWidget);
      expect(find.text('删除未识别笔迹后应用'), findsNothing);
      // 无红区时不显示红区说明
      expect(find.textContaining('手写未识别成功'), findsNothing);
      await tester.tap(find.text('跳过本页'));
      expect(tapped, SmartLayoutBarAction.skipPage);
    });

    testWidgets('单页 + 有失败：红区计数说明 + 删除未识别后应用，无跳过', (tester) async {
      SmartLayoutBarAction? tapped;
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(hasFailures: true),
        isMultiPage: false,
        onAction: (action) => tapped = action,
      )));
      expect(find.textContaining('1 处手写未识别成功'), findsOneWidget);
      expect(find.textContaining('红色区域'), findsOneWidget);
      expect(find.text('删除未识别笔迹后应用'), findsOneWidget);
      expect(find.text('跳过本页'), findsNothing);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('取消整个流程'), findsNothing);
      // 重新识别动作 → retry（取消当前草稿并自动重跑本页由页面层处理）
      await tester.tap(find.text('重新识别'));
      expect(tapped, SmartLayoutBarAction.retry);
    });

    testWidgets('窄宽度：动作区换行不溢出', (tester) async {
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(hasFailures: true),
        isMultiPage: true,
        onAction: (_) {},
      )));
      expect(tester.takeException(), isNull, reason: '窄宽度不得溢出');
      expect(find.text('应用'), findsOneWidget);
      expect(find.text('重新识别'), findsOneWidget);
    });
  });

  group('SmartLayoutProgressOverlay 与识别进度文案', () {
    test('整页识别阶段文案；逐块 total=0 回落整页文案', () {
      expect(const SmartLayoutRecognitionProgress.page().label, '正在识别页面…');
      expect(
        const SmartLayoutRecognitionProgress.blocks(
          completed: 0,
          total: 0,
        ).label,
        '正在识别页面…',
      );
    });

    test('逐块转写阶段文案为 x/y', () {
      expect(
        const SmartLayoutRecognitionProgress.blocks(
          completed: 3,
          total: 7,
        ).label,
        '正在识别文字 3/7',
      );
    });

    testWidgets('浮层渲染进度文案与取消按钮', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(wrap(SmartLayoutProgressOverlay(
        progress: const SmartLayoutRecognitionProgress.blocks(
          completed: 2,
          total: 5,
        ),
        onCancel: () => cancelled = true,
      )));
      expect(find.text('正在识别文字 2/5'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      await tester.tap(find.text('取消'));
      expect(cancelled, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('onCancel 为 null 时不显示取消按钮', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutProgressOverlay(
        progress: const SmartLayoutRecognitionProgress.page(),
      )));
      expect(find.text('正在识别页面…'), findsOneWidget);
      expect(find.text('取消'), findsNothing);
    });
  });
}
