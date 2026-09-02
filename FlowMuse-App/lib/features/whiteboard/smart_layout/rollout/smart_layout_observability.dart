/// V3-700B：智能排版 v3 可观测性（合并原 V3-700B~D）——版本化指标、
/// 告警规则与本地 synthetic sink。
///
/// - 指标 schema 版本化（metricsSchemaVersion v1）：事件即结构化记录，
///   生产端点由 V3-700A 接收（observability-endpoints-ready.json 是
///   外部输入）；本层提供本地 synthetic sink（进程内、零网络）。
/// - 告警：滑动窗口失败率超阈 → AlertEvent → 订阅者（如 kill switch
///   trip）；合成指标即可触发告警与关闭（acceptance）。
library;

import 'dart:convert';

const int metricsSchemaVersion = 1;

/// 指标事件（v1 schema）。
class SmartLayoutMetricEvent {
  const SmartLayoutMetricEvent({
    required this.kind,
    required this.atMs,
    this.attributes = const {},
  });

  /// request | success | failure | capabilityDecision | killSwitch
  final String kind;

  final int atMs;

  final Map<String, Object?> attributes;

  Map<String, Object?> toJson() => {
    'schema_version': metricsSchemaVersion,
    'kind': kind,
    'at_ms': atMs,
    'attributes': attributes,
  };
}

class SmartLayoutAlertEvent {
  const SmartLayoutAlertEvent({
    required this.ruleId,
    required this.detail,
    required this.atMs,
    required this.observedFailureRate,
  });

  final String ruleId;
  final String detail;
  final int atMs;
  final double observedFailureRate;

  Map<String, Object?> toJson() => {
    'schema_version': metricsSchemaVersion,
    'rule_id': ruleId,
    'detail': detail,
    'at_ms': atMs,
    'observed_failure_rate': observedFailureRate,
  };
}

/// 本地 synthetic sink：进程内接收事件（零网络、可断言）。
class LocalSyntheticMetricsSink {
  final List<Map<String, Object?>> events = [];
  final List<SmartLayoutAlertEvent> alerts = [];

  void emit(SmartLayoutMetricEvent event) => events.add(event.toJson());

  void raise(SmartLayoutAlertEvent alert) {
    alerts.add(alert);
    events.add(alert.toJson());
  }
}

/// 失败率告警规则：窗口内（窗口时长 windowMs）request+failure 事件
/// 计算 failureRate = failures/requests ≥ threshold 且样本数达
/// minSamples → 触发（每次 evaluate 至多一条，去抖由调用方节流）。
class SmartLayoutFailureRateAlertRule {
  const SmartLayoutFailureRateAlertRule({
    required this.ruleId,
    required this.threshold,
    required this.windowMs,
    required this.minSamples,
  });

  final String ruleId;
  final double threshold;
  final int windowMs;
  final int minSamples;

  SmartLayoutAlertEvent? evaluate(
    List<SmartLayoutMetricEvent> events,
    int nowMs,
  ) {
    var requests = 0;
    var failures = 0;
    for (final event in events) {
      if (event.atMs < nowMs - windowMs) continue;
      if (event.kind == 'request') {
        requests++;
      } else if (event.kind == 'failure') {
        failures++;
      }
    }
    if (requests < minSamples) return null;
    final rate = failures / requests;
    if (rate < threshold) return null;
    return SmartLayoutAlertEvent(
      ruleId: ruleId,
      detail: '窗口失败率 $rate ≥ $threshold（$failures/$requests，'
          '窗口 ${windowMs}ms，样本 ≥$minSamples）',
      atMs: nowMs,
      observedFailureRate: rate,
    );
  }
}

/// 可观测性门面：事件流 → sink + 告警评估 → 告警订阅者（kill switch）。
class SmartLayoutObservability {
  SmartLayoutObservability({
    required this.sink,
    required this.rules,
    required this.onAlert,
  });

  final LocalSyntheticMetricsSink sink;
  final List<SmartLayoutFailureRateAlertRule> rules;

  /// 告警回调（返回 true 表示已处理，例如 kill switch trip）。
  final bool Function(SmartLayoutAlertEvent alert) onAlert;

  final List<SmartLayoutMetricEvent> _events = [];

  List<SmartLayoutMetricEvent> get events => List.unmodifiable(_events);

  void emit(SmartLayoutMetricEvent event) {
    _events.add(event);
    sink.emit(event);
  }

  /// 评估全部规则；命中的告警进 sink 并回调 [onAlert]（合成指标可
  /// 触发告警与关闭的机制层闭环）。
  List<SmartLayoutAlertEvent> evaluateAlerts(int nowMs) {
    final fired = <SmartLayoutAlertEvent>[];
    for (final rule in rules) {
      final alert = rule.evaluate(_events, nowMs);
      if (alert == null) continue;
      fired.add(alert);
      sink.raise(alert);
      onAlert(alert);
    }
    return fired;
  }

  String snapshotJson() => jsonEncode({
    'schema_version': metricsSchemaVersion,
    'events': [for (final e in _events) e.toJson()],
  });
}
