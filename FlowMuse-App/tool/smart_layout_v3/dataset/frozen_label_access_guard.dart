/// V3-002C 冻结标签访问闸门：调参/训练类工具拒绝读取 frozen_holdout 标签。
///
/// 冻结集合（frozen_holdout）的标注标签只允许评测与门禁读取
/// （R8 单发判定：冻结前任何调参用途都构成污染）。任何标注加载器/
/// CLI 在返回 frozen 标签前必须先经 [FrozenLabelAccessGuard.check]。
library;

class FrozenLabelAccessGuard {
  const FrozenLabelAccessGuard._();

  /// 允许读取 frozen 标签的角色：评测、门禁与冻结清单本身的生成。
  static const Set<String> frozenReaderRoles = {'evaluation', 'gate', 'annotation_freeze'};

  static GuardDecision check({required String accessorRole, required String split}) {
    if (split != 'frozen_holdout') {
      return const GuardDecision.allowed();
    }
    if (frozenReaderRoles.contains(accessorRole)) {
      return const GuardDecision.allowed();
    }
    return GuardDecision.denied(
      'frozen_label_access_denied: split=frozen_holdout 只允许 evaluation/gate/annotation_freeze '
      '角色读取标注标签；调参或训练用途（role=$accessorRole）在冻结判定前禁止访问（R8）',
    );
  }
}

class GuardDecision {
  const GuardDecision.allowed()
      : allowed = true,
        reason = null;
  const GuardDecision.denied(this.reason) : allowed = false;
  final bool allowed;
  final String? reason;
}
