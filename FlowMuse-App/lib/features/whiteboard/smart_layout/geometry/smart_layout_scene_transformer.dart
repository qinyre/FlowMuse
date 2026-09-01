import '../../editor_core/flow_muse_whiteboard_editor.dart';
import '../snapshot/layout_page_snapshot.dart';
import 'affine_layout_transform.dart';
import 'smart_layout_transform_contract.dart';
import 'stroke_transform_adapter.dart';

/// 变换结果：全有或全无——失败不带 Scene（调用方原 Scene 未被触碰），
/// 成功携带 upsert 语义新 Scene 与可直接经 gateway commitValidated 落地
/// 的 [ToolResult] 列表（version 不在变换层推进，提交时统一 bump）。
sealed class SceneTransformOutcome {
  const SceneTransformOutcome();
}

class SceneTransformSuccess extends SceneTransformOutcome {
  const SceneTransformSuccess({
    required this.scene,
    required this.updatedElements,
    required this.appliedSourceIds,
  });

  final Scene scene;

  /// 变换后的元素（scene.orderedElements 顺序，确定性）。
  final List<Element> updatedElements;
  final List<String> appliedSourceIds;

  /// 单一聚合提交结果：经 gateway commitValidated 一次落地
  ///（applyResult 会统一 bump version 并进入 history）。
  ToolResult get commitResult => CompoundResult([
    for (final element in updatedElements) UpdateElementResult(element),
  ]);
}

class SceneTransformFailure extends SceneTransformOutcome {
  const SceneTransformFailure({required this.reason, required this.sourceId});

  final TransformRejectReason reason;

  /// 首个被拒绝的源（按 orderedElements 顺序，确定性）。
  final String sourceId;
}

/// 智能排版原子 Scene 变换器（V3-303A，feature-local，不导出通用 API）。
///
/// 固定传播顺序（V3-302A 契约）：members（闭包展开：目标 + 同组成员 +
/// frame 成员 + 容器文本）→ containers（整体变换下包含关系自动保持，
/// 无额外重算）→ bindings（被绑元素移动时箭头端点经编辑器
/// BindingUtils 重新采样，语义与拖拽路径一致）→ indexesAndVersion
/// （fractional index 与 version 不动；version 由提交入口统一推进）。
///
/// 预检全有或全无：任一 affected 元素被 [SmartLayoutTransformContract]
/// 拒绝（未知类型/背景/锁定/非法 resize 目标）即整体失败，Scene、
/// history 与 fingerprint 零副作用。
class SmartLayoutSceneTransformer {
  const SmartLayoutSceneTransformer._();

  static SceneTransformOutcome apply({
    required Scene scene,
    required Set<ElementId> targetIds,
    required LayoutTransformOp op,
    required AffineLayoutTransform transform,
    double rotationDelta = 0,
    double? resizeTargetWidth,
    double? resizeTargetHeight,
  }) {
    final semantics = TransformSemantics.of(transform, rotationDelta);
    final affected = _closure(scene, targetIds);

    // ---- 预检（全有或全无；含将被修改的绑定跟随箭头；软删元素跳过）----
    for (final element in scene.orderedElements) {
      if (element.isDeleted) continue;
      if (!affected.contains(element.id)) continue;
      final decision = SmartLayoutTransformContract.decide(
        kind: element.type,
        mobility: _mobilityOf(element),
        op: op,
        resizeTargetWidth: resizeTargetWidth,
        resizeTargetHeight: resizeTargetHeight,
      );
      if (!decision.supported) {
        return SceneTransformFailure(
          reason: decision.reason!,
          sourceId: element.id.value,
        );
      }
    }

    // ---- members：主体 + 闭包成员同变换（软删元素跳过）----
    final movedById = <ElementId, Element>{};
    for (final element in scene.orderedElements) {
      if (element.isDeleted) continue;
      if (!affected.contains(element.id)) continue;
      movedById[element.id] = _transformElement(element, transform, semantics);
    }

    // ---- bindings：非主体的绑定箭头端点跟随（BindingUtils 同语义）----
    var boundScene = scene;
    for (final entry in movedById.entries) {
      boundScene = boundScene.updateElement(entry.value);
    }
    final bindingUpdates = <ElementId, Element>{};
    for (final element in scene.orderedElements) {
      if (movedById.containsKey(element.id)) continue;
      if (element is! ArrowElement) continue;
      if (element.isDeleted) continue;
      if (element.startBinding == null && element.endBinding == null) {
        continue;
      }
      final bindsAffected = _bindsAny(element, affected, scene);
      if (!bindsAffected) continue;
      // 绑定跟随会修改该箭头：必须同样通过契约预检（如锁定箭头）。
      final decision = SmartLayoutTransformContract.decide(
        kind: element.type,
        mobility: _mobilityOf(element),
        op: op,
      );
      if (!decision.supported) {
        return SceneTransformFailure(
          reason: decision.reason!,
          sourceId: element.id.value,
        );
      }
      final updated = BindingUtils.updateBoundArrowEndpoints(
        element,
        boundScene,
      );
      if (!identical(updated, element)) {
        bindingUpdates[element.id] = updated;
      }
    }

    final allUpdates = {...movedById, ...bindingUpdates};
    var nextScene = scene;
    for (final element in allUpdates.values) {
      nextScene = nextScene.upsertRemoteElements([element]);
    }
    return SceneTransformSuccess(
      scene: nextScene,
      updatedElements: [
        for (final element in scene.orderedElements)
          if (allUpdates.containsKey(element.id)) allUpdates[element.id]!,
      ],
      appliedSourceIds: [
        for (final element in scene.orderedElements)
          if (allUpdates.containsKey(element.id)) element.id.value,
      ],
    );
  }

