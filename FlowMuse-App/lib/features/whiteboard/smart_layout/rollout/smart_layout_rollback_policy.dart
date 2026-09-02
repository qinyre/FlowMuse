/// V3-701A：切流回滚策略（合并原 V3-701A~B）。
///
/// - 独立切流提交：切流变更只允许 allowlist 路径（入口/门禁/kill
///   switch/观测），混入其他业务文件 → [validateSwitchCommit] 拒绝——
///   机器可判定，杜绝把业务改动藏进切流提交；
/// - Git 回滚：revert 切流提交即回到切流前形态——回滚校验
///   [validateRollback] 要求回滚后 diff 恰为切流提交的逆集；
/// - 关闭/重开：关闭零 Draft/History/广播残留；重开回到默认关闭。
library;

class SmartLayoutRollbackPolicy {
  const SmartLayoutRollbackPolicy({required this.switchCommitAllowlist});

  /// 切流提交允许的路径集合（仓库相对，前缀匹配）。
  final Set<String> switchCommitAllowlist;

  /// 校验切流提交文件集：全部命中 allowlist 才通过。
  /// 返回违规文件清单（空=通过）。
  List<String> validateSwitchCommit(Iterable<String> changedPaths) {
    return [
      for (final path in changedPaths)
        if (!switchCommitAllowlist.any(path.startsWith)) path,
    ];
  }

  /// 校验回滚完整性：回滚后的残余 diff（相对切流前基线）必须为空——
  /// 即回滚恰好是切流提交的逆。返回不为空的残余路径清单（空=通过）。
  List<String> validateRollback({
    required Iterable<String> baselinePaths,
    required Iterable<String> currentPaths,
  }) {
    final baseline = baselinePaths.toSet();
    final current = currentPaths.toSet();
    return [
      ...current.difference(baseline).map((p) => '+$p'),
      ...baseline.difference(current).map((p) => '-$p'),
    ];
  }

  /// 关闭/重开检查单（机器可执行口径；V3-506A 六态矩阵钉死会话级
  /// 语义，此处为切流层的入口复位要求）。
  static const List<String> closeReopenChecklist = [
    '关闭后 entry.open 返回 entryClosed（不可再开）',
    'capability 缓存清空（重开回到默认关闭）',
    '已开会话 close 零 Draft/History/广播残留（V3-506A 六态）',
    'kill switch 状态保留（回滚不自动解除已跳闸信号）',
  ];
}
