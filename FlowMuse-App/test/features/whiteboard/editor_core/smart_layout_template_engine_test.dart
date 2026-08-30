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
    double width = 200,
  }) => LayoutUnit(
    key: key,
    sourceBounds: source,
    size: Size(source.width, source.height),
    kind: LayoutUnitKind.text,
    textElement: bodyText(key, text, fontSize: fontSize, height: height, width: width),
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

  /// 图下注配对（注原稿 top 与图同高 → bind 归下方栈）。
  FigureTextPair pair(
    String figureKey,
    Size figureSize,
    String captionKey,
    String captionText, {
    Rect? figureSource,
  }) => FigureTextPair.bind(
    figure: figureUnit(figureKey, figureSize, source: figureSource),
    texts: [textUnit(captionKey, captionText)],
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

    test('孤行窄图整行居中（不再落左列）', () {
      // Given：仅一只窄图（奇数对落单）；When：handout 落位；
      // Then：图中心 = 内容区中心，不再偏左列。
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            pair('f1', const Size(120, 80), 'c1', '图一',
                figureSource: const Rect.fromLTWH(1000, 0, 120, 80)),
          ],
        ),
      );
      expect(result, isNotNull);
      final delta = result!.moveDeltas[const ElementId('f1')]!;
      expect(
        1000 + delta.dx + 60,
        closeTo(area.center.dx, 0.01),
        reason: '孤行图与标签栈以内容区中心水平居中',
      );
      // 图注随图居中于图。
      final caption = result.addElements.whereType<TextElement>().single;
      expect(
        caption.x + caption.width / 2,
        closeTo(area.center.dx, 0.01),
      );
      expect(caption.y, closeTo(delta.dy + 80 + 24, 0.01));
    });

    test('一图多标签：上栈 bottom 对齐图顶-gap、下栈 top 对齐图底+gap、栈内与图居中',
        () {
      // Given：一只窄图，上方一枚标签、下方两枚标签（多标签栈）。
      // When：handout 落位（孤行居中）；Then：栈几何按契约排布。
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            FigureTextPair(
              figure: figureUnit(
                'f1',
                const Size(200, 150),
                source: const Rect.fromLTWH(0, 0, 200, 150),
              ),
              topTexts: [
                textUnit(
                  't-top',
                  '上方标签',
                  source: const Rect.fromLTWH(50, -60, 100, 40),
                ),
              ],
              bottomTexts: [
                textUnit('t-b1', '注一', source: const Rect.fromLTWH(30, 160, 80, 40)),
                textUnit('t-b2', '注二', source: const Rect.fromLTWH(120, 210, 120, 40)),
              ],
            ),
          ],
        ),
      );
      expect(result, isNotNull);
      const gap = 24.0;
      final figDelta = result!.moveDeltas[const ElementId('f1')]!;
      final figTop = figDelta.dy;
      // 上方栈占据行顶（栈高 40），图整体下移：figTop = 栈高 + gap。
      expect(figTop, closeTo(40 + gap, 0.01));
      final elements = result.addElements.whereType<TextElement>().toList();
      final topLabel = elements.firstWhere((e) => e.text == '上方标签');
      expect(topLabel.y + topLabel.height, closeTo(figTop - gap, 0.01),
          reason: '上栈 bottom 对齐图顶-gap');
      expect(
        topLabel.x + topLabel.width / 2,
        closeTo(figDelta.dx + 100, 0.01),
        reason: '栈内每块与图水平居中',
      );
      final b1 = elements.firstWhere((e) => e.text == '注一');
      final b2 = elements.firstWhere((e) => e.text == '注二');
      expect(b1.y, closeTo(figTop + 150 + gap, 0.01), reason: '下栈 top 对齐图底+gap');
      expect(b2.y, closeTo(b1.y + 40, 0.01), reason: '栈内按阅读序紧邻堆叠');
      expect(b1.x + b1.width / 2, closeTo(figDelta.dx + 100, 0.01));
      expect(b2.x + b2.width / 2, closeTo(figDelta.dx + 100, 0.01));
      // 行高计入标签栈：下栈之后才是内容区剩余空间（全部 ⊆ 内容区）。
      for (final rect in result.previewRects) {
        expect(rect.bottom, lessThanOrEqualTo(area.bottom));
      }
    });

    test('窄图 + 超长图注：标签块横向钳回内容区，previewRect 不越界', () {
      // Given：两只窄图成行，图注宽 500（> 图宽 120，居中于图心会越出
      // 内容区：左列图心 194 左缘 -56、右列图心 606 右缘 856）。
      // When：handout 落位；Then：图注贴内容区边缘钳回，全部 previewRect
      // ⊆ contentArea。
      FigureTextPair wideCaptionPair(String figureKey, String captionKey, String text) =>
          FigureTextPair(
            figure: figureUnit(
              figureKey,
              const Size(120, 80),
              source: Rect.fromLTWH(1000, 0, 120, 80),
            ),
            bottomTexts: [
              textUnit(
                captionKey,
                text,
                source: Rect.fromLTWH(1000, 90, 500, 40),
                width: 500,
              ),
            ],
          );

      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          pairs: [
            wideCaptionPair('f1', 'c1', '左列超长图注'),
            wideCaptionPair('f2', 'c2', '右列超长图注'),
          ],
        ),
      );
      expect(result, isNotNull);
      // 左列图心 halfWidth/2 = (800-24)/4 = 194：居中左缘 -56 越出 → 钳回
      // 内容区左缘。右列图心 halfWidth + gap + halfWidth/2 = 606：居中右缘
      // 856 越出 → 钳回内容区右缘（x = 区宽 - 500）。
      final captions = result!.addElements.whereType<TextElement>().toList();
      final c1 = captions.firstWhere((e) => e.text == '左列超长图注');
      final c2 = captions.firstWhere((e) => e.text == '右列超长图注');
      expect(c1.x, area.left, reason: '左列图注左缘钳回内容区左缘');
      expect(c2.x + c2.width, closeTo(area.right, 0.01), reason: '右列图注右缘钳回内容区右缘');
      for (final rect in result.previewRects) {
        expect(rect.left, greaterThanOrEqualTo(area.left), reason: 'previewRect 不越内容区左缘');
        expect(rect.right, lessThanOrEqualTo(area.right), reason: 'previewRect 不越内容区右缘');
        expect(rect.top, greaterThanOrEqualTo(area.top), reason: 'previewRect 不越内容区顶缘');
        expect(rect.bottom, lessThanOrEqualTo(area.bottom), reason: 'previewRect 不越内容区底缘');
      }
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
      // t2 槽宽 700：贪心装行放不进 t1 所在行（200+24+700 > 800），独占一行。
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
              source: const Rect.fromLTWH(0, 300, 700, 200),
              height: 200,
              width: 700,
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

    test('looseTexts 贪心装行：放得下同行 top 对齐、放不下换行左对齐', () {
      // Given：三块正文（200/200/600 槽宽）；When：handout 落位；
      // Then：t1+t2 同行（200+24+200 ≤ 800），t3 放不下换行。
      final result = SmartLayoutTemplateEngine.layout(
        kind: SmartLayoutTemplateKind.handout,
        content: SmartLayoutContent(
          pageId: 'p1',
          contentArea: area,
          looseTexts: [
            textUnit('t1', '甲', source: const Rect.fromLTWH(0, 0, 200, 40)),
            textUnit('t2', '乙', source: const Rect.fromLTWH(0, 100, 200, 40)),
            textUnit(
              't3',
              '丙',
              source: const Rect.fromLTWH(0, 200, 600, 40),
              width: 600,
            ),
          ],
        ),
      );
      expect(result, isNotNull);
      final elements = result!.addElements.whereType<TextElement>().toList();
      final t1 = elements.firstWhere((e) => e.text == '甲');
      final t2 = elements.firstWhere((e) => e.text == '乙');
      final t3 = elements.firstWhere((e) => e.text == '丙');
      expect(t2.y, t1.y, reason: '同行 top 对齐');
      expect(t2.x, closeTo(t1.x + 200 + 24, 0.01), reason: '同行紧邻（间隙 24pt）');
      expect(t3.x, area.left, reason: '换行后行整体左对齐');
      expect(t3.y, closeTo(t1.y + 40 + 24, 0.01), reason: '行高取最高块 + 行距');
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

    test('小图（≤40% 条目宽）挂靠最近邻条目行右侧，标签栈居中于图', () {
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
              bottomTexts: [
                textUnit(
                  'c1',
                  '示意图',
                  source: const Rect.fromLTWH(460, 230, 100, 30),
                ),
              ],
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
      expect(
        caption.x + caption.width / 2,
        closeTo(area.right - 300 + 150, 0.01),
        reason: '标签与图水平居中',
      );
      expect(caption.y, 56 + 200 + 8);
    });

    test('大图独占通栏行（贴内容区左缘），标签栈居中于图', () {
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
              bottomTexts: [
                textUnit('c1', '示意图', source: const Rect.fromLTWH(0, 210, 100, 30)),
              ],
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
      expect(
        caption.x + caption.width / 2,
        closeTo(area.left + 200, 0.01),
        reason: '标签与图水平居中',
      );
      // 阅读序：条目在图之后。
      final bullet = result.addElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == '• 第一点');
      expect(bullet.y, greaterThan(caption.y));
    });

    test('独占行图 + 超长图注：标签块横向钳回内容区，previewRect 不越界', () {
      // Given：宽 400 的独占行图（图贴左缘，图心 x=200）+ 宽 500 的图注
      //（> 图宽，居中左缘 -50 越出内容区）；When：outline 落位；
      // Then：图注钳回内容区左缘，全部 previewRect ⊆ contentArea。
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
              bottomTexts: [
                textUnit(
                  'c1',
                  '示意图',
                  source: const Rect.fromLTWH(0, 210, 500, 30),
                  width: 500,
                ),
              ],
            ),
          ],
        ),
      );
      expect(result, isNotNull);
      final caption = result!.addElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == '示意图');
      expect(caption.x, area.left, reason: '独占行图注越出时钳回内容区左缘');
      for (final rect in result.previewRects) {
        expect(rect.left, greaterThanOrEqualTo(area.left), reason: 'previewRect 不越内容区左缘');
        expect(rect.right, lessThanOrEqualTo(area.right), reason: 'previewRect 不越内容区右缘');
        expect(rect.top, greaterThanOrEqualTo(area.top), reason: 'previewRect 不越内容区顶缘');
        expect(rect.bottom, lessThanOrEqualTo(area.bottom), reason: 'previewRect 不越内容区底缘');
      }
    });

    test('侧挂小图 + 超长图注：标签块横向钳回内容区，previewRect 不越界', () {
      // Given：宽 300 小图挂靠条目行右侧（图心 x=650）+ 宽 500 的图注
      //（> 图宽，居中右缘 900 越出内容区）；When：outline 落位；
      // Then：图注右缘钳回内容区右缘，全部 previewRect ⊆ contentArea。
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
              bottomTexts: [
                textUnit(
                  'c1',
                  '示意图',
                  source: const Rect.fromLTWH(460, 230, 500, 30),
                  width: 500,
                ),
              ],
            ),
          ],
          looseTexts: [
            textUnit('t1', '第一点', source: const Rect.fromLTWH(0, 0, 200, 40)),
          ],
        ),
      );
      expect(result, isNotNull);
      final caption = result!.addElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == '示意图');
      expect(caption.x, closeTo(area.right - 500, 0.01), reason: '侧挂图注右缘钳回内容区右缘');
      for (final rect in result.previewRects) {
        expect(rect.left, greaterThanOrEqualTo(area.left), reason: 'previewRect 不越内容区左缘');
        expect(rect.right, lessThanOrEqualTo(area.right), reason: 'previewRect 不越内容区右缘');
        expect(rect.top, greaterThanOrEqualTo(area.top), reason: 'previewRect 不越内容区顶缘');
        expect(rect.bottom, lessThanOrEqualTo(area.bottom), reason: 'previewRect 不越内容区底缘');
      }
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
              bottomTexts: [
                textUnit(
                  'c1',
                  '题注',
                  source: const Rect.fromLTWH(420, 310, 200, 30),
                ),
              ],
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
          bottomTexts: [
            inkTextUnit(
              'c1',
              '图注',
              source: const Rect.fromLTWH(1010, 160, 80, 30),
              memberIds: ['k-cap'],
            ),
          ],
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
        content0.pairs.single.bottomTexts.single,
        deltas[const ElementId('k-cap')]!,
      );
      final figureTarget = movedRect(
        content0.pairs.single.figure,
        deltas[const ElementId('img-a')]!,
      );
      expect(captionTarget.top, closeTo(figureTarget.bottom + 24, 0.01));
      expect(
        captionTarget.center.dx,
        closeTo(figureTarget.center.dx, 0.01),
        reason: '墨迹标签与图水平居中',
      );
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
        content0.pairs.single.bottomTexts.single,
        deltas[const ElementId('k-cap')]!,
      );
      expect(captionTarget.top, closeTo(figureTarget.bottom + 8, 0.01));
      expect(
        captionTarget.center.dx,
        closeTo(figureTarget.center.dx, 0.01),
        reason: '墨迹标签与图水平居中',
      );
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
          content0.pairs.single.bottomTexts.single.sourceBounds,
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

  group('FigureTextPair.bind（标签分栈）', () {
    test('原稿 top 小于图 top 归上栈，其余（含侧方）归下栈；各栈按阅读序', () {
      // Given：一枚图与四枚标签（上、下、侧、再下）。
      // When：bind；Then：上/下栈划分与排序确定。
      final figure = figureUnit(
        'f1',
        const Size(200, 200),
        source: const Rect.fromLTWH(100, 100, 200, 200),
      );
      final pair = FigureTextPair.bind(figure: figure, texts: [
        textUnit('below1', '下注一', source: const Rect.fromLTWH(100, 310, 80, 30)),
        textUnit('above1', '上标一', source: const Rect.fromLTWH(110, 40, 80, 30)),
        textUnit('side1', '图1', source: const Rect.fromLTWH(310, 150, 60, 30)),
        textUnit('above2', '上标二', source: const Rect.fromLTWH(30, 60, 60, 30)),
      ]);
      expect(
        pair.topTexts.map((u) => u.key),
        ['above1', 'above2'],
        reason: '上栈按阅读序（top→left）',
      );
      expect(
        pair.bottomTexts.map((u) => u.key),
        ['side1', 'below1'],
        reason: '侧方标签（top 不小于图 top）归下栈并按阅读序',
      );
      expect(pair.texts, hasLength(4), reason: 'texts 覆盖全部标签');
    });
  });
}
