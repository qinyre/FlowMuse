/// 识别期源账本（spec §6.4）：识别终态（谁可被哪个 unit 消费、谁保留）
/// 的唯一真值与准入权威。终态仅经本类写入；向 SemanticAssembly 单向
/// 投影（[SourceLedgerProjection]），下游不得重新决定识别准入。
///
/// 与快照侧 `SourceCoverageLedger`（物化真值，materializer 终结）分立；
/// 本账本禁止 preserve→consume 反向升级，仅允许 consume→preserve 单向
/// 降级（自动处理；用户显式撤销保留=新纠错代次、新账本）。
library;

/// 保留原因有限枚举（不收自由文本；spec §6.4）。
enum SourcePreserveReason {
  locked('locked'),
  binding('binding'),
  unreadable('unreadable'),
  nonText('nonText'),
  userKept('userKept'),
  budgetExceeded('budgetExceeded'),
  assetFailed('assetFailed'),
  missingResponse('missingResponse'),
  contextOnly('contextOnly');

  const SourcePreserveReason(this.wireName);

  final String wireName;
}

enum SourceLedgerStatus { pending, consumed, preserved }

class SourceLedgerEntry {
  const SourceLedgerEntry._pending()
    : status = SourceLedgerStatus.pending,
      unitId = null,
      reason = null;

  const SourceLedgerEntry._consumed(String this.unitId)
    : status = SourceLedgerStatus.consumed,
      reason = null;

  const SourceLedgerEntry._preserved(this.reason)
    : status = SourceLedgerStatus.preserved,
      unitId = null;

  final SourceLedgerStatus status;

  /// consumed 时：消费该源的 unit id（必须已登记）。
  final String? unitId;

  /// preserved 时：保留原因。
  final SourcePreserveReason? reason;
}

/// 识别账本 → SemanticAssembly 的单向投影（§6.4）：consumed/preserved
/// 与 sourceId → unitId 归属由识别账本导出，下游只读。
class SourceLedgerProjection {
  const SourceLedgerProjection._(
    this.sourceIds,
    this.consumedBy,
    this.preservedReasons,
  );

  /// 全部源 id（= 排除背景后的识别源集合）。
  final Set<String> sourceIds;

  /// sourceId → 消费它的 unitId。
  final Map<String, String> consumedBy;

  /// sourceId → 保留原因。
  final Map<String, SourcePreserveReason> preservedReasons;

  bool get fullySettled =>
      consumedBy.length + preservedReasons.length == sourceIds.length;

  /// 覆盖率（发布前必须 1.0）。
  double get coverage => sourceIds.isEmpty
      ? 1.0
      : (consumedBy.length + preservedReasons.length) / sourceIds.length;
}

/// 转换准入七条件（spec §6.4）：`recognized ≠ 可替换`。手写源进入删除
/// 集合必须同时满足全部条件；物化前再校验一遍。
enum ConversionAdmissionFailure {
  notRecognized,
  emptyOrPunctuationText,
  coverageIncomplete,
  sourceTypeForbidden,
  protectedSource,
  unresolvedConflict,
  versionInvalid,
}

/// 单源守卫事实（由调用方从快照/元素侧提供，不在此重复实现元素逻辑）。
class SourceGuardFacts {
  const SourceGuardFacts({
    required this.isReplaceableInk,
    required this.isLocked,
    required this.hasCrossBinding,
  });

  /// 条件 4：FreeDraw 且非高亮笔刷（typed/image/图形/一切非 FreeDraw 与
  /// 高亮笔迹均为 false）。
  final bool isReplaceableInk;

  /// 条件 5a：元素锁定。
  final bool isLocked;

  /// 条件 5b：越界绑定。
  final bool hasCrossBinding;
}

class ConversionAdmission {
  const ConversionAdmission._();

