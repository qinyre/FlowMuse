/// V3-702A：合成稳定性与故障注入评估——目标符号
/// [SyntheticStabilityEvaluator] 与 [SmartLayoutFaultInjectionMatrix]。
///
/// 用既有冻结实验的 48 个 dev 样本（datasets/splits/development/
/// manifest.json，固定 seed 洗牌重放，样本集哈希入报告）在真实客户端
/// 分析链（真实 [SmartLayoutSession] 四检守卫 + [V3AnalysisRepository]
/// 重试策略 + HTTP 网关错误映射）上注入 8 类故障：offline / timeout /
/// 429 / 500 / 503 / 坏 schema / 取消 / 迟到回调，汇总错误率、拒绝率、
/// 耗时与 critical（critical=未捕获异常 / Scene 被触碰 / 无结果逃逸）。
/// 失败样本不排除；不等待生产指标窗口（比赛交付口径）。
///
/// 运行形态：flutter test（[main] 之外的类由测试驱动）；证据一次性
/// 生成经 env 门控写入 evidence/competition/v3-702a-stability-report.json。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_request.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';

/// 故障注入矩阵：8 类故障的 fake 传输与编排语义。
abstract final class SmartLayoutFaultInjectionMatrix {
  static const List<String> faultIds = [
    'offline',
    'timeout',
    'http-429',
    'http-500',
    'http-503',
    'bad-schema',
    'cancel',
    'late-callback',
  ];

  /// 故障语义说明（入报告）。
  static const Map<String, String> semantics = {
    'offline': 'SocketException → network（可重试，耗尽后 failed）',
    'timeout': 'TimeoutException → timeout（可重试，耗尽后 failed）',
    'http-429': 'badStatus 429（可重试，耗尽后 failed）',
    'http-500': 'badStatus 500（可重试，耗尽后 failed）',
    'http-503': 'badStatus 503（可重试，耗尽后 failed）',
    'bad-schema': '200 + 非合约响应体 → badSchema（稳定失败不重试）',
    'cancel': '在途取消（响应落地前）→ late-guard 拒绝（协作式取消）',
    'late-callback': '传输延迟 50ms 后响应到达时操作已取消 → 落地前 late-guard 拒绝',
  };

  /// 每类故障的 fake 传输（迟到回调延迟 50ms 让取消先落地）。
  static SmartLayoutHttpPost postFor(String faultId) {
    switch (faultId) {
      case 'offline':
        return ({
          required String url,
          Map<String, String> headers = const {},
          required String body,
          connectTimeoutMs = 0,
          readTimeoutMs = 0,
          cancelToken,
        }) => Future.error(const io.SocketException('synthetic offline'));
      case 'timeout':
        // 真实传输边界把 TimeoutException 包成 network(detail=toString)；
        // 仓库按 detail 含 "TimeoutException" 归类 timeout，此处同口径。
        return ({
          required String url,
          Map<String, String> headers = const {},
          required String body,
          connectTimeoutMs = 0,
          readTimeoutMs = 0,
          cancelToken,
        }) => Future.error(
          const SmartLayoutHttpException.network(
            'TimeoutException: synthetic timeout after 5000ms',
          ),
        );
      case 'http-429':
      case 'http-500':
      case 'http-503':
        final status = int.parse(faultId.split('-')[1]);
        return ({
          required String url,
          Map<String, String> headers = const {},
          required String body,
          connectTimeoutMs = 0,
          readTimeoutMs = 0,
          cancelToken,
        }) => Future.error(
          SmartLayoutHttpException.badStatus(status, 'synthetic $status'),
        );
      case 'bad-schema':
        return ({
          required String url,
          Map<String, String> headers = const {},
          required String body,
          connectTimeoutMs = 0,
          readTimeoutMs = 0,
          cancelToken,
        }) => Future.value(
          NativeHttpResponse(
            statusCode: 200,
            body: '{"protocolVersion":3,"regions":"not-a-list","warnings":[]}',
          ),
        );
      case 'cancel':
        return ({
          required String url,
          Map<String, String> headers = const {},
          required String body,
          connectTimeoutMs = 0,
          readTimeoutMs = 0,
          cancelToken,
        }) => Future.value(
          NativeHttpResponse(
            statusCode: 200,
            body:
                '{"protocolVersion":3,"requestId":"cancel","regions":[],'
                '"warnings":[]}',
          ),
        );
      case 'late-callback':
        return ({
          required String url,
          Map<String, String> headers = const {},
          required String body,
          connectTimeoutMs = 0,
          readTimeoutMs = 0,
          cancelToken,
        }) => Future.delayed(
          const Duration(milliseconds: 50),
          () => NativeHttpResponse(
            statusCode: 200,
            body:
                '{"protocolVersion":3,"requestId":"late","regions":[],'
                '"warnings":[]}',
          ),
        );
      default:
        throw ArgumentError.value(faultId, 'faultId', '未知故障');
    }
  }

