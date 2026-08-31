/// V3-002C 标注一致性 CLI：读两名标注者的标签 JSON 与仲裁裁决 JSON，
/// 输出 agreement-report.json 与 adjudicated-labels.json。
///
/// 用法（仓库根，FlowMuse-App 目录下运行）：
///   dart run tool/smart_layout_v3/dataset/annotation_cli.dart
///     参数依次为 annotator-a.json、annotator-b.json、rulings.json（无裁决时传 -）、输出目录
/// 退出码：0 成功；2 一致性/裁决错误（仍写报告，status=failed）；3 输入错误。
library;

import 'dart:convert';
import 'dart:io';

import 'annotation_agreement_calculator.dart';

void main(List<String> args) {
  if (args.length != 4) {
    stderr.writeln('usage: annotation_cli.dart <a.json> <b.json> <rulings.json|-> <out_dir>');
    exit(3);
  }
  final fileA = File(args[0]);
  final fileB = File(args[1]);
  final rulingsFile = args[2] == '-' ? null : File(args[2]);
  final outDir = Directory(args[3]);
  if (!fileA.existsSync() || !fileB.existsSync()) {
    stderr.writeln('annotator input missing');
    exit(3);
  }
  outDir.createSync(recursive: true);

  Map<String, Object?> readJson(File f) =>
      jsonDecode(f.readAsStringSync(encoding: utf8)) as Map<String, Object?>;

  // 解析契约统一走 calculator 的 fromJson 工厂，杜绝 CLI 与库两层字段名漂移
  //（前轮复审 rejected 的根因：裁决文件字段 final_relations 被误读为 relations 后静默置空）。
  final setA = LabelAnnotationSet.fromJson(readJson(fileA));
  final setB = LabelAnnotationSet.fromJson(readJson(fileB));
  final rulings = <LabelRuling>[];
  if (rulingsFile != null && rulingsFile.existsSync()) {
    final raw = readJson(rulingsFile);
    for (final entry in raw['rulings'] as List) {
      rulings.add(LabelRuling.fromJson(entry as Map<String, Object?>));
    }
  }

  final adjudicated = AnnotationAgreementCalculator.applyLabelArbitration(
    raterA: setA,
    raterB: setB,
    rulings: rulings,
  );
  final report = adjudicated.report;
  final status = adjudicated.hasErrors ? 'failed' : 'passed';

  final agreementJson = {
    'status': status,
    'agreement': report.toJson(),
    'errors': adjudicated.errors,
  };
  File('${outDir.path}/agreement-report.json')
      .writeAsBytesSync(utf8.encode('${const JsonEncoder.withIndent('  ').convert(agreementJson)}\n'));

  final labelsJson = {
    'label_set_kind': 'smart-layout-v3-adjudicated-labels',
    'status': status,
    'rater_a': setA.raterId,
    'rater_b': setB.raterId,
    'annotations': [
      for (final a in adjudicated.annotations)
        {
          'sample_id': a.sampleId,
          'reading_order': a.readingOrder,
          'roles': a.roles,
          'relations': [
            for (final r in a.relations) {'type': r.type, 'from': r.from, 'to': r.to},
          ],
        }
    ],
  };
  final labelsBytes = utf8.encode('${const JsonEncoder.withIndent('  ').convert(labelsJson)}\n');
  File('${outDir.path}/adjudicated-labels.json').writeAsBytesSync(labelsBytes);

  stdout.writeln('label agreement: status=$status samples=${report.samples} '
      'ro=${report.readingOrderExact}/${report.samples} roles=${report.rolesExact}/${report.samples} '
      'rel=${report.relationsExact}/${report.samples}');
  exit(adjudicated.hasErrors ? 2 : 0);
}
