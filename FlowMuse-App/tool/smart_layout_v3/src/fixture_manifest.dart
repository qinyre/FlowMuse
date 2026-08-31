import 'deterministic_execution_environment.dart';

/// 智能排版 v3 FixtureManifest 契约解析器（V3-001A）。
///
/// 结构契约与 docs/研发记录/specs/smart-layout-v3/fixture-manifest.schema.json
/// 逐字段一致：本文件是唯一运行时闸门（runner 不挂 JSON Schema 引擎），
/// 因此 schema 的 required/enum/pattern/数值界与跨字段规则都必须在此机器执行：
/// - authorized_real 样本缺少 consent(granted)/anonymization/deletion/
///   user_isolation_key_hash 即拒绝；
/// - synthetic manifest 不得携带 authorized_real 录制响应（content_origin 枚举强校验）；
/// - failure_taxonomy_reference.path 固定为规范路径，防自造失败码词汇表；
/// - fixture 的 source_group_id 必须存在于来源组。
/// 所有错误一次性返回；畸形输入一律产生机器错误码，不抛未捕获异常。
class FixtureManifest {
  const FixtureManifest({
    required this.schemaVersion,
    required this.name,
    required this.version,
    required this.split,
    required this.dataBoundary,
    required this.fixtures,
    this.failureTaxonomyReference,
    this.modelReference,
  });

  static ManifestParseOutcome parse(Object? json) {
    final errors = <ManifestValidationError>[];
    if (json is! Map) {
      return ManifestParseOutcome.error(const [
        ManifestValidationError(code: 'manifest_not_object', pointer: '#', message: 'manifest 必须是 JSON 对象'),
      ]);
    }
    final root = _Obj(json, '#', errors);
    root.checkKeys({'schema_version', 'manifest_kind', 'manifest', 'data_boundary', 'fixtures'});

    // ---- 顶层版本与类型字段 ----
    if (root.string('schema_version') != expectedSchemaVersion) {
      errors.add(ManifestValidationError(
        code: 'schema_version_mismatch',
        pointer: '#/schema_version',
        message: "schema_version 必须是 '$expectedSchemaVersion'，实际为 '${root.at('schema_version')}'",
      ));
    }
    if (root.string('manifest_kind') != manifestKind) {
      errors.add(ManifestValidationError(
        code: 'manifest_kind_mismatch',
        pointer: '#/manifest_kind',
        message: "manifest_kind 必须是 '$manifestKind'",
      ));
    }

    // ---- manifest 元信息与版本字段 ----
    String? name;
    String? version;
    String? split;
    TaxonomyReference? taxonomyRef;
    ModelReference? modelRef;
    final meta = root.obj('manifest');
    if (meta != null) {
      meta.checkKeys(
          {'name', 'version', 'generated_at_utc', 'generator', 'split', 'failure_taxonomy_reference', 'model_reference'});
      name = meta.nonEmptyString('name');
      version = meta.patternString('version', semverPattern, 'semver 版本号');
      meta.patternString('generated_at_utc', utcPattern, 'UTC 时刻');
      meta.nonEmptyString('generator');
      split = meta.enumString('split', const {'synthetic', 'development', 'validation', 'frozen_holdout'});
      final ref = meta.obj('failure_taxonomy_reference', required: false);
      if (ref != null) {
        ref.checkKeys({'path', 'sha256'});
        final path = ref.nonEmptyString('path');
        final sha = ref.patternString('sha256', sha256Pattern, 'SHA-256', code: 'invalid_sha256');
        if (path != null && path != canonicalTaxonomyPath) {
          errors.add(const ManifestValidationError(
            code: 'taxonomy_path_invalid',
            pointer: '#/manifest/failure_taxonomy_reference/path',
            message: 'failure_taxonomy_reference.path 必须是规范路径 $canonicalTaxonomyPath',
          ));
        }
        if (path != null && sha != null) {
          taxonomyRef = TaxonomyReference(path: path, sha256: sha);
        }
      }
      final model = meta.obj('model_reference', required: false);
      if (model != null) {
        model.checkKeys({'name', 'version', 'hash'});
        final modelName = model.nonEmptyString('name');
        final modelVersion = model.nonEmptyString('version');
        final modelHash = model.patternString('hash', sha256Pattern, 'SHA-256', required: false);
        if (modelName != null && modelVersion != null) {
          modelRef = ModelReference(name: modelName, version: modelVersion, hash: modelHash);
        }
      }
    }

    // ---- 数据边界：来源组、授权/脱敏/删除 ----
    final boundaryObj = root.obj('data_boundary');
    DataBoundary? boundary;
    if (boundaryObj == null) {
      errors.add(const ManifestValidationError(
        code: 'data_boundary_missing',
        pointer: '#/data_boundary',
        message: 'data_boundary 对象缺失；缺少数据边界元数据的样本无法进入 runner',
      ));
    } else {
      boundaryObj.checkKeys(
          {'origin', 'source_groups', 'consent', 'anonymization', 'deletion', 'user_isolation_key_hash', 'forbidden_uses'});
      boundary = _parseDataBoundary(boundaryObj, errors);
    }

    // ---- fixtures ----
    final fixturesJson = root.at('fixtures');
    final fixtures = <FixtureEntry>[];
    if (fixturesJson is! List || fixturesJson.isEmpty) {
      errors.add(const ManifestValidationError(
        code: 'fixtures_missing',
        pointer: '#/fixtures',
        message: 'fixtures 必须是非空数组',
      ));
    } else {
      final seenIds = <String>{};
      final groupIds = boundary?.sourceGroups.map((g) => g.id).toSet() ?? const <String>{};
      for (var i = 0; i < fixturesJson.length; i++) {
        final fixture = _Obj(fixturesJson[i], '#/fixtures/$i', errors);
        if (fixture.raw is! Map) {
          errors.add(ManifestValidationError(
            code: 'fixture_not_object',
            pointer: '#/fixtures/$i',
            message: 'fixture 必须是 JSON 对象',
          ));
          continue;
        }
        final parsed = _parseFixture(fixture, boundary, groupIds, errors);
        if (parsed != null) {
          if (!seenIds.add(parsed.id)) {
            errors.add(ManifestValidationError(
              code: 'duplicate_fixture_id',
              pointer: '#/fixtures/$i/id',
              message: "fixture id 重复：${parsed.id}",
            ));
          }
          fixtures.add(parsed);
        }
      }
    }

    if (errors.isNotEmpty) {
      return ManifestParseOutcome.error(errors);
    }
    return ManifestParseOutcome.ok(FixtureManifest(
      schemaVersion: root.string('schema_version')!,
      name: name!,
      version: version!,
      split: split!,
      dataBoundary: boundary!,
      fixtures: fixtures,
      failureTaxonomyReference: taxonomyRef,
      modelReference: modelRef,
    ));
  }

