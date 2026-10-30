# 鸿蒙运行期间系统通知适配审查

审查日期：2026-10-29。范围为系统消息提醒的 Dart 适配、鸿蒙 ArkTS Channel、EntryAbility 注册与点击入口；不代表全工程审计。用户要求不构建鸿蒙，本轮没有运行 HAP 构建，也没有真机结果。

## 结论与调用链

当前实现通过 Flutter MethodChannel 调用鸿蒙原生 Notification Kit 和 Ability Kit，方向符合项目已有跨端边界。共享 Dart 层只传业务数据；鸿蒙端不调用 Android NotificationManager，也不使用 Web Notification API。

| 能力 | 已采用接口与入口 | 对照结果 |
| --- | --- | --- |
| 查询授权 | `notificationManager.isNotificationEnabled()` | 与官方 Notification Kit 授权流程一致 |
| 主动申请授权 | `requestEnableNotification(UIAbilityContext)` | 只由设置操作触发，处理拒绝码 1600004；未添加 Android 通知权限或误用系统级权限 |
| 本地发布 | `notificationManager.publish(NotificationRequest)` | 适用于应用进程运行期间；进程结束后的通知需要另一条 Push Kit 链路，本轮不包含 |
| 点击拉起/恢复 | `wantAgent.getWantAgent()`、`START_ABILITY`、`onCreate/onNewWant` | 使用实际 bundle/ability 信息；待 Flutter 就绪后消费点击，经过账号/有效期校验再打开既有收件箱 |
| 点击参数更新 | `actionType`、`actionFlags`、`UPDATE_PRESENT_FLAG`、`CONSTANT_FLAG` | 当前指南使用这些字段；没有照搬旧样例的 `operationType` / `wantAgentFlags` |
| 移除通知 | `cancel(id)`、`cancelAll()` | 当前只有此模块发布通知；已读、失效、退出与关闭提醒沿原协调器清除 |
| 前后台 | `FlutterAbility` 生命周期传给 Dart `AppLifecycleState` | 开启系统提醒时保留消息连接；未声明后台长时任务，不承诺进程暂停/终止后继续接收 |

## 已修正的两处问题

1. **遗漏社交通信通知类别。** 未传 `notificationSlotType` 时，SDK 默认类别为 `OTHER_TYPES`，其提醒能力与即时消息所需能力不一致。已显式使用 `SlotType.SOCIAL_COMMUNICATION`。最终铃声、锁屏和横幅是否展示仍受用户系统设置控制；官方指南说明横幅默认关闭，应用不能强制开启。
2. **过期清除只依赖应用计时。** 原协调器有 Dart 计时器和点击有效期检查，但进程暂停时不能及时执行清理。已将同一到期时间传入原生 `autoDeletedTime`，由系统按毫秒时间戳清除。`tapDismissed` 在携带 WantAgent 时默认 true，无需重复设置。

这两处只修改鸿蒙源码，不影响本轮已部署的 Web 与 Go 后端二进制。

## 官方依据

- [Notification Kit 简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-overview)：区分进程运行期间的本地通知与进程结束后的云推送。
- [请求通知授权](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-enable)。
- [管理通知渠道](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-slot)：类别、提醒方式和用户设置。
- [为通知添加行为意图](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-with-wantagent)。
- [OpenHarmony 官方 SDK NotificationRequest 类型定义](https://github.com/openharmony/interface_sdk-js/blob/master/api/notification/notificationRequest.d.ts)：本轮读取了 `notificationSlotType` 的默认值、`autoDeletedTime` 的绝对时间戳单位及 `tapDismissed` 默认行为。前者自动态 API 11 提供，后两项自动态 API 7 提供；工程当前兼容版本为 API 18，目标版本为 API 24。

部分华为在线参考页获取超时，接口行为同时依据本地官方指南镜像和 OpenHarmony 官方 SDK 类型定义核对。类型定义核对不能替代项目所用 HarmonyOS SDK 的编译验证。

## 待实机验收

首次授权与拒绝后重新开启、系统通知栏/锁屏展示、前后台切换时实际接收、同会话更新及声音策略、点击保留白板状态、账号切换清除、应用暂停期间的到期清除。应用被系统冻结或终止后不保证收到新消息；未接入厂商推送或后台保活。

## 2026-10-30 构建与安装补充

- 按用户新的更新安装要求，将主线快进至 `caf10625b61546e49627eeefe5aff3e5f9fbc81e`。首次 HAP 构建发现通知授权分支直接重抛 catch 变量触发 `arkts-limited-throw`；改为 `new Error('Notification permission unavailable')`，继续交由外层返回原有 `notification_unavailable`，拒绝授权码的处理保持不变。修复在 `codex/fix-harmony-notice-build` 分支进行，仅涉及鸿蒙通道一行。
- 依据 [ArkTS 官方 throw 限制](https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/typescript-to-arkts-migration-guide.md#throw-statements-do-not-accept-values-of-arbitrary-types)，不再重抛未明确为 Error 类的对象；本机编译器同样拒绝对 catch 变量断言为 `BusinessError` 后重抛。
- 本轮 `flutter pub get --enforce-lockfile`、`flutter analyze --no-pub` 和通知相关 19 项测试通过。最终 `flutter build hap --release --target=lib/main.dart` 通过，正式 API 为 `https://api.flowmuse.cloud`，分享入口为 `https://app.flowmuse.cloud`，湿墨分层及实时墨迹 V2 均显式开启。日志在 `FlowMuse-App/build/install-20261030/`，未运行全量测试。
- HAP SHA-256：`6f7b456ba445758a1451020d79a7dcd4a16f5d9da64ad21014cb88960a6b88a4`。北京时间 14:20:50 已通过 `hdc install -r` 覆盖安装到 SLG-W50；首次安装时间保持不变，未卸载或清除应用数据。系统确认 EntryAbility 启动成功且处于前台，进程持续存在。
- 此次补齐编译与启动证据，尚未实测上述通知授权、收发、点击及到期清除流程；不将启动成功等同于系统通知功能完整验收。
