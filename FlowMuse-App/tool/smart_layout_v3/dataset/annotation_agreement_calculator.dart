/// 智能排版 v3 标注一致性计算器（V3-002A）。
///
/// 供 V3-002C 双代理盲标与后续 AI surrogate 评测计算：
/// - 两名评分者的逐样本×逐维度槽一致性（exact / Δ=1 / Δ≥2 / insufficient 翻转 / code 集分歧）；
/// - 分歧处理与 V3-000B rubric 的 DG3/DG4 语义一致：Δ=1 保守取低分不需仲裁；
///   Δ≥2、insufficient 翻转、code 集分歧进入仲裁清单；
/// - [applyArbitration] 把仲裁裁决合并为最终分数（未裁决的 Δ=1 项按 DG3 取低）。
/// 纯函数、无 IO；结果可 toJson 落盘为 annotation_report。
library;

class AnnotationAgreementCalculator {
  const AnnotationAgreementCalculator._();

  /// 计算两套标注的一致性。样本集合必须一致（同 id 集合），
  /// 否则返回 [AgreementReport] 的 errors（机器错误码 annotation_set_mismatch）。
  static AgreementReport calculate(AnnotationSet raterA, AnnotationSet raterB) {
    final errors = <String>[];
    final idsA = raterA.ratings.map((r) => r.sampleId).toSet();
    final idsB = raterB.ratings.map((r) => r.sampleId).toSet();
    if (idsA.length != raterA.ratings.length || idsB.length != raterB.ratings.length) {
      errors.add('duplicate_sample_annotation');
    }
    if (!idsA.containsAll(idsB) || !idsB.containsAll(idsA)) {
      errors.add('annotation_set_mismatch:${idsA.difference(idsB).join(',')}|${idsB.difference(idsA).join(',')}');
    }
    final byA = {for (final r in raterA.ratings) r.sampleId: r};
    final byB = {for (final r in raterB.ratings) r.sampleId: r};

    var slots = 0, exact = 0, within1 = 0;
    final perDimension = <String, DimensionAgreement>{};
    final disagreements = <DisagreementItem>[];
    final commonIds = idsA.intersection(idsB).toList()..sort();
    for (final id in commonIds) {
      final a = byA[id]!, b = byB[id]!;
      final dims = {...a.scores.keys, ...b.scores.keys}.toList()..sort();
      for (final dim in dims) {
        final av = a.scores[dim];
        final bv = b.scores[dim];
        final stat = perDimension.putIfAbsent(dim, DimensionAgreement.new);
        slots++;
        stat.slots++;
        if (av == bv) {
          exact++;
          stat.exact++;
        } else if (av == null || bv == null) {
          // insufficient vs 有分数：DG4 强制仲裁项。
          disagreements.add(DisagreementItem(
            sampleId: id,
            dimension: dim,
            raterA: av,
            raterB: bv,
            kind: 'insufficient_flip',
          ));
          stat.insufficientFlips++;
        } else if ((av - bv).abs() == 1) {
          within1++;
          stat.delta1++;
        } else {
          disagreements.add(DisagreementItem(
            sampleId: id,
            dimension: dim,
            raterA: av,
            raterB: bv,
            kind: 'delta_ge2',
          ));
          stat.deltaGe2++;
        }
      }
      final codesA = a.codes.toSet(), codesB = b.codes.toSet();
      if (!codesA.containsAll(codesB) || !codesB.containsAll(codesA)) {
        disagreements.add(DisagreementItem(
          sampleId: id,
          dimension: null,
          raterA: null,
          raterB: null,
          kind: 'code_set_difference',
          codesA: codesA.toList()..sort(),
          codesB: codesB.toList()..sort(),
        ));
      }
    }
    return AgreementReport(
      raterAId: raterA.raterId,
      raterBId: raterB.raterId,
      slots: slots,
      exact: exact,
      within1: exact + within1,
      disagreements: disagreements,
      perDimension: perDimension,
      errors: errors,
    );
  }

