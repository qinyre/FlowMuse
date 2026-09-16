import 'dart:convert';
import 'dart:io';

import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_json_reader.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 双端 conformance：Dart 与 Go（layoutrecognitionv3 包）消费同一
/// fixtures（docs/研发记录/specs/smart-layout-v3/recognition/fixtures），
/// 正例无损 round-trip，负例同类拒绝。覆盖 spec §3.6 R-01..R-12、
/// `r:` 前缀命名空间冲突与 missingRegionIds 部分批次四情形。
/// flutter test CWD=FlowMuse-App。
void main() {
  final fixturesDir = Directory(
    '../docs/研发记录/specs/smart-layout-v3/recognition/fixtures',
  );
  test('fixtures 目录存在且覆盖正负例', () {
    expect(fixturesDir.existsSync(), isTrue);
    final positive = Directory(
      '${fixturesDir.path}/positive',
    ).listSync().whereType<File>().length;
    final negative = Directory(
      '${fixturesDir.path}/negative',
    ).listSync().whereType<File>().length;
    expect(positive, greaterThanOrEqualTo(8));
    expect(negative, greaterThanOrEqualTo(20));
  });

  group('正例：无损解析与 round-trip', () {
    for (final entity in Directory('${fixturesDir.path}/positive').listSync()) {
      final file = entity as File;
      final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final kind = doc['kind'] as String;
      test('${file.uri.pathSegments.last}（$kind）', () {
        final parsed = _parse(kind, doc);
        final roundTripped = _parse(
          kind,
          doc,
          reparse: _serialize(kind, parsed),
        );
        expect(roundTripped, parsed, reason: 'round-trip 必须语义无损');
      });
    }
  });

  group('负例：双端同类拒绝', () {
    for (final entity in Directory('${fixturesDir.path}/negative').listSync()) {
      final file = entity as File;
      final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final kind = doc['kind'] as String;
      final expected = doc['expectedErrorCode'] as String;
      test('${file.uri.pathSegments.last}（$kind → $expected）', () {
        expect(
          () => _parse(kind, doc),
          throwsA(
            isA<RecognitionProtocolException>()
                .having((e) => e.error.code.wireName, 'code', expected)
                .having((e) => e.error.message, 'message', isNotEmpty),
          ),
        );
      });
    }
  });

  group('R-01..R-12 双保险细节（代码内构造）', () {
    test('R-05：bounds NaN/Inf 拒绝（badGeometry）', () {
      for (final bad in <num>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => RecognitionRequest.fromJson(
            _structureRequestWithBounds({
              'left': 0.0,
              'top': 0.0,
              'width': bad,
              'height': 10.0,
            }),
          ),
          throwsA(_code(RecognitionExceptionCode.badGeometry)),
          reason: 'width=$bad',
        );
      }
    });

    test('R-05：imageScale NaN 拒绝（badGeometry）', () {
      expect(
        () => RecognitionRequest.fromJson(_readRequestWithScale(double.nan)),
        throwsA(_code(RecognitionExceptionCode.badGeometry)),
      );
    });

    test('stage 字段隔离：read 请求携带 units 拒绝', () {
      final payload = _readRequestWithScale(1.0);
      payload['units'] = [];
      expect(
        () => RecognitionRequest.fromJson(payload),
        throwsA(_code(RecognitionExceptionCode.invalidSchema)),
      );
    });

    test('stage 字段隔离：batch 响应携带 readingOrder 拒绝', () {
      final response = _batchResponseOf(<String>['r:a'], const []);
      response['readingOrder'] = <String>['r:a'];
      expect(
        () => RecognitionResponse.fromJson(response),
        throwsA(_code(RecognitionExceptionCode.invalidProviderResponse)),
      );
    });

    test('verify 请求 reason 缺失拒绝', () {
      final payload = _verifyRequestPayload()
        ..['regions'] = <Map<String, Object?>>[
          {
            'regionId': 'r:a',
            'imagePngBase64': 'iVBORw0KGgo=',
            'imageScale': 1.0,
          },
        ];
      expect(
        () => RecognitionRequest.fromJson(payload),
        throwsA(_code(RecognitionExceptionCode.invalidSchema)),
      );
    });

    test('命名空间冲突：ink:r:x 与 native:r:x 是不同 unitId', () {
      final request =
          RecognitionRequest.fromJson(
                _structureRequestWithBounds(
                  {'left': 0.0, 'top': 0.0, 'width': 10.0, 'height': 10.0},
                  extraUnits: [
                    {
                      'unitId': 'ink:r:x',
                      'kind': 'ink',
                      'text': '手写',
                      'bounds': {
                        'left': 0,
                        'top': 20,
                        'width': 10,
                        'height': 10,
                      },
                    },
                    {
                      'unitId': 'native:r:x',
                      'kind': 'preserved',
                      'bounds': {
                        'left': 0,
                        'top': 40,
                        'width': 10,
                        'height': 10,
                      },
                    },
                  ],
                ),
              )
              as RecognitionStructureRequest;
      final ids = request.units.map((unit) => unit.unitId).toSet();
      expect(ids.length, 3);
      expect(ids.containsAll(<String>['ink:r:x', 'native:r:x']), isTrue);
    });

    test('missingRegionIds 客户端保留语义可辨识（合法部分批次不抛）', () {
      final request = RecognitionRequest.fromJson(
        _readRequestOf(<String>['r:a', 'r:b']),
      );
      final response =
          RecognitionResponse.fromJson(
                _batchResponseOf(<String>['r:b'], const ['r:a']),
                expectedFor: request,
              )
              as RecognitionBatchResponse;
      expect(response.missingRegionIds, <String>['r:a']);
      expect(response.regions.single.regionId, 'r:b');
    });

    test('错误 envelope：可解析、未知字段拒绝、往返一致', () {
      final error = RecognitionWireError.fromJson(<String, Object?>{
        'code': 'providerError',
        'message': '上游 5xx',
        'retryable': true,
      });
      expect(error.code, RecognitionExceptionCode.providerError);
      expect(error.retryable, isTrue);
      expect(error.toJson(), <String, Object?>{
        'code': 'providerError',
        'message': '上游 5xx',
        'retryable': true,
      });
      expect(
        () => RecognitionWireError.fromJson(<String, Object?>{
          'code': 'providerError',
          'message': 'x',
          'oops': 1,
        }),
        throwsA(isA<RecognitionProtocolException>()),
      );
    });

    test('错误码表与旧 SmartLayoutV3ErrorCode 相互独立', () {
      // recognition 表是 camelCase + retryable 语义，不复用旧 snake_case 表。
      const codes = RecognitionExceptionCode.values;
      expect(
        codes.map((code) => code.wireName),
        containsAll(<String>[
          'invalidSchema',
          'duplicateId',
          'limitExceeded',
          'textTooLong',
          'badGeometry',
          'busy',
          'unconfigured',
          'providerTimeout',
          'providerError',
          'invalidProviderResponse',
        ]),
      );
      expect(
        RecognitionExceptionCode.invalidProviderResponse.defaultRetryable,
        isFalse,
        reason: '解析失败类不可重试（spec §3.5）',
      );
      expect(RecognitionExceptionCode.providerError.defaultRetryable, isTrue);
    });
  });
}

