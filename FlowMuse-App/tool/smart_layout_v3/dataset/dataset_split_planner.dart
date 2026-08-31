/// 智能排版 v3 分层抽样与集合隔离规划器（V3-002B）。
///
/// 输入：已通过 [DatasetAdmissionValidator] 准入的池 manifest 与预注册切分配置。
/// 保证（机器校验，违反即返回错误而非产出切分）：
/// - 同一生成种子/原稿/派生图构成的隔离组件（derivation_chain 连通分量 +
///   相同生成器身份 (name, seed, params_sha256)）绝不跨集合；
/// - 一个样本只属于一个集合，三分集并集恰为池全集；
/// - development/validation/frozen_holdout 分层覆盖满足预注册最小配额；
/// - 分配是种子化确定性过程：同池同配置同 seed 产出相同切分。
/// 所有错误一次性返回机器错误码，不抛未捕获异常。
library;

import 'dart:math' as math;

import 'dataset_admission_validator.dart';

class DatasetSplitPlanner {
  const DatasetSplitPlanner._();

  static const String configKind = 'smart-layout-v3-split-config';
  static const List<String> splitOrder = ['development', 'validation', 'frozen_holdout'];
  static const Set<String> knownAxes = {'scene_family', 'content_kind', 'complexity_band', 'platform_profile'};
  static const Set<String> knownIsolationRules = {'derivation_chain', 'same_generator_identity'};

