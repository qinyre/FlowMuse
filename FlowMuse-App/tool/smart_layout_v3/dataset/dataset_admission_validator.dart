/// 智能排版 v3 数据集准入验证器（V3-002A）。
///
/// 开发线（ai_synthetic_development）数据边界唯一闸门：
/// - 只接收确定性合成（synthetic）与机器可验证许可（licensed）样本；
/// - real_user_content 一律拒绝并指引推迟到 V3-700A 授权包；
/// - 每个样本必须记录来源、派生链、许可/权利 hash、删除流程与禁止用途；
/// - 内容与许可文件按 sha256 经由 [DatasetFileResolver] 实测校验，
///   来源或许可不可机器验证的样本无法进入 manifest。
/// 所有错误一次性返回（机器错误码 + JSON pointer），不抛未捕获异常。
library;

import 'package:crypto/crypto.dart' as crypto;

/// 文件解析器：dataset 清单内相对路径 → 文件字节；不可解析返回 null。
/// 由调用方注入（内存表或磁盘根），验证器不直接触网、不猜路径。
typedef DatasetFileResolver = List<int>? Function(String path);

class DatasetAdmissionValidator {
  const DatasetAdmissionValidator._();

  static const String expectedSchemaVersion = '1.0.0';
  static const String datasetKind = 'smart-layout-v3-dataset-manifest';
  static const String deferredRealContentDirective =
      'real_user_content 保持隔离并推迟到 V3-700A 授权包（数据授权/脱敏/同意批准）';

