/// V3-700A：比赛演示 smoke——目标符号 [SmartLayoutDemoSmoke]。
///
/// 四场景合成演示（默认关闭 / 阳性开启全链 / kill 跳闸 / 服务故障
/// 闭环），复用 V3-700B 的 capability / kill switch / observability
/// 本地配置（进程内 synthetic sink，零网络）：
/// 1. 默认关闭：无 capability 缓存 → open disabled（defaultOff）且
///    会话工厂零调用（零请求零 Draft 机制保证）；
/// 2. 阳性开启：未过期阳性缓存 + kill 未跳闸 → open enabled → 真实
///    编辑器全链（入口→候选→commit→undo→reopen，注入执行器在真实
///    控制器 + 本地 loopback analyzer 上运行）；
/// 3. kill 跳闸：阳性缓存 + killSwitch.trip → open disabled 且工厂
///    零调用（只关不换，无 v2 回退）；
/// 4. 服务故障闭环：本地 analyzer 故障 → 分析 fail closed（Scene 零
///    副作用）→ 按真实请求计数写入 failure 事件 → 失败率滑动窗口
///    告警 → onAlert 关闭 kill switch → 后续 open disabled。
///
/// 分层：本库不触碰编辑器控制器/HTTP 传输（gateways 最底层契约，
/// smart_layout_architecture_test.dart 守卫）——真实全链经注入执行器
/// 与会话工厂由测试侧提供。
library;

import 'smart_layout_capability.dart';
import 'smart_layout_kill_switch.dart';
import 'smart_layout_observability.dart';
import 'smart_layout_rollout_entry_gate.dart';

/// 注入的真实编辑器全链执行结果。
class SmartLayoutDemoChainResult {
  const SmartLayoutDemoChainResult({
    required this.passed,
    required this.detail,
    required this.requestCount,
  });

  /// 全链是否按预期通过（故障场景中 fail-closed 行为本身即通过）。
  final bool passed;
  final String detail;

  /// 全链实际发出的 HTTP 请求数（驱动 metrics 事件）。
  final int requestCount;
}

/// 单场景结果。
class SmartLayoutDemoSmokeScenario {
  const SmartLayoutDemoSmokeScenario({
    required this.id,
    required this.passed,
    required this.detail,
    required this.factoryCalls,
    required this.requestCount,
  });

  final String id;
  final bool passed;
  final String detail;
  final int factoryCalls;
  final int requestCount;

  Map<String, Object?> toJson() => {
    'id': id,
    'passed': passed,
    'detail': detail,
    'factory_calls': factoryCalls,
    'request_count': requestCount,
  };
}

/// smoke 报告（demo_smoke_report + synthetic_observability_report）。
class SmartLayoutDemoSmokeReport {
  const SmartLayoutDemoSmokeReport({
    required this.scenarios,
    required this.observabilitySnapshot,
  });

  final List<SmartLayoutDemoSmokeScenario> scenarios;
  final Map<String, Object?> observabilitySnapshot;

  bool get allPassed => scenarios.every((s) => s.passed);

  Map<String, Object?> toJson() => {
    'task': 'V3-700A',
    'kind': 'demo_smoke_report',
    'all_passed': allPassed,
    'scenarios': [for (final s in scenarios) s.toJson()],
    'synthetic_observability': observabilitySnapshot,
  };
}

/// 真实编辑器全链执行器：会话句柄打开后运行
/// 入口→候选→commit→undo→reopen（真实控制器 + 本地 analyzer）。
typedef SmartLayoutDemoChainRunner =
    Future<SmartLayoutDemoChainResult> Function(
      SmartLayoutV3SessionHandle handle,
    );

class SmartLayoutDemoSmoke {
  SmartLayoutDemoSmoke({
    required SmartLayoutDemoChainRunner healthyChain,
    required SmartLayoutDemoChainRunner failingChain,
    required this.nowMs,
    SmartLayoutV3SessionFactory? sessionFactory,
    SmartLayoutV3SessionFactory? failingSessionFactory,
    this.failureRateRule = const SmartLayoutFailureRateAlertRule(
      ruleId: 'demo-failure-rate',
      threshold: 0.5,
      windowMs: 600000,
      minSamples: 2,
    ),
  }) : _healthyChain = healthyChain,
       _failingChain = failingChain,
       _sessionFactory = sessionFactory,
       _failingSessionFactory = failingSessionFactory;