  /// 合并仲裁裁决，产出最终逐样本分数。
  /// - exact 槽直接采用共同分；
  /// - Δ=1 未裁决槽按 DG3 保守取低（记 conservativeApplied）；
  /// - Δ≥2 / insufficient 翻转槽必须有裁决，缺失即 errors（arbitration_missing）；
  /// - code 集分歧裁决给出最终 codes；
  /// - overall = 有分数维度的最小值（任一维 insufficient → overallInsufficient=true）。
  static AdjudicatedSet applyArbitration({
    required AnnotationSet raterA,
    required AnnotationSet raterB,
    required List<ArbitrationRuling> rulings,
  }) {
    final report = calculate(raterA, raterB);
    final errors = List<String>.of(report.errors);
    if (report.hasErrors) {
      // 样本集合不一致等前置错误：不产出裁决结果，错误原样上抛（不崩溃）。
      return AdjudicatedSet(report: report, ratings: const [], conservativeApplied: 0, errors: errors);
    }
    final rulingByItem = <String, ArbitrationRuling>{};
    for (final ruling in rulings) {
      rulingByItem['${ruling.sampleId}|${ruling.dimension ?? ''}|${ruling.kind}'] = ruling;
    }

    final byA = {for (final r in raterA.ratings) r.sampleId: r};
    final byB = {for (final r in raterB.ratings) r.sampleId: r};
    final finalRatings = <FinalRating>[];
    var conservativeApplied = 0;

    for (final entry in byA.entries) {
      final id = entry.key;
      final a = entry.value, b = byB[id]!;
      final dims = {...a.scores.keys, ...b.scores.keys}.toList()..sort();
      final scores = <String, int>{};
      final insufficient = <String>[];
      var codes = a.codes.toSet()..addAll(b.codes);
      for (final dim in dims) {
        final av = a.scores[dim], bv = b.scores[dim];
        if (av == bv) {
          if (av == null) {
            insufficient.add(dim);
          } else {
            scores[dim] = av;
          }
          continue;
        }
        final kind = (av == null || bv == null) ? 'insufficient_flip' : 'delta_ge2';
        final nonNullDelta = (av != null && bv != null) ? (av - bv).abs() : 0;
        if (kind == 'insufficient_flip' || nonNullDelta >= 2) {
          final ruling = rulingByItem['$id|$dim|$kind'];
          if (ruling == null || ruling.finalScore == null) {
            errors.add('arbitration_missing:$id|$dim|$kind');
            insufficient.add(dim);
            continue;
          }
          scores[dim] = ruling.finalScore!;
        } else if (av != null && bv != null) {
          // Δ=1：DG3 保守取低。
          conservativeApplied++;
          scores[dim] = av < bv ? av : bv;
        }
      }
      if (!_sameCodeSet(a.codes, b.codes)) {
        final codeRuling = rulingByItem['$id||code_set_difference'];
        if (codeRuling == null || codeRuling.finalCodes == null) {
          // DG4：code 集分歧必须仲裁，缺失即报错，不静默并集。
          errors.add('arbitration_missing:$id||code_set_difference');
        } else {
          codes = codeRuling.finalCodes!.toSet();
        }
      }
      final overall = scores.isEmpty ? null : scores.values.reduce((x, y) => x < y ? x : y);
      finalRatings.add(FinalRating(
        sampleId: id,
        scores: scores,
        insufficientDimensions: insufficient,
        codes: codes.toList()..sort(),
        overall: overall,
        overallInsufficient: insufficient.isNotEmpty,
      ));
    }
    return AdjudicatedSet(
      report: report,
      ratings: finalRatings,
      conservativeApplied: conservativeApplied,
      errors: errors,
    );
  }


  // ---- V3-002C 标签级双盲标注：reading_order / roles / relations ----

