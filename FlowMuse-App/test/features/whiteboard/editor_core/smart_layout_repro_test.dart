import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复现用户截图页面：标准页 1588x2246 + 4 行手写（跨"会话"）+ 形状障碍 +
/// 大图(620)。v2 视觉管线（去会话化全页聚类 + 模板预落位）下，
/// 三张模板都不应误报"空间不足"。
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
