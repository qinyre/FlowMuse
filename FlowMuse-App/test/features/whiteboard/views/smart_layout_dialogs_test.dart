import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/views/smart_layout_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SmartLayoutPlan fakePlan({
  bool hasFailures = false,
  List<SmartLayoutLowConfidenceText> lowConfidence = const [],
}) => SmartLayoutPlan(
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
  lowConfidenceTexts: lowConfidence,
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

  group('SmartLayoutConfirmBar 模板切换与置信度说明', () {
    testWidgets('chips：三个模板横排、当前高亮、放不下置灰、点选其他模板回调', (tester) async {
      SmartLayoutTemplateKind? tapped;
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(),
        isMultiPage: false,
        onAction: (_) {},
        currentKind: SmartLayoutTemplateKind.handout,
        availableKinds: const [
          SmartLayoutTemplateKind.handout,
          SmartLayoutTemplateKind.outline,
        ],
        onTemplateSelected: (kind) => tapped = kind,
      )));
      final current = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '图文讲义'),
      );
      expect(current.selected, isTrue, reason: '当前模板高亮');
      final switchable = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '要点清单'),
      );
      expect(switchable.selected, isFalse);
      expect(switchable.onSelected, isNotNull, reason: '放得下的模板可点选');
      final unavailable = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '原文整理'),
      );
      expect(unavailable.onSelected, isNull, reason: '放不下的模板置灰');
      await tester.tap(find.text('要点清单'));
      expect(tapped, SmartLayoutTemplateKind.outline);
      // 点当前模板：不回调（页面无需再忽略）。
      tapped = null;
      await tester.tap(find.text('图文讲义'));
      expect(tapped, isNull);
    });

    testWidgets('currentKind 为 null（旧调用方）不显示 chips', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(),
        isMultiPage: false,
        onAction: (_) {},
      )));
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('保留手写模式：标题旁标注"保留手写"', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(),
        isMultiPage: false,
        onAction: (_) {},
        currentKind: SmartLayoutTemplateKind.inplace,
        availableKinds: SmartLayoutTemplateKind.values,
        onTemplateSelected: (_) {},
        keepHandwriting: true,
      )));
      expect(find.text('保留手写'), findsOneWidget);
      // 关闭开关时不显示标注。
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(),
        isMultiPage: false,
        onAction: (_) {},
      )));
      expect(find.text('保留手写'), findsNothing);
    });

    testWidgets('置信度说明两态：有低置信解释橙框，无低置信给正向确认', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(
          lowConfidence: const [
            SmartLayoutLowConfidenceText(
              elementId: ElementId('t-1'),
              confidence: 0.4,
            ),
            SmartLayoutLowConfidenceText(
              elementId: ElementId('t-2'),
              confidence: 0.5,
            ),
          ],
        ),
        isMultiPage: false,
        onAction: (_) {},
      )));
      expect(find.textContaining('有 2 处内容识别把握较低'), findsOneWidget);
      expect(find.textContaining('画布橙框标出'), findsOneWidget);
      expect(find.text('全部内容识别把握良好'), findsNothing);
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(),
        isMultiPage: false,
        onAction: (_) {},
      )));
      expect(find.text('全部内容识别把握良好'), findsOneWidget);
      expect(find.textContaining('把握较低'), findsNothing);
    });

    testWidgets('有红区且无低置信时，不再自相矛盾地给"全部把握良好"确认',
        (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(hasFailures: true),
        isMultiPage: false,
        onAction: (_) {},
      )));
      expect(find.text('全部内容识别把握良好'), findsNothing);
      expect(find.textContaining('手写未识别成功'), findsOneWidget);
    });

    testWidgets('核对全文按钮：onReviewAll 为 null 隐藏，非 null 可点', (tester) async {
      var reviewed = false;
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(),
        isMultiPage: false,
        onAction: (_) {},
        onReviewAll: () async {
          reviewed = true;
        },
      )));
      expect(find.text('核对全文'), findsOneWidget);
      await tester.tap(find.text('核对全文'));
      expect(reviewed, isTrue);
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(),
        isMultiPage: false,
        onAction: (_) {},
      )));
      expect(find.text('核对全文'), findsNothing);
    });

    testWidgets('校对按钮强调态：N>0 用 tonal 强调，N==0 用普通次要样式', (tester) async {
      Future<void> pump(bool low) => tester.pumpWidget(
        wrap(SmartLayoutConfirmBar(
          plan: fakePlan(
            lowConfidence: low
                ? const [
                    SmartLayoutLowConfidenceText(
                      elementId: ElementId('t-1'),
                      confidence: 0.4,
                    ),
                  ]
                : const [],
          ),
          isMultiPage: false,
          onAction: (_) {},
          onProofread: () async {},
        )),
      );
      // N>0：校对按钮用 FilledButton.tonal 强调。
      await pump(true);
      expect(
        find.widgetWithText(FilledButton, '校对 1 处'),
        findsOneWidget,
        reason: '有低置信项时校对按钮强调（tonal）',
      );
      // N==0：校对按钮回落普通 TextButton 次要样式。
      await pump(false);
      expect(find.widgetWithText(FilledButton, '校对 0 处'), findsNothing);
      expect(find.widgetWithText(TextButton, '校对 0 处'), findsOneWidget);
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

    test('多页流程页码前缀；单页无页码不加前缀', () {
      expect(
        const SmartLayoutRecognitionProgress.page(
          pageLabel: '第 2/5 页',
        ).label,
        '第 2/5 页 · 正在识别页面…',
      );
      expect(
        const SmartLayoutRecognitionProgress.blocks(
          completed: 1,
          total: 4,
          pageLabel: '第 2/5 页',
        ).label,
        '第 2/5 页 · 正在识别文字 1/4',
      );
      expect(
        const SmartLayoutRecognitionProgress.page().label,
        isNot(contains('页 ·')),
        reason: '单页流程不带页码前缀',
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

  group('SmartLayoutProofreadSheet 校对编辑条', () {
    FilledButton saveButton(WidgetTester tester) =>
        tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '保存'),
        );

    testWidgets('改字可保存，清空文本禁用保存（防空文字元素）', (tester) async {
      String? revised;
      await tester.pumpWidget(wrap(SmartLayoutProofreadSheet(
        items: const [(id: ElementId('e1'), text: '先头小子')],
        onRevise: (id, newText) {
          revised = newText;
          return true;
        },
      )));
      // 初始未改字：保存禁用。
      expect(saveButton(tester).onPressed, isNull);
      // 改成新文字：保存可用。
      await tester.enterText(find.byType(TextField), '先头小子已核对');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('保存'));
      expect(revised, '先头小子已核对');
      // 清空文本：保存禁用（避免不可见空文字元素）。
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