  /// 评估七条件；null=通过。参数与 §6.4 逐条对应：
  /// - [statusConfirmedRecognized]：条件 1（recognized 且经复核规则未被推翻）；
  /// - [text]：条件 2（trim 后非空、非纯标点）；
  /// - [unitSourceIds]/[regionTargetSourceIds]：条件 3（恰为全集，无缺员无越界）；
  /// - [sourceGuards]：条件 4+5（对 unit 消费的全部源）；
  /// - [conflictsResolved]：条件 6（uncertain/复核冲突已消解）；
  /// - [versionValid]：条件 7（四元组校验通过且结构结果与正文指纹匹配）。
  static ConversionAdmissionFailure? check({
    required bool statusConfirmedRecognized,
    required String text,
    required Set<String> unitSourceIds,
    required Set<String> regionTargetSourceIds,
    required Map<String, SourceGuardFacts> sourceGuards,
    required bool conflictsResolved,
    required bool versionValid,
  }) {
    if (!statusConfirmedRecognized) {
      return ConversionAdmissionFailure.notRecognized;
    }
    if (!isMeaningfulText(text)) {
      return ConversionAdmissionFailure.emptyOrPunctuationText;
    }
    if (unitSourceIds.length != regionTargetSourceIds.length ||
        !unitSourceIds.containsAll(regionTargetSourceIds)) {
      return ConversionAdmissionFailure.coverageIncomplete;
    }
    for (final sourceId in unitSourceIds) {
      final guard = sourceGuards[sourceId];
      if (guard == null || !guard.isReplaceableInk) {
        return ConversionAdmissionFailure.sourceTypeForbidden;
      }
      if (guard.isLocked || guard.hasCrossBinding) {
        return ConversionAdmissionFailure.protectedSource;
      }
    }
    if (!conflictsResolved) {
      return ConversionAdmissionFailure.unresolvedConflict;
    }
    if (!versionValid) {
      return ConversionAdmissionFailure.versionInvalid;
    }
    return null;
  }

  /// 条件 2：trim 后非空且含至少一个非标点/非空白字符。
  static bool isMeaningfulText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    for (final rune in trimmed.runes) {
      if (!_isPunctuationOrSpace(rune)) {
        return true;
      }
    }
    return false;
  }

  /// ASCII/CJK 常用标点与符号的保守集合（Unicode 类 P 的实用近似）。
  static bool _isPunctuationOrSpace(int rune) {
    if (rune <= 0x20) return true;
    if (rune < 0x30) return true; // !"#$%&'()*+,-./
    if (rune >= 0x3a && rune <= 0x40) return true; // :;<=>?@
    if (rune >= 0x5b && rune <= 0x60) return true; // [\]^_`
    if (rune >= 0x7b && rune <= 0x7e) return true; // {|}~
    if (rune >= 0x2000 && rune <= 0x206f) return true; // 通用标点
    if (rune >= 0x3000 && rune <= 0x303f) return true; // CJK 标点 。、「」
    if (rune >= 0xff00 && rune <= 0xffef) return true; // 全角形式 ！，（）
    switch (rune) {
      case 0x00b7: // ·
      case 0x2022: // •
      case 0x2026: // …
      case 0x2014: // —
      case 0x2013: // –
      case 0x00d7: // ×
      case 0x00f7: // ÷
      case 0x00b0: // °
        return true;
    }
    return false;
  }
}

/// 源账本：不可变、copy-on-write（镜像 SourceCoverageLedger 风格）。
class SourceLedger {
  SourceLedger._(this._entries, this._units);

  /// 捕获时全量注册（范围为排除背景后的识别源集合）；id 重复即失败。
  factory SourceLedger.register(Iterable<String> sourceIds) {
    final entries = <String, SourceLedgerEntry>{};
    for (final id in sourceIds) {
      if (entries.containsKey(id)) {
        throw ArgumentError.value(id, 'sourceIds', '源 id 重复');
      }
      entries[id] = const SourceLedgerEntry._pending();
    }
    return SourceLedger._(entries, <String>{});
  }

  final Map<String, SourceLedgerEntry> _entries;
  final Set<String> _units;

  Set<String> get sourceIds => _entries.keys.toSet();

  Set<String> get registeredUnitIds => Set.unmodifiable(_units);

  int get pendingCount => _entries.values
      .where((entry) => entry.status == SourceLedgerStatus.pending)
      .length;

  int get consumedCount => _entries.values
      .where((entry) => entry.status == SourceLedgerStatus.consumed)
      .length;

  int get preservedCount => _entries.values
      .where((entry) => entry.status == SourceLedgerStatus.preserved)
      .length;

  SourceLedgerEntry entryOf(String sourceId) {
    final entry = _entries[sourceId];
    if (entry == null) {
      throw StateError('未知源 id: $sourceId');
    }
    return entry;
  }

