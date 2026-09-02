import 'smart_layout_v3_error.dart';
import 'smart_layout_v3_json_reader.dart';

/// v3 分析请求（canonical DTO；schema 冻结见 protocol.md）。
///
/// typed text 只存在于 [SmartLayoutV3ExactText.text]，由客户端 Scene
/// exactText 投影——服务端不得从图片重建打字文本。
class SmartLayoutV3Request {
  const SmartLayoutV3Request({
    required this.pageId,
    required this.sceneRevision,
    required this.assets,
    required this.marks,
    required this.exactTexts,
    required this.sourceRefs,
  });

  factory SmartLayoutV3Request.fromJson(Object? value) {
    const r = SmartLayoutV3JsonReader();
    final root = r.rootObject(value, SmartLayoutV3JsonReader.requestRootKeys);
    r.require(root, 'protocolVersion', '');
    final version = root['protocolVersion'];
    if (version is! int || version != 3) {
      r.invalid('protocolVersion', '必须为 3');
    }
    r.require(root, 'pageId', '');
    final pageId = r.string(root, 'pageId', '');
    r.nonEmpty(pageId, 'pageId');
    if (pageId.runes.length > 128) {
      r.reject(
        SmartLayoutV3ErrorCode.limitExceeded,
        'pageId',
        'pageId 超过 128 字符',
      );
    }

    r.require(root, 'sceneRevision', '');
    final revisionJson = root['sceneRevision'];
    if (revisionJson is! Map) {
      r.invalid('sceneRevision', '必须是对象');
    }
    final revisionMap = r.object(revisionJson, 'sceneRevision', {
      'epoch',
      'revision',
      'fingerprint',
    });
    final epoch = r.nonNegativeInt(revisionMap, 'epoch', 'sceneRevision');
    final revision = r.nonNegativeInt(revisionMap, 'revision', 'sceneRevision');
    final fingerprint = r.string(revisionMap, 'fingerprint', 'sceneRevision');
    r.fingerprint(fingerprint, 'sceneRevision.fingerprint');

    final assetsJson = r.list(root, 'assets', '');
    r.limit(assetsJson.length, 64, 'assets', 'assets 数');
    final assets = <SmartLayoutV3AssetRef>[];
    for (var i = 0; i < assetsJson.length; i++) {
      final map = r.objectAt(assetsJson, i, 'assets', {
        'key',
        'kind',
        'fingerprint',
      });
      r.require(map, 'key', 'assets[$i]');
      final key = r.string(map, 'key', 'assets[$i]');
      r.nonEmpty(key, 'assets[$i].key');
      final kind = r.enumValue(
        map['kind'],
        'assets[$i].kind',
        SmartLayoutV3AssetKind.byWire,
        'asset kind',
      );
      final assetFp = r.string(map, 'fingerprint', 'assets[$i]');
      r.fingerprint(assetFp, 'assets[$i].fingerprint');
      assets.add(
        SmartLayoutV3AssetRef(key: key, kind: kind, fingerprint: assetFp),
      );
    }
    r.unique(assets.map((a) => a.key), 'assets', 'key');

    final sourceRefsJson = r.list(root, 'sourceRefs', '');
    r.limit(sourceRefsJson.length, 2048, 'sourceRefs', 'sourceRef 数');
    final sourceRefs = <String>[];
    for (var i = 0; i < sourceRefsJson.length; i++) {
      final value = sourceRefsJson[i];
      if (value is! String || value.isEmpty) {
        r.invalid('sourceRefs[$i]', '必须是非空字符串');
      }
      sourceRefs.add(value);
    }
    r.unique(sourceRefs, 'sourceRefs', 'sourceRef');
    final sourceRefSet = sourceRefs.toSet();

    final marksJson = r.list(root, 'marks', '');
    r.limit(marksJson.length, 512, 'marks', 'mark 数');
    final marks = <SmartLayoutV3Mark>[];
    for (var i = 0; i < marksJson.length; i++) {
      final map = r.objectAt(marksJson, i, 'marks', {
        'markId',
        'label',
        'assetKey',
        'sourceId',
      });
      r.require(map, 'markId', 'marks[$i]');
      final markId = r.string(map, 'markId', 'marks[$i]');
      r.nonEmpty(markId, 'marks[$i].markId');
      r.require(map, 'label', 'marks[$i]');
      final label = r.string(map, 'label', 'marks[$i]');
      r.nonEmpty(label, 'marks[$i].label');
      r.require(map, 'assetKey', 'marks[$i]');
      final assetKey = r.string(map, 'assetKey', 'marks[$i]');
      r.require(map, 'sourceId', 'marks[$i]');
      final sourceId = r.string(map, 'sourceId', 'marks[$i]');
      marks.add(
        SmartLayoutV3Mark(
          markId: markId,
          label: label,
          assetKey: assetKey,
          sourceId: sourceId,
        ),
      );
    }
    r.unique(marks.map((m) => m.markId), 'marks', 'markId');
    final assetKeySet = assets.map((a) => a.key).toSet();
    for (var i = 0; i < marks.length; i++) {
      final mark = marks[i];
      if (!assetKeySet.contains(mark.assetKey)) {
        r.reject(
          SmartLayoutV3ErrorCode.danglingReference,
          'marks[$i].assetKey',
          'mark 引用了未声明的 asset: ${mark.assetKey}',
        );
      }
      if (!sourceRefSet.contains(mark.sourceId)) {
        r.reject(
          SmartLayoutV3ErrorCode.danglingReference,
          'marks[$i].sourceId',
          'mark 引用了未声明的 sourceRef: ${mark.sourceId}',
        );
      }
    }

    final exactTextsJson = r.list(root, 'exactTexts', '');
    final exactTexts = <SmartLayoutV3ExactText>[];
    for (var i = 0; i < exactTextsJson.length; i++) {
      final map = r.objectAt(exactTextsJson, i, 'exactTexts', {
        'sourceId',
        'text',
      });
      r.require(map, 'sourceId', 'exactTexts[$i]');
      final sourceId = r.string(map, 'sourceId', 'exactTexts[$i]');
      r.nonEmpty(sourceId, 'exactTexts[$i].sourceId');
      r.require(map, 'text', 'exactTexts[$i]');
      final text = r.string(map, 'text', 'exactTexts[$i]');
      // 长度按 Unicode 字符数（Go 侧 utf8.RuneCountInString 对齐）
      if (text.runes.length > 10000) {
        r.reject(
          SmartLayoutV3ErrorCode.limitExceeded,
          'exactTexts[$i].text',
          'text 超过 10000 字符',
        );
      }
      exactTexts.add(SmartLayoutV3ExactText(sourceId: sourceId, text: text));
    }
    r.unique(exactTexts.map((t) => t.sourceId), 'exactTexts', 'sourceId');
    for (var i = 0; i < exactTexts.length; i++) {
      if (!sourceRefSet.contains(exactTexts[i].sourceId)) {
        r.reject(
          SmartLayoutV3ErrorCode.danglingReference,
          'exactTexts[$i].sourceId',
          'exactText 引用了未声明的 sourceRef: ${exactTexts[i].sourceId}',
        );
      }
    }

    return SmartLayoutV3Request(
      pageId: pageId,
      sceneRevision: SmartLayoutV3SceneRevision(
        epoch: epoch,
        revision: revision,
        fingerprint: fingerprint,
      ),
      assets: List.unmodifiable(assets),
      marks: List.unmodifiable(marks),
      exactTexts: List.unmodifiable(exactTexts),
      sourceRefs: List.unmodifiable(sourceRefs),
    );
  }

