/// 独立识别链路 wire DTO（spec §3）。
///
/// - 请求侧 fromJson 供客户端发送前自检与双端 conformance fixtures 消费，
///   违规按 400 口径抛（invalidSchema/duplicateId/limitExceeded/textTooLong/
///   badGeometry）。
/// - 响应侧 fromJson 供回岸解析（可携带 [RecognitionResponse.expectedFor]
///   请求做覆盖/回填比对），上游非法输出统一 invalidProviderResponse（502）。
///
/// 命名空间（spec §1）：ink 单元 unitId=`ink:<regionId>`，原生/保留单元
/// `native:<sourceId>`。Scene id 无字符约束（可能本身以 `r:` 开头），
/// 两类 unitId 依字符串全等区分，禁止用 `r:` 前缀嗅探类别。
library;

import 'recognition_json_reader.dart';

const String recognitionSchemaVersion = 'recognition-v3/1';

/// 单图 base64 上限（Base64 为 ASCII，码元数=字节数）。
const int recognitionMaxImageBase64Chars = 3 * 1024 * 1024;

enum RecognitionStage {
  read('read'),
  verify('verify'),
  structure('structure');

  const RecognitionStage(this.wireName);

  final String wireName;

  static final Map<String, RecognitionStage> byWire = {
    for (final stage in RecognitionStage.values) stage.wireName: stage,
  };
}

enum RecognitionVerifyReason {
  lowConfidence('lowConfidence'),
  suspectedMiss('suspectedMiss'),
  maybeNonText('maybeNonText'),
  brokenNumbering('brokenNumbering'),
  shapeMismatch('shapeMismatch');

  const RecognitionVerifyReason(this.wireName);

  final String wireName;

  static final Map<String, RecognitionVerifyReason> byWire = {
    for (final reason in RecognitionVerifyReason.values)
      reason.wireName: reason,
  };
}

enum RecognitionUnitKind {
  typed('typed'),
  ink('ink'),
  figure('figure'),
  preserved('preserved');

  const RecognitionUnitKind(this.wireName);

  final String wireName;

  static final Map<String, RecognitionUnitKind> byWire = {
    for (final kind in RecognitionUnitKind.values) kind.wireName: kind,
  };
}

enum RecognitionRoleHint {
  title('title'),
  body('body'),
  caption('caption'),
  listItem('listItem');

  const RecognitionRoleHint(this.wireName);

  final String wireName;

  static final Map<String, RecognitionRoleHint> byWire = {
    for (final hint in RecognitionRoleHint.values) hint.wireName: hint,
  };
}

enum RecognitionRegionStatus {
  recognized('recognized'),
  uncertain('uncertain'),
  unreadable('unreadable'),
  nonText('nonText');

  const RecognitionRegionStatus(this.wireName);

  final String wireName;

  static final Map<String, RecognitionRegionStatus> byWire = {
    for (final status in RecognitionRegionStatus.values)
      status.wireName: status,
  };
}

/// structure 响应角色（spec §3.4；映射到 SemanticRole 见 semantic_adapter，
/// 此处只做 wire 校验）。
enum RecognitionStructureRole {
  title('title'),
  body('body'),
  caption('caption'),
  listItem('listItem'),
  other('other');

  const RecognitionStructureRole(this.wireName);

  final String wireName;

  static final Map<String, RecognitionStructureRole> byWire = {
    for (final role in RecognitionStructureRole.values) role.wireName: role,
  };
}

enum RecognitionListType {
  ordered('ordered'),
  unordered('unordered');

  const RecognitionListType(this.wireName);

  final String wireName;

  static final Map<String, RecognitionListType> byWire = {
    for (final type in RecognitionListType.values) type.wireName: type,
  };
}

class RecognitionSceneRevision {
  const RecognitionSceneRevision({
    required this.epoch,
    required this.revision,
    required this.fingerprint,
  });

  final int epoch;
  final int revision;
  final String fingerprint;

  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'revision': revision,
    'fingerprint': fingerprint,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionSceneRevision &&
      other.epoch == epoch &&
      other.revision == revision &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(epoch, revision, fingerprint);

  @override
  String toString() =>
      'RecognitionSceneRevision($epoch/$revision/$fingerprint)';
}

// ---------------------------------------------------------------------------
// 请求
// ---------------------------------------------------------------------------

const Set<String> _requestCommonKeys = {
  'schemaVersion',
  'stage',
  'operationId',
  'requestId',
  'pageId',
  'sceneRevision',
  'contentFingerprint',
  'generation',
};

const Set<String> _readRequestKeys = {..._requestCommonKeys, 'regions'};

const Set<String> _structureRequestKeys = {
  ..._requestCommonKeys,
  'units',
  'overviewPngBase64',
  'textFingerprint',
};

sealed class RecognitionRequest {
  const RecognitionRequest({
    required this.stage,
    required this.operationId,
    required this.requestId,
    required this.pageId,
    required this.sceneRevision,
    required this.contentFingerprint,
    required this.generation,
  });

  /// 严格解析 + 发送前自检（spec §3.6 请求侧）。
  static RecognitionRequest fromJson(Object? value) {
    const r = RecognitionJsonReader(RecognitionParseSide.request);
    final root = r.rootObject(
      value,
      _readRequestKeys.union(_structureRequestKeys),
    );
    r.require(root, 'schemaVersion', '');
    final schema = root['schemaVersion'];
    if (schema is! String || schema != recognitionSchemaVersion) {
      r.invalid('schemaVersion', '必须为 $recognitionSchemaVersion');
    }
    r.require(root, 'stage', '');
    final stage = r.enumValue(
      root['stage'],
      'stage',
      RecognitionStage.byWire,
      'stage',
    );
    _ensureStageKeys(r, root, stage);
    r.require(root, 'operationId', '');
    final operationId = r.string(root, 'operationId', '');
    r.nonEmpty(operationId, 'operationId');
    r.idLimit(operationId, 64, 'operationId', 'operationId');
    r.require(root, 'requestId', '');
    final requestId = r.string(root, 'requestId', '');
    r.nonEmpty(requestId, 'requestId');
    r.idLimit(requestId, 128, 'requestId', 'requestId');
    r.require(root, 'pageId', '');
    final pageId = r.string(root, 'pageId', '');
    r.nonEmpty(pageId, 'pageId');
    r.idLimit(pageId, 128, 'pageId', 'pageId');
    r.require(root, 'sceneRevision', '');
    final revisionMap = r.object(root['sceneRevision'], 'sceneRevision', const {
      'epoch',
      'revision',
      'fingerprint',
    });
    final epoch = r.nonNegativeInt(revisionMap, 'epoch', 'sceneRevision');
    final revision = r.nonNegativeInt(revisionMap, 'revision', 'sceneRevision');
    final revisionFingerprint = r.string(
      revisionMap,
      'fingerprint',
      'sceneRevision',
    );
    r.nonEmpty(revisionFingerprint, 'sceneRevision.fingerprint');
    r.idLimit(
      revisionFingerprint,
      64,
      'sceneRevision.fingerprint',
      'fingerprint',
    );
    r.require(root, 'contentFingerprint', '');
    final contentFingerprint = r.string(root, 'contentFingerprint', '');
    r.nonEmpty(contentFingerprint, 'contentFingerprint');
    r.idLimit(
      contentFingerprint,
      64,
      'contentFingerprint',
      'contentFingerprint',
    );
    r.require(root, 'generation', '');
    final generation = r.nonNegativeInt(root, 'generation', '');

    switch (stage) {
      case RecognitionStage.read:
        return RecognitionReadRequest(
          operationId: operationId,
          requestId: requestId,
          pageId: pageId,
          sceneRevision: RecognitionSceneRevision(
            epoch: epoch,
            revision: revision,
            fingerprint: revisionFingerprint,
          ),
          contentFingerprint: contentFingerprint,
          generation: generation,
          regions: _parseRegionImages(r, root['regions']),
        );
      case RecognitionStage.verify:
        return RecognitionVerifyRequest(
          operationId: operationId,
          requestId: requestId,
          pageId: pageId,
          sceneRevision: RecognitionSceneRevision(
            epoch: epoch,
            revision: revision,
            fingerprint: revisionFingerprint,
          ),
          contentFingerprint: contentFingerprint,
          generation: generation,
          regions: _parseVerifyRegions(r, root['regions']),
        );
      case RecognitionStage.structure:
        return _parseStructureRequest(
          r,
          root,
          operationId: operationId,
          requestId: requestId,
          pageId: pageId,
          epoch: epoch,
          revision: revision,
          revisionFingerprint: revisionFingerprint,
          contentFingerprint: contentFingerprint,
          generation: generation,
        );
    }
  }

