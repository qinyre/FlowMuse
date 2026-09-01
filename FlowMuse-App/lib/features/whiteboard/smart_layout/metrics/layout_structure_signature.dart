import '../composition/layout_composition_planner.dart';
import '../placement/flow_placer.dart';
import '../snapshot/deterministic_hash.dart';

/// 参与去重的放置结果条目（V3-405A）：候选 id + 骨架 + 完整放置
///（阅读序 placed）。分数/排名不参与结构等价判定——去重先于排序
/// 语义，Top 3 选择不在此层。
class PlacementEntry {
  const PlacementEntry({
    required this.candidateId,
    required this.skeleton,
    required this.placed,
  });

  final String candidateId;
  final LayoutSkeleton skeleton;
  final List<PlacedBlock> placed;
}

/// 被删条目记录（零静默删除：谁被删、等价于谁、签名是什么）。
class DroppedPlacement {
  const DroppedPlacement({
    required this.candidateId,
    required this.equivalentToCandidateId,
    required this.signature,
  });

  final String candidateId;
  final String equivalentToCandidateId;
  final String signature;
}

/// 去重结论。
class DeduplicatedPlacements {
  const DeduplicatedPlacements({
    required this.kept,
    required this.dropped,
  });

  final List<PlacementEntry> kept;
  final List<DroppedPlacement> dropped;
}

/// 结构等价签名（V3-405A 冻结契约）：**完整 placement 之后**判定
/// 两个候选是否为同一结构。等价 = 同骨架 + 每块同栏 + 栏内堆叠序
/// 相同 + 生效字号相同；**不比较像素坐标**（坐标差不是结构差）。
///
/// 叙事结构不误合并：块→栏指派或堆叠序任一不同 ⇒ 签名不同；内容
///（blockId）参与签名，不同叙事永远不同。
class LayoutStructureSignature {
  const LayoutStructureSignature();

  String of({
    required LayoutSkeleton skeleton,
    required List<PlacedBlock> placed,
  }) =>
      fingerprint64('structure|${skeleton.name}|${canonicalOf(placed)}');

  /// canonical 串（审计可读）：逐块 `id#column#rank#font`，阅读序。
  String canonicalOf(List<PlacedBlock> placed) {
    // 栏内堆叠秩：同栏按 top 升序（并列按输入序）的位次。
    final rankInColumn = <String, int>{};
    final byColumn = <int, List<PlacedBlock>>{};
    for (final p in placed) {
      byColumn.putIfAbsent(p.columnIndex, () => []).add(p);
    }
    final columnIndexes = byColumn.keys.toList()..sort();
    for (final c in columnIndexes) {
      final column = byColumn[c]!;
      final sorted = [...column]..sort((a, b) {
          final byTop = a.rect.top.compareTo(b.rect.top);
          return byTop != 0 ? byTop : a.blockId.compareTo(b.blockId);
        });
      for (var i = 0; i < sorted.length; i++) {
        rankInColumn[sorted[i].blockId] = i;
      }
    }
    String n(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return [
      for (final p in placed)
        '${p.blockId}#${p.columnIndex}#${rankInColumn[p.blockId]}'
        '#${n(p.appliedFontSize)}',
    ].join('|');
  }
}

/// 放置结果去重（V3-405A）：只删结构等价候选，**保留首个**（输入序
/// = 401A 枚举序，确定性；结构配额语义归 V3-401 不变）。零静默：
/// 每个被删条目都有 DroppedPlacement 记录。
class LayoutPlacementDeduplicator {
  const LayoutPlacementDeduplicator({LayoutStructureSignature? signature})
    : _signature = signature ?? const LayoutStructureSignature();

  final LayoutStructureSignature _signature;

  DeduplicatedPlacements dedupe(List<PlacementEntry> entries) {
    final kept = <PlacementEntry>[];
    final dropped = <DroppedPlacement>[];
    final signatureToKeptId = <String, String>{};
    for (final entry in entries) {
      final signature = _signature.of(
        skeleton: entry.skeleton,
        placed: entry.placed,
      );
      final existing = signatureToKeptId[signature];
      if (existing == null) {
        signatureToKeptId[signature] = entry.candidateId;
        kept.add(entry);
      } else {
        dropped.add(
          DroppedPlacement(
            candidateId: entry.candidateId,
            equivalentToCandidateId: existing,
            signature: signature,
          ),
        );
      }
    }
    return DeduplicatedPlacements(
      kept: List.unmodifiable(kept),
      dropped: List.unmodifiable(dropped),
    );
  }
}