  /// mobility 推断（与 SnapshotExtractor 同语义）。
  static SnapshotMobility _mobilityOf(Element element) {
    if (element.isCanvasPage || element.isPdfBackground) {
      return SnapshotMobility.background;
    }
    if (element.locked) return SnapshotMobility.protectedObstacle;
    return SnapshotMobility.movable;
  }

  /// 闭包展开：目标 + 同组成员 + frame 成员 + 容器文本。
  /// 与 v1 SmartLayoutMoveBuilder 的跟随范围对齐（组由调用方展开的
  /// 契约在此内聚：同组成员必须整体移动，排版不拆组）。
  static Set<ElementId> _closure(Scene scene, Set<ElementId> targetIds) {
    final active = scene.activeElements;
    final byId = {for (final e in active) e.id: e};
    final affected = <ElementId>{};
    final queue = <ElementId>[...targetIds];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (!affected.add(id)) continue;
      final element = byId[id];
      if (element == null) continue;
      // 同组成员跟随：任一组 id 相交即整体移动（与编辑器组选择
      // contains 语义一致，交叉嵌套组不拆开）。
      for (final other in active) {
        if (other.id == id) continue;
        if (other.groupIds.isNotEmpty &&
            element.groupIds.isNotEmpty &&
            other.groupIds.any(element.groupIds.contains)) {
          queue.add(other.id);
        }
      }
      // frame 成员跟随。
      if (element is FrameElement) {
        for (final other in active) {
          if (other.frameId == element.id.value) queue.add(other.id);
        }
      }
      // 容器文本跟随。
      for (final other in active) {
        if (other is TextElement &&
            other.containerId == element.id.value) {
          queue.add(other.id);
        }
      }
    }
    return affected;
  }

  static bool _bindsAny(
    ArrowElement arrow,
    Set<ElementId> affected,
    Scene scene,
  ) {
    for (final binding in [arrow.startBinding, arrow.endBinding]) {
      if (binding == null) continue;
      if (affected.contains(ElementId(binding.elementId))) return true;
    }
    return false;
  }

  static Element _transformElement(
    Element element,
    AffineLayoutTransform transform,
    TransformSemantics semantics,
  ) {
    if (element is FreedrawElement) {
      return StrokeTransformAdapter.transform(element, transform, semantics);
    }
    if (element is TextElement) {
      return TextTransformAdapter.transform(element, transform, semantics);
    }
    if (element is LineElement) {
      return LineLikeTransformAdapter.transform(
        element,
        transform,
        semantics,
      );
    }
    final next = transformBaseGeometry(element, transform, semantics);
    return element.copyWith(
      x: next.x,
      y: next.y,
      width: next.width,
      height: next.height,
      angle: next.angle,
    );
  }
}