  final RecognitionStage stage;
  final String operationId;
  final String requestId;
  final String pageId;
  final RecognitionSceneRevision sceneRevision;
  final String contentFingerprint;
  final int generation;

  Map<String, Object?> toJson() => {
    'schemaVersion': recognitionSchemaVersion,
    'stage': stage.wireName,
    'operationId': operationId,
    'requestId': requestId,
    'pageId': pageId,
    'sceneRevision': sceneRevision.toJson(),
    'contentFingerprint': contentFingerprint,
    'generation': generation,
    ...stageJson(),
  };

  Map<String, Object?> stageJson();

  @override
  bool operator ==(Object other) =>
      other is RecognitionRequest &&
      other.stage == stage &&
      other.operationId == operationId &&
      other.requestId == requestId &&
      other.pageId == pageId &&
      other.sceneRevision == sceneRevision &&
      other.contentFingerprint == contentFingerprint &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(stage, operationId, requestId, pageId);

  static void _ensureStageKeys(
    RecognitionJsonReader r,
    Map<String, Object?> root,
    RecognitionStage stage,
  ) {
    final allowed = stage == RecognitionStage.structure
        ? _structureRequestKeys
        : _readRequestKeys;
    for (final key in root.keys) {
      if (!allowed.contains(key)) {
        r.unknownField(key);
      }
    }
  }
}

/// read 请求的区域图（verify 区域复用同构字段，见
/// [RecognitionVerifyRegion]）。
class RecognitionRegionImage {
  const RecognitionRegionImage({
    required this.regionId,
    required this.imagePngBase64,
    required this.imageScale,
    this.contextBefore,
    this.contextAfter,
  });

  final String regionId;
  final String imagePngBase64;
  final double imageScale;
  final String? contextBefore;
  final String? contextAfter;

  Map<String, Object?> toJson() => {
    'regionId': regionId,
    'imagePngBase64': imagePngBase64,
    'imageScale': imageScale,
    if (contextBefore != null) 'contextBefore': contextBefore,
    if (contextAfter != null) 'contextAfter': contextAfter,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionRegionImage &&
      other.regionId == regionId &&
      other.imagePngBase64 == imagePngBase64 &&
      other.imageScale == imageScale &&
      other.contextBefore == contextBefore &&
      other.contextAfter == contextAfter;

  @override
  int get hashCode => Object.hash(
    regionId,
    imagePngBase64,
    imageScale,
    contextBefore,
    contextAfter,
  );
}

class RecognitionReadRequest extends RecognitionRequest {
  const RecognitionReadRequest({
    required super.operationId,
    required super.requestId,
    required super.pageId,
    required super.sceneRevision,
    required super.contentFingerprint,
    required super.generation,
    required this.regions,
  }) : super(stage: RecognitionStage.read);

  final List<RecognitionRegionImage> regions;

