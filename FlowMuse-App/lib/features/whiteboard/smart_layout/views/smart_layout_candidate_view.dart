import 'package:flutter/material.dart';

/// 单个排版候选卡片（review 阶段）。纯展示：全部输入经构造参数注入，
/// 自身不持有业务状态；选中态与回调都由会话 ViewModel 提供
///（V3-505B 在此扩展真实缩略图/评分解释/结构差异）。
class SmartLayoutCandidateView extends StatelessWidget {
  const SmartLayoutCandidateView({
    super.key,
    required this.candidateId,
    required this.structureLabel,
    required this.selected,
    this.onChoose,
  });

  final String candidateId;
  final String structureLabel;
  final bool selected;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '排版候选 $structureLabel',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: selected ? theme.colorScheme.primaryContainer : null,
        child: ListTile(
          title: Text(structureLabel),
          subtitle: Text(candidateId),
          trailing: selected
              ? Icon(Icons.check_circle, semanticLabel: '已选择')
              : null,
          onTap: onChoose,
        ),
      ),
    );
  }
}