  /// 计算两套标签标注的一致性。样本集合必须一致（annotation_set_mismatch）。
  static LabelAgreementReport calculateLabelAgreement(LabelAnnotationSet raterA, LabelAnnotationSet raterB) {
    final errors = <String>[];
    final idsA = raterA.annotations.map((a) => a.sampleId).toSet();
    final idsB = raterB.annotations.map((a) => a.sampleId).toSet();
    if (idsA.length != raterA.annotations.length || idsB.length != raterB.annotations.length) {
      errors.add('duplicate_sample_annotation');
    }
    if (!idsA.containsAll(idsB) || !idsB.containsAll(idsA)) {
      errors.add('annotation_set_mismatch');
    }
    final byA = {for (final a in raterA.annotations) a.sampleId: a};
    final byB = {for (final a in raterB.annotations) a.sampleId: a};
    final items = <LabelDisagreementItem>[];
    var samples = 0, readingOrderExact = 0, rolesExact = 0, relationsExact = 0;
    var roleSlots = 0, roleSlotsExact = 0;
    for (final id in idsA.intersection(idsB).toList()..sort()) {
      samples++;
      final a = byA[id]!, b = byB[id]!;
      final roEqual = listEquals(a.readingOrder, b.readingOrder);
      if (roEqual) {
        readingOrderExact++;
      } else {
        items.add(LabelDisagreementItem(sampleId: id, field: 'reading_order'));
      }
      final roleKeys = {...a.roles.keys, ...b.roles.keys}.toList()..sort();
      var rolesMatch = true;
      for (final key in roleKeys) {
        roleSlots++;
        if (a.roles[key] == b.roles[key]) {
          roleSlotsExact++;
        } else {
          rolesMatch = false;
          items.add(LabelDisagreementItem(sampleId: id, field: 'roles:$key', valueA: a.roles[key], valueB: b.roles[key]));
        }
      }
      if (rolesMatch) rolesExact++;
      final relA = canonicalRelations(a.relations).toSet();
      final relB = canonicalRelations(b.relations).toSet();
      if (relA.length == relB.length && relA.containsAll(relB)) {
        relationsExact++;
      } else {
        items.add(LabelDisagreementItem(sampleId: id, field: 'relations'));
      }
    }
    return LabelAgreementReport(
      raterAId: raterA.raterId,
      raterBId: raterB.raterId,
      samples: samples,
      readingOrderExact: readingOrderExact,
      rolesExact: rolesExact,
      relationsExact: relationsExact,
      roleSlots: roleSlots,
      roleSlotsExact: roleSlotsExact,
      disagreements: items,
      errors: errors,
    );
  }

