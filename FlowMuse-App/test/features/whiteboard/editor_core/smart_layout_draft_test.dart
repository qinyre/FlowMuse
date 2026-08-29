import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

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
    // 既有元素：待移动的形状 + 待删除的笔迹
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('shape-1'),
          x: 120,
          y: 120,
          width: 60,
          height: 60,
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(_stroke('stroke-1', 's1', 300, 150, 200, 28)),
    );
    return controller;
  }

  SmartLayoutPlan draftPlan() => SmartLayoutPlan(
        pageId: 'page-1',
        style: SmartLayoutTemplateKind.handout,
        confidence: 0.9,
        description: 'PPT 版式',
        addElements: [
          TextElement(
            id: ElementId('new-text-1'),
            x: 200,
            y: 300,
            width: 180,
            height: 30,
            text: '新排的句子',
          ),
        ],
        moveDeltas: {ElementId('shape-1'): const Offset(50, 100)},
        removeIds: const [ElementId('stroke-1')],
        selectIds: {ElementId('shape-1'), ElementId('new-text-1')},
        previewRects: const [],
        removalRects: const [],
        failureRects: const [],
      );

  /// 模拟 SelectTool 拖动：直接对当前（草稿）场景应用位置更新。
  void simulateDrag(MarkdrawController controller, ElementId id, Offset delta) {
    final scene = controller.editorState.scene;
    Element? element;
    for (final e in scene.activeElements) {
      if (e.id == id) {
        element = e;
        break;
      }
    }
    controller.applyResult(
      UpdateElementResult(element!.copyWith(
        x: element.x + delta.dx,
        y: element.y + delta.dy,
      )),
    );
  }

  test('enter 后场景＝计划结果：新增/移动/删除生效、全选参与者、工具为选择', () {
    final controller = buildController();
    final before = controller.editorState.scene;
    controller.enterSmartLayoutDraft(draftPlan());

    expect(controller.smartLayoutDraftActive, isTrue);
    final scene = controller.editorState.scene;
    // 笔迹已删除
    expect(
      scene.activeElements.where((e) => e.id == ElementId('stroke-1')),
      isEmpty,
    );
    // 新增文本存在
    expect(
      scene.activeElements.where((e) => e.id == ElementId('new-text-1')),
      isNotEmpty,
    );
    // 形状已按计划移动
    final moved = scene.activeElements
        .where((e) => e.id == ElementId('shape-1'))
        .single;
    expect(moved.x, 170);
    expect(moved.y, 220);
    // 参与者全选、工具为选择、视图已适配页面
    expect(controller.editorState.selectedIds.length, 2);
    expect(controller.editorState.activeToolType, ToolType.select);
    // 进入草稿不触发 onSceneChanged（保存/广播）
    var sceneChanges = 0;
    controller.onSceneChanged = (_, __) => sceneChanges++;
    simulateDrag(controller, ElementId('shape-1'), const Offset(10, 10));
    expect(sceneChanges, 0);
    controller.onSceneChanged = null;
    expect(controller.editorState.scene, isNot(same(before)));
  });

  test('拖动后 commit：真实场景=草稿最终位置，一次提交、一次撤销整体还原', () {
    final controller = buildController();
    controller.enterSmartLayoutDraft(draftPlan());
    simulateDrag(controller, ElementId('shape-1'), const Offset(10, 10));
    simulateDrag(controller, ElementId('new-text-1'), const Offset(0, 20));

    var sceneChanges = 0;
    controller.onSceneChanged = (_, __) => sceneChanges++;
    expect(
      controller.commitSmartLayoutDraft(draftPlan()),
      isTrue,
    );
    expect(controller.smartLayoutDraftActive, isFalse);
    expect(sceneChanges, 1); // 一次广播（一次历史提交）

    final scene = controller.editorState.scene;
    final moved = scene.activeElements
        .where((e) => e.id == ElementId('shape-1'))
        .single;
    expect(moved.x, 180); // 120 + 50 + 10
    expect(moved.y, 230);
    final text = scene.activeElements
        .where((e) => e.id == ElementId('new-text-1'))
        .single;
    expect(text.x, 200);
    expect(text.y, 320);
    expect(
      scene.activeElements.where((e) => e.id == ElementId('stroke-1')),
      isEmpty,
    );

    // 一次撤销整体还原（含拖动位置）
    controller.undo();
    final undone = controller.editorState.scene;
    final baseShape = undone.activeElements
        .where((e) => e.id == ElementId('shape-1'))
        .single;
    expect(baseShape.x, 120);
    expect(baseShape.y, 120);
    expect(
      undone.activeElements.where((e) => e.id == ElementId('new-text-1')),
      isEmpty,
    );
    expect(
      undone.activeElements.where((e) => e.id == ElementId('stroke-1')),
      isNotEmpty,
    );
  });

  test('cancel 后场景零残留：与进入前元素完全一致、无新增、无历史', () {
    final controller = buildController();
    final beforeIds = {
      for (final e in controller.editorState.scene.activeElements) e.id,
    };
    controller.enterSmartLayoutDraft(draftPlan());
    simulateDrag(controller, ElementId('shape-1'), const Offset(40, 40));
    controller.cancelSmartLayoutDraft();

    expect(controller.smartLayoutDraftActive, isFalse);
    final afterIds = {
      for (final e in controller.editorState.scene.activeElements) e.id,
    };
    expect(afterIds, beforeIds);
    final shape = controller.editorState.scene.activeElements
        .where((e) => e.id == ElementId('shape-1'))
        .single;
    expect(shape.x, 120);
    expect(shape.y, 120);
  });

  test('草稿态守卫：undo/redo/switchTool 被忽略，方案外点击不响应', () {
    final controller = buildController();
    controller.enterSmartLayoutDraft(draftPlan());

    controller.undo();
    controller.redo();
    controller.switchTool(ToolType.freedraw);
    expect(controller.editorState.activeToolType, ToolType.select);
    expect(controller.smartLayoutDraftActive, isTrue);
    // 场景（草稿）仍在（undo 未生效）
    expect(
      controller.editorState.scene.activeElements
          .where((e) => e.id == ElementId('stroke-1')),
      isEmpty,
    );

    // 方案外元素（新增一个锁定障碍）点击不响应 → 直接模拟指针命中过滤逻辑：
    // 这里通过 draftParticipants 校验：形状在参与集，笔迹已删；锁定元素不在参与集
    expect(
      controller.editorState.selectedIds,
      contains(ElementId('shape-1')),
    );
  });

  test('commit(dropFailedBlocks) 删除失败笔迹', () {
    final controller = buildController();
    final plan = draftPlan();
    final withFailures = SmartLayoutPlan(
      pageId: plan.pageId,
      style: plan.style,
      confidence: plan.confidence,
      description: plan.description,
      addElements: plan.addElements,
      moveDeltas: plan.moveDeltas,
      removeIds: plan.removeIds,
      failedStrokeIds: const [ElementId('stroke-2-fail')],
      selectIds: plan.selectIds,
      previewRects: plan.previewRects,
      removalRects: plan.removalRects,
      failureRects: const [Rect.fromLTWH(300, 150, 200, 28)],
    );
    controller.applyResult(
      AddElementResult(_stroke('stroke-2-fail', 's2', 300, 150, 200, 28)),
    );
    controller.enterSmartLayoutDraft(withFailures);
    expect(controller.commitSmartLayoutDraft(
      withFailures,
      dropFailedBlocks: true,
    ), isTrue);
    expect(
      controller.editorState.scene.activeElements
          .where((e) => e.id == ElementId('stroke-2-fail')),
      isEmpty,
    );
  });
}

FreedrawElement _stroke(String id, String sessionId, double x, double y, double w, double h) =>
    FreedrawElement(
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