  static final RegExp sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp sampleIdPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,127}$');
  static final RegExp utcPattern =
      RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$');
  static final RegExp semverPattern = RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$');
  static const Set<String> allowedKinds = {'synthetic', 'licensed', 'real_user_content'};
  static const Set<String> allowedContentKinds = {'handwritten_only', 'typed_only', 'mixed'};

  /// 校验 dataset manifest。返回全部错误（空 = 准入通过）。
  static AdmissionOutcome validate(Object? json, {required DatasetFileResolver resolveFile}) {
    final errors = <AdmissionError>[];
    if (json is! Map) {
      return AdmissionOutcome.error(const [
        AdmissionError(code: 'manifest_not_object', pointer: '#', message: 'dataset manifest 必须是 JSON 对象'),
      ]);
    }
    final root = _Ctx(json, '#', errors);
    root.checkKeys({'schema_version', 'dataset_kind', 'dataset', 'samples'});

    if (root.string('schema_version') != expectedSchemaVersion) {
      errors.add(AdmissionError(
        code: 'schema_version_mismatch',
        pointer: '#/schema_version',
        message: "schema_version 必须是 '$expectedSchemaVersion'",
      ));
    }
    if (root.string('dataset_kind') != datasetKind) {
      errors.add(AdmissionError(
        code: 'dataset_kind_mismatch',
        pointer: '#/dataset_kind',
        message: "dataset_kind 必须是 '$datasetKind'",
      ));
    }

    final dataset = root.obj('dataset');
    String? lane;
    if (dataset == null) {
      errors.add(const AdmissionError(
        code: 'dataset_meta_missing',
        pointer: '#/dataset',
        message: 'dataset 元信息缺失',
      ));
    } else {
      dataset.checkKeys({'name', 'version', 'generated_at_utc', 'lane', 'admission_policy'});
      dataset.nonEmptyString('name');
      dataset.patternString('version', semverPattern, 'semver 版本号');
      dataset.patternString('generated_at_utc', utcPattern, 'UTC 时刻');
      lane = dataset.nonEmptyString('lane');
      if (lane != null && lane != 'ai_synthetic_development') {
        errors.add(dataset.error('lane_not_development', 'lane',
            'V3-002 数据集只能属于 ai_synthetic_development 开发线，实际为 $lane'));
      }
      final policy = dataset.obj('admission_policy');
      if (policy == null) {
        errors.add(dataset.error('admission_policy_missing', 'admission_policy', 'admission_policy 缺失'));
      } else {
        policy.checkKeys({'admitted_kinds', 'rejected_kinds', 'rejection_directive'});
        final admitted = policy.stringList('admitted_kinds');
        final rejected = policy.stringList('rejected_kinds');
        if (admitted != null &&
            (!admitted.contains('synthetic') || !admitted.contains('licensed'))) {
          errors.add(policy.error('admitted_kinds_incomplete', 'admitted_kinds',
              'admitted_kinds 必须同时包含 synthetic 与 licensed'));
        }
        if (rejected != null && !rejected.contains('real_user_content')) {
          errors.add(policy.error(
              'real_user_content_not_rejected', 'rejected_kinds', 'rejected_kinds 必须包含 real_user_content'));
        }
        final directive = policy.nonEmptyString('rejection_directive');
        if (directive != null && !directive.contains('V3-700A')) {
          errors.add(policy.error('rejection_directive_missing_deferral', 'rejection_directive',
              'rejection_directive 必须写明推迟到 V3-700A 授权包'));
        }
      }
    }

    final samplesJson = root.at('samples');
    final samples = <AdmittedSample>[];
    if (samplesJson is! List || samplesJson.isEmpty) {
      errors.add(const AdmissionError(
        code: 'samples_missing',
        pointer: '#/samples',
        message: 'samples 必须是非空数组',
      ));
    } else {
      final seenIds = <String>{};
      for (var i = 0; i < samplesJson.length; i++) {
        final sample = _Ctx(samplesJson[i], '#/samples/$i', errors);
        if (sample.raw is! Map) {
          errors.add(sample.error('sample_not_object', '', '样本必须是 JSON 对象'));
          continue;
        }
        final parsed = _parseSample(sample, resolveFile, errors);
        if (parsed != null) {
          if (!seenIds.add(parsed.sampleId)) {
            errors.add(sample.error('duplicate_sample_id', 'sample_id', '样本 id 重复：${parsed.sampleId}'));
          }
          samples.add(parsed);
        }
      }
      // 派生链闭合与无环：父样本必须存在；环判定按『沿父边回走能重新到达自身』。
      // 已展开节点直接跳过（菱形派生合法）；环必在其任一成员的自身回走中暴露。
      final byId = {for (final s in samples) s.sampleId: s};
      for (final sample in samples) {
        for (final parent in sample.derivationChain) {
          if (!byId.containsKey(parent)) {
            errors.add(AdmissionError(
              code: 'unknown_derivation_parent',
              pointer: '#/samples/${sample.sampleId}/origin/derivation_chain',
              message: '样本 ${sample.sampleId} 的派生父 $parent 不在本 manifest 中',
            ));
          }
        }
        final visited = <String>{};
        final queue = List<String>.of(sample.derivationChain);
        while (queue.isNotEmpty) {
          final current = queue.removeLast();
          if (current == sample.sampleId) {
            errors.add(AdmissionError(
              code: 'derivation_cycle',
              pointer: '#/samples/${sample.sampleId}/origin/derivation_chain',
              message: '样本 ${sample.sampleId} 的派生链存在回到自身的环（经 $current）',
            ));
            break;
          }
          if (!visited.add(current)) continue;
          queue.addAll(byId[current]?.derivationChain ?? const []);
        }
      }
    }

    if (errors.isNotEmpty) return AdmissionOutcome.error(errors);
    return AdmissionOutcome.ok(samples);
  }

  static AdmittedSample? _parseSample(
    _Ctx sample,
    DatasetFileResolver resolveFile,
    List<AdmissionError> errors,
  ) {
    sample.checkKeys({'sample_id', 'kind', 'origin', 'rights', 'content', 'features'});
    final sampleId = sample.patternString('sample_id', sampleIdPattern, '样本 id');
    final kind = sample.enumString('kind', allowedKinds, code: 'unknown_sample_kind');

    // 真实用户内容：开发线不可接纳，机器拒绝并指向 V3-700A。
    if (kind == 'real_user_content') {
      errors.add(sample.error('real_user_content_not_admissible', 'kind',
          '真实用户内容不可进入开发线数据集；$deferredRealContentDirective'));
      return null;
    }

    // ---- origin：来源与派生链 ----
    final origin = sample.obj('origin');
    List<String> derivationChain = const [];
    if (origin == null) {
      errors.add(sample.error('origin_missing', 'origin', '来源（origin）缺失'));
    } else if (kind == 'synthetic') {
      origin.checkKeys({'generator', 'generated_at_utc', 'derivation_chain'});
      final generator = origin.obj('generator');
      if (generator == null) {
        errors.add(origin.error('generator_missing', 'generator', '合成样本必须声明生成器'));
      } else {
        generator.checkKeys({'name', 'version', 'seed', 'params_sha256', 'deterministic'});
        generator.nonEmptyString('name');
        generator.patternString('version', semverPattern, 'semver 版本号');
        final seed = generator.at('seed');
        if (seed is! int || seed < 0) {
          errors.add(generator.error('invalid_seed', 'seed', 'seed 必须是 >= 0 的整数'));
        }
        generator.patternString('params_sha256', sha256Pattern, 'SHA-256', code: 'invalid_sha256');
        if (generator.at('deterministic') != true) {
          errors.add(generator.error('synthetic_not_deterministic', 'deterministic',
              '合成样本的生成器必须 deterministic=true（非确定性样本无法进入 manifest）'));
        }
      }
      origin.patternString('generated_at_utc', utcPattern, 'UTC 时刻');
      final chain = origin.stringList('derivation_chain', required: false) ?? const <String>[];
      for (final parent in chain) {
        if (!sampleIdPattern.hasMatch(parent)) {
          errors.add(origin.error('invalid_derivation_parent', 'derivation_chain', '派生父 id 非法：$parent'));
        }
      }
      derivationChain = chain;
    } else if (kind == 'licensed') {
      origin.checkKeys({'source', 'acquired_at_utc', 'derivation_chain'});
      final source = origin.obj('source');
      if (source == null) {
        errors.add(origin.error('source_missing', 'source', '许可样本必须声明供应方来源'));
      } else {
        source.checkKeys({'supplier_id', 'reference'});
        source.nonEmptyString('supplier_id');
        source.nonEmptyString('reference');
      }
      origin.patternString('acquired_at_utc', utcPattern, 'UTC 时刻');
      derivationChain = origin.stringList('derivation_chain', required: false) ?? const <String>[];
    }

    // ---- rights：许可/权利 hash、删除流程、禁止用途 ----
    final rights = sample.obj('rights');
    if (rights == null) {
      errors.add(sample.error('rights_missing', 'rights', '权利（rights）记录缺失'));
    } else {
      rights.checkKeys({'kind', 'license', 'forbidden_uses', 'deletion'});
      final rightsKind = rights.enumString('kind', const {'synthetic', 'licensed'});
      if (rightsKind != null && kind != null && rightsKind != kind) {
        errors.add(rights.error('rights_kind_mismatch', 'kind', 'rights.kind 必须与样本 kind 一致'));
      }
      if (kind == 'licensed') {
        final license = rights.obj('license');
        if (license == null) {
          errors.add(rights.error('license_missing', 'license', '许可样本必须携带许可记录'));
        } else {
          license.checkKeys({'license_id', 'document_path', 'document_sha256', 'scope'});
          license.nonEmptyString('license_id');
          license.nonEmptyString('scope');
          final documentPath = license.nonEmptyString('document_path');
          final documentSha = license.patternString('document_sha256', sha256Pattern, 'SHA-256', code: 'invalid_sha256');
          if (documentPath != null && documentSha != null) {
            _verifyFileHash(documentPath, documentSha, license, 'license_document', resolveFile, errors);
          }
        }
      } else if (kind == 'synthetic') {
        // 合成样本的权利来自生成器策略：许可字段必须显式为 null（不得冒充许可来源）。
        if (rights.fieldPresent('license') && rights.at('license') != null) {
          errors.add(rights.error('synthetic_license_forbidden', 'license',
              '合成样本不得声明许可文档（rights.license 必须为 null；许可路径只属于 licensed 样本）'));
        }
      }
      // 缺失/空数组/空元素统一由 stringList 报 invalid_string_list。
      rights.stringList('forbidden_uses');
      final deletion = rights.obj('deletion');
      if (deletion == null) {
        errors.add(rights.error('deletion_missing', 'deletion', '删除流程（deletion）缺失'));
      } else {
        deletion.checkKeys({'policy_id', 'method', 'reference'});
        deletion.nonEmptyString('policy_id');
        deletion.enumString('method', const {'regenerable_no_retention', 'retention_bound', 'on_request'});
        deletion.nonEmptyString('reference');
      }
    }

    // ---- content：内容文件按 hash 实测 ----
    final content = sample.obj('content');
    if (content == null) {
      errors.add(sample.error('content_missing', 'content', '内容引用（content）缺失'));
    } else {
      content.checkKeys({'path', 'sha256'});
      final path = content.nonEmptyString('path');
      final sha = content.patternString('sha256', sha256Pattern, 'SHA-256', code: 'invalid_sha256');
      if (path != null && sha != null) {
        _verifyFileHash(path, sha, content, 'sample_content', resolveFile, errors);
      }
    }

    // ---- features：供 V3-002B 分层抽样的页面特征 ----
    final features = sample.obj('features');
    if (features == null) {
      errors.add(sample.error('features_missing', 'features', '页面特征（features）缺失'));
    } else {
      features.checkKeys({
        'content_kind', 'stroke_count', 'has_images', 'has_formula', 'has_shapes', 'has_groups',
        'has_frames', 'has_bindings', 'has_locked_objects', 'has_decorative_lines', 'has_list',
        'long_form', 'vertical_text_preserved', 'tidy_page', 'scattered_page', 'pressure_stress',
        'known_failure_page',
      });
      features.enumString('content_kind', allowedContentKinds);
      final strokeCount = features.at('stroke_count');
      if (strokeCount is! int || strokeCount < 0) {
        errors.add(features.error('invalid_stroke_count', 'stroke_count', 'stroke_count 必须是 >= 0 的整数'));
      }
      for (final flag in const [
        'has_images', 'has_formula', 'has_shapes', 'has_groups', 'has_frames', 'has_bindings',
        'has_locked_objects', 'has_decorative_lines', 'has_list', 'long_form',
        'vertical_text_preserved', 'tidy_page', 'scattered_page', 'pressure_stress',
        'known_failure_page',
      ]) {
        final value = features.at(flag);
        if (value is! bool) {
          errors.add(features.error('invalid_feature_flag', flag, '$flag 必须是布尔值'));
        }
      }
    }

    if (sampleId == null || kind == null) return null;
    return AdmittedSample(sampleId: sampleId, kind: kind, derivationChain: derivationChain);
  }

  static void _verifyFileHash(
    String path,
    String expectedSha256,
    _Ctx owner,
    String role,
    DatasetFileResolver resolveFile,
    List<AdmissionError> errors,
  ) {
    final bytes = resolveFile(path);
    if (bytes == null) {
      errors.add(owner.error('file_unresolvable', '', '$role 文件不可解析：$path（来源或许可不可机器验证）'));
      return;
    }
    final actual = _sha256Of(bytes);
    if (actual != expectedSha256) {
      errors.add(owner.error('hash_mismatch', '', '$role 文件 sha256 不匹配：$path 期望 $expectedSha256 实测 $actual'));
    }
  }

  static String _sha256Of(List<int> bytes) => crypto.sha256.convert(bytes).toString();
}

