import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'annotation_agreement_calculator.dart';
import 'frozen_label_access_guard.dart';

/// V3-002C 契约测试：标注一致性与仲裁合并、冻结标签访问闸门。
/// 含 V3-002A 复审 findings RF1-1/RF1-2 的负路径回归。
void main() {
  group('AnnotationAgreementCalculator V3-002A 遗留缺陷回归', () {
    test('RF1-1：样本集合不一致时 applyArbitration 不崩溃并报错', () {
      const a = AnnotationSet(raterId: 'A', ratings: [
        AnnotationRating(sampleId: 's1', scores: {'D1': 5}),
        AnnotationRating(sampleId: 's2', scores: {'D1': 4}),
      ]);
      const b = AnnotationSet(raterId: 'B', ratings: [
        AnnotationRating(sampleId: 's1', scores: {'D1': 5}),
      ]);
      final adjudicated = AnnotationAgreementCalculator.applyArbitration(
        raterA: a, raterB: b, rulings: const [],
      );
      expect(adjudicated.hasErrors, isTrue);
      expect(adjudicated.ratings, isEmpty);
      expect(adjudicated.errors.first, startsWith('annotation_set_mismatch'));
    });

    test('RF1-2：code 集分歧缺裁决报 arbitration_missing，不静默并集', () {
      const a = AnnotationSet(raterId: 'A', ratings: [
        AnnotationRating(sampleId: 's1', scores: {'D1': 5}, codes: ['C-SNAPSHOT-LOST-SOURCE']),
      ]);
      const b = AnnotationSet(raterId: 'B', ratings: [
        AnnotationRating(sampleId: 's1', scores: {'D1': 5}, codes: ['M-SNAPSHOT-PROTECTED-DAMAGE']),
      ]);
      final adjudicated = AnnotationAgreementCalculator.applyArbitration(
        raterA: a, raterB: b, rulings: const [],
      );
      expect(adjudicated.hasErrors, isTrue);
      expect(adjudicated.errors, contains('arbitration_missing:s1||code_set_difference'));
      // 有裁决时采用裁决的最终 code 集。
      final fixed = AnnotationAgreementCalculator.applyArbitration(
        raterA: a,
        raterB: b,
        rulings: const [
          ArbitrationRuling(
            sampleId: 's1',
            kind: 'code_set_difference',
            finalCodes: ['C-SNAPSHOT-LOST-SOURCE'],
          ),
        ],
      );
      expect(fixed.hasErrors, isFalse);
      expect(fixed.ratings.single.codes, ['C-SNAPSHOT-LOST-SOURCE']);
    });
  });

  group('LabelAgreement 标签级一致性', () {
    const setA = LabelAnnotationSet(raterId: 'annotator-a', annotations: [
      LabelAnnotation(
        sampleId: 's1',
        readingOrder: ['e1', 'e2', 'e3'],
        roles: {'e1': 'title', 'e2': 'paragraph', 'e3': 'figure'},
        relations: [LabelRelation(type: 'caption_of', from: 'e3', to: 'e2')],
      ),
      LabelAnnotation(
        sampleId: 's2',
        readingOrder: ['e1', 'e2'],
        roles: {'e1': 'paragraph', 'e2': 'paragraph'},
        relations: [],
      ),
    ]);
    const setB = LabelAnnotationSet(raterId: 'annotator-b', annotations: [
      LabelAnnotation(
        sampleId: 's1',
        readingOrder: ['e1', 'e2', 'e3'],
        roles: {'e1': 'title', 'e2': 'paragraph', 'e3': 'figure'},
        relations: [LabelRelation(type: 'caption_of', from: 'e3', to: 'e2')],
      ),
      LabelAnnotation(
        sampleId: 's2',
        readingOrder: ['e2', 'e1'],
        roles: {'e1': 'paragraph', 'e2': 'title'},
        relations: [LabelRelation(type: 'keep_together', from: 'e1', to: 'e2')],
      ),
    ]);

    test('逐字段一致率与分歧清单', () {
      final report = AnnotationAgreementCalculator.calculateLabelAgreement(setA, setB);
      expect(report.hasErrors, isFalse);
      expect(report.samples, 2);
      expect(report.readingOrderExact, 1);
      expect(report.rolesExact, 1);
      expect(report.relationsExact, 1);
      expect(report.roleSlots, 5);
      expect(report.roleSlotsExact, 4);
      final fields = report.disagreements.map((d) => d.field).toSet();
      expect(fields, containsAll(['reading_order', 'relations']));
      expect(fields.any((f) => f.startsWith('roles:')), isTrue);
      final json = report.toJson();
      expect(json['reading_order_rate'], 0.5);
    });

    test('标签仲裁：一致字段直接采用；分歧缺裁决报错；有裁决采用裁决', () {
      final missing = AnnotationAgreementCalculator.applyLabelArbitration(
        raterA: setA, raterB: setB, rulings: const [],
      );
      expect(missing.hasErrors, isTrue);
      // s2 的三处分歧：reading_order、roles:e2、relations。
      expect(missing.errors.where((e) => e.startsWith('arbitration_missing')), hasLength(3));

      final adjudicated = AnnotationAgreementCalculator.applyLabelArbitration(
        raterA: setA,
        raterB: setB,
        rulings: const [
          LabelRuling(sampleId: 's2', field: 'reading_order', readingOrder: ['e1', 'e2']),
          LabelRuling(sampleId: 's2', field: 'roles:e2', roleValue: 'paragraph'),
          LabelRuling(
            sampleId: 's2',
            field: 'relations',
            relations: [LabelRelation(type: 'keep_together', from: 'e1', to: 'e2')],
          ),
        ],
      );
      expect(adjudicated.hasErrors, isFalse, reason: adjudicated.errors.join('\n'));
      final s2 = adjudicated.annotations.firstWhere((a) => a.sampleId == 's2');
      expect(s2.readingOrder, ['e1', 'e2']);
      expect(s2.roles['e2'], 'paragraph');
      expect(s2.relations.single.type, 'keep_together');
    });

    test('样本集合不一致报错且不产出裁决', () {
      const partial = LabelAnnotationSet(raterId: 'b2', annotations: [
        LabelAnnotation(sampleId: 's9', readingOrder: [], roles: {}, relations: []),
      ]);
      final report = AnnotationAgreementCalculator.calculateLabelAgreement(setA, partial);
      expect(report.hasErrors, isTrue);
      final adjudicated = AnnotationAgreementCalculator.applyLabelArbitration(
        raterA: setA, raterB: partial, rulings: const [],
      );
      expect(adjudicated.annotations, isEmpty);
      expect(adjudicated.hasErrors, isTrue);
    });
  });

  group('annotation_cli 端到端（裁决 JSON 契约回归 R2C-1/R2C-4）', () {
    test('真实裁决文件格式（final_relations）驱动 CLI，裁决值必须落地', () {
      final temp = Directory.systemTemp.createTempSync('v3-002c-cli-');
      try {
        final sep = Platform.pathSeparator;
        final aFile = File('${temp.path}${sep}a.json');
        final bFile = File('${temp.path}${sep}b.json');
        final rFile = File('${temp.path}${sep}rulings.json');
        const aJson =
            '{"annotator":"A","annotations":[{"sample_id":"s1","reading_order":["e01","e02"],"roles":{"e01":"title","e02":"paragraph"},"relations":[]}]}';
        const bJson =
            '{"annotator":"B","annotations":[{"sample_id":"s1","reading_order":["e01","e02"],"roles":{"e01":"title","e02":"paragraph"},"relations":[{"type":"caption_of","from":"e01","to":"e02"}]}]}';
        // 裁决文件字段名是 final_relations（而非 relations）。
        const rulingsJson =
            '{"arbiter_run_id":"x","rulings":[{"sample_id":"s1","field":"relations","winner":"neither","final_relations":[{"type":"keep_together","from":"e01","to":"e02"}],"reason":"r"}]}';
        aFile.writeAsStringSync(aJson, encoding: utf8);
        bFile.writeAsStringSync(bJson, encoding: utf8);
        rFile.writeAsStringSync(rulingsJson, encoding: utf8);
        final outDir = Directory('${temp.path}${sep}out')..createSync();

        final dart = _findDart();
        final result = Process.runSync(dart, [
          'run', 'tool/smart_layout_v3/dataset/annotation_cli.dart',
          aFile.path, bFile.path, rFile.path, outDir.path,
        ], workingDirectory: Directory.current.path);
        expect(result.exitCode, 0, reason: (result.stderr as String).trim());

        final labels = jsonDecode(
                File('${outDir.path}${sep}adjudicated-labels.json').readAsStringSync(encoding: utf8))
            as Map<String, Object?>;
        final relations =
            (labels['annotations'] as List).cast<Map<String, Object?>>().single['relations'] as List;
        // 裁决值（keep_together）必须出现在最终标签里——防字段名漂移回归。
        expect(relations, hasLength(1));
        expect((relations.single as Map<String, Object?>)['type'], 'keep_together');

        final report = jsonDecode(
                File('${outDir.path}${sep}agreement-report.json').readAsStringSync(encoding: utf8))
            as Map<String, Object?>;
        expect(report['status'], 'passed');
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test('LabelRuling.fromJson：final_relations 缺失时载荷为 null（区别于空列表裁决）', () {
      final withPayload = LabelRuling.fromJson(const {
        'sample_id': 's1',
        'field': 'relations',
        'final_relations': <Object?>[],
      });
      expect(withPayload.relations, isNotNull);
      expect(withPayload.relations, isEmpty);
      final withoutPayload = LabelRuling.fromJson(const {
        'sample_id': 's1',
        'field': 'relations',
      });
      expect(withoutPayload.relations, isNull);
    });
  });
  group('FrozenLabelAccessGuard', () {
    test('调参/训练角色拒绝读取 frozen 标签', () {
      for (final role in ['tuning', 'training', 'development', '']) {
        final decision = FrozenLabelAccessGuard.check(accessorRole: role, split: 'frozen_holdout');
        expect(decision.allowed, isFalse, reason: role);
        expect(decision.reason, contains('frozen_label_access_denied'));
      }
    });

    test('评测/门禁/冻结清单角色允许；非 frozen 集合不受限', () {
      for (final role in ['evaluation', 'gate', 'annotation_freeze']) {
        expect(
          FrozenLabelAccessGuard.check(accessorRole: role, split: 'frozen_holdout').allowed,
          isTrue,
        );
      }
      expect(FrozenLabelAccessGuard.check(accessorRole: 'tuning', split: 'development').allowed,
          isTrue);
    });
  });
}

/// 定位 dart VM：与 V3-001 测试助手同法（沿 resolvedExecutable 祖先找 dart-sdk）。
String _findDart() {
  final exe = Platform.resolvedExecutable;
  var dir = File(exe).parent;
  for (var i = 0; i < 6; i++) {
    for (final rel in const [
      'bin/cache/dart-sdk/bin/dart.exe',
      'cache/dart-sdk/bin/dart.exe',
    ]) {
      final candidate =
          File('${dir.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
      if (candidate.existsSync()) return candidate.path;
    }
    dir = dir.parent;
  }
  return 'dart';
}