  static DataBoundary? _parseDataBoundary(_Obj boundary, List<ManifestValidationError> errors) {
    final origin = boundary.enumString('origin', const {'synthetic', 'authorized_real'});
    final groupsJson = boundary.at('source_groups');
    final groups = <SourceGroup>[];
    if (groupsJson is! List || groupsJson.isEmpty) {
      errors.add(const ManifestValidationError(
        code: 'source_groups_missing',
        pointer: '#/data_boundary/source_groups',
        message: 'source_groups 必须是非空数组（来源组）',
      ));
    } else {
      for (var i = 0; i < groupsJson.length; i++) {
        final group = _Obj(groupsJson[i], '#/data_boundary/source_groups/$i', errors);
        if (group.raw is! Map) {
          errors.add(ManifestValidationError(
            code: 'source_group_not_object',
            pointer: '#/data_boundary/source_groups/$i',
            message: '来源组必须是 JSON 对象',
          ));
          continue;
        }
        group.checkKeys({'id', 'origin', 'user_isolation_key_hash', 'sample_count', 'collected_at_utc', 'reference'});
        final id = group.patternString('id', idPattern, '来源组 id');
        final groupOrigin = group.enumString('origin', const {'synthetic', 'authorized_real'});
        String? isolationKey;
        if (group.fieldPresent('user_isolation_key_hash')) {
          isolationKey = group.nullablePattern('user_isolation_key_hash', sha256Pattern, 'SHA-256');
        } else {
          errors.add(group.error(
              'field_missing', 'user_isolation_key_hash', 'user_isolation_key_hash 字段必须存在（可为 null）'));
        }
        final sampleCount = group.at('sample_count');
        if (sampleCount is! int || sampleCount < 1) {
          errors.add(group.error('invalid_sample_count', 'sample_count', 'sample_count 必须是 >= 1 的整数'));
        }
        group.patternString('collected_at_utc', utcPattern, 'UTC 时刻', required: false);
        if (id != null && groupOrigin != null) {
          groups.add(SourceGroup(id: id, origin: groupOrigin, userIsolationKeyHash: isolationKey));
        }
      }
    }
    final forbiddenUses = boundary.at('forbidden_uses');
    if (forbiddenUses is! List || forbiddenUses.isEmpty) {
      errors.add(const ManifestValidationError(
        code: 'forbidden_uses_missing',
        pointer: '#/data_boundary/forbidden_uses',
        message: 'forbidden_uses 禁止用途清单必须是非空数组',
      ));
    } else {
      for (var i = 0; i < forbiddenUses.length; i++) {
        if (forbiddenUses[i] is! String || (forbiddenUses[i] as String).isEmpty) {
          errors.add(boundary.error('invalid_forbidden_use', 'forbidden_uses/$i', '禁止用途必须是非空字符串'));
        }
      }
    }

    Consent? consent;
    Anonymization? anonymization;
    Deletion? deletion;
    if (origin == 'authorized_real') {
      // 核心边界：真实样本缺少任一元数据即拒绝，错误码逐项给出。
      final consentObj = boundary.obj('consent');
      if (consentObj == null) {
        errors.add(const ManifestValidationError(
          code: 'data_boundary_missing_consent',
          pointer: '#/data_boundary/consent',
          message: 'authorized_real 样本缺少授权元数据（consent），无法进入 runner',
        ));
      } else {
        final status = consentObj.enumString('status', const {'granted', 'not_required'});
        if (status != null && status != 'granted') {
          errors.add(const ManifestValidationError(
            code: 'consent_not_granted',
            pointer: '#/data_boundary/consent/status',
            message: '真实样本的 consent.status 必须是 granted',
          ));
        }
        consentObj.checkKeys({'status', 'granted_at_utc', 'scope', 'reference'});
        consentObj.patternString('granted_at_utc', utcPattern, 'UTC 时刻', required: false);
        consentObj.nonEmptyString('scope');
        consentObj.nonEmptyString('reference');
        consent = Consent(status: status ?? 'granted');
      }
      final anonObj = boundary.obj('anonymization');
      if (anonObj == null) {
        errors.add(const ManifestValidationError(
          code: 'data_boundary_missing_anonymization',
          pointer: '#/data_boundary/anonymization',
          message: 'authorized_real 样本缺少脱敏元数据（anonymization），无法进入 runner',
        ));
      } else {
        anonObj.checkKeys({'status', 'method', 'applied_at_utc'});
        final status = anonObj.enumString('status', const {'not_required', 'applied'});
        anonObj.nonEmptyString('method', required: false);
        anonObj.patternString('applied_at_utc', utcPattern, 'UTC 时刻', required: false);
        anonymization = Anonymization(status: status ?? '');
      }
      final deletionObj = boundary.obj('deletion');
      if (deletionObj == null) {
        errors.add(const ManifestValidationError(
          code: 'data_boundary_missing_deletion',
          pointer: '#/data_boundary/deletion',
          message: 'authorized_real 样本缺少删除策略元数据（deletion），无法进入 runner',
        ));
      } else {
        deletionObj.checkKeys({'policy_id', 'retention_until_utc', 'verified_at_utc', 'reference'});
        final policyId = deletionObj.nonEmptyString('policy_id');
        deletionObj.nullablePattern('retention_until_utc', utcPattern, 'UTC 时刻');
        deletionObj.patternString('verified_at_utc', utcPattern, 'UTC 时刻');
        deletionObj.nonEmptyString('reference');
        deletion = Deletion(policyId: policyId ?? '');
      }
      boundary.patternString('user_isolation_key_hash', sha256Pattern, 'SHA-256', code: 'invalid_sha256');
      for (final group in groups) {
        if (group.userIsolationKeyHash == null) {
          errors.add(ManifestValidationError(
            code: 'source_group_missing_isolation_key',
            pointer: '#/data_boundary/source_groups/${group.id}',
            message: '真实来源组 ${group.id} 缺少 user_isolation_key_hash（用户隔离键）',
          ));
        }
      }
    }
    if (origin == null) return null;
    return DataBoundary(
      origin: origin,
      sourceGroups: groups,
      consent: consent,
      anonymization: anonymization,
      deletion: deletion,
    );
  }

