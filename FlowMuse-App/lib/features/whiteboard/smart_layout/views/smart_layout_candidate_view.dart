import 'package:flutter/material.dart';

/// 结构代表选择器。只转发选择，不写场景、不触发识别；技术指标在详情中。
class SmartLayoutCandidateView extends StatelessWidget {
  const SmartLayoutCandidateView({
    super.key,
    required this.structureLabel,
    required this.selected,
    this.onChoose,
    this.recommended = false,
  });

  final String structureLabel;
  final bool selected;
  final VoidCallback? onChoose;

  final bool recommended;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(recommended ? '$structureLabel · 推荐' : structureLabel),
    selected: selected,
    onSelected: onChoose == null ? null : (_) => onChoose!(),
  );
}
