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

- 当时按 `.env.example` 和 2026-09-23 部署记录将 `6917611606499874343` 视为应用级 Client ID；未将 Client Secret 放入客户端。后续 AGC 截图确认该应用的 APP ID 与 OAuth 2.0 应用级 Client ID 恰好同为此值。
- 账号专项测试 9 项通过；`flutter analyze --no-pub` 无问题；全量 `flutter test --no-pub` 1789 项通过、6 项既有跳过。
- `flutter build hap --no-pub` 首次因当前进程 `PATH` 缺少 `java.exe` 在打包阶段失败；临时将已有 JDK 21 的 `bin` 加入 `PATH` 后构建成功。产物为 `FlowMuse-App/build/ohos/hap/entry-default-signed.hap`，压缩包内 `module.json` 含配置的 Client ID。
- 当时未找到 `hdc`，尚未验证真实 Account Kit 授权。打包侧需核对 AGC 中 `com.flowmuse.app` 的应用级 Client ID 与签名证书公钥指纹，并安装本次 HAP 测试。若仍报错，界面现在会显示已知原因或原生数字错误码，便于继续定位。

依据：[华为官方 Client ID 配置](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/health-configuration-client-id)、[官方授权回调示例（仅在返回的 state 不匹配时拒绝）](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/account-get-phonenumber)、[Account Kit 指纹错误排查](https://developer.huawei.com/consumer/cn/doc/doccenter-atomic-service/account-guide-atomic-faq)。

## 2026-09-25 真机错误码跟进

用户安装新包后仍收到原生 `1001502003`。该错误发生在获取授权码之前，服务端尚未参与。后续找到了本机 DevEco SDK 的 `hdc`，设备已连接；`bm dump` 显示安装包内有预期的 `client_id`，应用采用 `debug` Profile，系统报告的应用签名指纹与本机 HAP 证书链中的开发证书一致。

本机 `hap-sign-tool` 对 HAP 和 Profile 的签名验证通过。Profile 的包名、设备、有效期和本地签名材料一致。HAP 实际开发证书的 SHA-256 指纹为 `A5111E5115C043FD540409D130D4B413519B7ED7D42696C713695E8CE094FE59`（证书链第 1 项，不是根 CA）。**这只证明本地签名材料彼此一致，不能证明 AGC 中的应用 Client ID 和 SHA-256 证书指纹已与之匹配。**

用户提供的新版 AGC 截图确认 `com.flowmuse.app` 的 **APP ID 和应用级 OAuth Client ID 都是 `6917611606499874343`**；本机 `debug` Profile 的 `bundle-info.app-identifier` 却是 **`6918737523937821249`**。AGC 当前登记的 SHA-256 指纹为 `E5F20841B73E08AD367DA70539DA2C7627CC3930240B274A49022DA47F3E63FC`，而安装包使用的是上文的 `A511...`，两者也不相同。本机 `.ohos/config` 中的所有现有证书均无 `E5F2...` 指纹，不能通过切换本地现成证书解决。这两处身份不一致是当前 `1001502003` 的明确配置线索。

下一步在 DevEco Studio 使用「关联注册应用」签名，选择 AGC 中 APP ID `6917611606499874343` 对应的 FlowMuse 应用；或在 AGC 为该 APP ID 重新申请调试 Profile。新 HAP 签名后解码 Profile 核对 `app-identifier`，提取实际开发证书指纹并添加到同一 AGC 应用，保留原有指纹，再安装真机测试。`debug` 模式本身受支持，关键是 Profile、Client ID、AGC 应用和签名指纹必须一致。[华为关联注册应用的自动签名说明](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto)。

## 2026-09-26 关联签名与安装验证

DevEco 的团队已切换到 FlowMuse 所属的「任逸青」，同包名冲突提示消失。新生成的 `default` 调试 Profile 经 `hap-sign-tool verify-profile` 验证，包名为 `com.flowmuse.app`，`app-identifier` 为 AGC APP ID `6917611606499874343`。但本机工程级 `ohos/build-profile.json5` 的默认产品仍引用旧 `debug` 签名配置；第一次 `flutter build hap --debug --no-pub` 产出的 HAP 因此仍携带旧 `app-identifier`。将默认产品的 `signingConfig` 改为 `default` 后重建，`hap-sign-tool verify-app` 确认包内 Profile 的 APP ID 为 `6917611606499874343`。证书链不能按输出顺序盲取第一项：第一项 SHA-256 `DF21A3C09F7954579305F85C64F80CAD86F79853EE3A887C1DEC95D218DF3A37` 是根证书；**实际开发证书在第二项，SHA-256 为 `5215C110A83A366570715425D04ECD2BA5B1C4AD65EF49028FE43A7E692F4768`**，与设备 `bm dump` 的 `fingerprint` 一致。曾让用户误将根证书指纹添加到 AGC，已通知用户删除并改加开发证书指纹，保留原有指纹。`build-profile.json5` 是本机生成的忽略文件，不提交签名路径、密码或私钥。

本次默认 release 构建在 `ProcessRouterMap` 阶段因本机 ohpm 依赖解析 `ENOENT: stat ''` 中止；针对真机调试的 `flutter build hap --debug --no-pub` 已成功。设备原有 FlowMuse 为旧 `app-identifier` 和旧证书，`hdc install -r` 返回 `9568332 install sign info inconsistent`，未覆盖安装。用户确认该测试设备无须保留旧应用数据后，已卸载旧包并安装新 HAP；设备 `bm dump` 显示 APP ID、`client_id` 都是 `6917611606499874343`，开发证书指纹为上述 `5215...`。待 AGC 指纹替换并完成真机授权测试前，不能声称登录已修复。