  /// 合并标签仲裁：字段一致直接采用；不一致必须有裁决，缺失即 arbitration_missing。
  static LabelAdjudicatedSet applyLabelArbitration({
    required LabelAnnotationSet raterA,
    required LabelAnnotationSet raterB,
    required List<LabelRuling> rulings,
  }) {
    final report = calculateLabelAgreement(raterA, raterB);
    final errors = List<String>.of(report.errors);
    if (report.hasErrors) {
      return LabelAdjudicatedSet(report: report, annotations: const [], errors: errors);
    }
    final rulingByItem = <String, LabelRuling>{};
    for (final ruling in rulings) {
      rulingByItem['${ruling.sampleId}|${ruling.field}'] = ruling;
    }
    final byA = {for (final a in raterA.annotations) a.sampleId: a};
    final byB = {for (final a in raterB.annotations) a.sampleId: a};
    final out = <LabelAnnotation>[];
    for (final id in byA.keys.toList()..sort()) {
      final a = byA[id]!, b = byB[id]!;
      // List 的 == 是引用比较，须走 listEquals 内容比较；裁决载荷缺失即报错，不静默回退。
      final List<String> readingOrder;
      if (listEquals(a.readingOrder, b.readingOrder)) {
        readingOrder = a.readingOrder;
      } else {
        final ruling = rulingByItem['$id|reading_order'];
        if (ruling == null) {
          errors.add('arbitration_missing:$id|reading_order');
          readingOrder = a.readingOrder;
        } else if (ruling.readingOrder == null) {
          errors.add('arbitration_payload_missing:$id|reading_order');
          readingOrder = a.readingOrder;
        } else {
          readingOrder = ruling.readingOrder!;
        }
      }
      final roles = <String, String>{};
      for (final key in {...a.roles.keys, ...b.roles.keys}.toList()..sort()) {
        // 角色分歧的裁决必须携带 roleValue 载荷，缺失即报错。
        if (a.roles[key] == b.roles[key]) {
          roles[key] = a.roles[key] ?? b.roles[key] ?? '';
          continue;
        }
        final ruling = rulingByItem['$id|roles:$key'];
        if (ruling == null) {
          errors.add('arbitration_missing:$id|roles:$key');
          roles[key] = a.roles[key] ?? '';
        } else if (ruling.roleValue == null) {
          errors.add('arbitration_payload_missing:$id|roles:$key');
          roles[key] = a.roles[key] ?? '';
        } else {
          roles[key] = ruling.roleValue!;
        }
      }
      final relA = canonicalRelations(a.relations).toSet();
      final relB = canonicalRelations(b.relations).toSet();
      List<LabelRelation> relations;
      if (relA.length == relB.length && relA.containsAll(relB)) {
        relations = a.relations;
      } else {
        final ruling = rulingByItem['$id|relations'];
        if (ruling == null) {
          errors.add('arbitration_missing:$id|relations');
          relations = a.relations;
        } else if (ruling.relations == null) {
          // 载荷缺失与空列表不同：空列表是合法裁决值，缺失必须报错。
          errors.add('arbitration_payload_missing:$id|relations');
          relations = a.relations;
        } else {
          relations = ruling.relations!;
        }
      }
      out.add(LabelAnnotation(
        sampleId: id, readingOrder: readingOrder, roles: roles, relations: relations));
    }
    return LabelAdjudicatedSet(report: report, annotations: out, errors: errors);
  }

  static List<String> canonicalRelations(List<LabelRelation> relations) {
    final sorted = List<LabelRelation>.of(relations)
      ..sort((x, y) => '${x.type}|${x.from}|${x.to}'.compareTo('${y.type}|${y.from}|${y.to}'));
    return [for (final r in sorted) '${r.type}|${r.from}|${r.to}'];
  }

  static bool _sameCodeSet(List<String> a, List<String> b) {
    final setA = a.toSet(), setB = b.toSet();
    return setA.length == setB.length && setA.containsAll(setB);
  }
}

bool listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 一名评分者对一套样本的标注。
class AnnotationSet {
  const AnnotationSet({required this.raterId, required this.ratings});
  final String raterId;
  final List<AnnotationRating> ratings;
}

/// 单样本标注：维度分数（null = insufficient）+ 识别 code 集。
class AnnotationRating {
  const AnnotationRating({required this.sampleId, required this.scores, this.codes = const []});
  final String sampleId;
  final Map<String, int?> scores;
  final List<String> codes;
}

class DimensionAgreement {
  var slots = 0, exact = 0, delta1 = 0, deltaGe2 = 0, insufficientFlips = 0;
  Map<String, int> toJson() => {
        'slots': slots,
        'exact': exact,
        'delta_1': delta1,
        'delta_ge2': deltaGe2,
        'insufficient_flips': insufficientFlips,
      };
}

class DisagreementItem {
  const DisagreementItem({
    required this.sampleId,
    required this.dimension,
    required this.raterA,
    required this.raterB,
    required this.kind,
    this.codesA = const [],
    this.codesB = const [],
  });
  final String sampleId;
  final String? dimension;
  final int? raterA;
  final int? raterB;
  final String kind;
  final List<String> codesA;
  final List<String> codesB;

