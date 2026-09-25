# 华为账号登录失败修复

日期：2026-09-25

## Context

鸿蒙端点击“华为账号登录”后提示“华为登录未完成”。当前提示由 Dart 适配层将原生授权错误统一折叠产生。`entry/src/main/module.json5` 未配置 Account Kit 要求的应用级 `client_id`；原生回调还要求 `state` 必须返回，而华为官方示例仅在返回了 `state` 且与请求不一致时拒绝。现有账号测试只模拟 MethodChannel，未覆盖这两项。

## 需求

恢复鸿蒙华为账号授权流程；取消授权仍不改变 FlowMuse 会话；失败时提示可定位的原因，且不记录授权码或凭证。其他平台邮箱登录保持原行为。

## 实现方案与关键文件

1. `FlowMuse-App/ohos/entry/src/main/module.json5`：配置与服务端应用凭据一致的公开 Client ID。签名证书及 AGC 公钥指纹仍需打包侧核对。
2. `FlowMuse-App/ohos/entry/src/main/ets/channels/HuaweiAccountChannel.ets`：只拒绝不匹配的非空 `state`，向 Dart 传递不含敏感信息的原生错误码。
3. `FlowMuse-App/lib/features/account/repositories/huawei_account_channel_ohos.dart`：对签名、设备账号及服务异常给出具体提示，保留取消、网络错误语义。
4. `FlowMuse-App/test/features/account/account_login_test.dart`：覆盖错误码映射和授权取消。

## 验证方案与实施步骤

先确认账号测试基线，再改配置与适配层；运行账号测试、全量 `flutter analyze`、`flutter test` 和 `flutter build hap`。随后由具备签名与设备的电脑安装新 HAP，核对 AGC 指纹，实测授权成功、取消和错误提示。没有设备记录前仅能确认代码与构建，不能宣称真机登录已通过。

## 实施与验证记录

- 应用级 Client ID 与已有 `.env.example` 和 2026-09-23 部署记录一致；未将 Client Secret 放入客户端。
- 账号专项测试 9 项通过；`flutter analyze --no-pub` 无问题；全量 `flutter test --no-pub` 1789 项通过、6 项既有跳过。
- `flutter build hap --no-pub` 首次因当前进程 `PATH` 缺少 `java.exe` 在打包阶段失败；临时将已有 JDK 21 的 `bin` 加入 `PATH` 后构建成功。产物为 `FlowMuse-App/build/ohos/hap/entry-default-signed.hap`，压缩包内 `module.json` 含配置的 Client ID。
- 本机无 `hdc` 和已连接设备的证据，尚未验证真实 Account Kit 授权。打包侧需核对 AGC 中 `com.flowmuse.app` 的应用级 Client ID 与签名证书公钥指纹，并安装本次 HAP 测试。若仍报错，界面现在会显示已知原因或原生数字错误码，便于继续定位。

依据：[华为官方 Client ID 配置](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/health-configuration-client-id)、[官方授权回调示例（仅在返回的 state 不匹配时拒绝）](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/account-get-phonenumber)、[Account Kit 指纹错误排查](https://developer.huawei.com/consumer/cn/doc/doccenter-atomic-service/account-guide-atomic-faq)。
