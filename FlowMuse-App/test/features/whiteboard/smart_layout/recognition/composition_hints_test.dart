import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_json_reader.dart';

const modelJson =
    '''{"version":"composition-hints/1","pageIntent":"reading","sections":[{"sectionId":"s1","headingUnitId":"h","memberUnitIds":["t","f1","f2","c"]}],"mediaGroups":[{"groupId":"m1","figureUnitIds":["f1","f2"],"textUnitIds":["t"],"confidence":0.95}],"softLineBreaks":[{"unitId":"t","newlineIndexes":[0],"confidence":0.95}]}''';

RecognitionStructureRequest request({bool composition = true}) =>
    RecognitionStructureRequest(
      operationId: 'op',
      requestId: 'req',
      pageId: 'page',
      sceneRevision: const RecognitionSceneRevision(
        epoch: 1,
        revision: 1,
        fingerprint: 'fp',
      ),
      contentFingerprint: 'cfp',
      generation: 1,
      textFingerprint: 'tfp',
      overviewPngBase64: 'png',
      includeCompositionHints: composition,
      units: [
        for (final id in ['h', 't', 'f1', 'f2', 'c'])
          RecognitionUnitInput(
            unitId: id,
            kind: id.startsWith('f')
                ? RecognitionUnitKind.figure
                : RecognitionUnitKind.ink,
            text: id.startsWith('f') ? null : '完整\n说明',
            bounds: const RecognitionBounds(
              left: 0,
              top: 0,
              width: 100,
              height: 100,
            ),
          ),
      ],
    );

RecognitionStructureResponse response(
  RecognitionStructureRequest r,
) => RecognitionStructureResponse(
  operationId: r.operationId,
  requestId: r.requestId,
  pageId: r.pageId,
  sceneRevision: r.sceneRevision,
  contentFingerprint: r.contentFingerprint,
  generation: r.generation,
  textFingerprint: r.textFingerprint,
  readingOrder: const ['h', 't', 'f1', 'f2', 'c'],
  roles: const [
    RecognitionRoleAssignment(
      unitId: 'h',
      role: RecognitionStructureRole.title,
    ),
    RecognitionRoleAssignment(unitId: 't', role: RecognitionStructureRole.body),
    RecognitionRoleAssignment(
      unitId: 'c',
      role: RecognitionStructureRole.caption,
    ),
  ],
  listGroups: const [],
  captions: const [RecognitionCaption(captionUnitId: 'c', targetUnitId: 'f2')],
  warnings: const [],
  compositionHints: RecognitionCompositionHints.fromJson(jsonDecode(modelJson)),
);