  static FixtureEntry? _parseFixture(
    _Obj fixture,
    DataBoundary? boundary,
    Set<String> groupIds,
    List<ManifestValidationError> errors,
  ) {
    final pointer = fixture.pointer;
    fixture.checkKeys({
      'id', 'description', 'source_group_id', 'features', 'scene', 'image', 'environment',
      'element_integrity', 'recorded_responses', 'expected'
    });
    final id = fixture.patternString('id', idPattern, 'fixture id');
    final sourceGroupId = fixture.patternString('source_group_id', groupIdPattern, '来源组 id');
    if (sourceGroupId != null && !groupIds.contains(sourceGroupId)) {
      errors.add(fixture.error('unknown_source_group', 'source_group_id', 'fixture 引用的来源组不存在：$sourceGroupId'));
    }

    final features = _parseFeatures(fixture.obj('features'), fixture, errors);

    final sceneRef = _parseArtifactRef(fixture.obj('scene'), '$pointer/scene', errors);
    final imageRef = _parseArtifactRef(fixture.obj('image', required: false), '$pointer/image', errors, required: false);

    final envObj = fixture.obj('environment');
    DeterministicExecutionEnvironment? environment;
    if (envObj == null) {
      errors.add(fixture.error('environment_missing', 'environment', '确定性环境缺失'));
    } else {
      envObj.checkKeys({'dpr', 'locale', 'timezone', 'clock', 'random_seed', 'fonts', 'platform', 'network_mode'});
      final dpr = envObj.at('dpr');
      if (dpr is! num || dpr <= 0) {
        errors.add(envObj.error('invalid_dpr', 'dpr', 'dpr 必须是 > 0 的数'));
      }
      envObj.patternString('locale', localePattern, 'BCP-47 locale');
      envObj.nonEmptyString('timezone');
      final clock = envObj.obj('clock');
      if (clock == null) {
        errors.add(envObj.error('clock_not_fixed', 'clock', 'clock 必须是固定时钟对象'));
      } else {
        clock.checkKeys({'mode', 'fixed_at_utc'});
        if (clock.at('mode') != 'fixed') {
          errors.add(clock.error('clock_not_fixed', 'mode', "clock.mode 必须是 fixed，实际为 '${clock.at('mode')}'"));
        }
        clock.patternString('fixed_at_utc', utcPattern, 'UTC 时刻');
      }
      final seed = envObj.at('random_seed');
      if (seed is! int || seed < 0) {
        errors.add(envObj.error('invalid_random_seed', 'random_seed', 'random_seed 必须是 >= 0 的整数'));
      }
      final fonts = envObj.at('fonts');
      if (fonts is! List || fonts.isEmpty) {
        errors.add(envObj.error('fonts_empty', 'fonts', 'fonts 必须是非空数组（固定字体集合）'));
      } else {
        for (var i = 0; i < fonts.length; i++) {
          final font = _Obj(fonts[i], '${envObj.pointer}/fonts/$i', errors);
          if (font.raw is! Map) {
            errors.add(font.error('font_not_object', '', '字体必须是 {family, file, sha256} 对象'));
            continue;
          }
          font.checkKeys({'family', 'file', 'sha256'});
          font.nonEmptyString('family');
          font.nonEmptyString('file');
          font.patternString('sha256', sha256Pattern, 'SHA-256', code: 'invalid_sha256');
        }
      }
      envObj.enumString('platform', const {'android', 'ios', 'macos', 'windows', 'web', 'ohos'});
      if (envObj.at('network_mode') != 'offline_replay') {
        errors.add(envObj.error('network_mode_not_offline', 'network_mode',
            "network_mode 必须是 offline_replay，实际为 '${envObj.at('network_mode')}'"));
      }
      environment = _tryEnvironment(envObj.raw);
    }

    final integrityObj = fixture.obj('element_integrity');
    ElementIntegrity? integrity;
    if (integrityObj == null) {
      errors.add(fixture.error('element_integrity_missing', 'element_integrity', 'element_integrity（元素 id/versionNonce 固定）缺失'));
    } else {
      integrityObj.checkKeys({'element_ids_sha256', 'version_nonce_seed'});
      final idsSha = integrityObj.patternString('element_ids_sha256', sha256Pattern, 'SHA-256', code: 'invalid_sha256');
      final seed = integrityObj.at('version_nonce_seed');
      if (seed is! int || seed < 0) {
        errors.add(integrityObj.error('invalid_version_nonce_seed', 'version_nonce_seed', 'version_nonce_seed 必须是 >= 0 的整数'));
      }
      if (idsSha != null && seed is int) {
        integrity = ElementIntegrity(elementIdsSha256: idsSha, versionNonceSeed: seed);
      }
    }

    final responses = <RecordedResponse>[];
    final responsesJson = fixture.list('recorded_responses');
    if (responsesJson != null) {
      for (var i = 0; i < responsesJson.length; i++) {
        final response = _Obj(responsesJson[i], '$pointer/recorded_responses/$i', errors);
        if (response.raw is! Map) {
          errors.add(response.error('recorded_response_not_object', '', '录制响应必须是 JSON 对象'));
          continue;
        }
        final name = response.nonEmptyString('name');
        final kind = response.enumString('kind', const {'vlm_overview', 'vlm_crop', 'ocr', 'other_network'});
        final contentOrigin = response.enumString('content_origin', const {'synthetic', 'authorized_real'});
        final path = response.nonEmptyString('path');
        response.patternString('sha256', sha256Pattern, 'SHA-256', code: 'invalid_sha256');
        response.checkKeys({'name', 'kind', 'content_origin', 'path', 'sha256'});
        if (boundary != null && contentOrigin == 'authorized_real' && boundary.origin != 'authorized_real') {
          errors.add(response.error(
            'real_recording_requires_authorized_origin',
            'content_origin',
            'synthetic manifest 不得携带 authorized_real 录制响应（数据授权前 record/replay 只接受合成内容）',
          ));
        }
        if (name != null && kind != null && contentOrigin != null && path != null) {
          responses.add(RecordedResponse(name: name, kind: kind, contentOrigin: contentOrigin, path: path));
        }
      }
    }

    final expectedObj = fixture.obj('expected');
    ExpectedArtifacts? expected;
    if (expectedObj == null) {
      errors.add(fixture.error('expected_missing', 'expected', '期望产物（expected）缺失'));
    } else {
      final coverage = expectedObj.obj('coverage');
      var minRecall = 0.0;
      if (coverage == null) {
        errors.add(expectedObj.error('invalid_coverage', 'coverage', 'expected.coverage 对象缺失'));
      } else {
        coverage.checkKeys({'min_source_recall'});
        final recall = coverage.at('min_source_recall');
        if (recall is! num || recall < 0 || recall > 1) {
          errors.add(coverage.error('invalid_coverage', 'min_source_recall', 'min_source_recall 必须是 [0,1] 内的数'));
        } else {
          minRecall = recall.toDouble();
        }
      }
      expectedObj.checkKeys({'coverage', 'relations', 'reading_order', 'renderer_golden', 'failure_codes'});
      final relationsJson = expectedObj.list('relations');
      final relations = <ExpectedRelation>[];
      if (relationsJson != null) {
        for (var i = 0; i < relationsJson.length; i++) {
          final relation = _Obj(relationsJson[i], '${expectedObj.pointer}/relations/$i', errors);
          if (relation.raw is! Map) {
            errors.add(relation.error('relation_not_object', '', '期望关系必须是 JSON 对象'));
            continue;
          }
          relation.checkKeys({'type', 'from', 'to', 'confidence'});
          final type = relation.enumString('type', allowedRelationTypes, code: 'unknown_relation_type');
          final from = _stringList(relation, 'from');
          final to = _stringList(relation, 'to');
          final confidence = relation.at('confidence');
          if (confidence is! num || confidence < 0 || confidence > 1) {
            errors.add(relation.error('invalid_confidence', 'confidence', 'confidence 必须是 [0,1] 内的数'));
          }
          if (type != null && from != null && to != null) {
            relations.add(ExpectedRelation(type: type, from: from, to: to));
          }
        }
      }
      final readingOrderJson = expectedObj.list('reading_order');
      if (readingOrderJson != null) {
        if (readingOrderJson.isEmpty) {
          errors.add(expectedObj.error('invalid_reading_order', 'reading_order', 'reading_order 若给出必须非空'));
        }
        for (var i = 0; i < readingOrderJson.length; i++) {
          if (readingOrderJson[i] is! String || (readingOrderJson[i] as String).isEmpty) {
            errors.add(
                expectedObj.error('invalid_reading_order', 'reading_order/$i', 'reading_order 元素必须是非空字符串'));
          }
        }
      }
      final goldenRef = _parseArtifactRef(expectedObj.obj('renderer_golden'), '${expectedObj.pointer}/renderer_golden', errors);
      final failureCodes = <String>[];
      final codesJson = expectedObj.list('failure_codes');
      if (codesJson != null) {
        for (final code in codesJson) {
          if (code is! String || !failureCodePattern.hasMatch(code)) {
            errors.add(expectedObj.error(
              'invalid_failure_code',
              'failure_codes',
              '失败码格式非法（须为 failure-taxonomy 的 C-/M-/m- 前缀码）：$code',
            ));
          } else {
            failureCodes.add(code);
          }
        }
      }
      if (goldenRef != null) {
        expected = ExpectedArtifacts(
          minSourceRecall: minRecall,
          relations: relations,
          rendererGolden: goldenRef,
          failureCodes: failureCodes,
        );
      }
    }

    if (id == null || sceneRef == null || environment == null || integrity == null || expected == null) {
      return null;
    }
    return FixtureEntry(
      id: id,
      sourceGroupId: sourceGroupId ?? '',
      features: features,
      scene: sceneRef,
      image: imageRef,
      environment: environment,
      elementIntegrity: integrity,
      recordedResponses: responses,
      expected: expected,
    );
  }

