import 'dart:ui';

import '../elements/elements.dart';
import '../math/math.dart';
import 'smart_layout_document.dart';

/// 一次"确定"后的智能排版本页计划：所有坐标已由客户端算好，apply 不依赖网络。
class SmartLayoutPlan {
  const SmartLayoutPlan({
    required this.pageId,
    required this.style,
    required this.confidence,
    required this.description,
    required this.addElements,
    required this.moveDeltas,
    required this.removeIds,
    this.failedStrokeIds = const [],
    required this.selectIds,
    this.document,
    required this.previewRects,
    required this.removalRects,
    required this.failureRects,
  });

  final String pageId;
  final SmartLayoutStyle style;
  final double confidence;
  final String description;

  /// 新增元素（已含最终坐标；尚未合并 pageId，apply 时统一合并）。
  final List<Element> addElements;

  /// 既有元素 → 左上角平移量（组内成员由调用方展开为各自 delta）。
  final Map<ElementId, Offset> moveDeltas;

  /// 本轮删除的元素 id（识别成功的笔迹 + 旧智能排版文本）。
  final List<ElementId> removeIds;

  /// 识别失败块的笔迹 id（用户选择"删除未识别笔迹后继续"时删除）。
  final List<ElementId> failedStrokeIds;

  final Set<ElementId> selectIds;

  /// 导出文档；为 null 表示清空（SetSmartLayoutResult(null)）。
  final SmartLayoutDocument? document;

  /// 场景坐标：新增/移动后的包围盒（蓝色幽灵预览）。
  final List<Rect> previewRects;

  /// 场景坐标：将被删除的笔迹区域（灰色幽灵预览）。
  final List<Rect> removalRects;

  /// 场景坐标：识别失败区域（红色高亮，仅失败提示模式）。
  final List<Rect> failureRects;
}

/// 单页计划构建结果：plan 为 null 表示本页无内容可排版（无手写）或整页失败。
class SmartLayoutPlanResult {
  const SmartLayoutPlanResult({
    this.plan,
    this.failures = const [],
    this.error,
  });

  final SmartLayoutPlan? plan;
  final List<SmartLayoutFailureInfo> failures;
  final String? error;

  bool get hasFailures => failures.isNotEmpty;
}

/// 单块识别失败信息（供失败对话框与红框高亮）。
class SmartLayoutFailureInfo {
  const SmartLayoutFailureInfo({
    required this.blockId,
    required this.bounds,
    this.snippet,
    this.error,
  });

  final String blockId;
  final Rect bounds;
  final String? snippet;
  final String? error;
}

/// 画布幽灵预览状态（controller.smartLayoutGhost 承载；null = 不显示）。
class SmartLayoutGhostSpec {
  const SmartLayoutGhostSpec.preview({
    required this.previewRects,
    required this.removalRects,
    this.failureRects = const [],
  });

  const SmartLayoutGhostSpec.failures({required this.failureRects})
    : previewRects = const [],
      removalRects = const [];

  final List<Rect> previewRects;
  final List<Rect> removalRects;
  final List<Rect> failureRects;

  bool get isFailure => failureRects.isNotEmpty;
}

/// 严格放置求位（从 markdraw_controller._findStrictInsertionBounds 提取为公开纯函数）。
/// 候选集：首选点、内容区四缘、各障碍右/下/左/上 + 间距；候选集耗尽后以 48 步长
/// 网格扫描兜底——只要页面上存在能完整放入且不碰撞的位置，就一定能找到。
class SmartLayoutPlacement {
  const SmartLayoutPlacement._();

  static const double _gap = 24.0;
  static const double _scanStep = 48.0;

  static Bounds? findInsertionBounds(
    Rect area,
    double width,
    double height,
    List<Bounds> occupied, {
    Bounds? preferred,
  }) {
    if (width > area.width || height > area.height) return null;
    final xCandidates = <double>{
      if (preferred != null)
        preferred.left.clamp(area.left, area.right - width).toDouble(),
      area.left,
      area.right - width,
      for (final bounds in occupied) bounds.right + _gap,
      for (final bounds in occupied) bounds.left - width - _gap,
    };
    final yCandidates = <double>{
      if (preferred != null)
        preferred.top.clamp(area.top, area.bottom - height).toDouble(),
      area.top,
      area.bottom - height,
      for (final bounds in occupied) bounds.bottom + _gap,
      for (final bounds in occupied) bounds.top - height - _gap,
    };
    final candidate = _firstLegalCandidate(area, width, height, occupied, xCandidates, yCandidates);
    if (candidate != null) return candidate;
    // 网格扫描兜底：候选集之外的大片空白（如障碍左侧/上方）也能被利用；确定性升序。
    for (var y = area.top; y <= area.bottom - height; y += _scanStep) {
      for (var x = area.left; x <= area.right - width; x += _scanStep) {
        final grid = Bounds.fromLTWH(x, y, width, height);
        if (_isLegal(area, grid, occupied)) return grid;
      }
    }
    return null;
  }

  static Bounds? _firstLegalCandidate(
    Rect area,
    double width,
    double height,
    List<Bounds> occupied,
    Set<double> xCandidates,
    Set<double> yCandidates,
  ) {
    for (final y in yCandidates) {
      for (final x in xCandidates) {
        final candidate = Bounds.fromLTWH(x, y, width, height);
        if (_isLegal(area, candidate, occupied)) return candidate;
      }
    }
    return null;
  }

  static bool _isLegal(Rect area, Bounds candidate, List<Bounds> occupied) {
    if (candidate.left < area.left ||
        candidate.top < area.top ||
        candidate.right > area.right ||
        candidate.bottom > area.bottom) {
      return false;
    }
    return !occupied.any(candidate.intersects);
  }
}

/// 页面归属合并（从 markdraw_controller._mergeCurrentPageCustomData 提取为公开纯函数）。
class SmartLayoutUtils {
  const SmartLayoutUtils._();

  static Map<String, Object?> mergePageCustomData(
    Map<String, Object?>? customData,
    String pageId,
  ) {
    final next = {...?customData};
    final existingFlowMuse = next['flowMuse'];
    next['flowMuse'] = {
      if (existingFlowMuse is Map<String, Object?>) ...existingFlowMuse,
      'pageId': pageId,
    };
    return next;
  }
}

/// 导出文档工厂：mindmap/ppt 风格由客户端构建 SmartLayoutDocument，保持导出能力。
class SmartLayoutDocumentFactory {
  const SmartLayoutDocumentFactory._();

  static SmartLayoutDocument fromBlocks(List<SmartLayoutBlock> blocks) {
    return SmartLayoutDocument(
      version: 1,
      generatedAt: DateTime.now().millisecondsSinceEpoch,
      blocks: blocks,
    );
  }
}