  final SmartLayoutDemoChainRunner _healthyChain;
  final SmartLayoutDemoChainRunner _failingChain;

  /// 真实会话工厂（enabled 场景经此创建真实 v3 会话；缺省用内部
  /// no-op 句柄——disabled 场景本就零调用）。
  final SmartLayoutV3SessionFactory? _sessionFactory;

  /// 故障场景真实会话工厂（指向故障 analyzer；缺省复用 [_sessionFactory]）。
  final SmartLayoutV3SessionFactory? _failingSessionFactory;

  /// 演示时钟（确定性：场景间用 nowMs + n 推进）。
  final int nowMs;

  /// 本地失败率告警规则（进程内配置；生产端点归外部输入，不在此）。
  final SmartLayoutFailureRateAlertRule failureRateRule;

  /// 运行四场景 smoke；返回报告。
  Future<SmartLayoutDemoSmokeReport> run() async {
    final scenarios = <SmartLayoutDemoSmokeScenario>[];

    // metrics 本地配置：进程内 sink + 失败率规则 + 告警→kill 闭环。
    final sink = LocalSyntheticMetricsSink();
    final alertKillSwitch = SmartLayoutKillSwitch();
    final observability = SmartLayoutObservability(
      sink: sink,
      rules: [failureRateRule],
      onAlert: (alert) {
        alertKillSwitch.trip('failure-rate:${alert.ruleId}');
        return true;
      },
    );

    Future<SmartLayoutDemoSmokeScenario> runGated({
      required String id,
      required SmartLayoutCapabilityRecord? cache,
      required SmartLayoutKillSwitch killSwitch,
      required SmartLayoutDemoChainRunner chain,
      required bool expectEnabled,
      SmartLayoutV3SessionFactory? sessionOverride,
    }) async {
      var factoryCalls = 0;
      final realFactory = sessionOverride ?? _sessionFactory;
      final gate = SmartLayoutRolloutEntryGate(
        capabilityCache: cache,
        killSwitch: killSwitch,
        sessionFactory: () {
          factoryCalls++;
          return realFactory != null ? realFactory() : _NoopSessionHandle();
        },
      );
      final outcome = gate.open(nowMs: nowMs);
      if (!expectEnabled) {
        return SmartLayoutDemoSmokeScenario(
          id: id,
          passed: !outcome.enabled && factoryCalls == 0,
          detail:
              'open=${outcome.enabled ? 'enabled' : 'disabled'
                  }(${outcome.reason}) factory_calls=$factoryCalls',
          factoryCalls: factoryCalls,
          requestCount: 0,
        );
      }
      if (!outcome.enabled) {
        return SmartLayoutDemoSmokeScenario(
          id: id,
          passed: false,
          detail: '预期 enabled 实际 disabled(${outcome.reason})',
          factoryCalls: factoryCalls,
          requestCount: 0,
        );
      }
      final chainResult = await chain(outcome.session!);
      return SmartLayoutDemoSmokeScenario(
        id: id,
        passed:
            chainResult.passed &&
            factoryCalls == 1 &&
            chainResult.requestCount > 0,
        detail: chainResult.detail,
        factoryCalls: factoryCalls,
        requestCount: chainResult.requestCount,
      );
    }

    // ---- 场景 1：默认关闭（无缓存 → defaultOff，零请求零 Draft）----
    observability.emit(
      SmartLayoutMetricEvent(
        kind: 'capabilityDecision',
        atMs: nowMs,
        attributes: const {
          'scenario': 'default-off',
          'enabled': false,
          'reason': 'defaultOff',
        },
      ),
    );
    scenarios.add(
      await runGated(
        id: 'default-off',
        cache: null,
        killSwitch: SmartLayoutKillSwitch(),
        chain: _healthyChain,
        expectEnabled: false,
      ),
    );