  @override
  Map<String, Object?> stageJson() => {
    'regions': [for (final region in regions) region.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionReadRequest &&
      super == other &&
      _listEq(other.regions, regions);

  @override
  int get hashCode => Object.hash(super.hashCode, regions.length);

  @override
  String toString() =>
      'RecognitionReadRequest($operationId, regions: ${regions.length})';
}

class RecognitionVerifyRegion {
  const RecognitionVerifyRegion({
    required this.regionId,
    required this.imagePngBase64,
    required this.imageScale,
    required this.reason,
    this.contextBefore,
    this.contextAfter,
    this.originalText,
    this.originalConfidence,
  });

  final String regionId;
  final String imagePngBase64;
  final double imageScale;
  final String? contextBefore;
  final String? contextAfter;
  final String? originalText;
  final double? originalConfidence;
  final RecognitionVerifyReason reason;

  Map<String, Object?> toJson() => {
    'regionId': regionId,
    'imagePngBase64': imagePngBase64,
    'imageScale': imageScale,
    if (contextBefore != null) 'contextBefore': contextBefore,
    if (contextAfter != null) 'contextAfter': contextAfter,
    if (originalText != null) 'originalText': originalText,
    if (originalConfidence != null) 'originalConfidence': originalConfidence,
    'reason': reason.wireName,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionVerifyRegion &&
      other.regionId == regionId &&
      other.imagePngBase64 == imagePngBase64 &&
      other.imageScale == imageScale &&
      other.contextBefore == contextBefore &&
      other.contextAfter == contextAfter &&
      other.originalText == originalText &&
      other.originalConfidence == originalConfidence &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(regionId, imagePngBase64, imageScale, reason);
}

class RecognitionVerifyRequest extends RecognitionRequest {
  const RecognitionVerifyRequest({
    required super.operationId,
    required super.requestId,
    required super.pageId,
    required super.sceneRevision,
    required super.contentFingerprint,
    required super.generation,
    required this.regions,
  }) : super(stage: RecognitionStage.verify);

  final List<RecognitionVerifyRegion> regions;

  @override
  Map<String, Object?> stageJson() => {
    'regions': [for (final region in regions) region.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionVerifyRequest &&
      super == other &&
      _listEq(other.regions, regions);

  @override
  int get hashCode => Object.hash(super.hashCode, regions.length);

  @override
  String toString() =>
      'RecognitionVerifyRequest($operationId, regions: ${regions.length})';
}

class RecognitionBounds {
  const RecognitionBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, Object?> toJson() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionBounds &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'RecognitionBounds($left,$top ${width}x$height)';
}

class RecognitionUnitInput {
  const RecognitionUnitInput({
    required this.unitId,
    required this.kind,
    required this.bounds,
    this.text,
    this.lineHintHeight,
    this.roleHint,
  });

  final String unitId;
  final RecognitionUnitKind kind;
  final String? text;
  final RecognitionBounds bounds;
  final double? lineHintHeight;
  final RecognitionRoleHint? roleHint;

  Map<String, Object?> toJson() => {
    'unitId': unitId,
    'kind': kind.wireName,
    if (text != null) 'text': text,
    'bounds': bounds.toJson(),
    if (lineHintHeight != null) 'lineHintHeight': lineHintHeight,
    if (roleHint != null) 'roleHint': roleHint!.wireName,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionUnitInput &&
      other.unitId == unitId &&
      other.kind == kind &&
      other.text == text &&
      other.bounds == bounds &&
      other.lineHintHeight == lineHintHeight &&
      other.roleHint == roleHint;

  @override
  int get hashCode => Object.hash(unitId, kind, bounds);

  bool get isTextUnit =>
      kind == RecognitionUnitKind.typed || kind == RecognitionUnitKind.ink;
}

class RecognitionStructureRequest extends RecognitionRequest {
  const RecognitionStructureRequest({
    required super.operationId,
    required super.requestId,
    required super.pageId,
    required super.sceneRevision,
    required super.contentFingerprint,
    required super.generation,
    required this.units,
    required this.textFingerprint,
    this.overviewPngBase64,
  }) : super(stage: RecognitionStage.structure);

  final List<RecognitionUnitInput> units;
  final String? overviewPngBase64;
  final String textFingerprint;

  @override
  Map<String, Object?> stageJson() => {
    'units': [for (final unit in units) unit.toJson()],
    if (overviewPngBase64 != null) 'overviewPngBase64': overviewPngBase64,
    'textFingerprint': textFingerprint,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionStructureRequest &&
      super == other &&
      _listEq(other.units, units) &&
      other.overviewPngBase64 == overviewPngBase64 &&
      other.textFingerprint == textFingerprint;

  @override
  int get hashCode =>
      Object.hash(super.hashCode, units.length, textFingerprint);

  @override
  String toString() =>
      'RecognitionStructureRequest($operationId, units: ${units.length})';
}

List<RecognitionRegionImage> _parseRegionImages(
  RecognitionJsonReader r,
  Object? regionsJson,
) {
  if (regionsJson is! List) {
    r.invalid('regions', 'regions 必须是数组');
  }
  // R-11：空批与超上限均为请求侧违规。
  r.nonEmptyList(regionsJson, 'regions');
  r.limit(regionsJson.length, 8, 'regions', 'regions 数');
  final regions = <RecognitionRegionImage>[];
  for (var i = 0; i < regionsJson.length; i++) {
    final map = r.objectAt(regionsJson, i, 'regions', const {
      'regionId',
      'imagePngBase64',
      'imageScale',
      'contextBefore',
      'contextAfter',
    });
    r.require(map, 'regionId', 'regions[$i]');
    final regionId = r.string(map, 'regionId', 'regions[$i]');
    r.nonEmpty(regionId, 'regions[$i].regionId');
    r.idLimit(regionId, 64, 'regions[$i].regionId', 'regionId');
    r.require(map, 'imagePngBase64', 'regions[$i]');
    final image = r.string(map, 'imagePngBase64', 'regions[$i]');
    r.nonEmpty(image, 'regions[$i].imagePngBase64');
    if (image.length > recognitionMaxImageBase64Chars) {
      r.reject(
        RecognitionExceptionCode.limitExceeded,
        'regions[$i].imagePngBase64',
        '单图 base64 超过 3MiB',
      );
    }
    r.require(map, 'imageScale', 'regions[$i]');
    final scale = r.positiveFiniteDouble(map, 'imageScale', 'regions[$i]');
    String? contextBefore;
    if (map.containsKey('contextBefore')) {
      contextBefore = r.string(map, 'contextBefore', 'regions[$i]');
      r.textLimit(
        contextBefore,
        200,
        'regions[$i].contextBefore',
        'contextBefore',
      );
    }
    String? contextAfter;
    if (map.containsKey('contextAfter')) {
      contextAfter = r.string(map, 'contextAfter', 'regions[$i]');
      r.textLimit(
        contextAfter,
        200,
        'regions[$i].contextAfter',
        'contextAfter',
      );
    }
    regions.add(
      RecognitionRegionImage(
        regionId: regionId,
        imagePngBase64: image,
        imageScale: scale,
        contextBefore: contextBefore,
        contextAfter: contextAfter,
      ),
    );
  }
  r.unique(regions.map((region) => region.regionId), 'regions', 'regionId');
  return List.unmodifiable(regions);
}

List<RecognitionVerifyRegion> _parseVerifyRegions(
  RecognitionJsonReader r,
  Object? regionsJson,
) {
  if (regionsJson is! List) {
    r.invalid('regions', 'regions 必须是数组');
  }
  r.nonEmptyList(regionsJson, 'regions');
  r.limit(regionsJson.length, 8, 'regions', 'regions 数');
  final regions = <RecognitionVerifyRegion>[];
  for (var i = 0; i < regionsJson.length; i++) {
    final map = r.objectAt(regionsJson, i, 'regions', const {
      'regionId',
      'imagePngBase64',
      'imageScale',
      'contextBefore',
      'contextAfter',
      'originalText',
      'originalConfidence',
      'reason',
    });
    r.require(map, 'regionId', 'regions[$i]');
    final regionId = r.string(map, 'regionId', 'regions[$i]');
    r.nonEmpty(regionId, 'regions[$i].regionId');
    r.idLimit(regionId, 64, 'regions[$i].regionId', 'regionId');
    r.require(map, 'imagePngBase64', 'regions[$i]');
    final image = r.string(map, 'imagePngBase64', 'regions[$i]');
    r.nonEmpty(image, 'regions[$i].imagePngBase64');
    if (image.length > recognitionMaxImageBase64Chars) {
      r.reject(
        RecognitionExceptionCode.limitExceeded,
        'regions[$i].imagePngBase64',
        '单图 base64 超过 3MiB',
      );
    }
    r.require(map, 'imageScale', 'regions[$i]');
    final scale = r.positiveFiniteDouble(map, 'imageScale', 'regions[$i]');
    String? contextBefore;
    if (map.containsKey('contextBefore')) {
      contextBefore = r.string(map, 'contextBefore', 'regions[$i]');
      r.textLimit(
        contextBefore,
        200,
        'regions[$i].contextBefore',
        'contextBefore',
      );
    }
    String? contextAfter;
    if (map.containsKey('contextAfter')) {
      contextAfter = r.string(map, 'contextAfter', 'regions[$i]');
      r.textLimit(
        contextAfter,
        200,
        'regions[$i].contextAfter',
        'contextAfter',
      );
    }
    String? originalText;
    if (map.containsKey('originalText')) {
      originalText = r.string(map, 'originalText', 'regions[$i]');
      r.textLimit(
        originalText,
        2000,
        'regions[$i].originalText',
        'originalText',
      );
    }
    double? originalConfidence;
    if (map.containsKey('originalConfidence')) {
      originalConfidence = r.unitInterval(
        map,
        'originalConfidence',
        'regions[$i]',
      );
    }
    r.require(map, 'reason', 'regions[$i]');
    final reason = r.enumValue(
      map['reason'],
      'regions[$i].reason',
      RecognitionVerifyReason.byWire,
      'reason',
    );
    regions.add(
      RecognitionVerifyRegion(
        regionId: regionId,
        imagePngBase64: image,
        imageScale: scale,
        contextBefore: contextBefore,
        contextAfter: contextAfter,
        originalText: originalText,
        originalConfidence: originalConfidence,
        reason: reason,
      ),
    );
  }
  r.unique(regions.map((region) => region.regionId), 'regions', 'regionId');
  return List.unmodifiable(regions);
}

RecognitionStructureRequest _parseStructureRequest(
  RecognitionJsonReader r,
  Map<String, Object?> root, {
  required String operationId,
  required String requestId,
  required String pageId,
  required int epoch,
  required int revision,
  required String revisionFingerprint,
  required String contentFingerprint,
  required int generation,
}) {
  final unitsJson = r.list(root, 'units', '');
  r.nonEmptyList(unitsJson, 'units');
  r.limit(unitsJson.length, 128, 'units', 'units 数');
  final units = <RecognitionUnitInput>[];
  for (var i = 0; i < unitsJson.length; i++) {
    final map = r.objectAt(unitsJson, i, 'units', const {
      'unitId',
      'kind',
      'text',
      'bounds',
      'lineHintHeight',
      'roleHint',
    });
    r.require(map, 'unitId', 'units[$i]');
    final unitId = r.string(map, 'unitId', 'units[$i]');
    r.nonEmpty(unitId, 'units[$i].unitId');
    r.idLimit(unitId, 64, 'units[$i].unitId', 'unitId');
    r.require(map, 'kind', 'units[$i]');
    final kind = r.enumValue(
      map['kind'],
      'units[$i].kind',
      RecognitionUnitKind.byWire,
      'unit kind',
    );
    String? text;
    if (map.containsKey('text')) {
      final raw = r.string(map, 'text', 'units[$i]');
      r.textLimit(raw, 2000, 'units[$i].text', 'text');
      if (raw.isNotEmpty) {
        text = raw;
      }
    }
    final isTextUnit =
        kind == RecognitionUnitKind.typed || kind == RecognitionUnitKind.ink;
    if (isTextUnit) {
      if (text == null) {
        r.invalid('units[$i].text', 'typed/ink 单元 text 必须非空');
      }
    } else if (text != null) {
      r.invalid('units[$i].text', 'figure/preserved 单元 text 必须缺省或空');
    }
    r.require(map, 'bounds', 'units[$i]');
    final bounds = _parseBounds(r, map['bounds'], 'units[$i].bounds');
    double? lineHintHeight;
    if (map.containsKey('lineHintHeight')) {
      lineHintHeight = r.positiveFiniteDouble(
        map,
        'lineHintHeight',
        'units[$i]',
      );
    }
    RecognitionRoleHint? roleHint;
    if (map.containsKey('roleHint')) {
      roleHint = r.enumValue(
        map['roleHint'],
        'units[$i].roleHint',
        RecognitionRoleHint.byWire,
        'roleHint',
      );
    }
    units.add(
      RecognitionUnitInput(
        unitId: unitId,
        kind: kind,
        text: text,
        bounds: bounds,
        lineHintHeight: lineHintHeight,
        roleHint: roleHint,
      ),
    );
  }
  r.unique(units.map((unit) => unit.unitId), 'units', 'unitId');
  String? overviewPngBase64;
  if (root.containsKey('overviewPngBase64')) {
    overviewPngBase64 = r.string(root, 'overviewPngBase64', '');
    r.nonEmpty(overviewPngBase64, 'overviewPngBase64');
    if (overviewPngBase64.length > recognitionMaxImageBase64Chars) {
      r.reject(
        RecognitionExceptionCode.limitExceeded,
        'overviewPngBase64',
        '单图 base64 超过 3MiB',
      );
    }
  }
  r.require(root, 'textFingerprint', '');
  final textFingerprint = r.string(root, 'textFingerprint', '');
  r.nonEmpty(textFingerprint, 'textFingerprint');
  r.idLimit(textFingerprint, 64, 'textFingerprint', 'textFingerprint');
  return RecognitionStructureRequest(
    operationId: operationId,
    requestId: requestId,
    pageId: pageId,
    sceneRevision: RecognitionSceneRevision(
      epoch: epoch,
      revision: revision,
      fingerprint: revisionFingerprint,
    ),
    contentFingerprint: contentFingerprint,
    generation: generation,
    units: List.unmodifiable(units),
    overviewPngBase64: overviewPngBase64,
    textFingerprint: textFingerprint,
  );
}

RecognitionBounds _parseBounds(
  RecognitionJsonReader r,
  Object? value,
  String field,
) {
  final map = r.object(value, field, const {'left', 'top', 'width', 'height'});
  double axis(String key) {
    final raw = map[key];
    if (raw is! num || !raw.isFinite) {
      r.reject(
        RecognitionExceptionCode.badGeometry,
        '$field.$key',
        '$key 必须是有限数',
      );
    }
    return raw.toDouble();
  }

  final left = axis('left');
  final top = axis('top');
  final width = axis('width');
  final height = axis('height');
  if (width < 0 || height < 0) {
    r.reject(RecognitionExceptionCode.badGeometry, field, '宽高不得为负');
  }
  return RecognitionBounds(left: left, top: top, width: width, height: height);
}

// ---------------------------------------------------------------------------
// 响应
// ---------------------------------------------------------------------------

const Set<String> _batchResponseKeys = {
  ..._responseCommonKeys,
  'regions',
  'missingRegionIds',
};

const Set<String> _responseCommonKeys = {
  'schemaVersion',
  'stage',
  'operationId',
  'requestId',
  'pageId',
  'sceneRevision',
  'contentFingerprint',
  'generation',
};

const Set<String> _structureResponseKeys = {
  ..._responseCommonKeys,
  'textFingerprint',
  'readingOrder',
  'roles',
  'listGroups',
  'captions',
  'warnings',
};

sealed class RecognitionResponse {
  const RecognitionResponse({
    required this.stage,
    required this.operationId,
    required this.requestId,
    required this.pageId,
    required this.sceneRevision,
    required this.contentFingerprint,
    required this.generation,
  });

  /// 严格解析（spec §3.6 响应侧双保险）。提供 [expectedFor] 时执行
  /// R-02/R-04/R-06/R-07/R-12 的请求上下文校验；未提供时仅做自包含校验
  /// （R-03/R-05/R-08/R-09/R-10 与结构自洽）。
  static RecognitionResponse fromJson(
    Object? value, {
    RecognitionRequest? expectedFor,
  }) {
    const r = RecognitionJsonReader(RecognitionParseSide.response);
    final root = r.rootObject(
      value,
      _batchResponseKeys.union(_structureResponseKeys),
    );
    r.require(root, 'schemaVersion', '');
    final schema = root['schemaVersion'];
    if (schema is! String || schema != recognitionSchemaVersion) {
      r.invalid('schemaVersion', '必须为 $recognitionSchemaVersion');
    }
    r.require(root, 'stage', '');
    final stage = r.enumValue(
      root['stage'],
      'stage',
      RecognitionStage.byWire,
      'stage',
    );
    final allowedKeys = stage == RecognitionStage.structure
        ? _structureResponseKeys
        : _batchResponseKeys;
    for (final key in root.keys) {
      if (!allowedKeys.contains(key)) {
        r.unknownField(key);
      }
    }
    r.require(root, 'operationId', '');
    final operationId = r.string(root, 'operationId', '');
    r.require(root, 'requestId', '');
    final requestId = r.string(root, 'requestId', '');
    r.require(root, 'pageId', '');
    final pageId = r.string(root, 'pageId', '');
    r.require(root, 'sceneRevision', '');
    final revisionMap = r.object(root['sceneRevision'], 'sceneRevision', const {
      'epoch',
      'revision',
      'fingerprint',
    });
    final epoch = r.nonNegativeInt(revisionMap, 'epoch', 'sceneRevision');
    final revision = r.nonNegativeInt(revisionMap, 'revision', 'sceneRevision');
    final revisionFingerprint = r.string(
      revisionMap,
      'fingerprint',
      'sceneRevision',
    );
    r.require(root, 'contentFingerprint', '');
    final contentFingerprint = r.string(root, 'contentFingerprint', '');
    r.require(root, 'generation', '');
    final generation = r.nonNegativeInt(root, 'generation', '');

    // R-12：回填字段与请求逐项一致（外壳由服务端回填，不依赖模型回显）。
    if (expectedFor != null) {
      if (expectedFor.stage != stage) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'stage',
          '响应 stage 与请求不一致',
        );
      }
      if (expectedFor.operationId != operationId ||
          expectedFor.requestId != requestId ||
          expectedFor.pageId != pageId ||
          expectedFor.generation != generation ||
          expectedFor.contentFingerprint != contentFingerprint ||
          expectedFor.sceneRevision.epoch != epoch ||
          expectedFor.sceneRevision.revision != revision ||
          expectedFor.sceneRevision.fingerprint != revisionFingerprint) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'operationId',
          '回填字段与请求不一致（过期响应）',
        );
      }
    }

    switch (stage) {
      case RecognitionStage.read:
      case RecognitionStage.verify:
        return _parseBatchResponse(
          r,
          root,
          stage: stage,
          operationId: operationId,
          requestId: requestId,
          pageId: pageId,
          epoch: epoch,
          revision: revision,
          revisionFingerprint: revisionFingerprint,
          contentFingerprint: contentFingerprint,
          generation: generation,
          expectedFor: expectedFor,
        );
      case RecognitionStage.structure:
        return _parseStructureResponse(
          r,
          root,
          operationId: operationId,
          requestId: requestId,
          pageId: pageId,
          epoch: epoch,
          revision: revision,
          revisionFingerprint: revisionFingerprint,
          contentFingerprint: contentFingerprint,
          generation: generation,
          expectedFor: expectedFor,
        );
    }
  }

  final RecognitionStage stage;
  final String operationId;
  final String requestId;
  final String pageId;
  final RecognitionSceneRevision sceneRevision;
  final String contentFingerprint;
  final int generation;

  Map<String, Object?> toJson() => {
    'schemaVersion': recognitionSchemaVersion,
    'stage': stage.wireName,
    'operationId': operationId,
    'requestId': requestId,
    'pageId': pageId,
    'sceneRevision': sceneRevision.toJson(),
    'contentFingerprint': contentFingerprint,
    'generation': generation,
    ...stageJson(),
  };

  Map<String, Object?> stageJson();

  @override
  bool operator ==(Object other) =>
      other is RecognitionResponse &&
      other.stage == stage &&
      other.operationId == operationId &&
      other.requestId == requestId &&
      other.pageId == pageId &&
      other.sceneRevision == sceneRevision &&
      other.contentFingerprint == contentFingerprint &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(stage, operationId, requestId, pageId);
}

class RecognizedRegion {
  const RecognizedRegion({
    required this.regionId,
    required this.status,
    this.text,
    this.confidence,
    this.diagnostics = const [],
  });

  final String regionId;
  final RecognitionRegionStatus status;
  final String? text;
  final double? confidence;
  final List<String> diagnostics;

  Map<String, Object?> toJson() => {
    'regionId': regionId,
    'status': status.wireName,
    if (text != null) 'text': text,
    if (confidence != null) 'confidence': confidence,
    'diagnostics': [...diagnostics],
  };

  @override
  bool operator ==(Object other) =>
      other is RecognizedRegion &&
      other.regionId == regionId &&
      other.status == status &&
      other.text == text &&
      other.confidence == confidence &&
      _listEq(other.diagnostics, diagnostics);

  @override
  int get hashCode => Object.hash(regionId, status, text, confidence);

  @override
  String toString() => 'RecognizedRegion($regionId, ${status.wireName})';
}

/// read/verify 共用响应形态（spec §3.3：响应同 3.2，含覆盖与部分批次规则）。
class RecognitionBatchResponse extends RecognitionResponse {
  const RecognitionBatchResponse({
    required super.stage,
    required super.operationId,
    required super.requestId,
    required super.pageId,
    required super.sceneRevision,
    required super.contentFingerprint,
    required super.generation,
    required this.regions,
    required this.missingRegionIds,
  });

  final List<RecognizedRegion> regions;
  final List<String> missingRegionIds;

  @override
  Map<String, Object?> stageJson() => {
    'regions': [for (final region in regions) region.toJson()],
    'missingRegionIds': [...missingRegionIds],
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionBatchResponse &&
      super == other &&
      _listEq(other.regions, regions) &&
      _listEq(other.missingRegionIds, missingRegionIds);

  @override
  int get hashCode => Object.hash(super.hashCode, regions.length);

  @override
  String toString() =>
      'RecognitionBatchResponse(${stage.wireName}, regions: '
      '${regions.length}, missing: ${missingRegionIds.length})';
}

class RecognitionRoleAssignment {
  const RecognitionRoleAssignment({required this.unitId, required this.role});

  final String unitId;
  final RecognitionStructureRole role;

  Map<String, Object?> toJson() => {'unitId': unitId, 'role': role.wireName};

  @override
  bool operator ==(Object other) =>
      other is RecognitionRoleAssignment &&
      other.unitId == unitId &&
      other.role == role;

  @override
  int get hashCode => Object.hash(unitId, role);

  @override
  String toString() => 'RecognitionRoleAssignment($unitId, ${role.wireName})';
}

class RecognitionListGroup {
  const RecognitionListGroup({
    required this.groupId,
    required this.members,
    required this.level,
    required this.listType,
    this.parentUnitId,
    this.startNumber,
  });

  final String groupId;
  final List<String> members;
  final int level;
  final String? parentUnitId;
  final RecognitionListType listType;
  final int? startNumber;

  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'members': [...members],
    'level': level,
    if (parentUnitId != null) 'parentUnitId': parentUnitId,
    'listType': listType.wireName,
    if (startNumber != null) 'startNumber': startNumber,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionListGroup &&
      other.groupId == groupId &&
      _listEq(other.members, members) &&
      other.level == level &&
      other.parentUnitId == parentUnitId &&
      other.listType == listType &&
      other.startNumber == startNumber;

  @override
  int get hashCode => Object.hash(groupId, level, listType);

  @override
  String toString() =>
      'RecognitionListGroup($groupId, members: ${members.length})';
}

class RecognitionCaption {
  const RecognitionCaption({
    required this.captionUnitId,
    required this.targetUnitId,
  });

  final String captionUnitId;
  final String targetUnitId;

  Map<String, Object?> toJson() => {
    'captionUnitId': captionUnitId,
    'targetUnitId': targetUnitId,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionCaption &&
      other.captionUnitId == captionUnitId &&
      other.targetUnitId == targetUnitId;

  @override
  int get hashCode => Object.hash(captionUnitId, targetUnitId);

  @override
  String toString() => 'RecognitionCaption($captionUnitId -> $targetUnitId)';
}

class RecognitionStructureResponse extends RecognitionResponse {
  const RecognitionStructureResponse({
    required super.operationId,
    required super.requestId,
    required super.pageId,
    required super.sceneRevision,
    required super.contentFingerprint,
    required super.generation,
    required this.textFingerprint,
    required this.readingOrder,
    required this.roles,
    required this.listGroups,
    required this.captions,
    required this.warnings,
  }) : super(stage: RecognitionStage.structure);

  final String textFingerprint;
  final List<String> readingOrder;
  final List<RecognitionRoleAssignment> roles;
  final List<RecognitionListGroup> listGroups;
  final List<RecognitionCaption> captions;
  final List<String> warnings;

  @override
  Map<String, Object?> stageJson() => {
    'textFingerprint': textFingerprint,
    'readingOrder': [...readingOrder],
    'roles': [for (final role in roles) role.toJson()],
    'listGroups': [for (final group in listGroups) group.toJson()],
    'captions': [for (final caption in captions) caption.toJson()],
    'warnings': [...warnings],
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionStructureResponse &&
      super == other &&
      other.textFingerprint == textFingerprint &&
      _listEq(other.readingOrder, readingOrder) &&
      _listEq(other.roles, roles) &&
      _listEq(other.listGroups, listGroups) &&
      _listEq(other.captions, captions) &&
      _listEq(other.warnings, warnings);

  @override
  int get hashCode => Object.hash(super.hashCode, textFingerprint);

  @override
  String toString() =>
      'RecognitionStructureResponse($operationId, units in order: '
      '${readingOrder.length})';
}

RecognitionBatchResponse _parseBatchResponse(
  RecognitionJsonReader r,
  Map<String, Object?> root, {
  required RecognitionStage stage,
  required String operationId,
  required String requestId,
  required String pageId,
  required int epoch,
  required int revision,
  required String revisionFingerprint,
  required String contentFingerprint,
  required int generation,
  RecognitionRequest? expectedFor,
}) {
  final regionsJson = r.list(root, 'regions', '');
  r.limit(regionsJson.length, 8, 'regions', 'regions 数');
  final regions = <RecognizedRegion>[];
  for (var i = 0; i < regionsJson.length; i++) {
    final map = r.objectAt(regionsJson, i, 'regions', const {
      'regionId',
      'status',
      'text',
      'confidence',
      'diagnostics',
    });
    r.require(map, 'regionId', 'regions[$i]');
    final regionId = r.string(map, 'regionId', 'regions[$i]');
    r.nonEmpty(regionId, 'regions[$i].regionId');
    r.idLimit(regionId, 64, 'regions[$i].regionId', 'regionId');
    r.require(map, 'status', 'regions[$i]');
    final status = r.enumValue(
      map['status'],
      'regions[$i].status',
      RecognitionRegionStatus.byWire,
      'status',
    );
    String? text;
    if (map.containsKey('text')) {
      final raw = r.string(map, 'text', 'regions[$i]');
      r.textLimit(raw, 2000, 'regions[$i].text', 'text');
      if (raw.isNotEmpty) {
        text = raw;
      }
    }
    // R-03：text 与 status 的一致性。
    final requiresText =
        status == RecognitionRegionStatus.recognized ||
        status == RecognitionRegionStatus.uncertain;
    if (requiresText && text == null) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'regions[$i].text',
        'status=${status.wireName} 必须携带非空 text',
      );
    }
    if (!requiresText && text != null) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'regions[$i].text',
        'status=${status.wireName} 必须缺省或空 text',
      );
    }
    double? confidence;
    if (map.containsKey('confidence')) {
      confidence = r.unitInterval(map, 'confidence', 'regions[$i]');
    }
    // diagnostics 可选（0..4 条，缺省=空）。
    final diagnosticsJson = map.containsKey('diagnostics')
        ? r.list(map, 'diagnostics', 'regions[$i]')
        : const <Object?>[];
    r.limit(
      diagnosticsJson.length,
      4,
      'regions[$i].diagnostics',
      'diagnostics 数',
    );
    final diagnostics = <String>[];
    for (var j = 0; j < diagnosticsJson.length; j++) {
      final entry = diagnosticsJson[j];
      if (entry is! String) {
        r.invalid('regions[$i].diagnostics[$j]', '必须是字符串');
      }
      r.textLimit(entry, 32, 'regions[$i].diagnostics[$j]', 'diagnostic');
      diagnostics.add(entry);
    }
    regions.add(
      RecognizedRegion(
        regionId: regionId,
        status: status,
        text: text,
        confidence: confidence,
        diagnostics: List.unmodifiable(diagnostics),
      ),
    );
  }
  r.unique(regions.map((region) => region.regionId), 'regions', 'regionId');

  final missingJson = r.list(root, 'missingRegionIds', '');
  r.limit(missingJson.length, 8, 'missingRegionIds', 'missingRegionIds 数');
  final missing = <String>[];
  for (var i = 0; i < missingJson.length; i++) {
    final value = missingJson[i];
    if (value is! String || value.isEmpty) {
      r.invalid('missingRegionIds[$i]', '必须是非空字符串');
    }
    missing.add(value);
  }
  r.unique(missing, 'missingRegionIds', 'missingRegionId');

  // R-04（需请求上下文）：并集恰等于请求集合、交集为空、两数组各自无重复。
  // 全部漏答（regions 空且 missing=请求全集）是合法 200；覆盖违规整批拒绝。
  if (expectedFor != null) {
    final expectedRegionIds = switch (expectedFor) {
      RecognitionReadRequest(:final regions) =>
        regions.map((region) => region.regionId).toSet(),
      RecognitionVerifyRequest(:final regions) =>
        regions.map((region) => region.regionId).toSet(),
      RecognitionStructureRequest() => <String>{},
    };
    final respondedIds = regions.map((region) => region.regionId).toSet();
    for (final id in respondedIds) {
      if (!expectedRegionIds.contains(id)) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'regions',
          '响应引用了请求外的 regionId: $id',
        );
      }
    }
    for (final id in missing) {
      if (!expectedRegionIds.contains(id)) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'missingRegionIds',
          'missingRegionIds 引用了请求外的 regionId: $id',
        );
      }
    }
    if (respondedIds.intersection(missing.toSet()).isNotEmpty) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'missingRegionIds',
        'regions 与 missingRegionIds 存在交集',
      );
    }
    final covered = respondedIds.union(missing.toSet());
    if (covered.length != expectedRegionIds.length ||
        !covered.containsAll(expectedRegionIds)) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'missingRegionIds',
        '覆盖声明不完整：regions ∪ missingRegionIds 必须恰等于请求集合',
      );
    }
  }

  return RecognitionBatchResponse(
    stage: stage,
    operationId: operationId,
    requestId: requestId,
    pageId: pageId,
    sceneRevision: RecognitionSceneRevision(
      epoch: epoch,
      revision: revision,
      fingerprint: revisionFingerprint,
    ),
    contentFingerprint: contentFingerprint,
    generation: generation,
    regions: List.unmodifiable(regions),
    missingRegionIds: List.unmodifiable(missing),
  );
}

