import '../snapshot/deterministic_hash.dart';

/// 语义块角色（与协议 role 枚举同集；unknown 一律 preserved 语义）。
enum SemanticRole {
  title('title'),
  body('body'),
  caption('caption'),
  figure('figure'),
  formula('formula'),
  list('list'),
  table('table'),
  unknown('unknown');

  const SemanticRole(this.wireName);

  final String wireName;

  static SemanticRole fromWireName(String name) => values.firstWhere(
    (role) => role.wireName == name,
    orElse: () => SemanticRole.unknown,
  );

  /// unknown 块的 source 默认 preserved（不参与自动重排）。
  bool get defaultsToPreserved => this == SemanticRole.unknown;
}

/// 语义块：一次分析结论在文档层的不可变投影。
class SemanticBlock {
  const SemanticBlock({
    required this.id,
    required this.role,
    required this.sourceIds,
    required this.orderIndex,
    required this.confidence,
    this.text,
    this.extras = const {},
  });

  final String id;
  final SemanticRole role;
  final List<String> sourceIds;
  final int orderIndex;
  final double confidence;

  /// typed text（只来自请求/快照 exactText，绝不来自模型）。
  final String? text;

  /// 序列化时未知字段的保留区（新版本字段读取不误删）。
  final Map<String, Object?> extras;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.wireName,
    'sourceIds': [...sourceIds],
    'orderIndex': orderIndex,
    'confidence': confidence,
    if (text != null) 'text': text,
    ...extras,
  };

  @override
  bool operator ==(Object other) =>
      other is SemanticBlock &&
      other.id == id &&
      other.role == role &&
      _listEq(other.sourceIds, sourceIds) &&
      other.orderIndex == orderIndex &&
      other.confidence == confidence &&
      other.text == text &&
      _mapEq(other.extras, extras);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SemanticBlock($id, ${role.wireName}, '
      'sources: ${sourceIds.length})';
}

/// 总览/crop 冲突留档（V3-202A 冲突语义的文档层投影）。
class SemanticConflict {
  const SemanticConflict({
    required this.regionId,
    required this.kind,
    required this.overview,
    required this.crop,
  });

  final String regionId;
  final String kind;
  final String overview;
  final String crop;

  Map<String, Object?> toJson() => {
    'regionId': regionId,
    'kind': kind,
    'overview': overview,
    'crop': crop,
  };

  @override
  bool operator ==(Object other) =>
      other is SemanticConflict &&
      other.regionId == regionId &&
      other.kind == kind &&
      other.overview == overview &&
      other.crop == crop;

  @override
  int get hashCode => Object.hash(regionId, kind);

  @override
  String toString() => 'SemanticConflict($regionId, $kind)';
}

/// 阅读序：确定性的块 id 全序 + 相邻对（供 order pair 指标）。
class SemanticReadingOrder {
  const SemanticReadingOrder({required this.orderedBlockIds});

  final List<String> orderedBlockIds;

  List<(String, String)> consecutivePairs() {
    final pairs = <(String, String)>[];
    for (var i = 0; i + 1 < orderedBlockIds.length; i++) {
      pairs.add((orderedBlockIds[i], orderedBlockIds[i + 1]));
    }
    return pairs;
  }

  Map<String, Object?> toJson() => {
    'blocks': [...orderedBlockIds],
  };

  @override
  bool operator ==(Object other) =>
      other is SemanticReadingOrder &&
      _listEq(other.orderedBlockIds, orderedBlockIds);

  @override
  int get hashCode => orderedBlockIds.length;

  @override
  String toString() => 'SemanticReadingOrder(${orderedBlockIds.join('→')})';
}

/// 语义文档格式版本映射（冻结）。
class SemanticDocumentFormat {
  const SemanticDocumentFormat._();

  static const int currentVersion = 1;

  /// 可读取的最早版本（当前与 current 相同；未来只增不改语义）。
  static const int minSupportedVersion = 1;
}

/// 不可变语义文档：唯一 ledger 投影 + 版本化持久化映射。
class SemanticDocument {
  const SemanticDocument({
    required this.formatVersion,
    required this.pageId,
    required this.epoch,
    required this.revision,
    required this.fingerprint,
    required this.blocks,
    required this.readingOrder,
    required this.conflicts,
    required this.consumedSourceIds,
    required this.preservedSourceIds,
    this.readVersion,
    this.extras = const {},
  });

