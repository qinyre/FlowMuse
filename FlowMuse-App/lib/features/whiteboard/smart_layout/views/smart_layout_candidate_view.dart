import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 单个排版候选卡片（review 阶段，V3-505B）：绑定当前
/// ValidatedCandidate——真实 renderer 缩略图（snapshot.image，非估算）、
/// 可还原评分解释（ProfileScore.entries）、结构代表与差异标签。
///
/// 纯展示：全部输入经构造参数注入，自身不持有业务状态；缩略图归
/// 候选所有，卡片不 dispose。切换候选只转发回调，不写权威 Scene。
class SmartLayoutCandidateView extends StatelessWidget {
  const SmartLayoutCandidateView({
    super.key,
    required this.candidateId,
    required this.structureLabel,
    required this.selected,
    this.onChoose,
    this.rank,
    this.structureDiffLabel,
    this.score,
    this.scoreEntries = const [],
    this.thumbnail,
  });

  final String candidateId;
  final String structureLabel;
  final bool selected;
  final VoidCallback? onChoose;

  /// 排名（1 起）；null = 未排名摘要卡。
  final int? rank;

  /// 与首名候选的结构差异标签（基准结构/同结构/结构不同）。
  final String? structureDiffLabel;

  /// profile 总分（可还原分解见 [scoreEntries]）。
  final double? score;
  final List<
    ({String metricId, double value, double weight, double contribution})
  >
  scoreEntries;

  /// 真实渲染缩略图（DraftRenderSnapshot.image；非估算缩略图）。
  final ui.Image? thumbnail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '排版候选 $structureLabel'
          '${rank == null ? '' : '，第 $rank 名'}',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: selected ? theme.colorScheme.primaryContainer : null,
        child: ListTile(
          leading: thumbnail == null
              ? null
              : SizedBox(
                  width: 64,
                  height: 48,
                  child: Semantics(
                    label: '候选渲染缩略图',
                    child: RawImage(image: thumbnail, fit: BoxFit.contain),
                  ),
                ),
          title: Text(
            rank == null ? structureLabel : '$structureLabel · 第 $rank 名',
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(candidateId),
              if (structureDiffLabel != null && structureDiffLabel!.isNotEmpty)
                Text('结构：$structureDiffLabel'),
              if (score != null) Text('评分 ${score!.toStringAsFixed(3)}'),
              if (scoreEntries.isNotEmpty)
                Text(
                  '构成：'
                  '${scoreEntries.map((e) => '${e.metricId} '
                      '${e.contribution.toStringAsFixed(2)}').join('，')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          trailing: selected
              ? Icon(Icons.check_circle, semanticLabel: '已选择')
              : null,
          onTap: onChoose,
        ),
      ),
    );
  }
}