  Map<String, Object?> toJson() => {
        'sample_id': sampleId,
        'dimension': dimension,
        'rater_a': raterA,
        'rater_b': raterB,
        'kind': kind,
        if (kind == 'code_set_difference') ...{'codes_a': codesA, 'codes_b': codesB},
      };
}

class AgreementReport {
  const AgreementReport({
    required this.raterAId,
    required this.raterBId,
    required this.slots,
    required this.exact,
    required this.within1,
    required this.disagreements,
    required this.perDimension,
    required this.errors,
  });
  final String raterAId;
  final String raterBId;
  final int slots;
  final int exact;
  final int within1;
  final List<DisagreementItem> disagreements;
  final Map<String, DimensionAgreement> perDimension;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;

  Map<String, Object?> toJson() {
    final deltaGe2Total =
        perDimension.values.map((d) => d.deltaGe2).fold<int>(0, (a, b) => a + b);
    final insufficientFlipsTotal =
        perDimension.values.map((d) => d.insufficientFlips).fold<int>(0, (a, b) => a + b);
    return {
        'unit': 'sample × dimension slot',
        'rater_a': raterAId,
        'rater_b': raterBId,
        'slots': slots,
        'exact': exact,
        'exact_rate': slots == 0 ? null : exact / slots,
        'within_1': within1,
        'delta_ge2': deltaGe2Total,
        'insufficient_flips': insufficientFlipsTotal,
        'code_set_differences':
            disagreements.where((d) => d.kind == 'code_set_difference').length,
        'arbitration_eligible': disagreements.length,
        'per_dimension': {for (final e in perDimension.entries) e.key: e.value.toJson()},
        'disagreement_items': [for (final d in disagreements) d.toJson()],
        'errors': errors,
      };
  }
}

/// 一条仲裁裁决（DG4：只裁分歧项）。
class ArbitrationRuling {
  const ArbitrationRuling({
    required this.sampleId,
    required this.kind,
    this.dimension,
    this.finalScore,
    this.finalCodes,
  });
  final String sampleId;
  final String? dimension;
  final String kind;
  final int? finalScore;
  final List<String>? finalCodes;
}

class FinalRating {
  const FinalRating({
    required this.sampleId,
    required this.scores,
    required this.insufficientDimensions,
    required this.codes,
    required this.overall,
    required this.overallInsufficient,
  });
  final String sampleId;
  final Map<String, int> scores;
  final List<String> insufficientDimensions;
  final List<String> codes;
  final int? overall;
  final bool overallInsufficient;
}

class AdjudicatedSet {
  const AdjudicatedSet({
    required this.report,
    required this.ratings,
    required this.conservativeApplied,
    required this.errors,
  });
  final AgreementReport report;
  final List<FinalRating> ratings;
  final int conservativeApplied;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;

  Map<String, Object?> toJson() => {
        'agreement': report.toJson(),
        'conservative_delta1_applied': conservativeApplied,
        'ratings': [
          for (final r in ratings)
            {
              'sample_id': r.sampleId,
              'scores': r.scores,
              'insufficient_dimensions': r.insufficientDimensions,
              'codes': r.codes,
              'overall': r.overall,
              'overall_insufficient': r.overallInsufficient,
            }
        ],
        'errors': errors,
      };
}

/// 一名标注者的标签集合（V3-002C）。
class LabelAnnotationSet {
  const LabelAnnotationSet({required this.raterId, required this.annotations});
  final String raterId;
  final List<LabelAnnotation> annotations;

  /// 标注者输出文件的解析契约（annotator-*.json）。
  static LabelAnnotationSet fromJson(Map<String, Object?> raw) {
    final annotations = <LabelAnnotation>[];
    for (final entry in raw['annotations'] as List) {
      final m = entry as Map<String, Object?>;
      annotations.add(LabelAnnotation(
        sampleId: m['sample_id'] as String,
        readingOrder: [for (final e in m['reading_order'] as List) e as String],
        roles: {
          for (final e in (m['roles'] as Map<String, Object?>).entries) e.key: e.value as String,
        },
        relations: [
          for (final r in (m['relations'] as List? ?? const []))
            LabelRelation(
              type: (r as Map<String, Object?>)['type'] as String,
              from: r['from'] as String,
              to: r['to'] as String,
            ),
        ],
      ));
    }
    return LabelAnnotationSet(raterId: raw['annotator'] as String? ?? '?', annotations: annotations);
  }
}

