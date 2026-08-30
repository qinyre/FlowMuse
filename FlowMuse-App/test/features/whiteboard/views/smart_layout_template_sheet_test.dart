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
    bool hasInkTextUnits = true,
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
      hasInkTextUnits: hasInkTextUnits,
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

  Future<ValueNotifier<SmartLayoutTemplateChoice?>> openSheet(
    WidgetTester tester,
    SmartLayoutTemplatePreparation preparation, {
    bool allowSkip = false,
    bool keepHandwriting = false,
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

  testWidgets('无保留手写变体时不显示模式开关', (tester) async {
    await openSheet(tester, buildPreparation());
    expect(find.text('转写为印刷体'), findsNothing);
    expect(find.text('保留手写笔迹'), findsNothing);
  });

  testWidgets('纯打字页（无手写转写文本）不显示模式开关', (tester) async {
    await openSheet(
      tester,
      buildPreparation(
        layoutsKeepInk: buildKeepInkLayouts(),
        hasInkTextUnits: false,
      ),
    );
    expect(find.text('转写为印刷体'), findsNothing);
    expect(find.text('保留手写笔迹'), findsNothing);
  });

  testWidgets('保留手写开关：弹层内切换模式，选卡随返回 keepHandwriting', (tester) async {
    final picked = await openSheet(
      tester,
      buildPreparation(
        layoutsKeepInk: buildKeepInkLayouts(
          missingKinds: {SmartLayoutTemplateKind.outline},
        ),
      ),
    );
    expect(find.text('转写为印刷体'), findsOneWidget);
    expect(find.text('保留手写笔迹'), findsOneWidget);
    // 切到保留手写（弹层内部状态，无需外部回调）：outline 放不下置灰。
    await tester.tap(find.text('保留手写笔迹'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('该模式下放不下'), findsOneWidget);
    // 点置灰卡不返回（先滚动到卡片区）。
    await tester.ensureVisible(find.text('要点清单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('要点清单'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked.value, isNull);
    // 切回印刷体模式恢复可选；选卡返回 keepHandwriting=false。
    await tester.tap(find.text('转写为印刷体'));
    await tester.pumpAndSettle();
    expect(find.text('该模式下放不下'), findsNothing);
    await tester.ensureVisible(find.text('要点清单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('要点清单'));
    await tester.pumpAndSettle();
    expect(picked.value?.kind, SmartLayoutTemplateKind.outline);
    expect(picked.value?.keepHandwriting, isFalse);
  });

  testWidgets('保留手写模式：缩略图切换 layoutsKeepInk 源，放不下的置灰', (tester) async {
    final picked = await openSheet(
      tester,
      buildPreparation(
        layoutsKeepInk: buildKeepInkLayouts(
          missingKinds: {SmartLayoutTemplateKind.outline},
        ),
      ),
    );
    // 印刷体模式：全部放得下。
    expect(find.text('内容放不下'), findsNothing);
    // 切到保留手写：outline 放不下置灰，缩略图切换为墨迹占位源。
    await tester.tap(find.text('保留手写笔迹'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('该模式下放不下'), findsOneWidget);
    // 切回印刷体模式恢复可选。
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
    );
    expect(tester.takeException(), isNull);
    expect(find.text('该模式下放不下'), findsNothing);
    expect(find.text('内容放不下'), findsNothing);
    await tester.ensureVisible(find.text('原文整理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原文整理'));
    await tester.pumpAndSettle();
    expect(picked.value?.kind, SmartLayoutTemplateKind.inplace);
    expect(picked.value?.keepHandwriting, isTrue);
  });

  test('缩略图屏幕字号下限：换算后不足 9 逻辑像素放大到 9', () {
    // Given：缩略图缩放比 0.25。
    const scale = 0.25;
    // When/Then：落位字号 2pt 换算到屏幕 0.5 → 放大到下限 9/scale。
    expect(
      smartLayoutThumbFontSize(2, scale),
      kSmartLayoutThumbMinOnScreenFontSize / scale,
    );
    // 落位字号换算后已超过下限：原样保留，不放大。
    expect(smartLayoutThumbFontSize(50, scale), 50);
  });

  test('缩略图行数上限：落位框高放得下为准，至少 1 行', () {
    expect(
      smartLayoutThumbMaxLines(slotHeight: 40, fontSize: 10, lineHeight: 1.5),
      2,
      reason: '40 / (10×1.5) ≈ 2.67 → 向下取整 2 行',
    );
    expect(
      smartLayoutThumbMaxLines(slotHeight: 5, fontSize: 10, lineHeight: 1),
      1,
      reason: '框高不足一行时保底 1 行',
    );
  });

  testWidgets('缩略图绘制超小字号内容不抛错（放大绘制与省略截断路径）', (tester) async {
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
    // Then：绘制（含字号放大与省略截断路径）不抛错。
    expect(tester.takeException(), isNull, reason: '放大绘制不得抛错');
  });
}
