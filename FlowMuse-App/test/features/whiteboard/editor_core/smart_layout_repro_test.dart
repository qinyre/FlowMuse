import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复现用户截图页面：标准页 1588x2246 + 4 行手写（同会话）+ 形状障碍 + 大图(620)。
/// 分别以 in_place / article / ppt 三种风格构建计划，定位"空间不足"的真实路径。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MarkdrawController buildController() {
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
    // 4 行手写（同一会话 s1，行距 45 ~ 同会话但不同行）
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
    // 形状障碍（保持原位的普通元素：星/框/三角 用形状元素近似）
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
    controller.applyResult(
      AddElementResult(
        EllipseElement(
          id: ElementId('shape-ellipse'),
          x: 280,
          y: 520,
          width: 60,
          height: 60,
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
    return controller;
  }

  SmartLayoutRecognizedBlock block(String id, String text, Bounds bounds) =>
      SmartLayoutRecognizedBlock(
        id: id,
        type: 'text',
        text: text,
        pageId: 'page-1',
        bounds: bounds,
      );

  test('in_place（旧服务端无 layout）不误报空间不足', () async {
    final controller = buildController();
    controller.onSmartLayoutInk = (request) async {
      return SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          generatedAt: 1,
          blocks: [],
        ),
        blocks: [
          for (final rb in request.blocks)
            block(rb.id, '这是第 ${rb.id} 句话', rb.bounds),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
      );
    };
    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull, reason: 'in_place 应能构建计划');
  });

  test('article（旧服务端段流）不误报空间不足', () async {
    final controller = buildController();
    controller.onSmartLayoutInk = (request) async {
      return SmartLayoutResponse(
        document: SmartLayoutDocument(
          version: 1,
          generatedAt: 1,
          blocks: [
            for (var i = 0; i < request.blocks.length; i++)
              SmartLayoutBlock(
                id: 'doc-$i',
                type: 'paragraph',
                text: '这是第 $i 句话',
                pageId: 'page-1',
                order: i,
              ),
          ],
        ),
        blocks: [
          for (final rb in request.blocks)
            block(rb.id, '这是 ${rb.id} 句话', rb.bounds),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'article'),
        ],
      );
    };
    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull, reason: 'article 应能构建计划');
  });

  test('ppt（AI 判为图文）大图不误报空间不足', () async {
    final controller = buildController();
    controller.onSmartLayoutInk = (request) async {
      return SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          generatedAt: 1,
          blocks: [],
        ),
        blocks: [
          for (final rb in request.blocks)
            block(rb.id, '这是第 ${rb.id} 句话', rb.bounds),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
        layout: SmartLayoutLayoutDecision(
          style: SmartLayoutStyle.ppt,
          confidence: 0.9,
          pptStructure: SmartLayoutPptStructure(
            groups: [
              SmartLayoutPptGroup(
                role: 'body',
                elementIds: [for (final rb in request.blocks) rb.id],
              ),
              const SmartLayoutPptGroup(
                role: 'figure',
                elementIds: ['img-cat'],
              ),
            ],
          ),
        ),
      );
    };
    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull, reason: 'ppt 应能构建计划');
  });
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