  /// 取消编排：两者都在分析发起后取消（系统语义：取消针对在途操作，
  /// beginOperation 会复位取消标记，"发起前取消"对本层是无操作）；
  /// cancel=即时响应在微任务前被取消拦截，late-callback=传输延迟后
  /// 到达才被 late-guard 丢弃。
}

/// 单次 (样本 × 故障) 运行结果。
class StabilityRunOutcome {
  const StabilityRunOutcome({
    required this.sampleId,
    required this.faultId,
    required this.outcomeKind,
    required this.failureKind,
    required this.attempts,
    required this.elapsedMs,
    required this.critical,
    required this.criticalReason,
  });

  final String sampleId;
  final String faultId;

  /// succeeded | failed | guardRejected | escaped（无结果=critical）。
  final String outcomeKind;

  /// failed 时的失败种类名（network/timeout/badStatus/badSchema/…）。
  final String? failureKind;
  final int attempts;
  final double elapsedMs;
  final bool critical;
  final String? criticalReason;

  Map<String, Object?> toJson() => {
    'sample_id': sampleId,
    'fault_id': faultId,
    'outcome': outcomeKind,
    if (failureKind != null) 'failure_kind': failureKind,
    'attempts': attempts,
    'elapsed_ms': elapsedMs,
    'critical': critical,
    if (criticalReason != null) 'critical_reason': criticalReason,
  };
}

/// 合成稳定性评估器：固定 seed 重放样本 × 故障矩阵。
class SyntheticStabilityEvaluator {
  SyntheticStabilityEvaluator({required this.repoRoot, this.seed = 20260902});

  final String repoRoot;

  /// 重放洗牌 seed（固定值入报告；与冻结实验统计 seed 20260831 区分）。
  final int seed;