/// 通过准入的样本（仅保留机器后续需要的字段）。
class AdmittedSample {
  const AdmittedSample({required this.sampleId, required this.kind, required this.derivationChain});
  final String sampleId;
  final String kind;
  final List<String> derivationChain;
}

class AdmissionOutcome {
  const AdmissionOutcome.ok(this.samples)
      : errors = const [],
        isOk = true;
  const AdmissionOutcome.error(this.errors)
      : samples = const [],
        isOk = false;
  final bool isOk;
  final List<AdmittedSample> samples;
  final List<AdmissionError> errors;
}

class AdmissionError {
  const AdmissionError({required this.code, required this.pointer, required this.message});
  final String code;
  final String pointer;
  final String message;

  Map<String, String> toJson() => {'code': code, 'pointer': pointer, 'message': message};

  @override
  String toString() => '$code at $pointer: $message';
}

class _Ctx {
  _Ctx(this.raw, this.pointer, this.errors);
  final Object? raw;
  final String pointer;
  final List<AdmissionError> errors;

  Object? at(String field) => raw is Map ? (raw as Map)[field] : null;

  bool fieldPresent(String field) => raw is Map && (raw as Map).containsKey(field);

  void checkKeys(Set<String> allowed) {
    if (raw is! Map) return;
    for (final key in (raw as Map).keys) {
      if (!allowed.contains(key)) {
        errors.add(error('unknown_field', key.toString(), '未知字段：$key'));
      }
    }
  }

