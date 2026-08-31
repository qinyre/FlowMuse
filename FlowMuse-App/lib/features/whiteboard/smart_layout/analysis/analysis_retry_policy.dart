/// 有限重试策略（V3-203A）：只对超时/网络故障与 429/500/502/503/504 重试，
/// 其余（schema 违例、其它 4xx、取消、守卫拒绝）立即终止。
class AnalysisRetryPolicy {
  const AnalysisRetryPolicy({this.maxAttempts = 2});

  /// 总尝试次数上限（含首次）。
  final int maxAttempts;

  static const retryableStatuses = {429, 500, 502, 503, 504};

  /// 判定一次失败是否值得再试。
  bool shouldRetry(AnalysisFailureKind kind, int? statusCode, int attempt) {
    if (attempt >= maxAttempts - 1) return false;
    return switch (kind) {
      AnalysisFailureKind.network => true,
      AnalysisFailureKind.timeout => true,
      AnalysisFailureKind.badStatus =>
        statusCode != null && retryableStatuses.contains(statusCode),
      AnalysisFailureKind.badSchema => false,
      AnalysisFailureKind.cancelled => false,
      AnalysisFailureKind.guardRejected => false,
      AnalysisFailureKind.capabilityOff => false,
    };
  }
}

enum AnalysisFailureKind {
  capabilityOff,
  network,
  timeout,
  badStatus,
  badSchema,
  cancelled,
  guardRejected,
}
