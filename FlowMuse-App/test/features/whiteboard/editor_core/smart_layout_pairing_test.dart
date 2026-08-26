import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 图文配对回归：AI 的 elements 摘要不含图片内容，可能返回错序的 groups；
/// 客户端必须按原稿几何（最近距离）配对，否则排版后"睁眼/睡觉"图文颠倒。
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
    // 文一（睁眼）在上、图一（睁眼）紧跟其下；文二（睡觉）在下、图二紧随
    controller.applyResult(
      AddElementResult(_stroke('t1', 's1', 600, 330, 300, 28)),
    );
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: ElementId('img-eye'),
          x: 700,
          y: 400,
          width: 500,
          height: 450,
          fileId: 'file-eye',
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(_stroke('t2', 's1', 600, 1190, 300, 28)),
    );
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: ElementId('img-sleep'),
          x: 700,
          y: 1250,
          width: 500,
          height: 450,
          fileId: 'file-sleep',
        ),
      ),
    );
    return controller;
  }

  test('AI groups 故意错序时仍按原稿几何配对（睁眼↔图一、睡觉↔图二）', () async {
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
            SmartLayoutRecognizedBlock(
              id: rb.id,
              type: 'text',
              text: rb.bounds.top < 600 ? '下面是一个睁眼的懒洋洋' : '下面是一个睡着的懒洋洋',
              pageId: 'page-1',
              bounds: rb.bounds,
            ),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
        layout: SmartLayoutLayoutDecision(
          style: SmartLayoutStyle.ppt,
          confidence: 0.9,
          pptStructure: SmartLayoutPptStructure(
            groups: [
              // 故意错序：睡觉图/文在前，睁眼图/文在后（body 引用真实识别块 id）
              const SmartLayoutPptGroup(role: 'figure', elementIds: ['img-sleep']),
              SmartLayoutPptGroup(
                role: 'body',
                elementIds: [
                  for (final rb in request.blocks)
                    if (rb.bounds.top >= 600) rb.id,
                ],
              ),
              const SmartLayoutPptGroup(role: 'figure', elementIds: ['img-eye']),
              SmartLayoutPptGroup(
                role: 'body',
                elementIds: [
                  for (final rb in request.blocks)
                    if (rb.bounds.top < 600) rb.id,
                ],
              ),
            ],
          ),
        ),
      );
    };

    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull);
    expect(controller.applySmartLayoutPlan(result.plan!), isTrue);

    final scene = controller.editorState.scene;
    final t1 = scene.activeElements
        .whereType<TextElement>()
        .singleWhere((e) => e.text.contains('睁眼'));
    final t2 = scene.activeElements
        .whereType<TextElement>()
        .singleWhere((e) => e.text.contains('睡着'));
    final imgEye = scene.activeElements
        .where((e) => e.id == ElementId('img-eye'))
        .single;
    final imgSleep = scene.activeElements
        .where((e) => e.id == ElementId('img-sleep'))
        .single;
    // ignore: avoid_print
    print(
      'POS t1=${t1.y} t2=${t2.y} imgEye=${imgEye.y} imgSleep=${imgSleep.y}',
    );

    // 单列文档流：配对图文紧邻（文上图下，间隔=行距 24），睁眼对在前、睡觉对在后
    expect(imgEye.y - (t1.y + t1.height), closeTo(24, 1),
        reason: '睁眼文本必须紧邻其配图上方（配对）');
    expect(t2.y - (imgEye.y + imgEye.height), closeTo(24, 1),
        reason: '睁眼图下方应紧接睡觉文本');
    expect(imgSleep.y - (t2.y + t2.height), closeTo(24, 1),
        reason: '睡觉文本必须紧邻其配图上方（配对）');
    expect(imgEye.y, lessThan(imgSleep.y),
        reason: '睁眼图应排在睡觉图上方（按配对顺序）');
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
