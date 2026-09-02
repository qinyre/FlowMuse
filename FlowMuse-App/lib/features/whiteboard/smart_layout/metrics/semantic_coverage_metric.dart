/// 语义覆盖度量（V3-405A）：最终 Scene 上源 ledger 的守恒核算——
/// 每个源必须恰好以 consumed 或 preserved 之一出现。
///
/// fail closed：未知渲染源（不在 ledger）、重复消费/保留 → 构造即抛
/// StateError；不产生"看似部分覆盖"的静默结果。
class SemanticCoverageMetric {
  SemanticCoverageMetric({
    required this.consumedFraction,
    required this.preservedFraction,
    required this.uncoveredFraction,
    required this.missingSourceIds,
  }) {
    for (final v in [
      consumedFraction,
      preservedFraction,
      uncoveredFraction,
    ]) {
      if (v.isNaN || v < 0 || v > 1) {
        throw StateError('coverage fraction out of range: $v');
      }
    }
  }

  /// consumed 源占比。
  final double consumedFraction;

  /// preserved 源占比。
  final double preservedFraction;

  /// 既未消费也未保留的源占比（信息丢失的直接证据）。
  final double uncoveredFraction;

  /// 未覆盖源 id（升序）。
  final List<String> missingSourceIds;

  /// 全覆盖判定（consumed + preserved == ledger 且无缺失）。
  bool get fullyCovered => missingSourceIds.isEmpty && uncoveredFraction == 0;

  /// 从集合代数构造（唯一入口；ledger 为权威全集）。
  static SemanticCoverageMetric of({
    required List<String> ledgerSourceIds,
    required List<String> renderedConsumedSourceIds,
    required List<String> renderedPreservedSourceIds,
  }) {
    final ledger = <String>{};
    for (final id in ledgerSourceIds) {
      if (!ledger.add(id)) {
        throw StateError('duplicate ledger source id: $id');
      }
    }
    final consumed = <String>{};
    for (final id in renderedConsumedSourceIds) {
      if (!ledger.contains(id)) {
        throw StateError('rendered consumed source not in ledger: $id');
      }
      if (!consumed.add(id)) {
        throw StateError('source consumed twice: $id');
      }
    }
    final preserved = <String>{};
    for (final id in renderedPreservedSourceIds) {
      if (!ledger.contains(id)) {
        throw StateError('rendered preserved source not in ledger: $id');
      }
      if (!preserved.add(id)) {
        throw StateError('source preserved twice: $id');
      }
      if (consumed.contains(id)) {
        throw StateError('source both consumed and preserved: $id');
      }
    }
    final total = ledger.length;
    final missing = ledger.difference(consumed).difference(preserved).toList()
      ..sort();
    return SemanticCoverageMetric(
      consumedFraction: total == 0 ? 1.0 : consumed.length / total,
      preservedFraction: total == 0 ? 1.0 : preserved.length / total,
      uncoveredFraction: total == 0 ? 0.0 : missing.length / total,
      missingSourceIds: List.unmodifiable(missing),
    );
  }
}