Matcher _code(RecognitionExceptionCode code) =>
    isA<RecognitionProtocolException>().having(
      (e) => e.error.code,
      'code',
      code,
    );

Object _parse(String kind, Map<String, Object?> doc, {Object? reparse}) {
  final payload = reparse ?? doc['payload'];
  if (kind == 'request') {
    return RecognitionRequest.fromJson(payload);
  }
  if (kind == 'response') {
    final requestJson = doc['request'];
    final request = requestJson == null
        ? null
        : RecognitionRequest.fromJson(requestJson);
    return RecognitionResponse.fromJson(payload, expectedFor: request);
  }
  throw ArgumentError('未知 fixture kind: $kind');
}

Object? _serialize(String kind, Object parsed) => switch (kind) {
  'request' => (parsed as RecognitionRequest).toJson(),
  'response' => (parsed as RecognitionResponse).toJson(),
  _ => throw ArgumentError(),
};

Map<String, Object?> _common() => <String, Object?>{
  'schemaVersion': 'recognition-v3/1',
  'stage': 'read',
  'operationId': '11111111-1111-4111-8111-111111111111',
  'requestId': '22222222-2222-4222-8222-222222222222',
  'pageId': 'page-1',
  'sceneRevision': <String, Object?>{
    'epoch': 0,
    'revision': 5,
    'fingerprint': '0123456789abcdef',
  },
  'contentFingerprint': 'fedcba9876543210',
  'generation': 0,
};

Map<String, Object?> _readRequestOf(List<String> regionIds) =>
    _common()
      ..['regions'] = <Map<String, Object?>>[
        for (final id in regionIds)
          <String, Object?>{
            'regionId': id,
            'imagePngBase64': 'iVBORw0KGgoAAAANSUhEUg==',
            'imageScale': 1.0,
          },
      ];

Map<String, Object?> _readRequestWithScale(double scale) =>
    _common()
      ..['regions'] = <Map<String, Object?>>[
        <String, Object?>{
          'regionId': 'r:a',
          'imagePngBase64': 'iVBORw0KGgoAAAANSUhEUg==',
          'imageScale': scale,
        },
      ];

Map<String, Object?> _verifyRequestPayload() => _common()..['stage'] = 'verify';

Map<String, Object?> _structureRequestWithBounds(
  Map<String, Object?> bounds, {
  List<Map<String, Object?>> extraUnits = const [],
}) {
  final units = <Map<String, Object?>>[
    <String, Object?>{
      'unitId': 'ink:r:base',
      'kind': 'ink',
      'text': '手写正文',
      'bounds': bounds,
    },
    ...extraUnits,
  ];
  return _common()
    ..['stage'] = 'structure'
    ..['units'] = units
    ..['textFingerprint'] = '0123456789abcdef';
}

Map<String, Object?> _batchResponseOf(
  List<String> regionIds,
  List<String> missing,
) => _common()
  ..['regions'] = <Map<String, Object?>>[
    for (final id in regionIds)
      <String, Object?>{
        'regionId': id,
        'status': 'recognized',
        'text': '正文-$id',
        'diagnostics': <String>[],
      },
  ]
  ..['missingRegionIds'] = missing;