    // ---- 场景 2：阳性缓存开启 → 真实全链 ----
    final unexpired = SmartLayoutCapabilityRecord(
      enabled: true,
      expiresAtMs: nowMs + 60000,
    );
    observability.emit(
      SmartLayoutMetricEvent(
        kind: 'capabilityDecision',
        atMs: nowMs,
        attributes: const {
          'scenario': 'enabled-full-chain',
          'enabled': true,
          'reason': 'cachedPositive',
        },
      ),
    );
    final healthy = await runGated(
      id: 'enabled-full-chain',
      cache: unexpired,
      killSwitch: SmartLayoutKillSwitch(),
      chain: _healthyChain,
      expectEnabled: true,
    );
    scenarios.add(healthy);
    for (var i = 0; i < healthy.requestCount; i++) {
      observability.emit(SmartLayoutMetricEvent(kind: 'request', atMs: nowMs));
    }
    observability.emit(
      SmartLayoutMetricEvent(
        kind: 'success',
        atMs: nowMs,
        attributes: const {'scenario': 'enabled-full-chain'},
      ),
    );

    // ---- 场景 3：kill 跳闸（阳性也不放行，只关不换）----
    final trippedSwitch = SmartLayoutKillSwitch()..trip('demo-manual');
    observability.emit(
      SmartLayoutMetricEvent(
        kind: 'killSwitch',
        atMs: nowMs,
        attributes: {'scenario': 'kill-switch', 'tripped': trippedSwitch.isTripped},
      ),
    );
    scenarios.add(
      await runGated(
        id: 'kill-switch',
        cache: unexpired,
        killSwitch: trippedSwitch,
        chain: _healthyChain,
        expectEnabled: false,
      ),
    );

    // ---- 场景 4：服务故障 → fail closed → 失败率告警 → kill 闭环 ----
    observability.emit(
      SmartLayoutMetricEvent(
        kind: 'capabilityDecision',
        atMs: nowMs + 1,
        attributes: const {
          'scenario': 'service-failure',
          'enabled': true,
          'reason': 'cachedPositive',
        },
      ),
    );
    final failure = await runGated(
      id: 'service-failure',
      cache: unexpired,
      killSwitch: alertKillSwitch,
      chain: _failingChain,
      expectEnabled: true,
      sessionOverride: _failingSessionFactory ?? _sessionFactory,
    );
    var failureScenario = failure;
    if (failure.passed) {
      for (var i = 0; i < failure.requestCount; i++) {
        observability.emit(
          SmartLayoutMetricEvent(kind: 'request', atMs: nowMs + 1),
        );
        observability.emit(
          SmartLayoutMetricEvent(
            kind: 'failure',
            atMs: nowMs + 1,
            attributes: const {'scenario': 'service-failure'},
          ),
        );
      }
      final alerts = observability.evaluateAlerts(nowMs + 2);
      // 闭环复验：kill 跳闸后再开 → disabled（工厂仍只有故障前那一次）。
      var reopenFactoryCalls = 0;
      final reopenedGate = SmartLayoutRolloutEntryGate(
        capabilityCache: unexpired,
        killSwitch: alertKillSwitch,
        sessionFactory: () {
          reopenFactoryCalls++;
          return _NoopSessionHandle();
        },
      );
      final reopened = reopenedGate.open(nowMs: nowMs + 3);
      failureScenario = SmartLayoutDemoSmokeScenario(
        id: failure.id,
        passed:
            alerts.isNotEmpty &&
            alertKillSwitch.isTripped &&
            !reopened.enabled &&
            reopenFactoryCalls == 0,
        detail:
            '${failure.detail}；告警 ${alerts.length} 条（失败率 '
            '${alerts.isNotEmpty ? alerts.last.observedFailureRate : null}）'
            'kill_tripped=${alertKillSwitch.isTripped} '
            'reopen=${reopened.enabled ? 'enabled' : 'disabled'
                }(${reopened.reason})',
        factoryCalls: failure.factoryCalls,
        requestCount: failure.requestCount,
      );
    }
    scenarios.add(failureScenario);

    return SmartLayoutDemoSmokeReport(
      scenarios: scenarios,
      observabilitySnapshot: {
        'schema_version': metricsSchemaVersion,
        'event_count': sink.events.length,
        'alert_count': sink.alerts.length,
        'failure_rate_rule': {
          'rule_id': failureRateRule.ruleId,
          'threshold': failureRateRule.threshold,
          'window_ms': failureRateRule.windowMs,
          'min_samples': failureRateRule.minSamples,
        },
        'events': List<Object?>.from(sink.events),
      },
    );
  }
}

class _NoopSessionHandle implements SmartLayoutV3SessionHandle {
  @override
  void close() {}
}
