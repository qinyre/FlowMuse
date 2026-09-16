/// 识别操作预算值对象（spec §6.2）。初值=计划书 §5；一个 operationId
/// 一个预算实例：显式用户纠错=新 operationId+新预算+generation+1，自动
/// 复核/重分组/重试/结构请求全部消耗当前操作预算、不刷新。
///
/// 不可变值对象：模型调用计数在派发前经 [spendModelCall] 递减（不足
/// 抛错，由 pipeline 先查 [canSpendModelCall] 决定不发并保留该批区域）；
/// 总时限用真实计时器约束（[remainingOf]），到期由 pipeline 主动取消
/// 在途请求。测试可经 [consumedModelCalls] 注入初值。
library;

class RecognitionBudget {
  const RecognitionBudget({
    this.overviewMaxEdgePx = 2048,
    this.regionTargetLineHeightMinPx = 48,
    this.regionTargetLineHeightMaxPx = 96,
    this.regionMaxEdgePx = 2048,
    this.regionMaxPixels = 2 * 1024 * 1024,
    this.regionPaddingLineHeight = 0.3,
    this.batchMaxRegions = 8,
    this.batchMaxRequestBytes = 16 * 1024 * 1024,
    this.firstRoundMaxRegions = 64,
    this.verifyMaxRegions = 16,
    this.regroupRounds = 1,
    this.localRenderConcurrency = 1,
    this.networkConcurrency = 2,
    this.modelCallBudget = 16,
    this.retryPerRequest = 1,
    this.totalTimeout = const Duration(seconds: 120),
    this.perRequestTimeout = const Duration(seconds: 45),
    this.pencilLightnessThreshold = 0.8,
    this.consumedModelCalls = 0,
  });

  /// 概览图长边上限（px）。
  final int overviewMaxEdgePx;

  /// 区域图缩放目标：局部行高落在 [min, max] px 区间。
  final double regionTargetLineHeightMinPx;
  final double regionTargetLineHeightMaxPx;

  /// 单区域图长边 / 总像素上限。
  final int regionMaxEdgePx;
  final int regionMaxPixels;

  /// 留白 = 该倍数 × 局部行高（页面单位）。
  final double regionPaddingLineHeight;

  /// 批量上限：区域数与编码后请求 JSON 字节数（§3.2 字节口径）。
  final int batchMaxRegions;
  final int batchMaxRequestBytes;

  /// 首轮分区区域数上限。
  final int firstRoundMaxRegions;

  /// 复核区域数 / 重分组轮数上限（至多一轮，先重分组后复核）。
  final int verifyMaxRegions;
  final int regroupRounds;

  /// 本地渲染 / 网络并发。
  final int localRenderConcurrency;
  final int networkConcurrency;

  /// 模型调用总预算（含拆批、重试、复核、结构）。
  final int modelCallBudget;

  /// 单请求重试次数（仅 retryable=true 且非 invalidProviderResponse）。
  final int retryPerRequest;

  final Duration totalTimeout;
  final Duration perRequestTimeout;

  /// 浅色铅笔判定阈值：笔画颜色亮度高于该值时，临时资产做一次固定参数
  /// 对比度增强（spec §5.5；阈值可注入）。
  final double pencilLightnessThreshold;

  /// 已耗模型调用数（测试可注入初值）。
  final int consumedModelCalls;

  int get modelCallsRemaining => modelCallBudget - consumedModelCalls;

  bool get canSpendModelCall => modelCallsRemaining > 0;

  /// 派发前递减；不足抛 [StateError]（fail closed——调用方必须先查
  /// [canSpendModelCall]，不足则不发且该批区域保留）。
  RecognitionBudget spendModelCall() {
    if (!canSpendModelCall) {
      throw StateError(
        '模型调用预算已耗尽（$consumedModelCalls/'
        '$modelCallBudget），本批不得派发',
      );
    }
    return RecognitionBudget(
      overviewMaxEdgePx: overviewMaxEdgePx,
      regionTargetLineHeightMinPx: regionTargetLineHeightMinPx,
      regionTargetLineHeightMaxPx: regionTargetLineHeightMaxPx,
      regionMaxEdgePx: regionMaxEdgePx,
      regionMaxPixels: regionMaxPixels,
      regionPaddingLineHeight: regionPaddingLineHeight,
      batchMaxRegions: batchMaxRegions,
      batchMaxRequestBytes: batchMaxRequestBytes,
      firstRoundMaxRegions: firstRoundMaxRegions,
      verifyMaxRegions: verifyMaxRegions,
      regroupRounds: regroupRounds,
      localRenderConcurrency: localRenderConcurrency,
      networkConcurrency: networkConcurrency,
      modelCallBudget: modelCallBudget,
      retryPerRequest: retryPerRequest,
      totalTimeout: totalTimeout,
      perRequestTimeout: perRequestTimeout,
      pencilLightnessThreshold: pencilLightnessThreshold,
      consumedModelCalls: consumedModelCalls + 1,
    );
  }

  /// 总时限剩余（真实计时器输入；≤0 表示已到期，应主动取消在途请求）。
  Duration remainingOf(Stopwatch clock) => totalTimeout - clock.elapsed;

  @override
  bool operator ==(Object other) =>
      other is RecognitionBudget &&
      other.overviewMaxEdgePx == overviewMaxEdgePx &&
      other.regionTargetLineHeightMinPx == regionTargetLineHeightMinPx &&
      other.regionTargetLineHeightMaxPx == regionTargetLineHeightMaxPx &&
      other.regionMaxEdgePx == regionMaxEdgePx &&
      other.regionMaxPixels == regionMaxPixels &&
      other.regionPaddingLineHeight == regionPaddingLineHeight &&
      other.batchMaxRegions == batchMaxRegions &&
      other.batchMaxRequestBytes == batchMaxRequestBytes &&
      other.firstRoundMaxRegions == firstRoundMaxRegions &&
      other.verifyMaxRegions == verifyMaxRegions &&
      other.regroupRounds == regroupRounds &&
      other.localRenderConcurrency == localRenderConcurrency &&
      other.networkConcurrency == networkConcurrency &&
      other.modelCallBudget == modelCallBudget &&
      other.retryPerRequest == retryPerRequest &&
      other.totalTimeout == totalTimeout &&
      other.perRequestTimeout == perRequestTimeout &&
      other.pencilLightnessThreshold == pencilLightnessThreshold &&
      other.consumedModelCalls == consumedModelCalls;

  @override
  int get hashCode =>
      Object.hash(modelCallBudget, consumedModelCalls, totalTimeout);

  @override
  String toString() =>
      'RecognitionBudget(calls: $consumedModelCalls/$modelCallBudget, '
      'timeout: ${totalTimeout.inSeconds}s, per-request: '
      '${perRequestTimeout.inSeconds}s)';
}
