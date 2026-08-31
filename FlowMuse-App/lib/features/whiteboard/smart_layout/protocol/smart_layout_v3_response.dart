import 'smart_layout_v3_error.dart';
import 'smart_layout_v3_json_reader.dart';

/// v3 分析响应（canonical DTO）。响应不含任何 text 字段——
/// typed text 只存在于请求 exactTexts，不从模型往返。
class SmartLayoutV3Response {
  const SmartLayoutV3Response({
    required this.regions,
    required this.warnings,
    this.requestId,
  });

  factory SmartLayoutV3Response.fromJson(Object? value) {
    const r = SmartLayoutV3JsonReader();
    final root = r.rootObject(value, SmartLayoutV3JsonReader.responseRootKeys);
    r.require(root, 'protocolVersion', '');
    final version = root['protocolVersion'];
    if (version is! int || version != 3) {
      r.invalid('protocolVersion', '必须为 3');
    }
    String? requestId;
    if (root.containsKey('requestId')) {
      requestId = r.string(root, 'requestId', '');
      r.nonEmpty(requestId, 'requestId');
      if (requestId.runes.length > 128) {
        r.reject(
          SmartLayoutV3ErrorCode.limitExceeded,
          'requestId',
          'requestId 超过 128 字符',
        );
      }
    }

    final regionsJson = r.list(root, 'regions', '');
    r.limit(regionsJson.length, 128, 'regions', 'region 数');
    final regions = <SmartLayoutV3Region>[];
    for (var i = 0; i < regionsJson.length; i++) {
      final map = r.objectAt(regionsJson, i, 'regions', {
        'id',
        'role',
        'sourceIds',
        'readingOrder',
        'confidence',
        'relations',
      });
      r.require(map, 'id', 'regions[$i]');
      final id = r.string(map, 'id', 'regions[$i]');
      r.nonEmpty(id, 'regions[$i].id');
      final role = r.enumValue(
        map['role'],
        'regions[$i].role',
        SmartLayoutV3Role.byWire,
        'role',
      );
      r.require(map, 'sourceIds', 'regions[$i]');
      final sourceIdsJson = r.list(map, 'sourceIds', 'regions[$i]');
      r.nonEmptyList(sourceIdsJson, 'regions[$i].sourceIds');
      final sourceIds = <String>[];
      for (var j = 0; j < sourceIdsJson.length; j++) {
        final sourceId = sourceIdsJson[j];
        if (sourceId is! String || sourceId.isEmpty) {
          r.invalid('regions[$i].sourceIds[$j]', '必须是非空字符串');
        }
        sourceIds.add(sourceId);
      }
      r.unique(sourceIds, 'regions[$i].sourceIds', 'sourceId');
      final readingOrder = r.nonNegativeInt(map, 'readingOrder', 'regions[$i]');
      final confidence = r.unitInterval(map, 'confidence', 'regions[$i]');
      r.require(map, 'relations', 'regions[$i]');
      final relationsJson = r.list(map, 'relations', 'regions[$i]');
      final relations = <SmartLayoutV3Relation>[];
      for (var j = 0; j < relationsJson.length; j++) {
        final relationMap = r.objectAt(
          relationsJson,
          j,
          'regions[$i].relations',
          {'type', 'targetRegionId'},
        );
        final type = r.enumValue(
          relationMap['type'],
          'regions[$i].relations[$j].type',
          SmartLayoutV3RelationType.byWire,
          'relation type',
        );
        r.require(relationMap, 'targetRegionId', 'regions[$i].relations[$j]');
        final target = r.string(
          relationMap,
          'targetRegionId',
          'regions[$i].relations[$j]',
        );
        relations.add(
          SmartLayoutV3Relation(type: type, targetRegionId: target),
        );
      }
      regions.add(
        SmartLayoutV3Region(
          id: id,
          role: role,
          sourceIds: List.unmodifiable(sourceIds),
          readingOrder: readingOrder,
          confidence: confidence,
          relations: List.unmodifiable(relations),
        ),
      );
    }
    r.unique(regions.map((region) => region.id), 'regions', 'region id');

    final idSet = regions.map((region) => region.id).toSet();
    for (var i = 0; i < regions.length; i++) {
      final relations = regions[i].relations;
      for (var j = 0; j < relations.length; j++) {
        if (!idSet.contains(relations[j].targetRegionId)) {
          r.reject(
            SmartLayoutV3ErrorCode.danglingReference,
            'regions[$i].relations[$j].targetRegionId',
            'relation 引用了未声明 region: ${relations[j].targetRegionId}',
          );
        }
      }
    }
    _rejectCycle(regions, r);

    final warningsJson = r.list(root, 'warnings', '');
    r.limit(warningsJson.length, 16, 'warnings', 'warning 数');
    final warnings = <String>[];
    for (var i = 0; i < warningsJson.length; i++) {
      final warning = warningsJson[i];
      if (warning is! String) {
        r.invalid('warnings[$i]', '必须是字符串');
      }
      if (warning.runes.length > 500) {
        r.reject(
          SmartLayoutV3ErrorCode.limitExceeded,
          'warnings[$i]',
          'warning 超过 500 字符',
        );
      }
      warnings.add(warning);
    }

    return SmartLayoutV3Response(
      requestId: requestId,
      regions: List.unmodifiable(regions),
      warnings: List.unmodifiable(warnings),
    );
  }

