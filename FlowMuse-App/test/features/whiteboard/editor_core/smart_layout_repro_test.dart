import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复现用户截图页面：标准页 1588x2246 + 4 行手写（跨"会话"）+ 形状障碍 +
/// 大图(620)。v2 视觉管线（去会话化全页聚类 + 模板预落位）下，
/// 三张模板都不应误报"空间不足"。
///
/// 第二组：第四轮走查主诉复现（宽图 + 方图 + 四短句 + 标题 + 两图注）——
/// 断言三模板 (a) previewRect 两两不重叠；(b) 全部 ⊆ contentArea；
/// (c) 图注几何配对兜底生效（图注与图成组，不再混进正文流）；
/// (d) 应用到草稿场景后元素最终包围盒 == previewRects 且仍不重叠；
/// (e) 留白：布局总宽 ≥ 内容区宽的 60%（宽图进网格自然铺开）。
void main() {
  testWidgets('真机回归：多行手写 + 大图页面三模板均能落位', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = _buildController();
    // 4 行手写（会话标记不再参与智能排版：v2 全页几何聚类）
    controller.applyResult(
      AddElementResult(_stroke('l1', 's1', 300, 150, 200, 28)),
    );
    controller.applyResult(
      AddElementResult(_stroke('l2', 's1', 320, 220, 200, 28)),
    );
    controller.applyResult(
      AddElementResult(_stroke('l3', 's1', 340, 290, 160, 28)),
    );
    controller.applyResult(
      AddElementResult(_stroke('l4', 's1', 300, 360, 140, 28)),
    );
    // 形状障碍（保持原位的普通元素）
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('shape-box'),
          x: 280,
          y: 430,
          width: 70,
          height: 70,
        ),
      ),
    );
    // 大图 620x620
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: ElementId('img-cat'),
          x: 480,
          y: 620,
          width: 620,
          height: 620,
          fileId: 'file-cat',
        ),
      ),
    );
    controller.onVisionSmartLayout = (request) async {
      // 阅读序编号：前 4 个编号是四行手写簇，其余是形状与大图
      expect(request.marks.length, greaterThanOrEqualTo(6));
      return SmartLayoutVisionResponse(
        elements: [
          for (var i = 0; i < 4; i++)
            _visionElement('body', '这是第 $i 句话', request.marks[i]),
          _visionElement('figure', '', request.marks.last, id: 'e-figure'),
        ],
      );
    };
    final preparation = (await tester.runAsync(
      () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
    ))!;
    for (final kind in SmartLayoutTemplateKind.values) {
      expect(
        preparation.layouts[kind],
        isNotNull,
        reason: '${kind.displayName} 不应误报空间不足',
      );
    }
    // 点选图文讲义：大图独占通栏、四句话按段落流落位
    final plan = controller
        .buildSmartLayoutPlanForTemplate(
          preparation,
          SmartLayoutTemplateKind.handout,
        )
        .plan;
    expect(plan, isNotNull);
    expect(
      plan!.moveDeltas.keys.map((id) => id.value),
      contains('img-cat'),
    );
    final texts = plan.addElements
        .whereType<TextElement>()
        .map((e) => e.text)
        .toList();
    for (var i = 0; i < 4; i++) {
      expect(texts, contains('这是第 $i 句话'));
    }
  });

  testWidgets('走查复现：宽图+方图+四短句+标题+两图注，三模板不重叠不溢出、图注成组',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = _buildController();
    // Given：走查主诉场景——宽图（16:9）、方图、四短句、"总结句"标题、
    // 两个紧邻图片的图注"图1"（caption 角色）与"图2"（body 角色）。
    // VLM 不返回任何 pairId（走查实况：配对失败），逼出客户端几何兜底。
    void addStroke(String id, double x, double y, double w, double h) {
      controller.applyResult(AddElementResult(_stroke(id, 's1', x, y, w, h)));
    }

    addStroke('l-title', 300, 150, 160, 44);
    addStroke('l-s1', 200, 250, 200, 40);
    addStroke('l-s2', 220, 320, 180, 40);
    addStroke('l-s3', 240, 390, 200, 40);
    addStroke('l-s4', 200, 460, 160, 40);
    addStroke('l-cap1', 140, 1636, 70, 30); // 宽图下缘 1606，垂直间隙 30
    addStroke('l-cap2', 1080, 1230, 70, 30); // 方图下缘 1200，垂直间隙 30
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: const ElementId('img-wide'),
          x: 100,
          y: 1100,
          width: 900,
          height: 506,
          fileId: 'file-wide',
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: const ElementId('img-square'),
          x: 1050,
          y: 700,
          width: 500,
          height: 500,
          fileId: 'file-square',
        ),
      ),
    );
    // 阅读序编号：m1 标题、m2-m5 四短句、m6 方图、m7 宽图、m8 "图2"、m9 "图1"。
    controller.onVisionSmartLayout = (request) async {
      expect(request.marks, hasLength(9), reason: '7 个手写簇 + 2 张图全部编号');
      return SmartLayoutVisionResponse(
        elements: [
          _visionElement('title', '总结句', request.marks[0]),
          _visionElement('body', '这是第一句话', request.marks[1]),
          _visionElement('body', '这是第二句话', request.marks[2]),
          _visionElement('body', '这是第三句话', request.marks[3]),
          _visionElement('body', '这是第四句话', request.marks[4]),
          _visionElement('figure', '', request.marks[5]),
          _visionElement('figure', '', request.marks[6]),
          _visionElement('body', '图2', request.marks[7]),
          _visionElement('caption', '图1', request.marks[8]),
        ],
      );
    };
    // When：识别准备 + 逐模板装配 + 进入草稿场景。
    final preparation = (await tester.runAsync(
      () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
    ))!;
    // Then(c)：配对兜底生效——两条图注都就近绑图，不再出现在 looseTexts。
    expect(preparation.content.pairs, hasLength(2), reason: '两条图注都应成组');
    expect(
      {
        for (final pair in preparation.content.pairs)
          for (final unit in pair.texts) unit.textElement!.text: pair.figure.size,
      },
      {
        '图1': const Size(900, 506),
        '图2': const Size(500, 500),
      },
      reason: '图注绑到正确的图（就近 + 正确编号映射）',
    );
    expect(
      preparation.content.looseTexts
          .map((u) => u.textElement!.text)
          .where((text) => text == '图1' || text == '图2'),
      isEmpty,
      reason: '图注不再混进正文流',
    );
    expect(preparation.content.looseTexts, hasLength(4));
    expect(preparation.content.looseFigures, isEmpty);

    final contentArea = preparation.content.contentArea;
    for (final kind in SmartLayoutTemplateKind.values) {
      final layout = preparation.layouts[kind];
      expect(layout, isNotNull, reason: '${kind.displayName} 应能放得下');
      final rects = layout!.previewRects;
      // Then(a)：previewRect 两两不重叠。
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].overlaps(rects[j]),
            isFalse,
            reason: '${kind.displayName} previewRect[$i]=$rects[i] 与'
                ' [$j]=${rects[j]} 不应重叠（走查主诉：图片重叠）',
          );
        }
      }
      // Then(b)：全部 ⊆ contentArea。
      for (var i = 0; i < rects.length; i++) {
        final rect = rects[i];
        final contained =
            contentArea.left <= rect.left &&
            rect.right <= contentArea.right &&
            contentArea.top <= rect.top &&
            rect.bottom <= contentArea.bottom;
        expect(
          contained,
          isTrue,
          reason: '${kind.displayName} previewRect[$i]=${rects[i]} 应在'
              ' 内容区 $contentArea 内（走查主诉：内容溢出）',
        );
      }
      // Then(e)：留白——布局总宽 ≥ 内容区宽的 60%（宽图自然铺开）。
      var union = rects.first;
      for (final rect in rects.skip(1)) {
        union = union.expandToInclude(rect);
      }
      expect(
        union.width,
        greaterThanOrEqualTo(contentArea.width * 0.6),
        reason: '${kind.displayName} 布局总宽 ${union.width} 应铺开内容区'
            ' （≥ ${contentArea.width * 0.6}，走查主诉：留白失衡）',
      );
      // Then(d)：应用到草稿场景后，元素最终包围盒 == previewRects 且仍不重叠。
      final plan = controller
          .buildSmartLayoutPlanForTemplate(preparation, kind)
          .plan!;
      controller.enterSmartLayoutDraft(plan);
      final draftRects = <Rect>{
        for (final element in controller.editorState.scene.activeElements)
          if (plan.addElements.any((e) => e.id == element.id) ||
              plan.moveDeltas.keys.contains(element.id))
            Rect.fromLTWH(element.x, element.y, element.width, element.height),
      };
      expect(
        draftRects.length,
        rects.length,
        reason: '${kind.displayName} 草稿参与者数量应与预览一致',
      );
      for (final rect in rects) {
        expect(
          draftRects.any(
            (draft) =>
                (draft.left - rect.left).abs() < 0.01 &&
                (draft.top - rect.top).abs() < 0.01 &&
                (draft.width - rect.width).abs() < 0.01 &&
                (draft.height - rect.height).abs() < 0.01,
          ),
          isTrue,
          reason: '${kind.displayName} 草稿元素包围盒应与 previewRect $rect 一致',
        );
      }
      final draftList = draftRects.toList();
      for (var i = 0; i < draftList.length; i++) {
        for (var j = i + 1; j < draftList.length; j++) {
          expect(
            draftList[i].overlaps(draftList[j]),
            isFalse,
            reason: '${kind.displayName} 草稿最终元素仍不重叠',
          );
        }
      }
      // 笔迹已按计划删除（草稿场景不留原稿手写）。
      expect(
        controller.editorState.scene.activeElements
            .where((e) => e.id == const ElementId('l-s1')),
        isEmpty,
      );
      controller.cancelSmartLayoutDraft();
    }
  });

  testWidgets('走查复现：两图各带上/侧/下三标签+底部两句——六标签全部入对、孤行居中、栈随图',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = _buildController();
    // Given：用户实测场景——标题；宽图（图1：上方"小懒羊睡觉"、右侧"图1"、
    // 下方"图1介绍"）；窄图（图2：上方"小猫"、左侧"图2"、下方"图2介绍"）；
    // 底部两句正文。VLM 不返回任何 pairId（走查实况），逼出客户端多标签兜底。
    void addStroke(String id, double x, double y, double w, double h) {
      controller.applyResult(AddElementResult(_stroke(id, 's-$id', x, y, w, h)));
    }

    addStroke('l-title', 300, 150, 160, 44);
    addStroke('l-above1', 380, 300, 240, 40); // 小懒羊睡觉（距图1顶 60pt）
    addStroke('l-side1', 1130, 500, 60, 40); // 图1（距图1右缘 30pt）
    addStroke('l-below1', 400, 950, 160, 40); // 图1介绍（距图1底 44pt）
    addStroke('l-above2', 1200, 900, 80, 40); // 小猫（距图2顶 60pt）
    addStroke('l-side2', 1020, 1100, 60, 40); // 图2（距图2左缘 20pt）
    addStroke('l-below2', 1200, 1340, 160, 40); // 图2介绍（距图2底 40pt）
    addStroke('l-end1', 300, 1900, 80, 40); // 结尾（远离两图）
    addStroke('l-end2', 400, 1980, 300, 40); // 小猫和懒羊羊都懒（远离两图）
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: const ElementId('img-sheep'),
          x: 200,
          y: 400,
          width: 900,
          height: 506,
          fileId: 'file-sheep',
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: const ElementId('img-cat'),
          x: 1100,
          y: 1000,
          width: 400,
          height: 300,
          fileId: 'file-cat',
        ),
      ),
    );
    // 阅读序编号：m1 标题、m2 小懒羊睡觉、m3 图1(羊)、m4 图1、m5 小猫、
    // m6 图1介绍、m7 图2(猫)、m8 图2、m9 图2介绍、m10 结尾、m11 结句。
    controller.onVisionSmartLayout = (request) async {
      expect(request.marks, hasLength(11), reason: '9 个手写簇 + 2 张图全部编号');
      return SmartLayoutVisionResponse(
        elements: [
          _visionElement('title', '我的画作', request.marks[0]),
          _visionElement('body', '小懒羊睡觉', request.marks[1]),
          _visionElement('figure', '', request.marks[2]),
          _visionElement('body', '图1', request.marks[3]),
          _visionElement('body', '小猫', request.marks[4]),
          _visionElement('body', '图1介绍', request.marks[5]),
          _visionElement('figure', '', request.marks[6]),
          _visionElement('body', '图2', request.marks[7]),
          _visionElement('body', '图2介绍', request.marks[8]),
          _visionElement('body', '结尾', request.marks[9]),
          _visionElement('body', '小猫和懒羊羊都懒', request.marks[10]),
        ],
      );
    };
    // When：识别准备。
    final preparation = (await tester.runAsync(
      () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
    ))!;
    // Then(1)：六个标签全部进对（一图收三标签），looseTexts 仅剩底部两句。
    expect(preparation.content.pairs, hasLength(2));
    final sheepPair = preparation.content.pairs[0];
    final catPair = preparation.content.pairs[1];
    expect(sheepPair.figure.key, 'img-sheep');
    expect(sheepPair.topTexts.map((u) => u.textElement!.text), ['小懒羊睡觉']);
    expect(sheepPair.bottomTexts.map((u) => u.textElement!.text), [
      '图1',
      '图1介绍',
    ], reason: '侧标与下注归下栈、按原稿阅读序');
    expect(catPair.figure.key, 'img-cat');
    expect(catPair.topTexts.map((u) => u.textElement!.text), ['小猫']);
    expect(catPair.bottomTexts.map((u) => u.textElement!.text), ['图2', '图2介绍']);
    expect(
      preparation.content.looseTexts.map((u) => u.textElement!.text),
      ['结尾', '小猫和懒羊羊都懒'],
      reason: '六枚图旁标签不再混进正文流',
    );
    expect(preparation.content.looseFigures, isEmpty);

    final contentArea = preparation.content.contentArea;
    // Then(2)：handout 孤行窄图整行居中（第四轮主诉"一张居中一张偏左"）。
    final handout = preparation.layouts[SmartLayoutTemplateKind.handout];
    expect(handout, isNotNull);
    final catDelta = handout!.moveDeltas[const ElementId('img-cat')]!;
    final catTarget = Rect.fromLTWH(
      1100 + catDelta.dx,
      1000 + catDelta.dy,
      400,
      300,
    );
    expect(
      catTarget.center.dx,
      closeTo(contentArea.center.dx, 0.01),
      reason: '孤行图与标签栈以内容区中心水平居中',
    );
    final sheepDelta = handout.moveDeltas[const ElementId('img-sheep')]!;
    final sheepTarget = Rect.fromLTWH(
      200 + sheepDelta.dx,
      400 + sheepDelta.dy,
      900,
      506,
    );
    expect(sheepTarget.center.dx, closeTo(contentArea.center.dx, 0.01));

    // Then(3)：标签栈居中于图；上栈 bottom 对齐图顶-24、下栈 top 对齐图底+24。
    TextElement textOf(String text) => handout.addElements
        .whereType<TextElement>()
        .firstWhere((element) => element.text == text);
    final above2 = textOf('小猫');
    expect(above2.y + above2.height, closeTo(catTarget.top - 24, 0.01));
    expect(above2.x + above2.width / 2, closeTo(catTarget.center.dx, 0.01));
    final side2 = textOf('图2');
    expect(side2.y, closeTo(catTarget.bottom + 24, 0.01));
    expect(side2.x + side2.width / 2, closeTo(catTarget.center.dx, 0.01));
    final below2 = textOf('图2介绍');
    expect(below2.y, closeTo(side2.y + side2.height, 0.01), reason: '下栈内紧邻堆叠');
    final above1 = textOf('小懒羊睡觉');
    expect(above1.y + above1.height, closeTo(sheepTarget.top - 24, 0.01));
    expect(above1.x + above1.width / 2, closeTo(sheepTarget.center.dx, 0.01));
    final side1 = textOf('图1');
    expect(side1.y, closeTo(sheepTarget.bottom + 24, 0.01));
    final below1 = textOf('图1介绍');
    expect(below1.y, closeTo(side1.y + side1.height, 0.01));

    // Then(4)：底部两句贪心装行——宽度允许时共一行（行内 top 对齐）。
    final end1 = textOf('结尾');
    final end2 = textOf('小猫和懒羊羊都懒');
    expect(end2.y, end1.y, reason: '两句共一行');
    expect(end2.x, closeTo(end1.x + end1.width + 24, 0.01));

    // Then(5)：previewRect 两两不交、全部 ⊆ 内容区。
    final rects = handout.previewRects;
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(
          rects[i].overlaps(rects[j]),
          isFalse,
          reason: 'previewRect[$i]=${rects[i]} 与 [$j]=${rects[j]} 不应重叠',
        );
      }
    }
    for (final rect in rects) {
      final contained =
          contentArea.left <= rect.left &&
          rect.right <= contentArea.right &&
          contentArea.top <= rect.top &&
          rect.bottom <= contentArea.bottom;
      expect(contained, isTrue, reason: '$rect 应在内容区 $contentArea 内');
    }

    // Then(6)：保留手写变体同断言——九块文本墨迹逐一移动、不误删、占位齐备。
    final inkLayout = preparation.layoutsKeepInk[SmartLayoutTemplateKind.handout];
    expect(inkLayout, isNotNull);
    expect(
      inkLayout!.inkSlotRects,
      hasLength(9),
      reason: '标题 + 六标签 + 底部两句的墨迹全部有占位矩形',
    );
    final inkPlan = controller
        .buildSmartLayoutPlanForTemplate(
          preparation,
          SmartLayoutTemplateKind.handout,
          keepHandwriting: true,
        )
        .plan!;
    expect(
      inkPlan.moveDeltas.keys.map((id) => id.value),
      containsAll([
        'img-sheep',
        'img-cat',
        'l-title',
        'l-above1',
        'l-side1',
        'l-below1',
        'l-above2',
        'l-side2',
        'l-below2',
        'l-end1',
        'l-end2',
      ]),
      reason: '图旁标签墨迹随图一起移动，不再被转写替换',
    );
    expect(
      inkPlan.removeIds,
      isEmpty,
      reason: '保留手写模式不删除任何文本墨迹',
    );
    Rect movedRect(Rect source, Offset delta) => Rect.fromLTWH(
      source.left + delta.dx,
      source.top + delta.dy,
      source.width,
      source.height,
    );
    final inkCatDelta = inkLayout.moveDeltas[const ElementId('img-cat')]!;
    final inkCatTarget = movedRect(
      const Rect.fromLTWH(1100, 1000, 400, 300),
      inkCatDelta,
    );
    expect(
      inkCatTarget.center.dx,
      closeTo(contentArea.center.dx, 0.01),
      reason: '保留手写孤行同样整行居中',
    );
    final inkAbove2 = movedRect(
      const Rect.fromLTWH(1200, 900, 80, 40),
      inkLayout.moveDeltas[const ElementId('l-above2')]!,
    );
    expect(inkAbove2.bottom, closeTo(inkCatTarget.top - 24, 0.01));
    expect(inkAbove2.center.dx, closeTo(inkCatTarget.center.dx, 0.01));
    final inkSide2 = movedRect(
      const Rect.fromLTWH(1020, 1100, 60, 40),
      inkLayout.moveDeltas[const ElementId('l-side2')]!,
    );
    expect(inkSide2.top, closeTo(inkCatTarget.bottom + 24, 0.01));
    expect(inkSide2.center.dx, closeTo(inkCatTarget.center.dx, 0.01));
    final inkBelow2 = movedRect(
      const Rect.fromLTWH(1200, 1340, 160, 40),
      inkLayout.moveDeltas[const ElementId('l-below2')]!,
    );
    expect(inkBelow2.top, closeTo(inkSide2.bottom, 0.01), reason: '墨迹栈内紧邻');
  });
}

MarkdrawController _buildController() {
  final controller = MarkdrawController(
    config: MarkdrawEditorConfig(
      initialLayout: CanvasLayout(
        type: CanvasLayoutType.paged,
        pages: const [
          CanvasPage(
            id: 'page-1',
            index: 0,
            bounds: Rect.fromLTWH(0, 0, 1588, 2246),
            template: CanvasPageTemplate.blank,
          ),
        ],
      ),
    ),
  );
  addTearDown(controller.dispose);
  controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
  return controller;
}

FreedrawElement _stroke(
  String id,
  String sessionId,
  double x,
  double y,
  double w,
  double h,
) => FreedrawElement(
  id: ElementId(id),
  x: x,
  y: y,
  width: w,
  height: h,
  points: const [Point(0, 0), Point(40, 20)],
  customData: {
    recognitionStrokeSessionKey: sessionId,
    'flowMuse': {'pageId': 'page-1'},
  },
);

SmartLayoutVisionElement _visionElement(
  String role,
  String text,
  String markId, {
  String? id,
}) => SmartLayoutVisionElement(
  id: id,
  role: role,
  text: text.isEmpty ? null : text,
  markIds: [markId],
);