void main() {
  test('composition双端契约：两图共说明往返、能力互斥和旧模式键集', () {
    final r = request();
    expect(RecognitionRequest.fromJson(r.toJson()), r);
    final expected = response(r);
    expect(
      RecognitionResponse.fromJson(expected.toJson(), expectedFor: r),
      expected,
    );
    expect(expected.toJson().containsKey('figureTextLinks'), isFalse);
    expect(
      () => RecognitionRequest.fromJson({
        ...r.toJson(),
        'includeFigureTextLinks': true,
      }),
      throwsA(isA<RecognitionProtocolException>()),
    );
    expect(
      () => RecognitionRequest.fromJson({
        ...r.toJson(),
        'includeCompositionHints': null,
      }),
      throwsA(isA<RecognitionProtocolException>()),
    );
    expect(
      () => RecognitionResponse.fromJson(
        expected.toJson(),
        expectedFor: request(composition: false),
      ),
      throwsA(isA<RecognitionProtocolException>()),
    );
    final old = {...expected.toJson()}..remove('compositionHints');
    expect(
      () => RecognitionResponse.fromJson(old, expectedFor: r),
      throwsA(isA<RecognitionProtocolException>()),
    );
    expect(
      RecognitionResponse.fromJson(
        old,
        expectedFor: request(composition: false),
      ),
      isA<RecognitionStructureResponse>(),
    );
  });

  test('严格解析拒绝未知字段、正文偷渡、null、重复与非法数字', () {
    for (final bad in [
      modelJson.replaceFirst('"pageIntent":"reading"', '"pageIntent":"bad"'),
      modelJson.replaceFirst(
        '"pageIntent":"reading"',
        '"pageIntent":"reading","text":null',
      ),
      modelJson.replaceFirst('"newlineIndexes":[0]', '"newlineIndexes":[0,0]'),
      modelJson.replaceFirst('"newlineIndexes":[0]', '"newlineIndexes":null'),
      modelJson.replaceFirst('"newlineIndexes":[0]', '"newlineIndexes":[0.5]'),
      modelJson.replaceFirst('"confidence":0.95', '"confidence":null'),
      modelJson.replaceFirst('"confidence":0.95', '"confidence":1.1'),
      modelJson.replaceFirst(
        '"figureUnitIds":["f1","f2"]',
        '"figureUnitIds":["f1","f1"]',
      ),
      modelJson.replaceFirst('"textUnitIds":["t"]', '"textUnitIds":[]'),
    ]) {
      expect(
        () => RecognitionCompositionHints.fromJson(jsonDecode(bad)),
        throwsA(isA<RecognitionProtocolException>()),
      );
    }
    for (final confidence in [double.nan, double.infinity]) {
      final raw = jsonDecode(modelJson) as Map<String, dynamic>;
      raw['mediaGroups'][0]['confidence'] = confidence;
      expect(
        () => RecognitionCompositionHints.fromJson(raw),
        throwsA(isA<RecognitionProtocolException>()),
      );
    }
  });

  test('拒绝交错/重复章节、图注冒充正文、无图关联和越界换行', () {
    final r = request();
    for (final bad in [
      modelJson.replaceFirst(
        '"figureUnitIds":["f1","f2"]',
        '"figureUnitIds":["f2"]',
      ),
      modelJson.replaceFirst('"textUnitIds":["t"]', '"textUnitIds":["c"]'),
      modelJson.replaceFirst('"headingUnitId":"h"', '"headingUnitId":"t"'),
      modelJson.replaceFirst(
        '"memberUnitIds":["t","f1","f2","c"]',
        '"memberUnitIds":["f1","t","f2","c"]',
      ),
      modelJson.replaceFirst('"newlineIndexes":[0]', '"newlineIndexes":[2]'),
    ]) {
      expect(
        () => RecognitionResponse.fromJson({
          ...response(r).toJson(),
          'compositionHints': jsonDecode(bad),
        }, expectedFor: r),
        throwsA(isA<RecognitionProtocolException>()),
      );
    }
    final noOverview = r.toJson()..remove('overviewPngBase64');
    expect(
      () => RecognitionResponse.fromJson(
        response(r).toJson(),
        expectedFor: RecognitionRequest.fromJson(noOverview),
      ),
      throwsA(isA<RecognitionProtocolException>()),
    );
    final native = r.toJson();
    (native['units'] as List)[1]['kind'] = 'typed';
    expect(
      () => RecognitionResponse.fromJson(
        response(r).toJson(),
        expectedFor: RecognitionRequest.fromJson(native),
      ),
      throwsA(isA<RecognitionProtocolException>()),
    );
    final blank = r.toJson();
    (blank['units'] as List)[1]['text'] = '段一\n\n段二';
    expect(
      () => RecognitionResponse.fromJson(
        response(r).toJson(),
        expectedFor: RecognitionRequest.fromJson(blank),
      ),
      throwsA(isA<RecognitionProtocolException>()),
    );
  });

  test('短图注允许软换行，但不得拆开列表子树', () {
    final r = request();
    final raw = response(r).toJson();
    final hint = jsonDecode(modelJson) as Map<String, dynamic>;
    hint['softLineBreaks'][0]['unitId'] = 'c';
    raw['compositionHints'] = hint;
    expect(
      RecognitionResponse.fromJson(raw, expectedFor: r),
      isA<RecognitionStructureResponse>(),
    );
    final responseRoles = raw['roles'] as List;
    responseRoles[1]['role'] = 'listItem';
    raw['listGroups'] = [
      {
        'groupId': 'l1',
        'members': ['t', 'h'],
        'level': 1,
        'listType': 'unordered',
      },
    ];
    expect(
      () => RecognitionResponse.fromJson(raw, expectedFor: r),
      throwsA(isA<RecognitionProtocolException>()),
    );
  });
}
