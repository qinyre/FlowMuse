import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_content.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_template_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// v2 三模板落位引擎几何契约：确定性、固定区域填充、all-or-nothing。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 内容区 800×600。
  const area = Rect.fromLTWH(0, 0, 800, 600);

  TextElement bodyText(
    String id,
    String text, {
    double fontSize = 20,
    double width = 200,
    double height = 40,
  }) => TextElement(
    id: ElementId(id),
    x: 0,
    y: 0,
    width: width,
    height: height,
    text: text,
    fontSize: fontSize,
    // 捆绑字体，避免测试环境触发 Google Fonts 异步加载。
    fontFamily: 'Excalifont',
  );

  LayoutUnit textUnit(
    String key,
    String text, {
    Rect source = const Rect.fromLTWH(0, 0, 200, 40),
    double fontSize = 20,
    double height = 40,
  }) => LayoutUnit(
    key: key,
    sourceBounds: source,
    size: Size(source.width, source.height),
    kind: LayoutUnitKind.text,
    textElement: bodyText(key, text, fontSize: fontSize, height: height),
  );

  LayoutUnit figureUnit(
    String key,
    Size size, {
    Rect? source,
    List<String> memberIds = const [],
  }) => LayoutUnit(
    key: key,
    sourceBounds:
        source ?? Rect.fromLTWH(1000, 1000, size.width, size.height),
    size: size,
    kind: LayoutUnitKind.image,
    memberIds: memberIds,
  );

  FigureTextPair pair(
    String figureKey,
    Size figureSize,
    String captionKey,
    String captionText, {
    Rect? figureSource,
  }) => FigureTextPair(
    figure: figureUnit(figureKey, figureSize, source: figureSource),
    caption: textUnit(captionKey, captionText),
    figureAbove: true,
  );

  group('handout 图文讲义', () {
    test('标题通栏置顶居中；字号不足 28 放大到 28', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          title: textUnit(
            'title',
            '标题',
            source: const Rect.fromLTWH(10, 10, 100, 40),
          ),
          looseTexts: [textUnit('t1', '正文一段')],
        ),
      );
      expect(result, isNotNull);
      final title = result!.addElements.first as TextElement;
      expect(title.fontSize, 28);
      expect(
        title.x + title.width / 2,
        closeTo(area.center.dx, 0.01),
      );
      expect(title.y, area.top);
      // 正文在标题之后。
      final body = result.addElements.last as TextElement;
      expect(body.y, greaterThan(title.y + title.height));
      // 转写模式（非保留手写）无墨迹占位矩形。
      expect(result.inkSlotRects, isEmpty, reason: 'typed 模式 inkSlotRects 为空');
    });

    test('窄图两两成行：图上图注下、格内居中，行高取两格较大者', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            pair('f1', const Size(120, 80), 'c1', '图一',
                figureSource: const Rect.fromLTWH(1000, 0, 120, 80)),
            pair('f2', const Size(120, 200), 'c2', '图二',
                figureSource: const Rect.fromLTWH(1200, 0, 120, 200)),
          ],
        ),
      );
      expect(result, isNotNull);
      // f1 与 f2 同行：两图 y 相同（source top 均为 0，dy 即目标 top）。
      final f1 = result!.moveDeltas[const ElementId('f1')]!;
      final f2 = result.moveDeltas[const ElementId('f2')]!;
      expect(f1.dy, f2.dy);
      // 左格中心 x = halfWidth/2；右格中心 x = halfWidth + gap + halfWidth/2。
      const gap = 24.0;
      final halfWidth = (area.width - gap) / 2;
      final f1TargetX = 1000 + f1.dx + 120 / 2;
      expect(f1TargetX, closeTo(halfWidth / 2, 0.01));
      final f2TargetX = 1200 + f2.dx + 120 / 2;
      expect(
        f2TargetX,
        closeTo(halfWidth + gap + halfWidth / 2, 0.01),
      );
      // 图上图注下：题注 y = 图 y + 图高 + gap。
      final c1 = result.addElements.whereType<TextElement>().first;
      expect(c1.text, '图一');
      expect(c1.y, closeTo(f1.dy + 80 + gap, 0.01));
    });

    test('宽图（>60% 页宽）独占通栏行且水平居中', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            pair('f1', const Size(500, 200), 'c1', '大图',
                figureSource: const Rect.fromLTWH(0, 0, 500, 200)),
          ],
        ),
      );
      expect(result, isNotNull);
      final delta = result!.moveDeltas[const ElementId('f1')]!;
      expect(0 + delta.dx + 250, closeTo(area.center.dx, 0.01));
    });

    test('空间不足先压间距：默认档失败后 12 档成功', () {
      // gap 24 时总高 602 超区；gap 12 时 566 放得下。
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            pair('f1', const Size(100, 100), 'c1', '图一',
                figureSource: const Rect.fromLTWH(0, 0, 100, 100)),
            pair('f2', const Size(100, 100), 'c2', '图二',
                figureSource: const Rect.fromLTWH(200, 0, 100, 100)),
          ],
          looseTexts: [
            textUnit(
              't1',
              '第一段',
              source: const Rect.fromLTWH(0, 0, 200, 200),
              height: 200,
            ),
            textUnit(
              't2',
              '第二段',
              source: const Rect.fromLTWH(0, 300, 200, 200),
              height: 200,
            ),
          ],
        ),
      );
      expect(result, isNotNull);
      // 窄图行（行高 152 = 100+12+40）→ t1 y=164 → t2 y=376。
      final t2 = result!.previewRects.last;
      expect(t2.top, 376);
      expect(t2.bottom, lessThanOrEqualTo(area.bottom));
    });

    test('压缩到底仍放不下 → 返回 null（提示分页）', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            pair('f1', const Size(700, 590), 'c1', '巨大图',
                figureSource: const Rect.fromLTWH(0, 0, 700, 590)),
          ],
        ),
      );
      expect(result, isNull);
    });
  });

  group('outline 要点清单', () {
    test('条目加"• "前缀并按阅读序排列', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.outline,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          looseTexts: [
            textUnit('t1', '第一点', source: const Rect.fromLTWH(0, 0, 200, 40)),
            textUnit('t2', '第二点', source: const Rect.fromLTWH(0, 100, 200, 40)),
          ],
        ),
      );
      expect(result, isNotNull);
      final texts = result!.addElements.whereType<TextElement>().toList();
      expect(texts[0].text, '• 第一点');
      expect(texts[1].text, '• 第二点');
      expect(texts[0].y, lessThan(texts[1].y));
      expect(texts[0].x, area.left);
    });

    test('小图（≤40% 条目宽）挂靠最近邻条目行右侧，caption 随图', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.outline,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            FigureTextPair(
              figure: figureUnit(
                'f1',
                const Size(300, 200),
                source: const Rect.fromLTWH(450, 20, 300, 200),
                memberIds: ['img-a'],
              ),
              caption: textUnit(
                'c1',
                '示意图',
                source: const Rect.fromLTWH(460, 230, 100, 30),
              ),
              figureAbove: true,
            ),
          ],
          looseTexts: [
            textUnit('t1', '第一点', source: const Rect.fromLTWH(0, 0, 200, 40)),
            textUnit('t2', '第二点', source: const Rect.fromLTWH(0, 100, 200, 40)),
          ],
        ),
      );
      expect(result, isNotNull);
      // 图中心 (600,120)：t2 中心 (100,120) 比 t1 中心 (100,20) 更近 → 挂靠 t2。
      final delta = result!.moveDeltas[const ElementId('img-a')]!;
      // t2 行 y：t1 行（高 40）+ 行距 16 = 56。
      expect(20 + delta.dy, 56);
      expect(450 + delta.dx, area.right - 300);
      final caption = result.addElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == '示意图');
      expect(caption.x, area.right - 300);
      expect(caption.y, 56 + 200 + 8);
    });

    test('大图独占通栏行（贴内容区左缘），caption 随图在下', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.outline,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            FigureTextPair(
              figure: figureUnit(
                'f1',
                const Size(400, 200),
                source: const Rect.fromLTWH(0, 0, 400, 200),
                memberIds: ['img-a'],
              ),
              caption: textUnit('c1', '示意图', source: const Rect.fromLTWH(0, 210, 100, 30)),
              figureAbove: true,
            ),
          ],
          looseTexts: [
            textUnit('t1', '第一点', source: const Rect.fromLTWH(0, 300, 200, 40)),
          ],
        ),
      );
      expect(result, isNotNull);
      final delta = result!.moveDeltas[const ElementId('img-a')]!;
      expect(0 + delta.dx, area.left);
      expect(0 + delta.dy, area.top);
      final caption = result.addElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == '示意图');
      expect(caption.y, area.top + 200 + 8);
      // 阅读序：条目在图之后。
      final bullet = result.addElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == '• 第一点');
      expect(bullet.y, greaterThan(caption.y));
    });

    test('条目流超出内容区 → 返回 null', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.outline,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: const Rect.fromLTWH(0, 0, 800, 100),
          looseTexts: [
            textUnit('t1', '第一点', source: const Rect.fromLTWH(0, 0, 200, 40)),
            textUnit('t2', '第二点', source: const Rect.fromLTWH(0, 50, 200, 40)),
            textUnit('t3', '第三点', source: const Rect.fromLTWH(0, 100, 200, 40)),
          ],
        ),
      );
      expect(result, isNull);
    });
  });

  group('inplace 原文整理', () {
    test('文本以原稿并集框中心原位替换；图与形不动（moveDeltas 空）', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.inplace,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            FigureTextPair(
              figure: figureUnit(
                'f1',
                const Size(300, 200),
                source: const Rect.fromLTWH(400, 100, 300, 200),
                memberIds: ['img-a'],
              ),
              caption: textUnit(
                'c1',
                '题注',
                source: const Rect.fromLTWH(420, 310, 200, 30),
              ),
              figureAbove: true,
            ),
          ],
          looseTexts: [
            textUnit('t1', '正文', source: const Rect.fromLTWH(100, 100, 200, 80)),
          ],
        ),
      );
      expect(result, isNotNull);
      expect(result!.moveDeltas, isEmpty);
      // 题注中心 (520, 325)：文本 200×40 → x=420, y=305。
      final caption = result.addElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == '题注');
      expect(caption.x, 420);
      expect(caption.y, 305);
      // 正文中心 (200, 140)：文本 200×40 → x=100, y=120。
      final body = result.addElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == '正文');
      expect(body.x, 100);
      expect(body.y, 120);
    });

    test('无文本内容 → 返回 null', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.inplace,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          looseFigures: [figureUnit('f1', const Size(100, 100))],
        ),
      );
      expect(result, isNull);
    });
  });

  group('保留手写（keepAsInk 墨迹占位）', () {
    LayoutUnit inkTextUnit(
      String key,
      String text, {
      Rect source = const Rect.fromLTWH(0, 0, 200, 40),
      List<String> memberIds = const [],
    }) => LayoutUnit(
      key: key,
      sourceBounds: source,
      size: Size(source.width, source.height),
      kind: LayoutUnitKind.text,
      textElement: bodyText(key, text),
      keepAsInk: true,
      memberIds: memberIds,
    );

    SmartLayoutContent keepInkContent() => SmartLayoutContent(
      pageId: 'p1',
      contentArea: area,
      title: inkTextUnit(
        'title',
        '标题',
        source: const Rect.fromLTWH(10, 10, 120, 40),
        memberIds: ['k-title'],
      ),
      pairs: [
        FigureTextPair(
          figure: figureUnit(
            'f1',
            const Size(200, 150),
            source: const Rect.fromLTWH(1000, 0, 200, 150),
            memberIds: ['img-a'],
          ),
          caption: inkTextUnit(
            'c1',
            '图注',
            source: const Rect.fromLTWH(1010, 160, 80, 30),
            memberIds: ['k-cap'],
          ),
          figureAbove: true,
        ),
      ],
      looseTexts: [
        inkTextUnit('t1', '第一句', source: const Rect.fromLTWH(0, 0, 160, 40), memberIds: ['k-t1']),
      ],
    );

    Rect movedRect(LayoutUnit unit, Offset delta) => Rect.fromLTWH(
      unit.sourceBounds.left + delta.dx,
      unit.sourceBounds.top + delta.dy,
      unit.size.width,
      unit.size.height,
    );

    test('handout：标题墨迹居中置顶（不放大）、图注随图、正文左对齐流，全部走移动', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: keepInkContent(),
      );
      expect(result, isNotNull);
      expect(
        result!.addElements.whereType<TextElement>(),
        isEmpty,
        reason: '保留手写不新增任何印刷体文本',
      );
      final deltas = result.moveDeltas;
      expect(deltas.keys.map((id) => id.value), containsAll([
        'k-title',
        'k-cap',
        'k-t1',
        'img-a',
      ]));
      // 标题墨迹居中置顶：目标中心 = 内容区中心，y = 顶。
      final titleTarget = movedRect(
        keepInkContent().title!,
        deltas[const ElementId('k-title')]!,
      );
      expect(titleTarget.center.dx, closeTo(area.center.dx, 0.01));
      expect(titleTarget.top, area.top);
      // 图注墨迹随图下方；正文墨迹左对齐流。
      final content0 = keepInkContent();
      final captionTarget = movedRect(
        content0.pairs.single.caption,
        deltas[const ElementId('k-cap')]!,
      );
      final figureTarget = movedRect(
        content0.pairs.single.figure,
        deltas[const ElementId('img-a')]!,
      );
      expect(captionTarget.top, closeTo(figureTarget.bottom + 24, 0.01));
      final bodyTarget = movedRect(
        content0.looseTexts.single,
        deltas[const ElementId('k-t1')]!,
      );
      expect(bodyTarget.left, area.left);
      expect(bodyTarget.top, greaterThan(figureTarget.bottom));
      // 预览矩形两两不重叠。
      for (var i = 0; i < result.previewRects.length; i++) {
        for (var j = i + 1; j < result.previewRects.length; j++) {
          expect(
            result.previewRects[i].overlaps(result.previewRects[j]),
            isFalse,
            reason: 'previewRect[$i] 与 [$j] 不应重叠',
          );
        }
      }
      // 墨迹占位矩形 = 三块文本墨迹的移动目标（不含图 img-a），供缩略图
      // 查表区分墨迹占位与图/形。
      expect(result.inkSlotRects.toSet(), {
        titleTarget,
        captionTarget,
        bodyTarget,
      });
    });

    test('outline：条目行墨迹左对齐、无"• "前缀，图注随图', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.outline,
        content: keepInkContent(),
      );
      expect(result, isNotNull);
      expect(
        result!.addElements.whereType<TextElement>(),
        isEmpty,
        reason: '保留手写条目不加"• "前缀、不新增印刷体',
      );
      final deltas = result.moveDeltas;
      final content0 = keepInkContent();
      final titleTarget = movedRect(
        content0.title!,
        deltas[const ElementId('k-title')]!,
      );
      final bodyTarget = movedRect(
        content0.looseTexts.single,
        deltas[const ElementId('k-t1')]!,
      );
      expect(titleTarget.left, area.left, reason: '标题墨迹左对齐置顶');
      expect(bodyTarget.left, area.left, reason: '条目墨迹左对齐');
      // 小图（200 ≤ 40%×800）挂靠唯一条目行右侧，图注墨迹随图下方。
      final figureTarget = movedRect(
        content0.pairs.single.figure,
        deltas[const ElementId('img-a')]!,
      );
      expect(figureTarget.left, area.right - 200);
      final captionTarget = movedRect(
        content0.pairs.single.caption,
        deltas[const ElementId('k-cap')]!,
      );
      expect(captionTarget.top, closeTo(figureTarget.bottom + 8, 0.01));
    });

    test('inplace：文本墨迹完全不动（仅预览占位），结果可用', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.inplace,
        content: keepInkContent(),
      );
      expect(result, isNotNull);
      expect(result!.addElements, isEmpty);
      expect(result.moveDeltas, isEmpty);
      final content0 = keepInkContent();
      expect(
        result.previewRects.toSet(),
        {
          content0.title!.sourceBounds,
          content0.pairs.single.caption.sourceBounds,
          content0.looseTexts.single.sourceBounds,
        },
        reason: '墨迹不动，预览即原稿包围盒',
      );
    });
  });

  group('确定性', () {
    test('同输入两次调用结果一致', () {
      SmartLayoutContent build() => SmartLayoutContent(
        pageId: 'p1',
        contentArea: area,
        pairs: [
          pair('f1', const Size(120, 80), 'c1', '图一',
              figureSource: const Rect.fromLTWH(1000, 0, 120, 80)),
        ],
        looseTexts: [
          textUnit('t1', '第一段', source: const Rect.fromLTWH(0, 0, 200, 40)),
        ],
      );
      final first = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: build(),
      );
      final second = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: build(),
      );
      expect(first!.previewRects.length, second!.previewRects.length);
      for (var i = 0; i < first.previewRects.length; i++) {
        expect(first.previewRects[i], second.previewRects[i]);
      }
      expect(
        (first.addElements.first as TextElement).text,
        (second.addElements.first as TextElement).text,
      );
    });
  });

  group('文档导出块', () {
    test('三种模板都产出文本导出块（阅读序）', () {
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.inplace,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          looseTexts: [
            textUnit('t1', '第一段', source: const Rect.fromLTWH(0, 0, 200, 40)),
            textUnit('t2', '第二段', source: const Rect.fromLTWH(0, 50, 200, 40)),
          ],
        ),
      );
      expect(result, isNotNull);
      final blocks = result!.document.blocks;
      expect(blocks.map((b) => b.text), ['第一段', '第二段']);
      expect(blocks.map((b) => b.order), [0, 1]);
    });
  });
}