  /// 登记 unit（consume 的 unit 必须已登记；§6.4 不变量）。
  SourceLedger registerUnits(Iterable<String> unitIds) {
    final units = {..._units};
    for (final id in unitIds) {
      if (id.isEmpty) {
        throw ArgumentError.value(id, 'unitIds', 'unit id 非空');
      }
      units.add(id);
    }
    return SourceLedger._(_entries, units);
  }

  SourceLedger _mark(String sourceId, SourceLedgerEntry entry) {
    final current = _entries[sourceId];
    if (current == null) {
      throw StateError('未知源 id: $sourceId');
    }
    if (current.status != SourceLedgerStatus.pending) {
      throw StateError(
        '源 $sourceId 已是终态 ${current.status.name}，'
        '不可再标记（降级仅限 consume→preserve，走 downgradeToPreserved）',
      );
    }
    final next = {..._entries};
    next[sourceId] = entry;
    return SourceLedger._(next, _units);
  }

  /// 标记源被 unit 消费（unit 必须已登记；仅 pending 可消费）。
  SourceLedger consume(String sourceId, String unitId) {
    if (!_units.contains(unitId)) {
      throw StateError('unit 未登记: $unitId（consume 的 unit 必须已登记）');
    }
    return _mark(sourceId, SourceLedgerEntry._consumed(unitId));
  }

  /// 标记源保留（pending → preserved）。
  SourceLedger preserve(String sourceId, SourcePreserveReason reason) {
    return _mark(sourceId, SourceLedgerEntry._preserved(reason));
  }

  /// 单向降级（§6.4-3）：consume → preserve 仅自动处理允许；preserve →
  /// consume 禁止（用户显式撤销保留=新纠错代次，重建账本重新验证）。
  SourceLedger downgradeToPreserved(
    String sourceId,
    SourcePreserveReason reason,
  ) {
    final current = _entries[sourceId];
    if (current == null) {
      throw StateError('未知源 id: $sourceId');
    }
    if (current.status == SourceLedgerStatus.consumed) {
      final next = {..._entries};
      next[sourceId] = SourceLedgerEntry._preserved(reason);
      return SourceLedger._(next, _units);
    }
    if (current.status == SourceLedgerStatus.preserved) {
      throw StateError('源 $sourceId 已保留，禁止变更保留终态');
    }
    return preserve(sourceId, reason);
  }

  /// 不变量校验：每个源恰一次终态、覆盖率 100%；违反抛 [StateError]。
  void assertAllSettled() {
    final pending =
        _entries.entries
            .where((entry) => entry.value.status == SourceLedgerStatus.pending)
            .map((entry) => entry.key)
            .toList()
          ..sort();
    if (pending.isNotEmpty) {
      throw StateError('存在未结算源: $pending（发布前覆盖率必须 100%）');
    }
  }

  /// 单向投影（§6.4）：assembly 的账目输入，只读。
  SourceLedgerProjection get projection {
    final consumedBy = <String, String>{};
    final preserved = <String, SourcePreserveReason>{};
    for (final entry in _entries.entries) {
      final value = entry.value;
      switch (value.status) {
        case SourceLedgerStatus.consumed:
          consumedBy[entry.key] = value.unitId!;
        case SourceLedgerStatus.preserved:
          preserved[entry.key] = value.reason!;
        case SourceLedgerStatus.pending:
          break;
      }
    }
    return SourceLedgerProjection._(
      Set.unmodifiable(_entries.keys.toSet()),
      Map.unmodifiable(consumedBy),
      Map.unmodifiable(preserved),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceLedger && _mapEquals(other._entries, _entries);

  @override
  int get hashCode => Object.hashAll([
    for (final id in _entries.keys.toList()..sort()) id,
    for (final id in _entries.keys.toList()..sort()) _entries[id]!.status.name,
  ]);

  @override
  String toString() =>
      'SourceLedger(${_entries.length} sources, pending: $pendingCount, '
      'consumed: $consumedCount, preserved: $preservedCount, '
      'units: ${_units.length})';
}

bool _mapEquals(
  Map<String, SourceLedgerEntry> a,
  Map<String, SourceLedgerEntry> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null ||
        other.status != entry.value.status ||
        other.unitId != entry.value.unitId ||
        other.reason != entry.value.reason) {
      return false;
    }
  }
  return true;
}
