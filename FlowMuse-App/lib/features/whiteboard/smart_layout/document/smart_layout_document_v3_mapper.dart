import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

/// 一次版本映射读取的结果：规范 [SmartLayoutDocument] + 版本账目 +
/// 未知字段保真区（文档级与块级分开，原样回写不误删——与 V3-204A
/// SemanticDocument extras 同一策略）。
class SmartLayoutDocumentRead {
  const SmartLayoutDocumentRead({
    required this.document,
    required this.readVersion,
    required this.versionWasAbsent,
    required this.upgradedToCurrent,
    required this.unknownDocumentFields,
    required this.unknownFieldsByBlockId,
  });

  /// 规范化后的文档（确定性默认：generatedAt 缺失=0、块 id 缺失按序
  /// 'legacy-block-N'，杜绝 SmartLayoutBlock.fromJson 的随机 id 与
  /// DateTime.now() 时间默认——重开深度一致的前提）。
  final SmartLayoutDocument document;

  /// 实际读到的版本号；version 字段缺失（前版本化存量）记 0。
  final int readVersion;

  /// version 字段是否缺失（legacy 存量标记）。
  final bool versionWasAbsent;

  /// 读入版本是否低于写出版本（write 恒归一 currentVersion）。
  final bool upgradedToCurrent;

  /// 文档级未知字段（键→原值，原样保留）。
  final Map<String, Object?> unknownDocumentFields;

  /// 块级未知字段（块 id→未知字段集合，原样保留）。
  final Map<String, Map<String, Object?>> unknownFieldsByBlockId;
}

/// SmartLayoutDocument 持久化 JSON 的版本映射（V3-601A，合并原
/// V3-601A~B）。
///
/// 职责（feature-private，不改 editor_core 序列化框架）：
/// - 版本策略：version 缺失（legacy=0）或 1（native）读入并归一；
///   大于 current 的未来版本可读（前向兼容，未知字段保真）；负数
///   FormatException 拒绝；
/// - 旧读新写：legacy/未来版本读入后由 [writeJson] 以当前版本写回，
///   文档级与块级未知字段原样合并不丢失；
/// - 确定性：缺失 generatedAt 与块 id 的确定性默认先于既有
///   [SmartLayoutDocument.fromJson] 注入（既有路径保持零改动）。
abstract final class SmartLayoutDocumentV3Mapper {
  static const int currentVersion = 1;
  static const int minSupportedVersion = 1;

  static const Set<String> _knownDocumentKeys = {'version', 'generatedAt', 'blocks'};
  static const Set<String> _knownBlockKeys = {
    'id', 'type', 'text', 'latex', 'pageId', 'bounds', 'order', 'writingMode',
    'sourceIds',
  };

  /// legacy 存量（version 缺失）读到的版本值。
  static const int legacyAbsentVersion = 0;

  /// 读入持久化 JSON：版本映射 + 未知字段捕获 + 确定性默认注入，
  /// 块反序列化委托既有 [SmartLayoutBlock.fromJson]。
  static SmartLayoutDocumentRead readFromJson(Map<String, Object?> json) {
    final rawVersion = json['version'];
    if (rawVersion != null && rawVersion is! num) {
      throw FormatException('SmartLayoutDocument version 非数值: $rawVersion');
    }
    final version = rawVersion is num ? rawVersion.toInt() : legacyAbsentVersion;
    if (version < legacyAbsentVersion) {
      throw FormatException('SmartLayoutDocument 版本号非法: $version');
    }
    final versionWasAbsent = rawVersion == null;

    // 文档级未知字段捕获（先于规范化注入的 generatedAt）。
    final unknownDocumentFields = <String, Object?>{
      for (final entry in json.entries)
        if (!_knownDocumentKeys.contains(entry.key)) entry.key: entry.value,
    };

    // 确定性默认注入（缺 generatedAt=0；缺块 id 按序 legacy-block-N），
    // 然后委托既有反序列化路径。
    final rawBlocks = json['blocks'];
    if (rawBlocks != null && rawBlocks is! List) {
      throw const FormatException('SmartLayoutDocument blocks 非数组');
    }
    final blocksJson = [
      for (final (index, item) in (rawBlocks as List<Object?>? ?? const []).indexed)
        if (item is Map)
          _normalizeBlockJson(Map<String, Object?>.from(item), index),
    ];
    final normalized = <String, Object?>{
      ...json,
      'version': version == legacyAbsentVersion ? minSupportedVersion : version,
      if (json['generatedAt'] == null) 'generatedAt': 0,
      'blocks': blocksJson,
    };
    final document = SmartLayoutDocument.fromJson(normalized);

    // 块级未知字段捕获（按规范化后的块 id 键控）。
    final unknownByBlock = <String, Map<String, Object?>>{};
    for (final (index, item) in blocksJson.indexed) {
      final unknown = <String, Object?>{
        for (final entry in item.entries)
          if (!_knownBlockKeys.contains(entry.key)) entry.key: entry.value,
      };
      if (unknown.isNotEmpty) {
        unknownByBlock[document.blocks[index].id] = unknown;
      }
    }

    return SmartLayoutDocumentRead(
      document: document,
      readVersion: version,
      versionWasAbsent: versionWasAbsent,
      upgradedToCurrent:
          version != currentVersion,
      unknownDocumentFields: Map.unmodifiable(unknownDocumentFields),
      unknownFieldsByBlockId: Map.unmodifiable(unknownByBlock),
    );
  }

  /// 以当前版本写回（旧读新写）：结构复用 [SmartLayoutDocument.toJson]，
  /// 读入时捕获的文档级/块级未知字段原样合并——未来版本字段随写保留，
  /// 不因版本归一而丢失。
  static Map<String, Object?> writeJson(
    SmartLayoutDocument document, {
    SmartLayoutDocumentRead? read,
  }) {
    final base = document.toJson();
    base['version'] = currentVersion;
    final blocks = [
      for (final block in base['blocks'] as List<Object?>)
        () {
          final blockJson = Map<String, Object?>.from(block as Map);
          final unknown = read?.unknownFieldsByBlockId[blockJson['id']];
          if (unknown != null) blockJson.addAll(unknown);
          return blockJson;
        }(),
    ];
    base['blocks'] = blocks;
    if (read != null) base.addAll(read.unknownDocumentFields);
    return base;
  }

  /// 规范深度相等：双方 canonical 写回（不含 read 上下文）后逐字段比对。
  static bool deepEquals(SmartLayoutDocument a, SmartLayoutDocument b) {
    return _deepEq(_canonical(writeJson(a)), _canonical(writeJson(b)));
  }

  static Map<String, Object?> _normalizeBlockJson(
    Map<String, Object?> block,
    int index,
  ) {
    if (block['id'] is String && (block['id'] as String).isNotEmpty) {
      return block;
    }
    return {...block, 'id': 'legacy-block-$index'};
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.toList()..sort();
      return {
        for (final key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List) return [for (final item in value) _canonical(item)];
    return value;
  }

  static bool _deepEq(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEq(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEq(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