  factory SemanticDocument.fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version is! int) {
      throw const FormatException('SemanticDocument 缺 formatVersion');
    }
    if (version < SemanticDocumentFormat.minSupportedVersion) {
      throw FormatException('不支持的语义文档版本: $version');
    }
    final known = const {
      'formatVersion',
      'pageId',
      'revision',
      'blocks',
      'readingOrder',
      'conflicts',
      'ledger',
    };
    final extras = <String, Object?>{
      for (final entry in json.entries)
        if (!known.contains(entry.key)) entry.key: entry.value,
    };
    final revisionMap = json['revision'];
    if (revisionMap is! Map) {
      throw const FormatException('SemanticDocument 缺 revision');
    }
    final blocksJson = json['blocks'];
    if (blocksJson is! List) {
      throw const FormatException('SemanticDocument 缺 blocks');
    }
    final knownBlockKeys = const {
      'id',
      'role',
      'sourceIds',
      'orderIndex',
      'confidence',
      'text',
    };
    final blocks = <SemanticBlock>[
      for (final raw in blocksJson)
        if (raw is Map)
          _blockFromJson(Map<String, Object?>.from(raw), knownBlockKeys),
    ];
    final orderJson = json['readingOrder'];
    if (orderJson is! Map || orderJson['blocks'] is! List) {
      throw const FormatException('SemanticDocument 缺 readingOrder');
    }
    final orderIds = [
      for (final id in orderJson['blocks'] as List)
        if (id is String) id,
    ];
    final conflictsJson = json['conflicts'];
    final conflicts = <SemanticConflict>[
      if (conflictsJson is List)
        for (final raw in conflictsJson)
          if (raw is Map)
            SemanticConflict(
              regionId: raw['regionId'] as String? ?? '',
              kind: raw['kind'] as String? ?? '',
              overview: raw['overview'] as String? ?? '',
              crop: raw['crop'] as String? ?? '',
            ),
    ];
    final ledgerJson = json['ledger'];
    if (ledgerJson is! Map) {
      throw const FormatException('SemanticDocument 缺 ledger');
    }
    StringList idsOf(String key) => [
      if (ledgerJson[key] is List)
        for (final id in ledgerJson[key] as List)
          if (id is String) id,
    ];

    return SemanticDocument(
      formatVersion: version,
      pageId: json['pageId'] as String? ?? '',
      epoch: revisionMap['epoch'] as int? ?? 0,
      revision: revisionMap['revision'] as int? ?? 0,
      fingerprint: revisionMap['fingerprint'] as String? ?? '',
      blocks: List.unmodifiable(blocks),
      readingOrder: SemanticReadingOrder(
        orderedBlockIds: List.unmodifiable(orderIds),
      ),
      conflicts: List.unmodifiable(conflicts),
      consumedSourceIds: List.unmodifiable(idsOf('consumed')),
      preservedSourceIds: List.unmodifiable(idsOf('preserved')),
      readVersion: version == SemanticDocumentFormat.currentVersion
          ? null
          : version,
      extras: Map.unmodifiable(extras),
    );
  }

  static SemanticBlock _blockFromJson(
    Map<String, Object?> json,
    Set<String> knownKeys,
  ) {
    final extras = <String, Object?>{
      for (final entry in json.entries)
        if (!knownKeys.contains(entry.key)) entry.key: entry.value,
    };
    final sourceIds = [
      if (json['sourceIds'] is List)
        for (final id in json['sourceIds'] as List)
          if (id is String) id,
    ];
    return SemanticBlock(
      id: json['id'] as String? ?? '',
      role: SemanticRole.fromWireName(json['role'] as String? ?? 'unknown'),
      sourceIds: List.unmodifiable(sourceIds),
      orderIndex: json['orderIndex'] as int? ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      text: json['text'] as String?,
      extras: Map.unmodifiable(extras),
    );
  }

  final int formatVersion;

  /// 读取时若来自其它版本则记录（当前版本写入时恒为 current）。
  final int? readVersion;
  final String pageId;
  final int epoch;
  final int revision;
  final String fingerprint;
  final List<SemanticBlock> blocks;
  final SemanticReadingOrder readingOrder;
  final List<SemanticConflict> conflicts;
  final List<String> consumedSourceIds;
  final List<String> preservedSourceIds;
  final Map<String, Object?> extras;

  /// ledger 守恒哈希：consumed+preserved 全量参与。
  String get ledgerHash => fingerprint64(
    'semantic-ledger|'
    '${consumedSourceIds.join(',')}|${preservedSourceIds.join(',')}',
  );

  /// source 守恒：每个 source 恰好一个终态。
  bool get ledgerConserved {
    if (consumedSourceIds.toSet().length != consumedSourceIds.length) {
      return false;
    }
    if (preservedSourceIds.toSet().length != preservedSourceIds.length) {
      return false;
    }
    return consumedSourceIds
        .toSet()
        .intersection(preservedSourceIds.toSet())
        .isEmpty;
  }

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'pageId': pageId,
    'revision': {
      'epoch': epoch,
      'revision': revision,
      'fingerprint': fingerprint,
    },
    'blocks': [for (final block in blocks) block.toJson()],
    'readingOrder': readingOrder.toJson(),
    'conflicts': [for (final conflict in conflicts) conflict.toJson()],
    'ledger': {
      'consumed': [...consumedSourceIds],
      'preserved': [...preservedSourceIds],
      'hash': ledgerHash,
    },
    ...extras,
  };

  @override
  bool operator ==(Object other) =>
      other is SemanticDocument &&
      other.formatVersion == formatVersion &&
      other.pageId == pageId &&
      other.epoch == epoch &&
      other.revision == revision &&
      other.fingerprint == fingerprint &&
      _listEq(other.blocks, blocks) &&
      other.readingOrder == readingOrder &&
      _listEq(other.conflicts, conflicts) &&
      _listEq(other.consumedSourceIds, consumedSourceIds) &&
      _listEq(other.preservedSourceIds, preservedSourceIds) &&
      _mapEq(other.extras, extras);

  @override
  int get hashCode => Object.hash(pageId, fingerprint);

  @override
  String toString() =>
      'SemanticDocument(v$formatVersion, $pageId, blocks: ${blocks.length}, '
      'consumed: ${consumedSourceIds.length}, '
      'preserved: ${preservedSourceIds.length})';
}

typedef StringList = List<String>;

bool _listEq(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