  /// 读取 dev split 的 48 样本并按固定 seed 洗牌。
  ///
  /// 返回 (样本 id 列表, 样本内容表, 样本集哈希)。
  (List<String>, Map<String, Map<String, Object?>>, String) loadSamples() {
    final manifest = _readJson(
      '$repoRoot/docs/研发记录/evidence/smart-layout-v3/datasets/splits/'
      'development/manifest.json',
    );
    final ids = [
      for (final s
          in (manifest['samples'] as List).cast<Map<String, Object?>>())
        s['sample_id'] as String,
    ];
    final samples = <String, Map<String, Object?>>{};
    final hashes = <String>[];
    for (final id in ids) {
      final path =
          '$repoRoot/docs/研发记录/evidence/smart-layout-v3/datasets/'
          'synthetic-pool-v2/samples/$id.scene.json';
      final normalized = io.File(
        path,
      ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      hashes.add(_sha256String(normalized));
      samples[id] = _readJson(path);
    }
    final ordered = _shuffle(ids, seed);
    return (
      ordered,
      samples,
      _sha256String("${ids.join(',')};${hashes.join(',')}"),
    );
  }

  /// 由样本合成协议请求：sourceRefs=全元素 id，exactTexts=typed 文本。
  SmartLayoutV3Request buildRequest(
    String sampleId,
    Map<String, Object?> sample,
  ) {
    final elements = (sample['elements'] as List).cast<Map<String, Object?>>();
    final exactTexts = <Map<String, Object?>>[
      for (final e in elements)
        if (e['type'] == 'text' && e['text_kind'] == 'typed')
          {'sourceId': e['id'] as String, 'text': e['chars'] as String},
    ];
    return SmartLayoutV3Request.fromJson({
      'protocolVersion': 3,
      'pageId': 'stability-$sampleId',
      'sceneRevision': {
        'epoch': 0,
        'revision': 1,
        'fingerprint': '0123456789abcdef',
      },
      'assets': <Object?>[],
      'marks': <Object?>[],
      'exactTexts': exactTexts,
      'sourceRefs': [for (final e in elements) e['id'] as String],
    });
  }

  /// 单次注入运行：真实 Session/守卫/重试链 + fake 传输。
  Future<StabilityRunOutcome> runOne({
    required String sampleId,
    required Map<String, Object?> sample,
    required String faultId,
  }) async {
    final controller = MarkdrawController();
    try {
      final editor = SmartLayoutEditorGateway(controller);
      final tracker = SceneRevisionTracker(editor: editor);
      final session = SmartLayoutSession(
        editor: editor,
        revisions: tracker,
        pageId: 'stability-page',
      );
      final http = SmartLayoutHttpGateway(
        serverUri: Uri.parse('http://synthetic.invalid'),
        post: SmartLayoutFaultInjectionMatrix.postFor(faultId),
      );
      final repo = V3AnalysisRepository(http: http, session: session);
      final request = buildRequest(sampleId, sample);
      final before = SceneFingerprint.of(controller.currentScene);

      final sw = Stopwatch()..start();
      Object? escaped;
      SmartLayoutAnalysisOutcome? outcome;
      try {
        final future = repo.analyze(
          request: request,
          ticket: session.beginOperation(),
        );
        if (faultId == 'cancel' || faultId == 'late-callback') {
          session.cancelOperation();
        }
        outcome = await future;
      } catch (error) {
        escaped = error;
      }
      sw.stop();

      var critical = false;
      String? criticalReason;
      if (escaped != null) {
        critical = true;
        criticalReason = '未捕获异常：$escaped';
      } else if (outcome == null) {
        critical = true;
        criticalReason = '无结果逃逸';
      } else if (SceneFingerprint.of(controller.currentScene) != before) {
        critical = true;
        criticalReason = '故障路径触碰 Scene';
      }

      final (kind, failureKind, attempts) = switch (outcome) {
        SmartLayoutAnalysisSucceeded(:final attempts) => (
          'succeeded',
          null,
          attempts,
        ),
        SmartLayoutAnalysisFailed(:final kind, :final attempts) => (
          'failed',
          kind.name,
          attempts,
        ),
        SmartLayoutAnalysisGuardRejected(:final attempts) => (
          'guardRejected',
          null,
          attempts,
        ),
        null => ('escaped', null, 0),
      };
      return StabilityRunOutcome(
        sampleId: sampleId,
        faultId: faultId,
        outcomeKind: kind,
        failureKind: failureKind,
        attempts: attempts,
        elapsedMs: sw.elapsedMicroseconds / 1000.0,
        critical: critical,
        criticalReason: criticalReason,
      );
    } finally {
      controller.dispose();
    }
  }

  /// 全矩阵重放：48 样本 × 8 故障（失败样本不排除）。
  Future<Map<String, Object?>> evaluate({
    void Function(int done, int total)? onProgress,
  }) async {
    final (orderedSamples, samples, samplesHash) = loadSamples();
    final outcomes = <StabilityRunOutcome>[];
    var done = 0;
    final total =
        orderedSamples.length * SmartLayoutFaultInjectionMatrix.faultIds.length;
    for (final id in orderedSamples) {
      for (final fault in SmartLayoutFaultInjectionMatrix.faultIds) {
        outcomes.add(
          await runOne(sampleId: id, sample: samples[id]!, faultId: fault),
        );
        done++;
        onProgress?.call(done, total);
      }
    }
    return _summarize(
      orderedSamples: orderedSamples,
      samplesHash: samplesHash,
      outcomes: outcomes,
    );
  }

  Map<String, Object?> _summarize({
    required List<String> orderedSamples,
    required String samplesHash,
    required List<StabilityRunOutcome> outcomes,
  }) {
    final byFault = <String, Map<String, Object?>>{};
    for (final fault in SmartLayoutFaultInjectionMatrix.faultIds) {
      final runs = outcomes.where((o) => o.faultId == fault).toList();
      final failed = runs.where((o) => o.outcomeKind == 'failed').length;
      final rejected = runs
          .where((o) => o.outcomeKind == 'guardRejected')
          .length;
      final succeeded = runs.where((o) => o.outcomeKind == 'succeeded').length;
      final critical = runs.where((o) => o.critical).length;
      final latencies = runs.map((o) => o.elapsedMs).toList()..sort();
      final failureKinds = <String, int>{};
      for (final o in runs) {
        if (o.failureKind != null) {
          failureKinds[o.failureKind!] = (failureKinds[o.failureKind] ?? 0) + 1;
        }
      }
      byFault[fault] = {
        'semantics': SmartLayoutFaultInjectionMatrix.semantics[fault],
        'runs': runs.length,
        'succeeded': succeeded,
        'failed': failed,
        'guard_rejected': rejected,
        'failure_kinds': failureKinds,
        'error_rate': runs.isEmpty ? null : (failed + rejected) / runs.length,
        'critical': critical,
        'latency_ms': {
          'min': latencies.first,
          'median': latencies[latencies.length ~/ 2],
          'p95':
              latencies[((latencies.length * 0.95).floor()).clamp(
                0,
                latencies.length - 1,
              )],
          'max': latencies.last,
        },
      };
    }
    final failed = outcomes.where((o) => o.outcomeKind == 'failed').length;
    final rejected = outcomes
        .where((o) => o.outcomeKind == 'guardRejected')
        .length;
    final critical = outcomes.where((o) => o.critical).length;
    return {
      'task': 'V3-702A',
      'kind': 'synthetic_stability_report',
      'sample_source': {
        'split': 'datasets/splits/development/manifest.json',
        'sample_count': orderedSamples.length,
        'replay_order_seed': seed,
        'samples_sha256': samplesHash,
      },
      'fault_matrix': {
        'faults': SmartLayoutFaultInjectionMatrix.faultIds,
        'semantics': SmartLayoutFaultInjectionMatrix.semantics,
      },
      'totals': {
        'runs': outcomes.length,
        'failed': failed,
        'guard_rejected': rejected,
        'succeeded': outcomes.where((o) => o.outcomeKind == 'succeeded').length,
        'error_rate': outcomes.isEmpty
            ? null
            : (failed + rejected) / outcomes.length,
        'rejection_rate': outcomes.isEmpty ? null : rejected / outcomes.length,
        'critical': critical,
        'failed_samples_excluded': false,
      },
      'by_fault': byFault,
      'critical_events': [
        for (final o in outcomes.where((o) => o.critical)) o.toJson(),
      ],
      'runs': [for (final o in outcomes) o.toJson()],
    };
  }
}

Map<String, Object?> _readJson(String path) {
  final bytes = io.File(path).readAsBytesSync();
  return jsonDecode(utf8.decode(bytes, allowMalformed: false))
      as Map<String, Object?>;
}

String _sha256String(String value) =>
    crypto.sha256.convert(utf8.encode(value)).toString();

/// splitmix64 洗牌（固定 seed 确定性；与 606A 实现同族算法独立实现）。
List<String> _shuffle(List<String> items, int seed) {
  var state = seed;
  int next() {
    state = (state + 0x9E3779B97F4A7C15) & 0x7fffffffffffffff;
    var z = state;
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0x7fffffffffffffff;
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0x7fffffffffffffff;
    return z ^ (z >> 31);
  }

  final list = [...items];
  for (var i = list.length - 1; i > 0; i--) {
    final j = next() % (i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
  return list;
}
