import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'fixture_manifest.dart';

/// 智能排版 v3 fixture runner 的准入层（V3-001A）。
///
/// 职责：在 fixture 进入 runner 之前完成机器准入——
/// 1. FixtureManifest 契约解析（含数据边界元数据强制）；
/// 2. 产物校验：scene/image/renderer golden 的存在性与 SHA-256；录制响应文件
///    的存在性（录制内容哈希与字体文件由 V3-001B 环境层冻结，此处不校验）；
/// 3. 失败码与 failure-taxonomy.json 的一致性校验（路径锁定为规范 taxonomy）。
/// 任一环节失败即拒绝进入 runner。单页/批量执行、受控回放、分层报告与
/// 产物 hash 由 V3-001C 在本准入层之上实现。
class SmartLayoutFixtureRunner {
  const SmartLayoutFixtureRunner({this.repoRoot});

  /// 仓库根目录；为 null 时跳过需要读文件与读 taxonomy 的校验（纯契约解析）。
  final String? repoRoot;

  /// 从磁盘加载并准入一个 manifest 文件。
  RunnerAdmission loadAndAdmit(String manifestPath) {
    final file = File(manifestPath);
    if (!file.isAbsolute && repoRoot != null) {
      // 相对路径一律相对仓库根，避免受当前工作目录影响。
      return _admitFile(File('$repoRoot${Platform.pathSeparator}$manifestPath'));
    }
    return _admitFile(file);
  }

  RunnerAdmission _admitFile(File file) {
    if (!file.existsSync()) {
      return RunnerAdmission.refused([
        ManifestValidationError(code: 'manifest_file_missing', pointer: '#', message: 'manifest 文件不存在：${file.path}'),
      ]);
    }
    final Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      return RunnerAdmission.refused([
        ManifestValidationError(code: 'manifest_json_invalid', pointer: '#', message: 'manifest 不是合法 JSON：${e.message}'),
      ]);
    }
    return admitJson(json);
  }

  /// 准入已解析的 manifest JSON（便于测试与上游复用）。
  RunnerAdmission admitJson(Object? json) {
    final outcome = FixtureManifest.parse(json);
    if (!outcome.isOk) {
      return RunnerAdmission.refused(outcome.errors);
    }
    final manifest = outcome.manifest!;
    final errors = <ManifestValidationError>[...outcome.errors];

    if (repoRoot != null) {
      errors.addAll(_verifyTaxonomy(manifest));
      for (final fixture in manifest.fixtures) {
        errors.addAll(_verifyFixtureArtifacts(fixture));
      }
    }
    if (errors.isNotEmpty) {
      return RunnerAdmission.refused(errors);
    }
    return RunnerAdmission.accepted(manifest);
  }

  List<ManifestValidationError> _verifyTaxonomy(FixtureManifest manifest) {
    final errors = <ManifestValidationError>[];
    final usedCodes = [
      for (final fixture in manifest.fixtures) ...fixture.expected.failureCodes,
    ];
    final reference = manifest.failureTaxonomyReference;
    if (usedCodes.isEmpty) return errors;
    if (reference == null) {
      errors.add(const ManifestValidationError(
        code: 'taxonomy_reference_missing',
        pointer: '#/manifest/failure_taxonomy_reference',
        message: '期望产物使用了 failure_codes，必须引用 failure-taxonomy.json 并给出 sha256',
      ));
      return errors;
    }
    final taxonomyFile = File('$repoRoot${Platform.pathSeparator}${reference.path}');
    if (!taxonomyFile.existsSync()) {
      errors.add(ManifestValidationError(
        code: 'taxonomy_file_missing',
        pointer: '#/manifest/failure_taxonomy_reference/path',
        message: 'failure-taxonomy 文件不存在：${reference.path}',
      ));
      return errors;
    }
    final bytes = taxonomyFile.readAsBytesSync();
    final digest = _sha256Of(bytes);
    if (digest != reference.sha256) {
      errors.add(ManifestValidationError(
        code: 'taxonomy_hash_mismatch',
        pointer: '#/manifest/failure_taxonomy_reference/sha256',
        message: 'failure-taxonomy 实际 sha256 为 $digest，与引用不一致',
      ));
      return errors;
    }
    final taxonomy = jsonDecode(utf8.decode(bytes));
    if (taxonomy is! Map<String, Object?>) {
      errors.add(const ManifestValidationError(
        code: 'taxonomy_invalid',
        pointer: '#/manifest/failure_taxonomy_reference',
        message: 'failure-taxonomy 结构非法',
      ));
      return errors;
    }
    final codes = taxonomy['failure_codes'];
    final known = codes is Map<String, Object?> ? codes.keys.toSet() : const <String>{};
    for (final code in usedCodes) {
      if (!known.contains(code)) {
        errors.add(ManifestValidationError(
          code: 'unknown_failure_code',
          pointer: '#/fixtures',
          message: '失败码 $code 不在 failure-taxonomy.json 中',
        ));
      }
    }
    return errors;
  }

  List<ManifestValidationError> _verifyFixtureArtifacts(FixtureEntry fixture) {
    final errors = <ManifestValidationError>[];
    void verify(ArtifactRef ref, String what) {
      final file = File('$repoRoot${Platform.pathSeparator}${ref.path}');
      if (!file.existsSync()) {
        errors.add(ManifestValidationError(
          code: 'artifact_file_missing',
          pointer: '#/fixtures/${fixture.id}',
          message: '$what 文件不存在：${ref.path}',
        ));
        return;
      }
      final actual = _sha256Of(file.readAsBytesSync());
      if (actual != ref.sha256) {
        errors.add(ManifestValidationError(
          code: 'artifact_hash_mismatch',
          pointer: '#/fixtures/${fixture.id}',
          message: '$what sha256 不匹配：${ref.path} 声明 ${ref.sha256} 实际 $actual',
        ));
      }
    }

    verify(fixture.scene, 'scene');
    final image = fixture.image;
    if (image != null) verify(image, 'image');
    verify(fixture.expected.rendererGolden, 'renderer golden');
    for (final response in fixture.recordedResponses) {
      final file = File('$repoRoot${Platform.pathSeparator}${response.path}');
      if (!file.existsSync()) {
        errors.add(ManifestValidationError(
          code: 'artifact_file_missing',
          pointer: '#/fixtures/${fixture.id}/recorded_responses',
          message: '录制响应文件不存在：${response.path}',
        ));
      }
    }
    return errors;
  }

  static String _sha256Of(List<int> bytes) => crypto.sha256.convert(bytes).toString();
}

class RunnerAdmission {
  const RunnerAdmission.accepted(this.manifest) : errors = const [];
  const RunnerAdmission.refused(this.errors) : manifest = null;

  final FixtureManifest? manifest;
  final List<ManifestValidationError> errors;
  bool get admitted => manifest != null;
}