RecognitionStructureResponse _parseStructureResponse(
  RecognitionJsonReader r,
  Map<String, Object?> root, {
  required String operationId,
  required String requestId,
  required String pageId,
  required int epoch,
  required int revision,
  required String revisionFingerprint,
  required String contentFingerprint,
  required int generation,
  RecognitionRequest? expectedFor,
}) {
  r.require(root, 'textFingerprint', '');
  final textFingerprint = r.string(root, 'textFingerprint', '');
  r.nonEmpty(textFingerprint, 'textFingerprint');
  final structureRequest = expectedFor is RecognitionStructureRequest
      ? expectedFor
      : null;
  if (structureRequest != null &&
      structureRequest.textFingerprint != textFingerprint) {
    r.reject(
      RecognitionExceptionCode.invalidProviderResponse,
      'textFingerprint',
      'textFingerprint 与请求不一致（过期响应）',
    );
  }

  final readingOrderJson = r.list(root, 'readingOrder', '');
  final readingOrder = <String>[];
  for (var i = 0; i < readingOrderJson.length; i++) {
    final value = readingOrderJson[i];
    if (value is! String || value.isEmpty) {
      r.invalid('readingOrder[$i]', '必须是非空字符串');
    }
    readingOrder.add(value);
  }
  r.unique(readingOrder, 'readingOrder', 'readingOrder unitId');

  final rolesJson = r.list(root, 'roles', '');
  final roles = <RecognitionRoleAssignment>[];
  for (var i = 0; i < rolesJson.length; i++) {
    // R-10：结构响应携带正文字段（text 等）按未知字段 → 502。
    final map = r.objectAt(rolesJson, i, 'roles', const {'unitId', 'role'});
    r.require(map, 'unitId', 'roles[$i]');
    final unitId = r.string(map, 'unitId', 'roles[$i]');
    r.nonEmpty(unitId, 'roles[$i].unitId');
    r.require(map, 'role', 'roles[$i]');
    final role = r.enumValue(
      map['role'],
      'roles[$i].role',
      RecognitionStructureRole.byWire,
      'role',
    );
    roles.add(RecognitionRoleAssignment(unitId: unitId, role: role));
  }
  r.unique(roles.map((assignment) => assignment.unitId), 'roles', 'unitId');

  final listGroupsJson = r.list(root, 'listGroups', '');
  final listGroups = <RecognitionListGroup>[];
  for (var i = 0; i < listGroupsJson.length; i++) {
    final map = r.objectAt(listGroupsJson, i, 'listGroups', const {
      'groupId',
      'members',
      'level',
      'parentUnitId',
      'listType',
      'startNumber',
    });
    r.require(map, 'groupId', 'listGroups[$i]');
    final groupId = r.string(map, 'groupId', 'listGroups[$i]');
    r.nonEmpty(groupId, 'listGroups[$i].groupId');
    r.idLimit(groupId, 16, 'listGroups[$i].groupId', 'groupId');
    r.require(map, 'members', 'listGroups[$i]');
    final membersJson = r.list(map, 'members', 'listGroups[$i]');
    r.nonEmptyList(membersJson, 'listGroups[$i].members');
    final members = <String>[];
    for (var j = 0; j < membersJson.length; j++) {
      final value = membersJson[j];
      if (value is! String || value.isEmpty) {
        r.invalid('listGroups[$i].members[$j]', '必须是非空字符串');
      }
      members.add(value);
    }
    r.unique(members, 'listGroups[$i].members', 'member');
    r.require(map, 'level', 'listGroups[$i]');
    final level = map['level'];
    if (level is! int || level < 1) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'listGroups[$i].level',
        'level 必须是 ≥1 的整数',
      );
    }
    String? parentUnitId;
    if (map.containsKey('parentUnitId')) {
      parentUnitId = r.string(map, 'parentUnitId', 'listGroups[$i]');
      r.nonEmpty(parentUnitId, 'listGroups[$i].parentUnitId');
    }
    r.require(map, 'listType', 'listGroups[$i]');
    final listType = r.enumValue(
      map['listType'],
      'listGroups[$i].listType',
      RecognitionListType.byWire,
      'listType',
    );
    int? startNumber;
    if (map.containsKey('startNumber')) {
      final raw = map['startNumber'];
      if (raw is! int) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'listGroups[$i].startNumber',
          'startNumber 必须是整数',
        );
      }
      startNumber = raw;
    }
    listGroups.add(
      RecognitionListGroup(
        groupId: groupId,
        members: List.unmodifiable(members),
        level: level,
        parentUnitId: parentUnitId,
        listType: listType,
        startNumber: startNumber,
      ),
    );
  }
  r.unique(listGroups.map((group) => group.groupId), 'listGroups', 'groupId');

  final captionsJson = r.list(root, 'captions', '');
  final captions = <RecognitionCaption>[];
  for (var i = 0; i < captionsJson.length; i++) {
    final map = r.objectAt(captionsJson, i, 'captions', const {
      'captionUnitId',
      'targetUnitId',
    });
    r.require(map, 'captionUnitId', 'captions[$i]');
    final captionUnitId = r.string(map, 'captionUnitId', 'captions[$i]');
    r.nonEmpty(captionUnitId, 'captions[$i].captionUnitId');
    r.require(map, 'targetUnitId', 'captions[$i]');
    final targetUnitId = r.string(map, 'targetUnitId', 'captions[$i]');
    r.nonEmpty(targetUnitId, 'captions[$i].targetUnitId');
    if (captionUnitId == targetUnitId) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'captions[$i]',
        '图注不得自指',
      );
    }
    captions.add(
      RecognitionCaption(
        captionUnitId: captionUnitId,
        targetUnitId: targetUnitId,
      ),
    );
  }

  final warningsJson = r.list(root, 'warnings', '');
  r.limit(warningsJson.length, 8, 'warnings', 'warnings 数');
  final warnings = <String>[];
  for (var i = 0; i < warningsJson.length; i++) {
    final value = warningsJson[i];
    if (value is! String) {
      r.invalid('warnings[$i]', '必须是字符串');
    }
    r.textLimit(value, 200, 'warnings[$i]', 'warning');
    warnings.add(value);
  }

  // 请求上下文校验（R-02/R-06/R-07 + 分组悬空）。
  if (structureRequest != null) {
    final unitIds = structureRequest.units.map((unit) => unit.unitId).toSet();
    final textUnitIds = structureRequest.units
        .where((unit) => unit.isTextUnit)
        .map((unit) => unit.unitId)
        .toSet();
    // R-06：readingOrder 恰覆盖全部 units（含 figure/preserved）各一次。
    if (readingOrder.length != unitIds.length ||
        !readingOrder.toSet().containsAll(unitIds)) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'readingOrder',
        'readingOrder 必须恰覆盖全部 units 各一次',
      );
    }
    // R-02：结构输出引用请求外 id。
    for (final assignment in roles) {
      if (!unitIds.contains(assignment.unitId)) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'roles',
          'roles 引用了请求外的 unitId: ${assignment.unitId}',
        );
      }
    }
    // R-07：roles 恰覆盖全部文本单元、不包含 figure/preserved。
    final roleUnitIds = roles.map((assignment) => assignment.unitId).toSet();
    if (roleUnitIds.length != textUnitIds.length ||
        !roleUnitIds.containsAll(textUnitIds)) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'roles',
        'roles 必须恰覆盖全部文本单元（typed/ink）且不含 figure/preserved',
      );
    }
    for (final group in listGroups) {
      for (final member in group.members) {
        if (!unitIds.contains(member)) {
          r.reject(
            RecognitionExceptionCode.invalidProviderResponse,
            'listGroups',
            'listGroup 成员引用了请求外的 unitId: $member',
          );
        }
      }
    }
    for (final caption in captions) {
      if (!unitIds.contains(caption.captionUnitId) ||
          !unitIds.contains(caption.targetUnitId)) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'captions',
          'captions 引用了请求外的 unitId',
        );
      }
    }
  }

  // R-08：分组自洽（悬空父、成环、跨组重复、顶层 <2）。
  _validateListGroups(r, listGroups);
  // §3.4 嵌套列表连续性：每个组的完整子树在 readingOrder 中连续。
  _validateSubtreeContinuity(r, readingOrder, listGroups);

  return RecognitionStructureResponse(
    operationId: operationId,
    requestId: requestId,
    pageId: pageId,
    sceneRevision: RecognitionSceneRevision(
      epoch: epoch,
      revision: revision,
      fingerprint: revisionFingerprint,
    ),
    contentFingerprint: contentFingerprint,
    generation: generation,
    textFingerprint: textFingerprint,
    readingOrder: List.unmodifiable(readingOrder),
    roles: List.unmodifiable(roles),
    listGroups: List.unmodifiable(listGroups),
    captions: List.unmodifiable(captions),
    warnings: List.unmodifiable(warnings),
  );
}

