import 'package:flow_muse/features/whiteboard/smart_layout/rollout/smart_layout_capability.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rollout/smart_layout_kill_switch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rollout/smart_layout_observability.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-700B：fail-closed capability / kill switch / 可观测性合成闭环。
void main() {
  group('SmartLayoutCapability：默认/过期/故障一律 off', () {
    test('无缓存（默认）→ off(defaultOff)，入口零请求', () {
      final decision = SmartLayoutCapability.resolve(
        cached: null,
        nowMs: 1000,
      );
      expect(decision.enabled, isFalse);
      expect(decision.reason, SmartLayoutCapabilityReason.defaultOff);
    });

    test('阳性缓存未过期 → on(cachedPositive)', () {
      final decision = SmartLayoutCapability.resolve(
        cached: const SmartLayoutCapabilityRecord(
          enabled: true,
          expiresAtMs: 5000,
        ),
        nowMs: 4000,
      );
      expect(decision.enabled, isTrue);
      expect(decision.reason, SmartLayoutCapabilityReason.cachedPositive);
    });

    test('过期（now ≥ expiresAtMs）→ off(expired)：服务端确认前不放宽', () {
      final decision = SmartLayoutCapability.resolve(
        cached: const SmartLayoutCapabilityRecord(
          enabled: true,
          expiresAtMs: 5000,
        ),
        nowMs: 5000,
      );
      expect(decision.enabled, isFalse);
      expect(decision.reason, SmartLayoutCapabilityReason.expired);
    });

    test('损坏（非 JSON/缺字段/类型不符）→ off(malformed)', () {
      for (final body in ['not json', '{}', '{"enabled":1,"expiresAtMs":5}']) {
        final record = SmartLayoutCapabilityRecord.tryParse(body);
        expect(record.isMalformed, isTrue, reason: body);
        expect(
          SmartLayoutCapability.resolve(cached: record, nowMs: 0).enabled,
          isFalse,
        );
      }
    });

    test('拉取失败语义：off 绝不因失败翻 on（解析层无 on 信号即 off）', () {
      // 拉取失败 ⇒ 无新缓存记录 ⇒ 只剩旧记录或无记录：
      // 无记录=defaultOff；旧记录按 TTL 自然衰减——不存在故障路径产 on。
      const failure = SmartLayoutCapabilityRecord.malformed();
      expect(
        SmartLayoutCapability.resolve(cached: failure, nowMs: 1).reason,
        SmartLayoutCapabilityReason.malformed,
      );
    });

    test('enabled=false 缓存 → off(expired)（阴性信号不放行）', () {
      final decision = SmartLayoutCapability.resolve(
        cached: const SmartLayoutCapabilityRecord(
          enabled: false,
          expiresAtMs: 99999,
        ),
        nowMs: 1,
      );
      expect(decision.enabled, isFalse);
    });
  });

  group('SmartLayoutKillSwitch：只关不换（无 v2 回退路径）', () {
    test('trip 后 capability 阳性也不放行；off 时入口零请求', () {
      final kill = SmartLayoutKillSwitch();
      var analyzeRequests = 0;
      bool entryGate() {
        final decision = kill.combine(
          SmartLayoutCapability.resolve(
            cached: const SmartLayoutCapabilityRecord(
              enabled: true,
              expiresAtMs: 99999,
            ),
            nowMs: 1,
          ),
        );
        if (!decision.enabled) return false; // fail closed：直接零请求
        analyzeRequests++;
        return true;
      }

      expect(entryGate(), isTrue);
      expect(analyzeRequests, 1);
      kill.trip('alert:failure-rate');
      expect(kill.isTripped, isTrue);
      expect(entryGate(), isFalse);
      expect(analyzeRequests, 1, reason: '关闭后不得再发请求');
    });

    test('reset 解除；maxTripCount 达到后锁定 reset 失效', () {
      final kill = SmartLayoutKillSwitch(maxTripCount: 2);
      kill.trip('a');
      kill.reset();
      expect(kill.isTripped, isFalse);
      kill.trip('b');
      kill.trip('c');
      expect(kill.isLatched, isTrue);
      kill.reset();
      expect(kill.isTripped, isTrue, reason: '锁定后人工介入口径');
    });

    test('kill switch 不提供任何 v2 回退 API（类型面只有关/解/锁）', () {
      // 断网/配置故障不回退 v2：本类型无 fallback 概念——编译面保证
      // （无 v2 路由方法），运行面 trip 只降 off。
      final kill = SmartLayoutKillSwitch();
      kill.trip('offline');
      final decision = kill.combine(
        const SmartLayoutCapabilityDecision(
          enabled: true,
          reason: SmartLayoutCapabilityReason.cachedPositive,
          expiresAtMs: 9,
        ),
      );
      expect(decision.enabled, isFalse);
    });
  });

  group('SmartLayoutObservability：版本化指标+告警+synthetic sink', () {
    test('事件 schema 版本化；sink 进程内零网络', () {
      final sink = LocalSyntheticMetricsSink();
      final obs = SmartLayoutObservability(
        sink: sink,
        rules: const [],
        onAlert: (_) => false,
      );
      obs.emit(
        const SmartLayoutMetricEvent(kind: 'request', atMs: 100),
      );
      expect(sink.events.single['schema_version'], metricsSchemaVersion);
      expect(sink.events.single['kind'], 'request');
    });

    test('合成指标触发告警并关闭 kill switch（闭环）', () {
      final kill = SmartLayoutKillSwitch();
      final sink = LocalSyntheticMetricsSink();
      final obs = SmartLayoutObservability(
        sink: sink,
        rules: const [
          SmartLayoutFailureRateAlertRule(
            ruleId: 'failure-rate',
            threshold: 0.5,
            windowMs: 10000,
            minSamples: 4,
          ),
        ],
        onAlert: (alert) {
          kill.trip(alert.ruleId);
          return true;
        },
      );

      for (var i = 0; i < 4; i++) {
        obs.emit(SmartLayoutMetricEvent(kind: 'request', atMs: 1000 + i));
      }
      // 3/4 失败 = 0.75 ≥ 0.5，样本 ≥4。
      for (var i = 0; i < 3; i++) {
        obs.emit(SmartLayoutMetricEvent(kind: 'failure', atMs: 2000 + i));
      }
      expect(kill.isTripped, isFalse);
      final fired = obs.evaluateAlerts(3000);
      expect(fired, hasLength(1));
      expect(fired.single.observedFailureRate, closeTo(0.75, 1e-9));
      expect(kill.isTripped, isTrue, reason: '合成指标 → 告警 → 关闭');
      expect(sink.alerts, hasLength(1));
    });

    test('样本不足/未达阈值不告警（去抖口径）', () {
      final sink = LocalSyntheticMetricsSink();
      final obs = SmartLayoutObservability(
        sink: sink,
        rules: const [
          SmartLayoutFailureRateAlertRule(
            ruleId: 'r',
            threshold: 0.5,
            windowMs: 10000,
            minSamples: 10,
          ),
        ],
        onAlert: (_) => false,
      );
      for (var i = 0; i < 5; i++) {
        obs.emit(SmartLayoutMetricEvent(kind: 'request', atMs: 100 + i));
        obs.emit(SmartLayoutMetricEvent(kind: 'failure', atMs: 200 + i));
      }
      expect(obs.evaluateAlerts(1000), isEmpty, reason: '样本 5 < 10');
    });

    test('窗口外事件不参与判定', () {
      final sink = LocalSyntheticMetricsSink();
      final obs = SmartLayoutObservability(
        sink: sink,
        rules: const [
          SmartLayoutFailureRateAlertRule(
            ruleId: 'r',
            threshold: 0.5,
            windowMs: 1000,
            minSamples: 2,
          ),
        ],
        onAlert: (_) => false,
      );
      obs.emit(const SmartLayoutMetricEvent(kind: 'request', atMs: 0));
      obs.emit(const SmartLayoutMetricEvent(kind: 'failure', atMs: 0));
      // 窗口 [now-1000, now]：now=5000 时两个事件都在窗外。
      expect(obs.evaluateAlerts(5000), isEmpty);
    });
  });
}