  static DeterministicExecutionEnvironment? _tryEnvironment(Object? raw) {
    if (raw is! Map) return null;
    final dpr = raw['dpr'];
    final seed = raw['random_seed'];
    final clock = raw['clock'];
    final fonts = raw['fonts'];
    if (dpr is! num || seed is! int || clock is! Map || fonts is! List) return null;
    try {
      return DeterministicExecutionEnvironment.fromJson({
        ...raw,
        'dpr': dpr.toDouble(),
        'fonts': [for (final font in fonts) if (font is Map) font],
      });
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static PageFeatures? _parseFeatures(_Obj? features, _Obj fixture, List<ManifestValidationError> errors) {
    if (features == null) {
      errors.add(fixture.error('features_missing', 'features', '页面特征（features）缺失'));
      return null;
    }
    features.checkKeys({
      'content_kind', 'stroke_count', 'has_images', 'has_formula', 'has_shapes', 'has_groups', 'has_frames',
      'has_bindings', 'has_locked_objects', 'has_decorative_lines', 'has_list', 'long_form',
      'vertical_text_preserved', 'tidy_page', 'scattered_page', 'pressure_stress', 'known_failure_page',
    });
    final contentKind = features.enumString('content_kind', const {'handwritten_only', 'typed_only', 'mixed'});
    final strokeCount = features.at('stroke_count');
    if (strokeCount is! int || strokeCount < 0) {
      errors.add(features.error('invalid_stroke_count', 'stroke_count', 'stroke_count 必须是 >= 0 的整数'));
    }
    if (contentKind != null && strokeCount is int) {
      return PageFeatures(
        contentKind: contentKind,
        strokeCount: strokeCount,
        raw: {for (final entry in (features.raw as Map).entries) entry.key as String: entry.value},
      );
    }
    return null;
  }

  static ArtifactRef? _parseArtifactRef(
    _Obj? ref,
    String pointer,
    List<ManifestValidationError> errors, {
    bool required = true,
  }) {
    if (ref == null) {
      if (required) {
        errors.add(ManifestValidationError(
          code: 'artifact_ref_missing',
          pointer: pointer,
          message: '产物引用缺失',
        ));
      }
      return null;
    }
    ref.checkKeys({'path', 'sha256'});
    final path = ref.nonEmptyString('path');
    final sha = ref.patternString('sha256', sha256Pattern, 'SHA-256', code: 'invalid_sha256');
    if (path == null || sha == null) return null;
    return ArtifactRef(path: path, sha256: sha);
  }

  static List<String>? _stringList(_Obj obj, String field) {
    final value = obj.raw is Map ? (obj.raw as Map)[field] : null;
    if (value is! List || value.isEmpty) {
      obj.errors.add(obj.error('invalid_string_list', field, '$field 必须是非空字符串数组'));
      return null;
    }
    final out = <String>[];
    for (var i = 0; i < value.length; i++) {
      if (value[i] is! String || (value[i] as String).isEmpty) {
        obj.errors.add(obj.error('invalid_string_list', '$field/$i', '$field 元素必须是非空字符串'));
        return null;
      }
      out.add(value[i] as String);
    }
    return out;
  }

  static const String expectedSchemaVersion = '1.0.0';
  static const String manifestKind = 'smart-layout-v3-fixture-manifest';
  static const String canonicalTaxonomyPath = 'docs/研发记录/specs/smart-layout-v3/failure-taxonomy.json';

  /// 与 failure-taxonomy.json allowed_relations.registry 一致的关系类型。
  static const Set<String> allowedRelationTypes = {'caption_of', 'keep_together', 'belongs_to'};

  static final RegExp sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp semverPattern = RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$');
  static final RegExp utcPattern = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$');
  static final RegExp localePattern = RegExp(r'^[a-zA-Z]{2,3}(-[a-zA-Z0-9]+)*$');
  static final RegExp idPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,127}$');
  static final RegExp groupIdPattern = RegExp(r'^[a-z0-9_-]{1,64}$');
  static final RegExp failureCodePattern = RegExp(r'^[CMm]-[A-Z0-9-]+$');

  final String schemaVersion;
  final String name;
  final String version;
  final String split;
  final DataBoundary dataBoundary;
  final List<FixtureEntry> fixtures;
  final TaxonomyReference? failureTaxonomyReference;
  final ModelReference? modelReference;
}

/// 带指针与错误收集的对象访问器：所有字段读取都经过类型检查，
/// 畸形值产生机器错误码而不是抛异常。
class _Obj {
  _Obj(this.raw, this.pointer, this.errors);

