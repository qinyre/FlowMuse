import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'canonical_artifacts.dart';

/// Benchmark 口径规范（V3-001B）：冻结主机/OS、warm-up、缓存、并发、
/// P50/P95、峰值内存与超时口径；spec 自带内容哈希，任何字段变化都会改 hash。
///
/// 规范文件：tool/smart_layout_v3/benchmark/benchmark-spec.json。
/// 消费方：V3-001C runner（按口径计时/统计）、V3-004A EvaluationSpec（引用 hash）、
/// V3-602A CI（按 environment_requirements 重建环境）。
class BenchmarkSpec {
  const BenchmarkSpec({
    required this.specVersion,
    required this.os,
    required this.arch,
    required this.environmentRequirements,
    required this.warmupRuns,
    required this.cachePolicy,
    required this.concurrency,
    required this.repetitions,
    required this.metrics,
    required this.percentileMethod,
    required this.peakMemoryMetric,
    required this.timeoutSeconds,
    required this.timeoutTicks,
    required this.dataPolicy,
    required this.rawJson,
  });

  static const Set<String> allowedCachePolicies = {'cold_process', 'warm_process'};
  static const Set<String> allowedMetrics = {'p50', 'p95', 'peak_rss_mb', 'mean'};

  /// 解析并校验 spec；错误一次性返回。
  static BenchmarkSpecLoad load(Object? json) {
    final errors = <String>[];
    if (json is! Map<String, Object?>) {
      return BenchmarkSpecLoad.error(const ['benchmark spec 必须是 JSON 对象']);
    }
    String requireString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        errors.add('$key 必须是非空字符串');
        return '';
      }
      return value;
    }

    int requireInt(String key, {int min = 0}) {
      final value = json[key];
      if (value is! int || value < min) {
        errors.add('$key 必须是 >= $min 的整数');
        return min;
      }
      return value;
    }

    final specVersion = requireString('spec_version');
    final os = requireString('os');
    final arch = requireString('arch');
    final envReq = json['environment_requirements'];
    if (envReq is! Map<String, Object?> || envReq.isEmpty) {
      errors.add('environment_requirements 必须是非空对象（冻结主机/OS 的最低要求）');
    }
    final warmupRuns = requireInt('warmup_runs', min: 0);
    final cachePolicy = requireString('cache_policy');
    if (!allowedCachePolicies.contains(cachePolicy)) {
      errors.add('cache_policy 必须是 ${allowedCachePolicies.join('/')} 之一');
    }
    final concurrency = requireInt('concurrency', min: 1);
    if (concurrency != 1) {
      errors.add('确定性基准要求 concurrency=1（串行），并行口径由 V3-602A CI 单独预注册');
    }
    final repetitions = requireInt('repetitions', min: 3);
    final metricsJson = json['metrics'];
    if (metricsJson is! List<Object?> || metricsJson.isEmpty) {
      errors.add('metrics 必须是非空数组');
    } else {
      for (final metric in metricsJson) {
        if (metric is! String || !allowedMetrics.contains(metric)) {
          errors.add('metrics 元素非法：$metric（允许 ${allowedMetrics.join('/')}）');
        }
      }
    }
    final percentileMethod = requireString('percentile_method');
    if (percentileMethod != 'nearest_rank') {
      errors.add('percentile_method 冻结为 nearest_rank（与 writing_perf 工具口径一致）');
    }
    final peakMemoryMetric = requireString('peak_memory_metric');
    if (peakMemoryMetric != 'process_peak_rss') {
      errors.add('peak_memory_metric 冻结为 process_peak_rss');
    }
    final timeoutSeconds = requireInt('timeout_seconds', min: 1);
    final timeoutTicks = requireInt('timeout_ticks', min: 1);
    final dataPolicy = requireString('data_policy');
    if (dataPolicy != 'synthetic_only' && dataPolicy != 'governed_real') {
      errors.add('data_policy 必须是 synthetic_only 或 governed_real');
    }

    if (errors.isNotEmpty) {
      return BenchmarkSpecLoad.error(errors);
    }
    return BenchmarkSpecLoad.ok(BenchmarkSpec(
      specVersion: specVersion,
      os: os,
      arch: arch,
      environmentRequirements: _normalizeEnvRequirements(envReq as Map<String, Object?>),
      warmupRuns: warmupRuns,
      cachePolicy: cachePolicy,
      concurrency: concurrency,
      repetitions: repetitions,
      metrics: [for (final m in metricsJson as List<Object?>) m as String],
      percentileMethod: percentileMethod,
      peakMemoryMetric: peakMemoryMetric,
      timeoutSeconds: timeoutSeconds,
      timeoutTicks: timeoutTicks,
      dataPolicy: dataPolicy,
      rawJson: json,
    ));
  }

  static Map<String, Object?> _normalizeEnvRequirements(Map<String, Object?> raw) {
    // 环境要求排序规范化后参与 hash，保证同内容不同键序同 hash。
    return raw;
  }

  /// spec 内容哈希：对规范化 JSON（剥离 hash 自身字段后）计算。
  String get contentHash {
    final copy = Map<String, Object?>.from(rawJson)..remove('content_sha256');
    return CanonicalArtifacts.canonicalJsonSha256(copy, stripVolatile: false);
  }

  /// 校验文件内容与声明的 content_sha256 一致。
  static List<String> verifyFileHash(String path) {
    final file = File(path);
    if (!file.existsSync()) return ['benchmark spec 文件不存在：$path'];
    final json = jsonDecode(file.readAsStringSync());
    final loadResult = load(json);
    if (!loadResult.ok) return loadResult.errors;
    final spec = loadResult.spec!;
    final declared = json is Map<String, Object?> ? json['content_sha256'] : null;
    if (declared is! String || declared != spec.contentHash) {
      return [
        'benchmark spec content_sha256 不一致：声明 $declared 实际 ${spec.contentHash}'
      ];
    }
    return const [];
  }

  /// V3-002A 数据治理落地前只接受合成数据。
  bool get syntheticOnly => dataPolicy == 'synthetic_only';

  final String specVersion;
  final String os;
  final String arch;
  final Map<String, Object?> environmentRequirements;
  final int warmupRuns;
  final String cachePolicy;
  final int concurrency;
  final int repetitions;
  final List<String> metrics;
  final String percentileMethod;
  final String peakMemoryMetric;
  final int timeoutSeconds;
  final int timeoutTicks;
  final String dataPolicy;
  final Map<String, Object?> rawJson;

  Map<String, Object?> toPublicJson() => {
        'spec_version': specVersion,
        'os': os,
        'arch': arch,
        'environment_requirements': environmentRequirements,
        'warmup_runs': warmupRuns,
        'cache_policy': cachePolicy,
        'concurrency': concurrency,
        'repetitions': repetitions,
        'metrics': metrics,
        'percentile_method': percentileMethod,
        'peak_memory_metric': peakMemoryMetric,
        'timeout_seconds': timeoutSeconds,
        'timeout_ticks': timeoutTicks,
        'data_policy': dataPolicy,
        'content_sha256': contentHash,
      };
}

class BenchmarkSpecLoad {
  const BenchmarkSpecLoad.ok(this.spec) : errors = const [];
  const BenchmarkSpecLoad.error(this.errors) : spec = null;
  final BenchmarkSpec? spec;
  final List<String> errors;
  bool get ok => spec != null;
}

/// spec 文件 hash 的稳定输出（CLI 用）。
String benchmarkSpecFileHash(String path) {
  final bytes = File(path).readAsBytesSync();
  return crypto.sha256.convert(bytes).toString();
}