/// 单样本标签：阅读顺序、逐元素角色、关系三元组。
class LabelAnnotation {
  const LabelAnnotation({
    required this.sampleId,
    required this.readingOrder,
    required this.roles,
    required this.relations,
  });
  final String sampleId;
  final List<String> readingOrder;
  final Map<String, String> roles;
  final List<LabelRelation> relations;
}

class LabelRelation {
  const LabelRelation({required this.type, required this.from, required this.to});
  final String type;
  final String from;
  final String to;
}

class LabelDisagreementItem {
  const LabelDisagreementItem({
    required this.sampleId,
    required this.field,
    this.valueA,
    this.valueB,
  });
  final String sampleId;
  final String field;
  final String? valueA;
  final String? valueB;
}

class LabelRuling {
  const LabelRuling({
    required this.sampleId,
    required this.field,
    this.readingOrder,
    this.roleValue,
    this.relations,
  });
  final String sampleId;
  final String field;
  final List<String>? readingOrder;
  final String? roleValue;

  /// null=未提供载荷（报错）；空列表是合法裁决值（例如裁决为无关系）。
  final List<LabelRelation>? relations;

  /// 仲裁输出文件的解析契约（arbitration-rulings.json）。
  /// 裁决字段名：reading_order / role_value / final_relations。
  static LabelRuling fromJson(Map<String, Object?> raw) => LabelRuling(
        sampleId: raw['sample_id'] as String,
        field: raw['field'] as String,
        readingOrder: (raw['reading_order'] as List?)?.cast<String>(),
        roleValue: raw['role_value'] as String?,
        relations: raw.containsKey('final_relations')
            ? [
                for (final r in (raw['final_relations'] as List))
                  LabelRelation(
                    type: (r as Map<String, Object?>)['type'] as String,
                    from: r['from'] as String,
                    to: r['to'] as String,
                  ),
              ]
            : null,
      );
}

class LabelAgreementReport {
  const LabelAgreementReport({
    required this.raterAId,
    required this.raterBId,
    required this.samples,
    required this.readingOrderExact,
    required this.rolesExact,
    required this.relationsExact,
    required this.roleSlots,
    required this.roleSlotsExact,
    required this.disagreements,
    required this.errors,
  });
  final String raterAId;
  final String raterBId;
  final int samples;
  final int readingOrderExact;
  final int rolesExact;
  final int relationsExact;
  final int roleSlots;
  final int roleSlotsExact;
  final List<LabelDisagreementItem> disagreements;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;

  Map<String, Object?> toJson() => {
        'samples': samples,
        'reading_order_exact': readingOrderExact,
        'reading_order_rate': samples == 0 ? null : readingOrderExact / samples,
        'roles_exact': rolesExact,
        'roles_rate': samples == 0 ? null : rolesExact / samples,
        'role_slots': roleSlots,
        'role_slots_exact_rate': roleSlots == 0 ? null : roleSlotsExact / roleSlots,
        'relations_exact': relationsExact,
        'relations_rate': samples == 0 ? null : relationsExact / samples,
        'disagreement_items': [
          for (final d in disagreements)
            {'sample_id': d.sampleId, 'field': d.field, 'a': d.valueA, 'b': d.valueB},
        ],
        'errors': errors,
      };
}

class LabelAdjudicatedSet {
  const LabelAdjudicatedSet({required this.report, required this.annotations, required this.errors});
  final LabelAgreementReport report;
  final List<LabelAnnotation> annotations;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
}