  final String? requestId;
  final List<SmartLayoutV3Region> regions;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
    'protocolVersion': 3,
    if (requestId != null) 'requestId': requestId,
    'regions': [
      for (final region in regions)
        {
          'id': region.id,
          'role': region.role.wireName,
          'sourceIds': [...region.sourceIds],
          'readingOrder': region.readingOrder,
          'confidence': region.confidence,
          'relations': [
            for (final relation in region.relations)
              {
                'type': relation.type.wireName,
                'targetRegionId': relation.targetRegionId,
              },
          ],
        },
    ],
    'warnings': [...warnings],
  };

  @override
  bool operator ==(Object other) =>
      other is SmartLayoutV3Response &&
      other.requestId == requestId &&
      _listEq(other.regions, regions) &&
      _listEq(other.warnings, warnings);

  @override
  int get hashCode => requestId.hashCode;

  @override
  String toString() =>
      'SmartLayoutV3Response(${requestId ?? '-'}, regions: ${regions.length})';
}

/// 关系链成环检测（DFS 三色标记，确定性）。
void _rejectCycle(
  List<SmartLayoutV3Region> regions,
  SmartLayoutV3JsonReader r,
) {
  final edges = <String, List<String>>{
    for (final region in regions)
      region.id: [
        for (final relation in region.relations) relation.targetRegionId,
      ],
  };
  const visiting = 1;
  const done = 2;
  final state = <String, int>{};
  final stack = <String>[];

  bool dfs(String id) {
    final mark = state[id];
    if (mark == done) return false;
    if (mark == visiting) {
      final cycleStart = stack.indexOf(id);
      r.reject(
        SmartLayoutV3ErrorCode.referenceCycle,
        'regions',
        '关系链成环: ${stack.skip(cycleStart).join('->')}->$id',
      );
    }
    state[id] = visiting;
    stack.add(id);
    for (final next in edges[id] ?? const <String>[]) {
      if (dfs(next)) return true;
    }
    stack.removeLast();
    state[id] = done;
    return false;
  }

  for (final id in edges.keys) {
    dfs(id);
  }
}

bool _listEq(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

enum SmartLayoutV3Role {
  title('title'),
  body('body'),
  caption('caption'),
  figure('figure'),
  formula('formula'),
  list('list'),
  table('table'),
  unknown('unknown');

  const SmartLayoutV3Role(this.wireName);

  final String wireName;

  static final Map<String, SmartLayoutV3Role> byWire = {
    for (final role in SmartLayoutV3Role.values) role.wireName: role,
  };
}

enum SmartLayoutV3RelationType {
  captionOf('captionOf'),
  boundTo('boundTo'),
  sameColumn('sameColumn');

  const SmartLayoutV3RelationType(this.wireName);

  final String wireName;

  static final Map<String, SmartLayoutV3RelationType> byWire = {
    for (final type in SmartLayoutV3RelationType.values) type.wireName: type,
  };
}

class SmartLayoutV3Region {
  const SmartLayoutV3Region({
    required this.id,
    required this.role,
    required this.sourceIds,
    required this.readingOrder,
    required this.confidence,
    required this.relations,
  });

  final String id;
  final SmartLayoutV3Role role;
  final List<String> sourceIds;
  final int readingOrder;
  final double confidence;
  final List<SmartLayoutV3Relation> relations;

  @override
  bool operator ==(Object other) =>
      other is SmartLayoutV3Region &&
      other.id == id &&
      other.role == role &&
      _listEq(other.sourceIds, sourceIds) &&
      other.readingOrder == readingOrder &&
      other.confidence == confidence &&
      _listEq(other.relations, relations);

  @override
  int get hashCode => id.hashCode;
}

class SmartLayoutV3Relation {
  const SmartLayoutV3Relation({
    required this.type,
    required this.targetRegionId,
  });

  final SmartLayoutV3RelationType type;
  final String targetRegionId;

  @override
  bool operator ==(Object other) =>
      other is SmartLayoutV3Relation &&
      other.type == type &&
      other.targetRegionId == targetRegionId;

  @override
  int get hashCode => Object.hash(type, targetRegionId);
}
