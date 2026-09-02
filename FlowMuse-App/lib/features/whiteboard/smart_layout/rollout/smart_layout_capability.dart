/// V3-700B：fail-closed capability 解析（合并原 V3-700B~D）。
///
/// 规则（默认/过期/故障一律 off——fail closed）：
/// - 无缓存（默认）→ off(defaultOff)：入口零请求；
/// - 缓存 enabled=true 且未过期 → on(cachedPositive)；
/// - 缓存过期 → off(expired)：服务端确认前不放宽；
/// - 缓存形态损坏 → off(malformed)；
/// - 拉取失败不改变既有判定方向：已 on 保持 on 直至 TTL 到期（缓存
///   阳性信号过期自然回 off），任何失败绝不把 off 翻成 on。
library;

import 'dart:convert';

enum SmartLayoutCapabilityReason {
  defaultOff,
  cachedPositive,
  expired,
  malformed,
}

class SmartLayoutCapabilityDecision {
  const SmartLayoutCapabilityDecision({
    required this.enabled,
    required this.reason,
    required this.expiresAtMs,
  });

  /// 入口是否放行 v3。
  final bool enabled;

  final SmartLayoutCapabilityReason reason;

  /// 阳性缓存的到期时刻（ms epoch）；off 判定为 0。
  final int expiresAtMs;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'reason': reason.name,
    'expires_at_ms': expiresAtMs,
  };
}

/// 服务端 capability 缓存记录（拉取成功才有；任何字段缺失/类型不符
/// 即 malformed）。
class SmartLayoutCapabilityRecord {
  const SmartLayoutCapabilityRecord({
    required this.enabled,
    required this.expiresAtMs,
  });

  factory SmartLayoutCapabilityRecord.tryParse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const SmartLayoutCapabilityRecord.malformed();
    }
    if (decoded is! Map<String, Object?>) {
      return const SmartLayoutCapabilityRecord.malformed();
    }
    final enabled = decoded['enabled'];
    final expires = decoded['expiresAtMs'];
    if (enabled is! bool || expires is! num) {
      return const SmartLayoutCapabilityRecord.malformed();
    }
    return SmartLayoutCapabilityRecord(
      enabled: enabled,
      expiresAtMs: expires.toInt(),
    );
  }

  const SmartLayoutCapabilityRecord.malformed()
    : enabled = false,
      expiresAtMs = -1;

  final bool enabled;

  /// 缓存到期时刻（ms epoch）。
  final int expiresAtMs;

  bool get isMalformed => expiresAtMs == -1;
}

abstract final class SmartLayoutCapability {
  /// 解析当前判定。无缓存/损坏/过期 → off；阳性未过期 → on。
  static SmartLayoutCapabilityDecision resolve({
    SmartLayoutCapabilityRecord? cached,
    required int nowMs,
  }) {
    if (cached == null) {
      return const SmartLayoutCapabilityDecision(
        enabled: false,
        reason: SmartLayoutCapabilityReason.defaultOff,
        expiresAtMs: 0,
      );
    }
    if (cached.isMalformed) {
      return const SmartLayoutCapabilityDecision(
        enabled: false,
        reason: SmartLayoutCapabilityReason.malformed,
        expiresAtMs: 0,
      );
    }
    if (!cached.enabled || nowMs >= cached.expiresAtMs) {
      return SmartLayoutCapabilityDecision(
        enabled: false,
        reason: SmartLayoutCapabilityReason.expired,
        expiresAtMs: 0,
      );
    }
    return SmartLayoutCapabilityDecision(
      enabled: true,
      reason: SmartLayoutCapabilityReason.cachedPositive,
      expiresAtMs: cached.expiresAtMs,
    );
  }
}