  final Object? raw;
  final String pointer;
  final List<ManifestValidationError> errors;

  /// 读取字段；非对象宿主一律返回 null（类型错误已由各校验器登记）。
  Object? at(String field) => raw is Map ? (raw as Map)[field] : null;

  bool fieldPresent(String field) => raw is Map && (raw as Map).containsKey(field);

  /// 读取数组字段；缺失返回 null，给出但非数组产生 field_not_array 机器错误。
  List<Object?>? list(String field, {bool required = false}) {
    final value = at(field);
    if (value == null) {
      if (required) {
        errors.add(error('field_missing', field, '$field 缺失'));
      }
      return null;
    }
    if (value is! List) {
      errors.add(error('field_not_array', field, '$field 必须是数组，实际为 ${value.runtimeType}'));
      return null;
    }
    return value;
  }

  /// 与 schema additionalProperties:false 对齐：拒绝未知字段。
  void checkKeys(Set<String> allowed) {
    if (raw is! Map) return;
    for (final key in (raw as Map).keys) {
      if (!allowed.contains(key)) {
        errors.add(error('unknown_field', key.toString(), '未知字段：$key（schema additionalProperties:false）'));
      }
    }
  }

  _Obj? obj(String field, {bool required = true}) {
    final value = raw is Map ? (raw as Map)[field] : null;
    if (value is Map) {
      return _Obj(value, '$pointer/$field', errors);
    }
    if (value == null) {
      if (required) {
        errors.add(error('field_missing', field, '$field 缺失或必须是对象'));
      }
      return null;
    }
    errors.add(error('field_not_object', field, '$field 必须是 JSON 对象'));
    return null;
  }

