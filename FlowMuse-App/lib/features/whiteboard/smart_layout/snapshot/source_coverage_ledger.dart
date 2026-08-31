import 'deterministic_hash.dart';

/// 源对象覆盖状态的完整生命周期：pending（快照创建时）→ consumed 或
/// preserved（终态）。终态不可再变更；不存在"主观忽略"分支——不可靠
/// 消费的内容一律 preserved。
enum SourceCoverageStatus { pending, consumed, preserved }

/// 唯一 SourceCoverageLedger：LayoutPageSnapshot 创建后，SemanticDocument、
/// LayoutBlock、ScenePatch、Draft Scene 与 metrics 只透传并校验同一 ledger
/// 实例，不创建第二套 source 状态。
class SourceCoverageLedger {
  SourceCoverageLedger._(Map<String, SourceCoverageStatus> status)
    : _status = Map.unmodifiable(status),
      hashValue = _hashOf(status);

  /// 以全部源 id 的 pending 状态建账；id 重复即构造失败（账本不允许
  /// 二义来源）。
  factory SourceCoverageLedger.pending(Iterable<String> sourceIds) {
    final status = <String, SourceCoverageStatus>{};
    for (final id in sourceIds) {
      if (status.containsKey(id)) {
        throw ArgumentError.value(id, 'sourceIds', '源 id 重复');
      }
      status[id] = SourceCoverageStatus.pending;
    }
    return SourceCoverageLedger._(status);
  }

  final Map<String, SourceCoverageStatus> _status;

  /// canonical 覆盖哈希：id 排序 + 终态/中间态全量参与，
  /// 供 renderer/metrics/ledger 一致性校验（V3-502/V3-504）。
  final String hashValue;

  static String _hashOf(Map<String, SourceCoverageStatus> status) {
    final ids = status.keys.toList()..sort();
    final payload = ids.map((id) => '$id:${status[id]!.name}').join('|');
    return fingerprint64('ledger|$payload');
  }

  int get sourceCount => _status.length;

  int get pendingCount =>
      _status.values.where((s) => s == SourceCoverageStatus.pending).length;

  int get consumedCount =>
      _status.values.where((s) => s == SourceCoverageStatus.consumed).length;

  int get preservedCount =>
      _status.values.where((s) => s == SourceCoverageStatus.preserved).length;

  /// 处理中允许 pending；最终每个源只能是 consumed 或 preserved。
  bool get isFinalized => pendingCount == 0;

  SourceCoverageStatus statusOf(String sourceId) {
    final status = _status[sourceId];
    if (status == null) {
      throw StateError('未知源 id: $sourceId');
    }
    return status;
  }

  /// 全量状态视图（id 排序、不可变）。
  Map<String, SourceCoverageStatus> get statuses => _status;

  SourceCoverageLedger _mark(
    Iterable<String> ids,
    SourceCoverageStatus terminal,
  ) {
    final next = {..._status};
    for (final id in ids) {
      final current = next[id];
      if (current == null) {
        throw StateError('未知源 id: $id');
      }
      if (current != SourceCoverageStatus.pending) {
        throw StateError('源 $id 已是终态 $current，不可再标记');
      }
      next[id] = terminal;
    }
    return SourceCoverageLedger._(next);
  }

  /// 标记源已被排版消费。
  SourceCoverageLedger markConsumed(Iterable<String> ids) =>
      _mark(ids, SourceCoverageStatus.consumed);

  /// 标记源保持原样保留（不可靠消费、保护物、背景等一律走此分支）。
  SourceCoverageLedger markPreserved(Iterable<String> ids) =>
      _mark(ids, SourceCoverageStatus.preserved);

  @override
  bool operator ==(Object other) =>
      other is SourceCoverageLedger && _mapEquals(other._status, _status);

  @override
  int get hashCode => hashValue.hashCode;

  @override
  String toString() =>
      'SourceCoverageLedger(${_status.length} sources, '
      'pending: $pendingCount, consumed: $consumedCount, '
      'preserved: $preservedCount)';
}

bool _mapEquals(
  Map<String, SourceCoverageStatus> a,
  Map<String, SourceCoverageStatus> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