void _validateListGroups(
  RecognitionJsonReader r,
  List<RecognitionListGroup> listGroups,
) {
  // 跨组重复成员。
  final memberOwner = <String, String>{};
  for (final group in listGroups) {
    for (final member in group.members) {
      final existing = memberOwner[member];
      if (existing != null) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'listGroups',
          '成员跨组重复: $member（$existing 与 ${group.groupId}）',
        );
      }
      memberOwner[member] = group.groupId;
    }
  }
  final memberToGroup = memberOwner; // unitId -> groupId
  final groupById = {for (final group in listGroups) group.groupId: group};
  for (final group in listGroups) {
    if (group.parentUnitId == null) {
      if (group.members.length < 2) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'listGroups',
          '顶层组 ${group.groupId} 成员必须 ≥2',
        );
      }
      continue;
    }
    final parentGroup = memberToGroup[group.parentUnitId!];
    if (parentGroup == null) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'listGroups',
        'parentUnitId ${group.parentUnitId} 必须属于另一 listGroup 的成员',
      );
    }
    if (parentGroup == group.groupId) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'listGroups',
        'parentUnitId 不得指向自身组的成员',
      );
    }
  }
  // 成环检测：沿 parentUnitId → 其所属组 → 该组 parentUnitId 链走，
  // 超过组数仍未到顶层即成环。
  for (final group in listGroups) {
    var cursor = group;
    var hops = 0;
    while (cursor.parentUnitId != null) {
      hops++;
      if (hops > listGroups.length) {
        r.reject(
          RecognitionExceptionCode.invalidProviderResponse,
          'listGroups',
          'parentUnitId 链成环（涉及 ${group.groupId}）',
        );
      }
      final parentGroupId = memberToGroup[cursor.parentUnitId!];
      if (parentGroupId == null) break; // 悬空已在上方拒绝
      cursor = groupById[parentGroupId]!;
    }
  }
}

