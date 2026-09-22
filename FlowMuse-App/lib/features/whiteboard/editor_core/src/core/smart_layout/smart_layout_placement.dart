import 'dart:ui';

import '../math/math.dart';

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
    final candidate = _firstLegalCandidate(
      area,
      width,
      height,
      occupied,
      xCandidates,
      yCandidates,
    );
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
