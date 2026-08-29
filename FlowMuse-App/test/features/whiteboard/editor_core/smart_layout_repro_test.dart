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
          pair.caption.textElement!.text: pair.figure.size,
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
