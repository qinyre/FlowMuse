/// V3-002B 切分 CLI：读入池 manifest 与预注册切分配置，
/// 运行 DatasetSplitPlanner，输出三个集合 manifest 与分层覆盖报告。
///
/// 用法（仓库根）：
///   dart run tool/smart_layout_v3/dataset/split_cli.dart \
///     docs/研发记录/evidence/smart-layout-v3/datasets/synthetic-pool-v2 \
///     docs/研发记录/evidence/smart-layout-v3/datasets/splits/split-config.json \
///     docs/研发记录/evidence/smart-layout-v3/datasets/splits
///
/// 退出码：0 成功；2 配额/不变量失败（coverage-report.json 记录 failed）；3 输入错误。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'dataset_admission_validator.dart';
import 'dataset_split_planner.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('usage: split_cli.dart <pool_root> <split_config.json> <out_root>');
    exit(3);
  }
  final poolRoot = Directory(args[0]);
  final configFile = File(args[1]);
  final outRoot = Directory(args[2]);
  if (!poolRoot.existsSync() || !configFile.existsSync()) {
    stderr.writeln('pool root or config missing');
    exit(3);
  }
  outRoot.createSync(recursive: true);

  Map<String, Object?> readJson(File file) =>
      jsonDecode(file.readAsStringSync(encoding: utf8)) as Map<String, Object?>;

  final poolManifest = readJson(File('${poolRoot.path}/dataset-manifest.json'));
  final splitConfig = readJson(configFile);

  // 池先过准入闸门（内容 hash 实测，相对池根解析）。
  final admission = DatasetAdmissionValidator.validate(
    poolManifest,
    resolveFile: (path) {
      final file = File('${poolRoot.path}/$path');
      return file.existsSync() ? file.readAsBytesSync() : null;
    },
  );
  if (!admission.isOk) {
    stderr.writeln('pool admission failed:');
    for (final error in admission.errors) {
      stderr.writeln('  $error');
    }
    exit(3);
  }

  final outcome = DatasetSplitPlanner.plan(poolManifest: poolManifest, splitConfig: splitConfig);
  if (!outcome.isOk) {
    _writeCoverageReport(outRoot, poolManifest, splitConfig, configFile, null, outcome.errors);
    stderr.writeln('split planning failed:');
    for (final error in outcome.errors) {
      stderr.writeln('  $error');
    }
    exit(2);
  }
  final plan = outcome.plan!;

  String poolName = 'pool';
  final datasetMeta = poolManifest['dataset'];
  if (datasetMeta is Map<String, Object?> && datasetMeta['name'] is String) {
    poolName = datasetMeta['name'] as String;
  }
  final manifestHashes = <String, String>{};
  for (final split in DatasetSplitPlanner.splitOrder) {
    final splitDir = Directory('${outRoot.path}/$split');
    splitDir.createSync(recursive: true);
    final ids = plan.splits[split]!.toSet();
    final splitManifest = <String, Object?>{
      ...poolManifest,
      'dataset': {
        ...(datasetMeta as Map<String, Object?>),
        'name': '$poolName-$split',
        'split': split,
        'content_root': _relativePath('${outRoot.path}/$split', poolRoot.path),
      },
      'samples': [
        for (final raw in poolManifest['samples'] as List)
          if (raw is Map<String, Object?> && ids.contains(raw['sample_id'])) raw,
      ],
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(splitManifest);
    final bytes = utf8.encode('$encoded\n');
    File('${splitDir.path}/manifest.json').writeAsBytesSync(bytes);
    manifestHashes[split] = _sha256(bytes);
  }

  _writeCoverageReport(
    outRoot, poolManifest, splitConfig, configFile, plan, const [], manifestHashes: manifestHashes,
  );
  final dev = plan.coverage['development'] as Map<String, Object?>;
  stdout.writeln('split ok: development=${dev['sample_count']} samples; '
      'hashes=${manifestHashes.length}');
}

void _writeCoverageReport(
  Directory outRoot,
  Map<String, Object?> poolManifest,
  Map<String, Object?> splitConfig,
  File configFile,
  SplitPlan? plan,
  List<String> errors, {
  Map<String, String> manifestHashes = const {},
}) {
  final report = <String, Object?>{
    'schema_version': '1.0.0',
    'artifact': 'dataset-split-coverage-report',
    'task': 'V3-002B',
    'status': plan == null ? 'failed' : 'passed',
    'pool': {
      'name': (poolManifest['dataset'] as Map<String, Object?>)['name'],
      'manifest_sha256': _sha256(
          utf8.encode('${const JsonEncoder.withIndent('  ').convert(poolManifest)}\n')),
      'sample_count': (poolManifest['samples'] as List).length,
    },
    'config': {
      'path': configFile.path.replaceAll('\\', '/'),
      'sha256': _sha256(configFile.readAsBytesSync()),
      'seed': splitConfig['seed'],
      'weights': splitConfig['weights'],
      'min_quotas': splitConfig['min_quotas'],
      'isolation': splitConfig['isolation'],
    },
    if (plan != null) ...{
      'coverage': plan.coverage,
      'quota_checks': plan.quotaChecks,
      'isolation_proof': {
        'rules': const ['derivation_chain', 'same_generator_identity'],
        'component_count': plan.components.length,
        'components_crossing_splits': 0,
        'components': plan.components,
      },
      'split_manifest_sha256': manifestHashes,
    },
    'errors': errors,
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  File('${outRoot.path}/coverage-report.json').writeAsBytesSync(utf8.encode('$encoded\n'));
}

String _relativePath(String fromDir, String toPath) {
  final from = Directory(fromDir).absolute.uri.pathSegments.sublist(0, null).toList();
  from.removeLast(); // 目录前缀本身
  final to = Directory(toPath).absolute.uri.pathSegments.toList();
  var common = 0;
  while (common < from.length && common < to.length - 1 && from[common] == to[common]) {
    common++;
  }
  final parts = <String>[
    for (var i = common; i < from.length; i++) '..',
    for (var i = common; i < to.length; i++) to[i],
  ];
  var joined = parts.join('/');
  while (joined.endsWith('/')) {
    joined = joined.substring(0, joined.length - 1);
  }
  return joined.isEmpty ? '.' : joined;
}

String _sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();