  String? string(String field) => raw is Map && (raw as Map)[field] is String ? (raw as Map)[field] as String : null;

  String? nonEmptyString(String field, {bool required = true}) {
    final value = raw is Map ? (raw as Map)[field] : null;
    if (value == null && !required) return null;
    if (value is! String || value.isEmpty) {
      errors.add(error('field_missing_or_empty', field, '$field 必须是非空字符串'));
      return null;
    }
    return value;
  }

  String? patternString(String field, RegExp pattern, String description,
      {bool required = true, String code = 'field_invalid_format'}) {
    final value = raw is Map ? (raw as Map)[field] : null;
    if (value == null && !required) return null;
    if (value is! String || !pattern.hasMatch(value)) {
      errors.add(error(code, field, '$field 必须是合法的$description：$value'));
      return null;
    }
    return value;
  }

  String? nullablePattern(String field, RegExp pattern, String description) {
    final value = raw is Map ? (raw as Map)[field] : null;
    if (value == null) return null;
    if (value is! String || !pattern.hasMatch(value)) {
      errors.add(error('field_invalid_format', field, '$field 必须是合法的$description 或 null：$value'));
      return null;
    }
    return value;
  }

  String? enumString(String field, Set<String> allowed, {String code = 'field_invalid_value'}) {
    final value = raw is Map ? (raw as Map)[field] : null;
    if (value is! String || !allowed.contains(value)) {
      errors.add(error(code, field, '$field 必须是 ${allowed.join('/')} 之一，实际为 $value'));
      return null;
    }
    return value;
  }

