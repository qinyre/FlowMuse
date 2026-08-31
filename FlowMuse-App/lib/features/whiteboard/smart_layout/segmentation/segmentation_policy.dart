/// 分割算法的可校准参数束（计划 §4.3：算法常量是待校准参数，
/// 不在代码里伪装成已证明真值；development 原型 → validation 一次选择
/// → Gate 1 后冻结，frozen holdout 不参与调参）。
class SegmentationPolicy {
  const SegmentationPolicy({
    this.neighborRadiusFactor = 4.0,
    this.gapFactor = 1.6,
    this.gridCellFactor = 4.0,
    this.maxDeskewRadians = 0.2618,
    this.deskewBinRadians = 0.0873,
    this.columnGapFactor = 2.5,
    this.verticalAspectThreshold = 1.25,
    this.horizontalAspectThreshold = 1.25,
    this.minNeighborVotesForDeskew = 3,
  });

  /// 局部尺度搜索半径（× 局部中位笔画高）。
  final double neighborRadiusFactor;

  /// 笔画可视间隙邻接阈值（× 相邻双方较大局部尺度）。
  final double gapFactor;

  /// 空间网格边长（× 局部中位笔画高）。
  final double gridCellFactor;

  /// deskew 估计的最大纠正角（15°）。
  final double maxDeskewRadians;

  /// deskew 主方向直方图 bin 宽（5°）。
  final double deskewBinRadians;

  /// 列间隔阈值（× 全页中位笔画高）。
  final double columnGapFactor;

  /// 区域高/宽超过该比例判为竖排行进方向。
  final double verticalAspectThreshold;

  /// 区域宽/高超过该比例判为横排行进方向；两档之外记 mixed。
  final double horizontalAspectThreshold;

  /// 少于该数量的右邻投票时不做 deskew（角度记 0）。
  final int minNeighborVotesForDeskew;

  /// development 原型默认参数（103B 冻结前唯一实例）。
  static const SegmentationPolicy development = SegmentationPolicy();
}