  static SplitPlanOutcome plan({
    required Map<String, Object?> poolManifest,
    required Map<String, Object?> splitConfig,
  }) {
    final errors = <String>[];

    // ---- 配置解析 ----
    if (splitConfig['config_kind'] != configKind) {
      errors.add('config_kind_mismatch:${splitConfig['config_kind']}');
    }
    final seed = splitConfig['seed'];
    if (seed is! int || seed < 0) {
      errors.add('invalid_seed:$seed');
      return SplitPlanOutcome.error(errors);
    }
    final weightsRaw = splitConfig['weights'];
    final weights = <String, double>{};
    if (weightsRaw is Map<String, Object?>) {
      for (final name in splitOrder) {
        final value = weightsRaw[name];
        if (value is! num || value < 0) {
          errors.add('invalid_weight:$name=$value');
        } else {
          weights[name] = value.toDouble();
        }
      }
      final total = weights.values.fold<double>(0, (a, b) => a + b);
      if ((total - 1.0).abs() > 0.01) {
        errors.add('weights_not_normalized:$total');
      }
    } else {
      errors.add('weights_missing');
    }
    final quotas = <String, Map<String, int>>{for (final name in splitOrder) name: {}};
    final quotasRaw = splitConfig['min_quotas'];
    if (quotasRaw is Map<String, Object?>) {
      for (final entry in quotasRaw.entries) {
        if (!splitOrder.contains(entry.key)) {
          errors.add('unknown_split_in_quotas:${entry.key}');
          continue;
        }
        final axisMap = entry.value;
        if (axisMap is Map<String, Object?>) {
          for (final rawAxis in axisMap.keys) {
            // 兼容预注册配置的 per_<axis> 书写与裸轴名书写。
            final axis = rawAxis.startsWith('per_') ? rawAxis.substring(4) : rawAxis;
            if (!knownAxes.contains(axis)) {
              errors.add('unknown_quota_axis:$rawAxis');
              continue;
            }
            final value = axisMap[rawAxis];
            if (value is! int || value < 0) {
              errors.add('invalid_quota:${entry.key}.$axis=$value');
            } else {
              quotas[entry.key]![axis] = value;
            }
          }
        } else {
          errors.add('invalid_quota_block:${entry.key}');
        }
      }
    } else {
      errors.add('min_quotas_missing');
    }
    final isolationRaw = splitConfig['isolation'];
    if (isolationRaw is Map<String, Object?>) {
      final rules = isolationRaw['rules'];
      if (rules is List<Object?>) {
        for (final rule in rules) {
          if (rule is! String || !knownIsolationRules.contains(rule)) {
            errors.add('unknown_isolation_rule:$rule');
          }
        }
      } else {
        errors.add('isolation_rules_missing');
      }
    } else {
      errors.add('isolation_missing');
    }
    if (errors.isNotEmpty) return SplitPlanOutcome.error(errors);

    // ---- 样本与轴值提取 ----
    final samplesJson = poolManifest['samples'];
    if (samplesJson is! List || samplesJson.isEmpty) {
      return SplitPlanOutcome.error(const ['pool_empty']);
    }
    final samples = <String, Map<String, Object?>>{};
    for (final raw in samplesJson) {
      if (raw is! Map<String, Object?>) continue;
      final id = raw['sample_id'];
      if (id is String) samples[id] = raw;
    }
    if (samples.length != samplesJson.length) {
      errors.add('duplicate_or_invalid_sample_id');
    }

    String axisOf(Map<String, Object?> sample, String axis) {
      final features = sample['features'];
      final featureMap = features is Map<String, Object?> ? features : const <String, Object?>{};
      if (axis == 'content_kind') {
        final value = featureMap['content_kind'];
        return value is String && value.isNotEmpty ? value : 'unspecified';
      }
      if (axis == 'complexity_band') {
        final strokeCount = featureMap['stroke_count'];
        if (strokeCount is! int) return 'unspecified';
        if (strokeCount == 0) return 'none';
        if (strokeCount <= 15) return 'low';
        if (strokeCount <= 40) return 'medium';
        return 'high';
      }
      final value = sample[axis];
      return value is String && value.isNotEmpty ? value : 'unspecified';
    }

    // ---- 隔离组件：并查集（派生链边 + 相同生成器身份） ----
    final parent = <String, String>{for (final id in samples.keys) id: id};
    String find(String x) {
      var root = x;
      while (parent[root] != root) {
        root = parent[root]!;
      }
      var cursor = x;
      while (parent[cursor] != root) {
        final next = parent[cursor]!;
        parent[cursor] = root;
        cursor = next;
      }
      return root;
    }

    void union(String a, String b) {
      final ra = find(a), rb = find(b);
      if (ra == rb) return;
      // 确定性：字典序小的根获胜。
      if (ra.compareTo(rb) <= 0) {
        parent[rb] = ra;
      } else {
        parent[ra] = rb;
      }
    }

    for (final entry in samples.entries) {
      final sample = entry.value;
      final origin = sample['origin'];
      if (origin is! Map<String, Object?>) continue;
      final chain = origin['derivation_chain'];
      if (chain is List<Object?>) {
        for (final parent_ in chain) {
          if (parent_ is String && samples.containsKey(parent_)) {
            union(entry.key, parent_);
          }
        }
      }
    }
    final identityGroups = <String, List<String>>{};
    for (final entry in samples.entries) {
      final sample = entry.value;
      if (sample['kind'] != 'synthetic') continue;
      final origin = sample['origin'];
      final generator = origin is Map<String, Object?> ? origin['generator'] : null;
      if (generator is! Map<String, Object?>) continue;
      final name = generator['name'];
      final seedValue = generator['seed'];
      final params = generator['params_sha256'];
      if (name is String && seedValue is int && params is String) {
        final key = '$name|$seedValue|$params';
        identityGroups.putIfAbsent(key, () => []).add(entry.key);
      }
    }
    for (final group in identityGroups.values) {
      for (var i = 1; i < group.length; i++) {
        union(group.first, group[i]);
      }
    }

    final components = <String, List<String>>{};
    for (final id in samples.keys) {
      components.putIfAbsent(find(id), () => []).add(id);
    }
    for (final members in components.values) {
      members.sort();
    }

    // 组件分层轴一致性：同一组件成员必须同轴（否则无法整组件归入同一分层格）。
    final componentStrata = <String, Map<String, String>>{};
    for (final entry in components.entries) {
      final stratum = <String, String>{};
      for (final axis in knownAxes) {
        final first = axisOf(samples[entry.value.first]!, axis);
        for (final memberId in entry.value) {
          if (axisOf(samples[memberId]!, axis) != first) {
            errors.add('component_stratum_mixed:${entry.key}.$axis');
          }
        }
        stratum[axis] = first;
      }
      componentStrata[entry.key] = stratum;
    }
    if (errors.isNotEmpty) return SplitPlanOutcome.error(errors);

    // ---- 确定性分配 ----
    final random = math.Random(seed);
    final componentIds = components.keys.toList()..sort();
    // 分层格 → 组件列表（格内再按确定性洗牌，打破 id 排序与配额选择的耦合）。
    final stratumBuckets = <String, List<String>>{};
    for (final componentId in componentIds) {
      final stratum = componentStrata[componentId]!;
      final key = knownAxes.map((a) => stratum[a]).join('|');
      stratumBuckets.putIfAbsent(key, () => []).add(componentId);
    }
    for (final bucket in stratumBuckets.values) {
      bucket.shuffle(random);
    }

    final assignment = <String, String>{}; // componentId -> split
    final splitComponents = <String, List<String>>{for (final s in splitOrder) s: []};
    final total = componentIds.length;
    final targets = <String, int>{
      for (final split in splitOrder) split: (total * (weights[split] ?? 0)).round(),
    };
    int quotaFor(String split, String axis) => quotas[split]?[axis] ?? 0;

    // 未分配组件的确定性遍历顺序：分层格按 key 排序，格内保持种子化洗牌序。
    final orderedComponents = <String>[
      for (final key in stratumBuckets.keys.toList()..sort()) ...stratumBuckets[key]!,
    ];

    // 组件 c 归入 split 能新满足的配额轴数（当前计数 < 配额的轴）。
    int quotaGain(String componentId, String split) {
      var gain = 0;
      for (final axis in knownAxes) {
        final need = quotaFor(split, axis);
        if (need == 0) continue;
        final value = componentStrata[componentId]![axis]!;
        final have = splitComponents[split]!
            .where((c) => componentStrata[c]![axis] == value)
            .length;
        if (have < need) gain++;
      }
      return gain;
    }

    // 阶段一：配额压力贪心——每轮选择 (配额增益, 权重缺口, splitOrder 靠前) 最大的
    // (组件, 集合) 对；跨轴联合配额由此联合满足，避免单一 split 先吃光小分层格。
    while (true) {
      String? bestComponent;
      String? bestSplit;
      var bestGain = 0;
      var bestDeficit = -1;
      for (final componentId in orderedComponents) {
        if (assignment.containsKey(componentId)) continue;
        for (final split in splitOrder) {
          final gain = quotaGain(componentId, split);
          if (gain == 0) continue;
          final deficit = math.max(targets[split]! - splitComponents[split]!.length, 0);
          final better = gain > bestGain ||
              (gain == bestGain && deficit > bestDeficit) ||
              (gain == bestGain && deficit == bestDeficit && bestSplit == null);
          if (better) {
            bestGain = gain;
            bestDeficit = deficit;
            bestComponent = componentId;
            bestSplit = split;
          }
        }
      }
      if (bestComponent == null || bestSplit == null) break;
      assignment[bestComponent] = bestSplit;
      splitComponents[bestSplit]!.add(bestComponent);
    }

    // 阶段二：按权重分配剩余组件（目标 = round(组件数 × 权重)，缺口最大者优先，
    // 平局按 splitOrder）。
    final remaining = <String>[
      for (final componentId in orderedComponents) if (!assignment.containsKey(componentId)) componentId,
    ];
    for (final componentId in remaining) {
      String? best;
      var bestDeficit = -1.0;
      for (final split in splitOrder) {
        final deficit = targets[split]! - splitComponents[split]!.length;
        if (deficit <= 0) continue;
        // 确定性平局：按 splitOrder 顺序先到先得。
        if (deficit.toDouble() > bestDeficit) {
          bestDeficit = deficit.toDouble();
          best = split;
        }
      }
      assignment[componentId] = best ?? splitOrder.first;
      splitComponents[best ?? splitOrder.first]!.add(componentId);
    }

    // ---- 机器复核四不变量 ----
    // 1) 组件不跨集合。
    for (final entry in components.entries) {
      final splits = entry.value.map((id) => assignment[find(id)]).toSet();
      if (splits.length != 1) {
        errors.add('component_crosses_splits:${entry.key}');
      }
    }
    // 2) 样本唯一归属且全覆盖。
    final assigned = <String>{};
    for (final split in splitOrder) {
      for (final componentId in splitComponents[split]!) {
        for (final memberId in components[componentId]!) {
          if (!assigned.add(memberId)) {
            errors.add('sample_in_multiple_splits:$memberId');
          }
        }
      }
    }
    if (assigned.length != samples.length) {
      errors.add('not_all_samples_assigned:${samples.length - assigned.length}');
    }
    // 3) 配额满足。
    final quotaChecks = <Map<String, Object?>>[];
    for (final split in splitOrder) {
      for (final axis in knownAxes) {
        final need = quotaFor(split, axis);
        if (need == 0) continue;
        final values = <String>{};
        for (final componentId in componentIds) {
          values.add(componentStrata[componentId]![axis]!);
        }
        for (final value in values.toList()..sort()) {
          final actual = splitComponents[split]!
              .where((c) => componentStrata[c]![axis] == value)
              .length;
          final pass = actual >= need;
          if (!pass) {
            errors.add('quota_not_met:$split.$axis.$value=$actual<$need');
          }
          quotaChecks.add({
            'split': split, 'axis': axis, 'value': value,
            'required': need, 'actual': actual, 'pass': pass,
          });
        }
      }
    }
    if (errors.isNotEmpty) return SplitPlanOutcome.error(errors);

    // ---- 覆盖统计 ----
    final axisValues = <String, List<String>>{};
    for (final axis in knownAxes) {
      final values = componentStrata.values.map((s) => s[axis]!).toSet().toList()..sort();
      axisValues[axis] = values;
    }
    final coverage = <String, Object?>{
      for (final split in splitOrder)
        split: {
          'component_count': splitComponents[split]!.length,
          'sample_count':
              splitComponents[split]!.expand((c) => components[c]!).length,
          'per_axis': {
            for (final axis in knownAxes)
              axis: {
                for (final value in axisValues[axis]!)
                  value: splitComponents[split]!
                      .where((c) => componentStrata[c]![axis] == value)
                      .length,
              },
          },
        },
    };

    final orderedSplits = <String, List<String>>{};
    for (final split in splitOrder) {
      final samplesInSplit = <String>[];
      for (final componentId in splitComponents[split]!) {
        samplesInSplit.addAll(components[componentId]!);
      }
      samplesInSplit.sort();
      orderedSplits[split] = samplesInSplit;
    }

    return SplitPlanOutcome.ok(SplitPlan(
      splits: orderedSplits,
      components: {
        for (final entry in components.entries)
          entry.key: {
            'members': entry.value,
            'split': assignment[entry.key],
            'stratum': componentStrata[entry.key],
          },
      },
      coverage: coverage,
      quotaChecks: quotaChecks,
    ));
  }
}

class SplitPlan {
  const SplitPlan({
    required this.splits,
    required this.components,
    required this.coverage,
    required this.quotaChecks,
  });

  /// split 名 → 样本 id 列表（成员按组件分组、组件内按 id 排序）。
  final Map<String, List<String>> splits;

  /// 组件 id → {members, split, stratum}（隔离证明）。
  final Map<String, Map<String, Object?>> components;
  final Map<String, Object?> coverage;
  final List<Map<String, Object?>> quotaChecks;
}

class SplitPlanOutcome {
  const SplitPlanOutcome.ok(this.plan)
      : errors = const [],
        isOk = true;
  const SplitPlanOutcome.error(this.errors)
      : plan = null,
        isOk = false;
  final bool isOk;
  final SplitPlan? plan;
  final List<String> errors;
}
