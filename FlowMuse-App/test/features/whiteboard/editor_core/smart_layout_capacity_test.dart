import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复现"空位很多却提示没有空位"：blank 标准页 + 中部 620x620 大图 + 四周 7 个手写文本簇。
/// 四种风格逐一强制，定位抛"智能排版没有足够的空白区域"的路径。
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
    // 7 个手写文本簇（同会话 s1，分散在图片四周；每个都是独立块尺寸 ~120x28）
    const clusters = [
      (900.0, 90.0), // 右上
      (700.0, 180.0), //
      (620.0, 260.0), //
      (350.0, 290.0), // 左上
      (400.0, 470.0), // 图左
      (880.0, 700.0), // 图右
      (700.0, 900.0), // 图下
    ];
    for (var i = 0; i < clusters.length; i++) {
      controller.applyResult(
        AddElementResult(
          _stroke('c$i', 's1', clusters[i].$1, clusters[i].$2, 120, 28),
        ),
      );
    }
    // 中部大图 620x620
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: ElementId('img-big'),
          x: 480,
          y: 540,
          width: 620,
          height: 620,
          fileId: 'file-big',
        ),
      ),
    );
    return controller;
  }

  SmartLayoutRecognizedBlock rblock(String id, String text, Bounds bounds) =>
      SmartLayoutRecognizedBlock(
        id: id,
        type: 'text',
        text: text,
        pageId: 'page-1',
        bounds: bounds,
      );

  test('in_place 风格（图+多文本）：不误报空间不足', () async {
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
            rblock(rb.id, '关键词 ${rb.id}', rb.bounds),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
      );
    };
    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull, reason: 'in_place 应能构建计划');
  });

  test('article 风格（图+多文本）：不误报空间不足', () async {
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
                text: '关键词 $i',
                pageId: 'page-1',
                order: i,
              ),
          ],
        ),
        blocks: [
          for (final rb in request.blocks)
            rblock(rb.id, '关键词 ${rb.id}', rb.bounds),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'article'),
        ],
      );
    };
    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull, reason: 'article 应能构建计划');
  });

  test('ppt 风格（图+多文本）：不误报空间不足', () async {
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
            rblock(rb.id, '关键词 ${rb.id}', rb.bounds),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
        layout: SmartLayoutLayoutDecision(
          style: SmartLayoutStyle.ppt,
          confidence: 0.9,
          pptStructure: SmartLayoutPptStructure(
            groups: [
              for (final rb in request.blocks)
                SmartLayoutPptGroup(
                  role: 'body',
                  elementIds: [rb.id],
                ),
              const SmartLayoutPptGroup(
                role: 'figure',
                elementIds: ['img-big'],
              ),
            ],
          ),
        ),
      );
    };
    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull, reason: 'ppt 应能构建计划');
  });

  test('mindmap 风格（关键词簇）：不误报空间不足', () async {
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
            rblock(rb.id, '关键词 ${rb.id}', rb.bounds),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
        layout: SmartLayoutLayoutDecision(
          style: SmartLayoutStyle.mindmap,
          confidence: 0.9,
          mindmapStructure: const MindmapStructure(
            root: MindmapStructureNode(
              text: '主题',
              children: [
                MindmapStructureNode(
                  text: '分支A',
                  children: [
                    MindmapStructureNode(text: '子A1', children: []),
                    MindmapStructureNode(text: '子A2', children: []),
                  ],
                ),
                MindmapStructureNode(
                  text: '分支B',
                  children: [
                    MindmapStructureNode(text: '子B1', children: []),
                    MindmapStructureNode(text: '子B2', children: []),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    };
    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull, reason: 'mindmap 应能构建计划');
  });

  test('障碍居中时：只要存在合法位置就能找到且不与障碍相交', () {
    // 内容区 72..1516 x 72..2174；障碍 620x620 居中(480,540)
    final area = const Rect.fromLTWH(72, 72, 1444, 2102);
    final occupied = [Bounds.fromLTWH(480, 540, 620, 620)];
    final result = SmartLayoutPlacement.findInsertionBounds(
      area,
      400,
      500,
      occupied,
      preferred: Bounds.fromLTWH(1200, 600, 400, 500),
    );
    expect(result, isNotNull, reason: '页面存在大片空白，必须能放置');
    expect(result!.left, greaterThanOrEqualTo(area.left));
    expect(result.right, lessThanOrEqualTo(area.right));
    expect(result.bottom, lessThanOrEqualTo(area.bottom));
    expect(occupied.any(result.intersects), isFalse);
  });

  test('障碍占满右列时：目标落到左侧空白（覆盖左/上方候选与网格兜底）', () {
    final area = const Rect.fromLTWH(72, 72, 1444, 2102);
    final occupied = [Bounds.fromLTWH(916, 72, 600, 2102)]; // 右列整高
    final result = SmartLayoutPlacement.findInsertionBounds(
      area,
      700,
      400,
      occupied,
      preferred: Bounds.fromLTWH(1000, 600, 700, 400), // 首选在障碍内
    );
    expect(result, isNotNull);
    expect(result!.right, lessThanOrEqualTo(916), reason: '必须落到障碍左侧');
    expect(occupied.any(result.intersects), isFalse);
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
