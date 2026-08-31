import 'dart:convert';
import 'dart:io';

import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_error.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_request.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_response.dart';
import 'package:flutter_test/flutter_test.dart';

/// 双端 conformance：Dart 与 Go 消费同一 fixtures
///（docs/研发记录/specs/smart-layout-v3/protocol/fixtures），
/// 正例无损 round-trip，负例同类拒绝。flutter test CWD=FlowMuse-App。
void main() {
  final fixturesDir = Directory(
    '../docs/研发记录/specs/smart-layout-v3/protocol/fixtures',
  );
  test('fixtures 目录存在且覆盖正负例', () {
    expect(fixturesDir.existsSync(), isTrue);
    expect(
      fixturesDir.listSync(recursive: true).whereType<File>().length,
      greaterThanOrEqualTo(15),
    );
  });

  group('正例：无损解析与 round-trip', () {
    for (final entity in Directory('${fixturesDir.path}/positive').listSync()) {
      final file = entity as File;
      final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final kind = doc['kind'] as String;
      test('${file.uri.pathSegments.last}（$kind）', () {
        final parsed = _parse(kind, doc['payload']);
        final roundTripped = _parse(kind, _serialize(kind, parsed));
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
          () => _parse(kind, doc['payload']),
          throwsA(
            isA<SmartLayoutV3ProtocolException>()
                .having((e) => e.error.code.wireName, 'code', expected)
                .having((e) => e.error.message, 'message', isNotEmpty)
                .having((e) => e.error.field, 'field', isNotEmpty),
          ),
        );
      });
    }
  });

  test('尾随内容拒绝（Dart jsonDecode 层）', () {
    const raw = '{"protocolVersion":3,"pageId":"p",';
    expect(() => jsonDecode('$raw} 垃圾'), throwsFormatException);
    expect(() => jsonDecode('$raw}$raw}'), throwsFormatException);
  });

  test('错误 envelope 自身可解析且拒绝未知字段', () {
    final error = SmartLayoutV3Error.fromJson({
      'code': 'unknown_enum',
      'message': 'x',
      'field': 'assets[0].kind',
    });
    expect(error.code, SmartLayoutV3ErrorCode.unknownEnum);
    expect(error.toJson(), {
      'code': 'unknown_enum',
      'message': 'x',
      'field': 'assets[0].kind',
    });
    expect(
      () => SmartLayoutV3Error.fromJson({
        'code': 'invalid_request',
        'message': 'x',
        'oops': 1,
      }),
      throwsA(isA<SmartLayoutV3ProtocolException>()),
    );
  });
}

Object _parse(String kind, Object? payload) => switch (kind) {
  'request' => SmartLayoutV3Request.fromJson(payload),
  'response' => SmartLayoutV3Response.fromJson(payload),
  _ => throw ArgumentError('未知 fixture kind: $kind'),
};

Object? _serialize(String kind, Object parsed) => switch (kind) {
  'request' => (parsed as SmartLayoutV3Request).toJson(),
  'response' => (parsed as SmartLayoutV3Response).toJson(),
  _ => throw ArgumentError(),
};
