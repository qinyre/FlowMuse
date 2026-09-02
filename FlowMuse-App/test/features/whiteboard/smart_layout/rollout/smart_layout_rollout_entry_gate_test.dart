import 'dart:io';

import 'package:flow_muse/features/whiteboard/smart_layout/rollout/smart_layout_capability.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rollout/smart_layout_kill_switch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rollout/smart_layout_rollout_entry_gate.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rollout/smart_layout_rollback_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-701A：公开入口默认关闭切换、回滚与关闭行为。

class RecordingSession implements SmartLayoutV3SessionHandle {
  bool closed = false;

  @override
  void close() => closed = true;
}

void main() {
  group('SmartLayoutRolloutEntryGate：默认关闭零请求/零 Draft', () {
    test('无缓存（默认关）→ disabled 且会话工厂零调用', () {
      var creations = 0;
      final entry = SmartLayoutRolloutEntryGate(
        capabilityCache: null,
        killSwitch: SmartLayoutKillSwitch(),
        sessionFactory: () {
          creations++;
          return RecordingSession();
        },
      );
      final outcome = entry.open(nowMs: 1000);
      expect(outcome.enabled, isFalse);
      expect(outcome.reason, 'defaultOff');
      expect(creations, 0, reason: '默认关闭零请求/零 Draft');
    });

    test('服务不可用（损坏/过期/阴性）不能开启', () {
      const caches = [
        SmartLayoutCapabilityRecord.malformed(),
        SmartLayoutCapabilityRecord(enabled: true, expiresAtMs: 100),
        SmartLayoutCapabilityRecord(enabled: false, expiresAtMs: 99999),
      ];
      for (final cache in caches) {
        final entry = SmartLayoutRolloutEntryGate(
          capabilityCache: cache,
          killSwitch: SmartLayoutKillSwitch(),
          sessionFactory: () => throw StateError('不得创建会话'),
        );
        expect(entry.open(nowMs: 200).enabled, isFalse, reason: '${cache.expiresAtMs}');
      }
    });

    test('阳性未过期 + kill 未跳闸 → 创建真实 v3 会话（签名保持，内部只到 v3）',
        () {
      final sessions = <RecordingSession>[];
      final entry = SmartLayoutRolloutEntryGate(
        capabilityCache: const SmartLayoutCapabilityRecord(
          enabled: true,
          expiresAtMs: 9999,
        ),
        killSwitch: SmartLayoutKillSwitch(),
        sessionFactory: () {
          final session = RecordingSession();
          sessions.add(session);
          return session;
        },
      );
      final outcome = entry.open(nowMs: 1);
      expect(outcome.enabled, isTrue);
      expect(sessions, hasLength(1));
      // 关闭委托：零残留口径。
      entry.closeSession(sessions.single);
      expect(sessions.single.closed, isTrue);
    });

    test('kill 跳闸 → 阳性缓存也不放行（零工厂调用）', () {
      final kill = SmartLayoutKillSwitch()..trip('alert');
      final entry = SmartLayoutRolloutEntryGate(
        capabilityCache: const SmartLayoutCapabilityRecord(
          enabled: true,
          expiresAtMs: 9999,
        ),
        killSwitch: kill,
        sessionFactory: () => throw StateError('不得创建会话'),
      );
      expect(entry.open(nowMs: 1).enabled, isFalse);
    });

    test('关闭/重开：close 后 entryClosed，缓存清空回到默认关', () {
      final entry = SmartLayoutRolloutEntryGate(
        capabilityCache: const SmartLayoutCapabilityRecord(
          enabled: true,
          expiresAtMs: 9999,
        ),
        killSwitch: SmartLayoutKillSwitch(),
        sessionFactory: () => throw StateError('close 后不得创建'),
      );
      entry.close();
      final outcome = entry.open(nowMs: 1);
      expect(outcome.enabled, isFalse);
      expect(outcome.reason, 'entryClosed');
      expect(entry.capabilityCache, isNull, reason: '缓存清空=重开默认关');
    });
  });

  group('入口代码不可达 v2（源码守卫）', () {
    test('入口/门禁/回滚源码零 v2 路由符号', () {
      const files = [
        'lib/features/whiteboard/smart_layout/rollout/smart_layout_rollout_entry_gate.dart',
        'lib/features/whiteboard/smart_layout/rollout/smart_layout_capability.dart',
        'lib/features/whiteboard/smart_layout/rollout/smart_layout_kill_switch.dart',
        'lib/features/whiteboard/smart_layout/rollout/smart_layout_rollback_policy.dart',
      ];
      for (final file in files) {
        final source = File(file).readAsStringSync();
        expect(
          RegExp(r'\bv2[a-z_]*reflow|fallbackToV2|routeToV2|legacyV2')
              .hasMatch(source),
          isFalse,
          reason: '$file 不得含 v2 回退路由',
        );
      }
    });
  });

  group('SmartLayoutRollbackPolicy：独立切流提交与回滚完整性', () {
    test('切流提交混入 allowlist 外文件 → 拒绝', () {
      const policy = SmartLayoutRollbackPolicy(
        switchCommitAllowlist: {
          'FlowMuse-App/lib/features/whiteboard/smart_layout/rollout/',
        },
      );
      expect(
        policy.validateSwitchCommit(
          const ['FlowMuse-App/lib/features/whiteboard/smart_layout/rollout/smart_layout_public_entry.dart'],
        ),
        isEmpty,
      );
      final violations = policy.validateSwitchCommit(const [
        'FlowMuse-App/lib/features/whiteboard/smart_layout/rollout/smart_layout_kill_switch.dart',
        'FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart',
      ]);
      expect(violations, ['FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart']);
    });

    test('回滚完整性：残余 diff 为空才通过（恰为切流提交的逆）', () {
      const policy = SmartLayoutRollbackPolicy(switchCommitAllowlist: {});
      expect(
        policy.validateRollback(
          baselinePaths: const ['a', 'b'],
          currentPaths: const ['a', 'b'],
        ),
        isEmpty,
      );
      expect(
        policy.validateRollback(
          baselinePaths: const ['a', 'b'],
          currentPaths: const ['a', 'c'],
        ),
        containsAll(['-b', '+c']),
      );
    });

    test('关闭/重开检查单四条齐备（机器可执行口径）', () {
      expect(SmartLayoutRollbackPolicy.closeReopenChecklist, hasLength(4));
      expect(
        SmartLayoutRollbackPolicy.closeReopenChecklist.join(),
        contains('默认关闭'),
      );
      expect(
        SmartLayoutRollbackPolicy.closeReopenChecklist.join(),
        contains('kill switch 状态保留'),
      );
    });
  });
}