  ManifestValidationError error(String code, String field, String message) =>
      ManifestValidationError(code: code, pointer: field.isEmpty ? pointer : '$pointer/$field', message: message);
}

class ManifestParseOutcome {
  const ManifestParseOutcome.ok(this.manifest) : errors = const [];
  const ManifestParseOutcome.error(this.errors) : manifest = null;

  final FixtureManifest? manifest;
  final List<ManifestValidationError> errors;
  bool get isOk => manifest != null;
}

class ManifestValidationError {
  const ManifestValidationError({required this.code, required this.pointer, required this.message});

  /// 机器可读错误码；runner/CI 按此分诊，不解析 message。
  final String code;
  final String pointer;
  final String message;

  Map<String, String> toJson() => {'code': code, 'pointer': pointer, 'message': message};

  @override
  String toString() => '$code at $pointer: $message';
}

class TaxonomyReference {
  const TaxonomyReference({required this.path, required this.sha256});
  final String path;
  final String sha256;
}

/// 被测模型引用（§5.1 schema/model hash）：V3-201x 服务端能力上线后由生成器填写；
/// 契约层保证字段可解析、hash 格式合法。
class ModelReference {
  const ModelReference({required this.name, required this.version, this.hash});
  final String name;
  final String version;
  final String? hash;
}

class DataBoundary {
  const DataBoundary({
    required this.origin,
    required this.sourceGroups,
    this.consent,
    this.anonymization,
    this.deletion,
  });
  final String origin;
  final List<SourceGroup> sourceGroups;
  final Consent? consent;
  final Anonymization? anonymization;
  final Deletion? deletion;
}

class SourceGroup {
  const SourceGroup({required this.id, required this.origin, this.userIsolationKeyHash});
  final String id;
  final String origin;
  final String? userIsolationKeyHash;
}

class Consent {
  const Consent({required this.status});
  final String status;
}

class Anonymization {
  const Anonymization({required this.status});
  final String status;
}

class Deletion {
  const Deletion({required this.policyId});
  final String policyId;
}

class PageFeatures {
  const PageFeatures({required this.contentKind, required this.strokeCount, required this.raw});
  final String contentKind;
  final int strokeCount;
  final Map<String, Object?> raw;
}

class ArtifactRef {
  const ArtifactRef({required this.path, required this.sha256});
  final String path;
  final String sha256;
}

class ElementIntegrity {
  const ElementIntegrity({required this.elementIdsSha256, required this.versionNonceSeed});
  final String elementIdsSha256;
  final int versionNonceSeed;
}

class RecordedResponse {
  const RecordedResponse({required this.name, required this.kind, required this.contentOrigin, required this.path});
  final String name;
  final String kind;
  final String contentOrigin;
  final String path;
}

class ExpectedRelation {
  const ExpectedRelation({required this.type, required this.from, required this.to});
  final String type;
  final List<String> from;
  final List<String> to;
}

class ExpectedArtifacts {
  const ExpectedArtifacts({
    required this.minSourceRecall,
    required this.relations,
    required this.rendererGolden,
    required this.failureCodes,
  });
  final double minSourceRecall;
  final List<ExpectedRelation> relations;
  final ArtifactRef rendererGolden;
  final List<String> failureCodes;
}

class FixtureEntry {
  const FixtureEntry({
    required this.id,
    required this.sourceGroupId,
    required this.features,
    required this.scene,
    required this.environment,
    required this.elementIntegrity,
    required this.expected,
    this.image,
    this.recordedResponses = const [],
  });
  final String id;
  final String sourceGroupId;
  final PageFeatures? features;
  final ArtifactRef scene;
  final ArtifactRef? image;
  final DeterministicExecutionEnvironment environment;
  final ElementIntegrity elementIntegrity;
  final List<RecordedResponse> recordedResponses;
  final ExpectedArtifacts expected;
}
