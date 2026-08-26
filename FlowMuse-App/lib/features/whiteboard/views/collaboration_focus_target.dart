/// 协作聚焦目标（本机视图态，永不进入 Scene/History/网络）。
/// 判等约定：**消费方**必须按 [CreatorFocus.creatorKey] 字段做值比较
/// （见 WhiteboardPage `_isFocusedOn`），本类刻意不覆写 `==`（避免与
/// labelSnapshot 变化混淆）；禁止依赖对象 identity（v4 §6.1）。
sealed class CollaborationFocusTarget {
  const CollaborationFocusTarget();
}

final class CreatorFocus extends CollaborationFocusTarget {
  const CreatorFocus(
    this.creatorKey, {
    required this.labelSnapshot,
    required this.isGuest,
  });

  final String creatorKey;

  /// 离线回退显示名：在线 presence 出现时持续更新为最后已知在线名，
  /// 离线后回退到该最新快照，不倒退（v4 §6.1）。
  final String labelSnapshot;

  final bool isGuest;
}

final class HistoricalFocus extends CollaborationFocusTarget {
  const HistoricalFocus();
}

/// 纯本机状态转换；本文件不得 import repository、Socket、Scene 或存储层。
CollaborationFocusTarget? toggleCollaborationCreatorFocus(
  CollaborationFocusTarget? current, {
  required String creatorKey,
  required String labelSnapshot,
  required bool isGuest,
}) {
  if (current is CreatorFocus && current.creatorKey == creatorKey) {
    return null;
  }
  return CreatorFocus(
    creatorKey,
    labelSnapshot: labelSnapshot,
    isGuest: isGuest,
  );
}
