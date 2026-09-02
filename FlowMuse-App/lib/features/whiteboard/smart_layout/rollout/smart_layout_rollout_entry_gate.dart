/// V3-701A：智能排版 v3 切流门禁入口（合并原 V3-701A~B）。
///
/// 与既有 gateways/SmartLayoutPublicEntry（V3-100A 唯一页面层入口）
/// 组合使用：门禁不过零请求零 Draft；公开符号不重复——本类是门禁层。
///
/// 语义（保持公开签名，内部只路由到 v3 Session）：
/// - 默认关闭：无 capability 阳性缓存时 [open] 直接返回 disabled——
///   **零请求、零 Draft**（session 工厂不被调用，fail closed）；
/// - 服务不可用（无缓存/损坏/过期）不能开启；
/// - 类型面零 v2 路径：入口不导入、不路由任何 v2 实现（源码守卫测试
///   钉死）；调用者源码不迁移（入口签名即既有公开形态）；
/// - 关闭零残留：[close] 委托会话关闭并复位门禁，无 Draft/History/
///   广播残留（会话级六态语义由 V3-506A 矩阵钉死，此处入口级复验）。
library;

import 'smart_layout_capability.dart';
import 'smart_layout_kill_switch.dart';

/// 打开结果：disabled（零副作用）或 enabled（真实 v3 会话已创建）。
class SmartLayoutRolloutEntryGateOutcome {
  const SmartLayoutRolloutEntryGateOutcome.disabled({
    required this.reason,
  })  : session = null,
        enabled = false;

  const SmartLayoutRolloutEntryGateOutcome.enabled(this.session)
    : enabled = true,
      reason = 'enabled';

  /// 是否放行（真实会话已创建）。
  final bool enabled;

  /// 门禁判定说明（disabled 时为 capability/kill 原因）。
  final String reason;

  /// 打开的 v3 会话（T 为 [SmartLayoutV3SessionHandle] 子类型）。
  final SmartLayoutV3SessionHandle? session;
}

/// v3 会话句柄契约：入口只依赖关闭语义，不感知会话内部。
abstract class SmartLayoutV3SessionHandle {
  /// 关闭会话：零 Draft/History/广播残留（V3-506A 六态语义）。
  void close();
}

/// 会话工厂（测试注入计数；生产为真实 Session 构造）。
typedef SmartLayoutV3SessionFactory = SmartLayoutV3SessionHandle Function();

class SmartLayoutRolloutEntryGate {
  SmartLayoutRolloutEntryGate({
    required this.capabilityCache,
    required this.killSwitch,
    required this.sessionFactory,
  });

  /// 当前 capability 缓存（null=无缓存默认关）。
  SmartLayoutCapabilityRecord? capabilityCache;

  final SmartLayoutKillSwitch killSwitch;

  final SmartLayoutV3SessionFactory sessionFactory;

  bool _closed = false;

  /// 打开入口：门禁不过 → disabled 且**不调用**会话工厂（零请求/零
  /// Draft 的机制保证：工厂调用即产生请求与 Draft 生命周期）。
  SmartLayoutRolloutEntryGateOutcome open({required int nowMs}) {
    if (_closed) {
      return const SmartLayoutRolloutEntryGateOutcome.disabled(reason: 'entryClosed');
    }
    final decision = killSwitch.combine(
      SmartLayoutCapability.resolve(cached: capabilityCache, nowMs: nowMs),
    );
    if (!decision.enabled) {
      return SmartLayoutRolloutEntryGateOutcome.disabled(
        reason: decision.reason.name,
      );
    }
    return SmartLayoutRolloutEntryGateOutcome.enabled(sessionFactory());
  }

  /// 关闭入口：复位门禁上下文；已开 会话由调用方持有者关闭（或经
  /// [closeSession] 委托），零 Draft/History/广播残留由会话关闭语义
  /// 保证（V3-506A）。
  void close() {
    _closed = true;
    capabilityCache = null;
  }

  /// 委托关闭一个已开 会话（入口级复验：关闭后句柄不可再用）。
  void closeSession(SmartLayoutV3SessionHandle session) => session.close();
}