  _Ctx? obj(String field) {
    final value = at(field);
    if (value is Map) return _Ctx(value, '$pointer/$field', errors);
    if (value == null) {
      errors.add(error('field_missing', field, '$field 缺失或必须是对象'));
      return null;
    }
    errors.add(error('field_not_object', field, '$field 必须是 JSON 对象'));
    return null;
  }

  String? string(String field) => at(field) is String ? at(field) as String : null;

  String? nonEmptyString(String field) {
    final value = at(field);
    if (value is! String || value.isEmpty) {
      errors.add(error('field_missing_or_empty', field, '$field 必须是非空字符串'));
      return null;
    }
    return value;
  }

  String? patternString(String field, RegExp pattern, String description, {String code = 'field_invalid_format'}) {
    final value = at(field);
    if (value is! String || !pattern.hasMatch(value)) {
      errors.add(error(code, field, '$field 必须是合法的$description：$value'));
      return null;
    }
    return value;
  }

  String? enumString(String field, Set<String> allowed, {String code = 'field_invalid_value'}) {
    final value = at(field);
    if (value is! String || !allowed.contains(value)) {
      errors.add(error(code, field, '$field 必须是 ${allowed.join('/')} 之一，实际为 $value'));
      return null;
    }
    return value;
  }

  List<String>? stringList(String field, {bool required = true}) {
    final value = at(field);
    if (value == null) {
      if (required) errors.add(error('field_missing', field, '$field 必须是非空字符串数组'));
      return null;
    }
    if (value is! List) {
      errors.add(error('field_not_array', field, '$field 必须是数组'));
      return null;
    }
    final out = <String>[];
    for (var i = 0; i < value.length; i++) {
      if (value[i] is! String || (value[i] as String).isEmpty) {
        errors.add(error('invalid_string_list', '$field/$i', '$field 元素必须是非空字符串'));
        return required ? null : const <String>[];
      }
      out.add(value[i] as String);
    }
    if (required && out.isEmpty) {
      errors.add(error('invalid_string_list', field, '$field 必须是非空字符串数组'));
      return null;
    }
    return out;
  }

  AdmissionError error(String code, String field, String message) => AdmissionError(
        code: code,
        pointer: field.isEmpty ? pointer : '$pointer/$field',
        message: message,
      );
}
