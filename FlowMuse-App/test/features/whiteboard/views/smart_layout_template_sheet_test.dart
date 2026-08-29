import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/views/smart_layout_template_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模板选择卡：三张真实内容缩略图卡、点选返回模板、放不下置灰、取消零残留、
/// 适用场景说明与"保留手写笔迹"模式开关。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TextElement textElement(String text, {double fontSize = 20}) => TextElement(
    id: ElementId.generate(),
    x: 100,
    y: 100,
    width: 200,
    height: 40,
    text: text,
    fontSize: fontSize,
    // 捆绑字体，避免测试环境触发 Google Fonts 异步加载
    fontFamily: 'Excalifont',
  );

  LayoutUnit textUnit(String key, String text, {double fontSize = 20}) =>
      LayoutUnit(
        key: key,
        sourceBounds: Rect.fromLTWH(100, 100, 200, 40),
        size: const Size(200, 40),
        kind: LayoutUnitKind.text,
        textElement: textElement(text, fontSize: fontSize),
      );

  SmartLayoutContent buildContent() => SmartLayoutContent(
    pageId: 'p-1',
    contentArea: const Rect.fromLTWH(0, 0, 800, 600),
    title: textUnit('title', '页面标题'),
    looseTexts: [textUnit('t1', '第一段正文')],
  );

  SmartLayoutTemplatePreparation buildPreparation({
    bool handoutFits = true,
    Map<SmartLayoutTemplateKind, SmartLayoutTemplateLayoutResult?>
    layoutsKeepInk = const {},
  }) {
    final content = buildContent();
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
      layoutsKeepInk: layoutsKeepInk,
      removeIds: const [],
      failedStrokeIds: const [],
      removalRects: const [],
      failureRects: const [],
      failures: const [],
      confidence: 0.9,
      confidenceByBlockId: const {},
    );
  }

  /// 保留手写模式预落位：文本单元置 keepAsInk 后交真实引擎现算；
  /// [missingKinds] 中的模板为 null（模拟该模式下放不下）。
  Map<SmartLayoutTemplateKind, SmartLayoutTemplateLayoutResult?>
  buildKeepInkLayouts({Set<SmartLayoutTemplateKind> missingKinds = const {}}) {
    final inkContent = buildContent().withTextAsInk();
    return {
      for (final kind in SmartLayoutTemplateKind.values)
        kind: missingKinds.contains(kind)
            ? null
            : SmartLayoutTemplateEngine.layout(kind: kind, content: inkContent),
    };
  }

  /// 图文讲义卡缩略图的 painter（通过 CustomPaint 观测绘制数据）。
  CustomPainter handoutThumbPainter(WidgetTester tester) =>
      tester
          .widget<CustomPaint>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('template-thumb-handout')),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .painter!;

  Future<ValueNotifier<SmartLayoutTemplateChoice?>> openSheet(
    WidgetTester tester,
    SmartLayoutTemplatePreparation preparation, {
    bool allowSkip = false,
    bool keepHandwriting = false,
    ValueChanged<bool>? onKeepHandwritingChanged,
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
                    keepHandwriting: keepHandwriting,
                    onKeepHandwritingChanged: onKeepHandwritingChanged,
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
    // 说明行使内容超出弹层默认最大高度，先滚动到底部再点跳过。
    await tester.ensureVisible(find.text('跳过本页'));
    await tester.pumpAndSettle();
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

  testWidgets('每张模板卡显示适用场景说明', (tester) async {
    await openSheet(tester, buildPreparation());
    expect(find.text('标题与图文成组编排，适合讲义式整理'), findsOneWidget);
    expect(find.text('条目式清单，配图随就近条目走'), findsOneWidget);
    expect(find.text('仅转写文字，版式保持原样'), findsOneWidget);
  });

  testWidgets('未提供保留手写回调时不显示模式开关（向后兼容）', (tester) async {
    await openSheet(tester, buildPreparation());
    expect(find.text('转写为印刷体'), findsNothing);
    expect(find.text('保留手写笔迹'), findsNothing);
  });

  testWidgets('保留手写开关：显示、点击回调新值、可来回切换', (tester) async {
    final events = <bool>[];
    await openSheet(
      tester,
      buildPreparation(layoutsKeepInk: buildKeepInkLayouts()),
      onKeepHandwritingChanged: events.add,
    );
    expect(find.text('转写为印刷体'), findsOneWidget);
    expect(find.text('保留手写笔迹'), findsOneWidget);
    await tester.tap(find.text('保留手写笔迹'));
    await tester.pumpAndSettle();
    expect(events, [true]);
    await tester.tap(find.text('转写为印刷体'));
    await tester.pumpAndSettle();
    expect(events, [true, false]);
  });

  testWidgets('保留手写模式：缩略图切换 layoutsKeepInk 源，放不下的置灰', (tester) async {
    final picked = await openSheet(
      tester,
      buildPreparation(
        layoutsKeepInk: buildKeepInkLayouts(
          missingKinds: {SmartLayoutTemplateKind.outline},
        ),
      ),
      onKeepHandwritingChanged: (_) {},
    );
    // 印刷体模式：全部放得下，缩略图绘制新增印刷体文本。
    expect(find.text('内容放不下'), findsNothing);
    expect(
      (handoutThumbPainter(tester) as dynamic).paintedOnScreenFontSizes as List<double>,
      isNotEmpty,
      reason: '印刷体模式缩略图绘制新增文本',
    );
    // 切到保留手写：outline 放不下置灰，缩略图不再画印刷体文本（墨迹占位）。
    await tester.tap(find.text('保留手写笔迹'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('该模式下放不下'), findsOneWidget);
    expect(
      (handoutThumbPainter(tester) as dynamic).paintedOnScreenFontSizes as List<double>,
      isEmpty,
      reason: '保留手写模式无新增印刷体文本',
    );
    // 点置灰卡不返回（先滚动到卡片区）
    await tester.ensureVisible(find.text('要点清单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('要点清单'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked.value, isNull);
    // 切回印刷体模式恢复可选
    await tester.tap(find.text('转写为印刷体'));
    await tester.pumpAndSettle();
    expect(find.text('该模式下放不下'), findsNothing);
    await tester.ensureVisible(find.text('要点清单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('要点清单'));
    await tester.pumpAndSettle();
    expect(picked.value?.kind, SmartLayoutTemplateKind.outline);
  });

  testWidgets('初始保留手写模式：直接按 layoutsKeepInk 渲染且可点选', (tester) async {
    final picked = await openSheet(
      tester,
      buildPreparation(layoutsKeepInk: buildKeepInkLayouts()),
      keepHandwriting: true,
      onKeepHandwritingChanged: (_) {},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('该模式下放不下'), findsNothing);
    expect(find.text('内容放不下'), findsNothing);
    await tester.ensureVisible(find.text('原文整理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原文整理'));
    await tester.pumpAndSettle();
    expect(picked.value?.kind, SmartLayoutTemplateKind.inplace);
  });

  testWidgets('缩略图字号下限：超小字号文本放大绘制并省略截断', (tester) async {
    // Given：字号 2pt 的超小文本（默认缩放比约 0.27，屏幕字号远小于 9）。
    final content = SmartLayoutContent(
      pageId: 'p-1',
      contentArea: const Rect.fromLTWH(0, 0, 800, 600),
      title: textUnit('title', '页面标题'),
      looseTexts: [
        textUnit(
          't1',
          '这是一段字号极小的手写正文内容，缩略图放大绘制后必须省略截断',
          fontSize: 2,
        ),
        textUnit(
          't2',
          '第二段同样是超小字号的正文内容，用于覆盖字号下限与截断逻辑',
          fontSize: 2,
        ),
      ],
    );
    final preparation = SmartLayoutTemplatePreparation(
      pageId: 'p-1',
      content: content,
      layouts: {
        for (final kind in SmartLayoutTemplateKind.values)
          kind: SmartLayoutTemplateEngine.layout(kind: kind, content: content),
      },
      removeIds: const [],
      failedStrokeIds: const [],
      removalRects: const [],
      failureRects: const [],
      failures: const [],
      confidence: 0.9,
      confidenceByBlockId: const {},
    );
    // When：打开模板选择卡。
    await openSheet(tester, preparation);
    // Then：绘制不抛错；所有文本屏幕字号 >= 9；放大后触发省略截断。
    expect(tester.takeException(), isNull, reason: '放大绘制不得抛错');
    final painter = handoutThumbPainter(tester) as dynamic;
    final onScreenSizes = painter.paintedOnScreenFontSizes as List<double>;
    expect(onScreenSizes, isNotEmpty);
    expect(
      onScreenSizes.every((size) => size >= 9 - 0.01),
      isTrue,
      reason: '缩略图屏幕字号不得小于 9 逻辑像素',
    );
    expect(
      painter.paintedTruncatedTextCount as int,
      greaterThan(0),
      reason: '放大后文本超出落位框应触发省略截断',
    );
  });
}