  final String pageId;
  final SmartLayoutV3SceneRevision sceneRevision;
  final List<SmartLayoutV3AssetRef> assets;
  final List<SmartLayoutV3Mark> marks;
  final List<SmartLayoutV3ExactText> exactTexts;
  final List<String> sourceRefs;

  Map<String, Object?> toJson() => {
    'protocolVersion': 3,
    'pageId': pageId,
    'sceneRevision': {
      'epoch': sceneRevision.epoch,
      'revision': sceneRevision.revision,
      'fingerprint': sceneRevision.fingerprint,
    },
    'assets': [
      for (final asset in assets)
        {
          'key': asset.key,
          'kind': asset.kind.wireName,
          'fingerprint': asset.fingerprint,
        },
    ],
    'marks': [
      for (final mark in marks)
        {
          'markId': mark.markId,
          'label': mark.label,
          'assetKey': mark.assetKey,
          'sourceId': mark.sourceId,
        },
    ],
    'exactTexts': [
      for (final text in exactTexts)
        {'sourceId': text.sourceId, 'text': text.text},
    ],
    'sourceRefs': [...sourceRefs],
  };

  @override
  bool operator ==(Object other) =>
      other is SmartLayoutV3Request &&
      other.pageId == pageId &&
      other.sceneRevision == sceneRevision &&
      _listEq(other.assets, assets) &&
      _listEq(other.marks, marks) &&
      _listEq(other.exactTexts, exactTexts) &&
      _listEq(other.sourceRefs, sourceRefs);

  @override
  int get hashCode => pageId.hashCode;

  @override
  String toString() =>
      'SmartLayoutV3Request($pageId, assets: ${assets.length}, '
      'marks: ${marks.length}, texts: ${exactTexts.length}, '
      'refs: ${sourceRefs.length})';
}

bool _listEq(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class SmartLayoutV3SceneRevision {
  const SmartLayoutV3SceneRevision({
    required this.epoch,
    required this.revision,
    required this.fingerprint,
  });

  final int epoch;
  final int revision;
  final String fingerprint;

  @override
  bool operator ==(Object other) =>
      other is SmartLayoutV3SceneRevision &&
      other.epoch == epoch &&
      other.revision == revision &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(epoch, revision, fingerprint);
}

enum SmartLayoutV3AssetKind {
  clean('clean'),
  annotated('annotated'),
  crop('crop');

  const SmartLayoutV3AssetKind(this.wireName);

  final String wireName;

  static final Map<String, SmartLayoutV3AssetKind> byWire = {
    for (final kind in SmartLayoutV3AssetKind.values) kind.wireName: kind,
  };
}

class SmartLayoutV3AssetRef {
  const SmartLayoutV3AssetRef({
    required this.key,
    required this.kind,
    required this.fingerprint,
  });

  final String key;
  final SmartLayoutV3AssetKind kind;
  final String fingerprint;

  @override
  bool operator ==(Object other) =>
      other is SmartLayoutV3AssetRef &&
      other.key == key &&
      other.kind == kind &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(key, kind, fingerprint);
}

class SmartLayoutV3Mark {
  const SmartLayoutV3Mark({
    required this.markId,
    required this.label,
    required this.assetKey,
    required this.sourceId,
  });

  final String markId;
  final String label;
  final String assetKey;
  final String sourceId;

  @override
  bool operator ==(Object other) =>
      other is SmartLayoutV3Mark &&
      other.markId == markId &&
      other.label == label &&
      other.assetKey == assetKey &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(markId, label, assetKey, sourceId);
}

class SmartLayoutV3ExactText {
  const SmartLayoutV3ExactText({required this.sourceId, required this.text});

  final String sourceId;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SmartLayoutV3ExactText &&
      other.sourceId == sourceId &&
      other.text == text;

  @override
  int get hashCode => Object.hash(sourceId, text);
}
