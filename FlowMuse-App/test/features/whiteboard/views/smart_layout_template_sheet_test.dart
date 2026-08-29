import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/views/smart_layout_template_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模板选择卡：三张真实内容缩略图卡、点选返回模板、放不下置灰、取消零残留。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TextElement textElement(String text) => TextElement(
    id: ElementId.generate(),
    x: 100,
    y: 100,
    width: 200,
    height: 40,
    text: text,
    fontSize: 20,
    // 捆绑字体，避免测试环境触发 Google Fonts 异步加载
    fontFamily: 'Excalifont',
  );

  LayoutUnit textUnit(String key, String text) => LayoutUnit(
    key: key,
    sourceBounds: Rect.fromLTWH(100, 100, 200, 40),
    size: const Size(200, 40),
    kind: LayoutUnitKind.text,
    textElement: textElement(text),
  );

  SmartLayoutTemplatePreparation buildPreparation({
    bool handoutFits = true,
  }) {
    final content = SmartLayoutContent(
      pageId: 'p-1',
      contentArea: const Rect.fromLTWH(0, 0, 800, 600),
      title: textUnit('title', '页面标题'),
      looseTexts: [textUnit('t1', '第一段正文')],
    );
    final layouts = <SmartLayoutTemplateKind, SmartLayoutTemplateLayoutResult?>{
      for (final kind in SmartLayoutTemplateKind.values)
        kind: SmartLayoutTemplateEngine.layout(kind: kind, content: content),
    };
    if (!handoutFits) {
      layouts[SmartLayoutTemplateKind.handout] = null;
    }
    return SmartLayoutTemplatePreparation(
      pageId: 'p-1',
      content: content,
      layouts: layouts,
      removeIds: const [],
      failedStrokeIds: const [],
      removalRects: const [],
      failureRects: const [],
      failures: const [],
      confidence: 0.9,
      confidenceByBlockId: const {},
    );
  }

  Future<ValueNotifier<SmartLayoutTemplateChoice?>> openSheet(
    WidgetTester tester,
    SmartLayoutTemplatePreparation preparation, {
    bool allowSkip = false,
  }) async {
    final picked = ValueNotifier<SmartLayoutTemplateChoice?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked.value = await showSmartLayoutTemplateSheet(
                    context: context,
                    preparation: preparation,
                    allowSkip: allowSkip,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('三张模板卡渲染真实内容缩略图与模板名', (tester) async {
    final picked = await openSheet(tester, buildPreparation());
    expect(picked.value, isNull, reason: '未点选时应保持打开');
    expect(find.text('选择排版模板'), findsOneWidget);
    expect(find.text('图文讲义'), findsOneWidget);
    expect(find.text('要点清单'), findsOneWidget);
    expect(find.text('原文整理'), findsOneWidget);
    expect(find.text('内容放不下'), findsNothing);
    expect(
      find.byKey(const ValueKey('template-thumb-handout')),
      findsOneWidget,
      reason: '三卡都有缩略图',
    );
    expect(find.byKey(const ValueKey('template-thumb-outline')), findsOneWidget);
    expect(find.byKey(const ValueKey('template-thumb-inplace')), findsOneWidget);
  });

  testWidgets('点选模板卡 → 返回对应模板，进入后续草稿态', (tester) async {
    final picked = await openSheet(tester, buildPreparation());
    expect(picked.value, isNull);
    await tester.tap(find.text('要点清单'));
    await tester.pumpAndSettle();
    expect(picked.value?.kind, SmartLayoutTemplateKind.outline);
  });

  testWidgets('放不下的模板置灰不可点，标注"内容放不下"', (tester) async {
    final picked =
        await openSheet(tester, buildPreparation(handoutFits: false));
    expect(find.text('内容放不下'), findsOneWidget);
    // 点置灰卡不返回
    await tester.tap(find.text('图文讲义'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked.value, isNull);
  });

  testWidgets('关闭按钮 → 返回 null（取消零残留）', (tester) async {
    final picked = await openSheet(tester, buildPreparation());
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(picked.value, isNull);
  });

  testWidgets('窄视口：三卡纵向铺满、无溢出，首卡可见可点', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final picked = await openSheet(tester, buildPreparation());
    expect(tester.takeException(), isNull, reason: '窄视口不得溢出');
    // 纵向铺满：缩略图宽度接近可用宽度（400 - 32 内边距），远大于横排均分
    final thumbWidth = tester
        .getSize(find.byKey(const ValueKey('template-thumb-handout')))
        .width;
    expect(thumbWidth, greaterThan(300));
    // 首卡可见可点
    expect(find.text('图文讲义'), findsOneWidget);
    await tester.tap(find.text('图文讲义'));
    await tester.pumpAndSettle();
    expect(picked.value?.kind, SmartLayoutTemplateKind.handout);
  });

  testWidgets('窄视口：滚动后末卡可见可点（纵向滚动列表）', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final picked = await openSheet(tester, buildPreparation());
    await tester.drag(find.text('图文讲义'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('原文整理'), findsOneWidget);
    await tester.tap(find.text('原文整理'));
    await tester.pumpAndSettle();
    expect(picked.value?.kind, SmartLayoutTemplateKind.inplace);
  });

  testWidgets('多页流程：跳过本页 → skipped=true，继续后续页', (tester) async {
    final picked = await openSheet(tester, buildPreparation(), allowSkip: true);
    expect(find.text('跳过本页'), findsOneWidget);
    await tester.tap(find.text('跳过本页'));
    await tester.pumpAndSettle();
    expect(picked.value?.skipped, isTrue);
    expect(picked.value?.kind, isNull);
  });

  testWidgets('单页流程不显示跳过按钮', (tester) async {
    await openSheet(tester, buildPreparation());
    expect(find.text('跳过本页'), findsNothing);
  });

  testWidgets('三卡全放不下 → 显示分页整体提示', (tester) async {
    final preparation = buildPreparation();
    final allDisabled = SmartLayoutTemplatePreparation(
      pageId: preparation.pageId,
      content: preparation.content,
      layouts: {
        for (final kind in SmartLayoutTemplateKind.values) kind: null,
      },
      removeIds: const [],
      failedStrokeIds: const [],
      removalRects: const [],
      failureRects: const [],
      failures: const [],
      confidence: 0.9,
      confidenceByBlockId: const {},
    );
    await openSheet(tester, allDisabled, allowSkip: true);
    expect(find.textContaining('超出所有模板的容量'), findsOneWidget);
    expect(find.text('跳过本页'), findsOneWidget);
  });
}