void _validateSubtreeContinuity(
  RecognitionJsonReader r,
  List<String> readingOrder,
  List<RecognitionListGroup> listGroups,
) {
  final indexByUnit = <String, int>{
    for (var i = 0; i < readingOrder.length; i++) readingOrder[i]: i,
  };
  final childrenOfGroup = <String, List<RecognitionListGroup>>{};
  for (final group in listGroups) {
    final parent = group.parentUnitId;
    if (parent != null) {
      childrenOfGroup.putIfAbsent(parent, () => []).add(group);
    }
  }

  Set<String> subtreeOf(RecognitionListGroup group) {
    final units = <String>{...group.members};
    for (final member in group.members) {
      for (final child in childrenOfGroup[member] ?? const []) {
        units.addAll(subtreeOf(child));
      }
    }
    return units;
  }

  for (final group in listGroups) {
    final subtree = subtreeOf(group);
    final indices =
        subtree.map((unit) => indexByUnit[unit]).whereType<int>().toList()
          ..sort();
    if (indices.isEmpty) continue;
    final span = indices.last - indices.first + 1;
    if (span != indices.length) {
      r.reject(
        RecognitionExceptionCode.invalidProviderResponse,
        'listGroups',
        '列表组 ${group.groupId} 的完整子树在 readingOrder 中不连续',
      );
    }
  }
}

bool _listEq(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
