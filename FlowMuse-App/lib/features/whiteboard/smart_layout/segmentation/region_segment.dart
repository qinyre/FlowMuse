/// 分割区域：一组经连通分量得到的笔画集合 + 其 reading geometry。
class RegionSegment {
  const RegionSegment({
    required this.id,
    required this.strokeIds,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.lineDirection,
    required this.columnIndex,
    required this.skewRadians,
    required this.localScale,
  });

  /// 稳定 id：按确定性排序（先 top 后 left）后的序号。
  final String id;

  /// 成员笔画 id（排序、不可变）；split/merge 防护在 V3-103B，
  /// 本阶段的 membership 一经产出即冻结。
  final List<String> strokeIds;

  /// 原始坐标系下的区域框（未做 deskew 旋转，供渲染/校正引用）。
  final double left;
  final double top;
  final double width;
  final double height;

  /// reading geometry：主行进方向。
  final SegmentLineDirection lineDirection;

  /// deskew 后全局列聚类给出的列号（0 起，左→右）。
  final int columnIndex;

  /// 本区域估计的书写倾角（弧度，向 0 纠正过）。
  final double skewRadians;

  /// 局部笔画尺度（邻域中位笔画高）。
  final double localScale;

  @override
  String toString() =>
      'RegionSegment($id, strokes: ${strokeIds.length}, '
      'dir: ${lineDirection.name}, column: $columnIndex)';
}

/// 行进方向（竖排为保留模式候选，不参与重排——由后续阶段决定）。
enum SegmentLineDirection { horizontal, vertical, mixed }
