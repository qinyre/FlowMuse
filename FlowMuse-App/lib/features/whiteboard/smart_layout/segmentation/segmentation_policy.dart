import '../snapshot/deterministic_hash.dart';

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
    this.preserveConfidenceThreshold = 0.55,
    this.rowClusteringTolerance = 0.6,
    this.oversizedStrokeFactor = 3.0,
    this.tableGridCoverage = 0.6,
    this.formulaStackRatio = 0.25,
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

  /// 置信低于该阈值的区域进入 preserved 语义（不自动重排）。
  final double preserveConfidenceThreshold;

  /// 行聚类容差（× 局部尺度）。
  final double rowClusteringTolerance;

  /// 尺寸超过局部尺度该倍数的笔画视为 oversized（装饰线候选）。
  final double oversizedStrokeFactor;

  /// table 判定的网格覆盖率下限。
  final double tableGridCoverage;

  /// formula 判定的 x 重叠堆叠对比例下限。
  final double formulaStackRatio;

  /// development 原型默认参数。
  static const SegmentationPolicy development = SegmentationPolicy();

  /// validation 一次选择后的冻结参数 v1（V3-103B）。
  ///
  /// validation 单轮选择结论：与 development 数值一致（无上调依据）；
  /// 冻结后不参与调参，frozen holdout 只用于 Gate 1 一次性判定。
  /// 参数集合由 [paramsCanonicalHash] 钉定，任何字段变化都会改变哈希。
  static const SegmentationPolicy frozenValidationV1 = SegmentationPolicy();

  /// 参数束 canonical 哈希：所有字段按名字典序 + canonical 数值文本
  /// 参与（复用 snapshot 的跨端确定性哈希），用于冻结校验与审计。
  String get paramsCanonicalHash {
    final fields = <String, num>{
      'neighborRadiusFactor': neighborRadiusFactor,
      'gapFactor': gapFactor,
      'gridCellFactor': gridCellFactor,
      'maxDeskewRadians': maxDeskewRadians,
      'deskewBinRadians': deskewBinRadians,
      'columnGapFactor': columnGapFactor,
      'verticalAspectThreshold': verticalAspectThreshold,
      'horizontalAspectThreshold': horizontalAspectThreshold,
      'minNeighborVotesForDeskew': minNeighborVotesForDeskew,
      'preserveConfidenceThreshold': preserveConfidenceThreshold,
      'rowClusteringTolerance': rowClusteringTolerance,
      'oversizedStrokeFactor': oversizedStrokeFactor,
      'tableGridCoverage': tableGridCoverage,
      'formulaStackRatio': formulaStackRatio,
    };
    final keys = fields.keys.toList()..sort();
    return fingerprint64(
      'segmentation-policy-v1|${[
        for (final key in keys) '$key=${_num(fields[key]!)}',
      ].join('|')}',
    );
  }
}

String _num(num value) {
  if (value is int) return value.toString();
  final d = value as double;
  if (d == d.truncateToDouble() && d.abs() < 1e15) {
    return d.truncateToDouble().toInt().toString();
  }
  return d.toString();
}
