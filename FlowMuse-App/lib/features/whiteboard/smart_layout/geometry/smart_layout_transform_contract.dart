import '../snapshot/layout_page_snapshot.dart';

/// 智能排版会施加的元素操作（V3-302A；实际 Scene 变换归 V3-303A）。
enum LayoutTransformOp { move, resize, rotate }

/// 稳定拒绝码：每格拒绝都必须落在其中一个，禁止"尽量变换"。
enum TransformRejectReason {
  /// 元素类型不在支持矩阵（未知/未来类型）：整批原子拒绝。
  unsupportedElementType,

  /// 页面框/PDF 底图等背景基础设施：排版不触碰。
  backgroundElement,

  /// 锁定保护对象：排版绕开而非移动。
  protectedObstacleLocked,

  /// resize 目标几何非法（负尺寸/NaN/无穷）。
  degenerateResizeTarget,
}

class TransformSupportDecision {
  const TransformSupportDecision.supported()
    : supported = true,
      reason = null;

  const TransformSupportDecision.rejected(this.reason)
    : assert(reason != null),
      supported = false;

  final bool supported;
  final TransformRejectReason? reason;

  @override
  String toString() =>
      supported ? 'supported' : 'rejected(${reason!.name})';
}

/// 依赖重算传播顺序（契约常量；V3-303A 按此顺序执行）。
enum DependencyRecalcPhase {
  /// 1. 组/frame 成员与主元素几何（页面坐标系合成：
  ///    frame 旋转时成员期望 = frame 变换 ∘ 成员自身变换）。
  members,

  /// 2. group/frame 包围盒与成员关系表收敛（嵌套组自内向外）。
  containers,

  /// 3. 绑定端点：arrow 端点/容器文本随被绑元素几何跟随。
  bindings,

  /// 4. 索引、z 序与版本号（scene revision/fingerprint 最后一次性推进）。
  indexesAndVersion,
}

/// 元素 move/resize/rotate 支持矩阵、拒绝条件与传播顺序契约
///（V3-302A）。只读声明，不执行变换，不重构 SelectTool。
class SmartLayoutTransformContract {
  const SmartLayoutTransformContract._();

  /// 支持矩阵：kind × 操作。未列出的 kind 一律拒绝
  ///（unknown 类型原子拒绝，不存在部分支持）。
  static const Map<String, Set<LayoutTransformOp>> supportByKind = {
    'rectangle': _allOps,
    'ellipse': _allOps,
    'diamond': _allOps,
    'text': _allOps,
    'image': _allOps,
    'frame': _allOps,
    'line': _allOps,
    'arrow': _allOps,
    'freedraw': _allOps,
  };

  static const _allOps = <LayoutTransformOp>{
    LayoutTransformOp.move,
    LayoutTransformOp.resize,
    LayoutTransformOp.rotate,
  };

  /// mobility 拒绝优先于类型矩阵：背景与锁定物不参与重排。
  static TransformSupportDecision decide({
    required String kind,
    required SnapshotMobility mobility,
    required LayoutTransformOp op,
    double? resizeTargetWidth,
    double? resizeTargetHeight,
  }) {
    if (mobility == SnapshotMobility.background) {
      return const TransformSupportDecision.rejected(
        TransformRejectReason.backgroundElement,
      );
    }
    if (mobility == SnapshotMobility.protectedObstacle) {
      return const TransformSupportDecision.rejected(
        TransformRejectReason.protectedObstacleLocked,
      );
    }
    final ops = supportByKind[kind];
    if (ops == null || !ops.contains(op)) {
      return const TransformSupportDecision.rejected(
        TransformRejectReason.unsupportedElementType,
      );
    }
    if (op == LayoutTransformOp.resize) {
      final w = resizeTargetWidth;
      final h = resizeTargetHeight;
      final degenerate =
          (w != null && !(w >= 0 && w.isFinite)) ||
          (h != null && !(h >= 0 && h.isFinite));
      if (degenerate) {
        return const TransformSupportDecision.rejected(
          TransformRejectReason.degenerateResizeTarget,
        );
      }
    }
    return const TransformSupportDecision.supported();
  }

  /// 绑定引用是否跟随被绑元素（契约：绑定是几何跟随关系，
  /// 变换不得断链；容器文本与 arrow 端点同规）。
  static bool bindingFollowsElement(String kind) => kind == 'arrow';

  /// 传播顺序（固定；V3-303A 必须按序执行并整体成功或整体不变）。
  static const List<DependencyRecalcPhase> propagationOrder = [
    DependencyRecalcPhase.members,
    DependencyRecalcPhase.containers,
    DependencyRecalcPhase.bindings,
    DependencyRecalcPhase.indexesAndVersion,
  ];
}
