# 华为账号登录后填充头像与昵称

日期：2026-09-26

## Context

华为登录真机已可建立 FlowMuse 会话，但原生请求仅返回授权码；服务端只校验 UnionID，并把首次用户昵称写为“华为用户”、头像留空。用户希望登录后自动显示华为头像和昵称。现有 `users.display_name/avatar_url`、账户响应和头像组件可直接复用。

## 需求

- 鸿蒙华为登录申请 `profile` 授权；取得授权码后仍由服务端核验 UnionID，绝不信任客户端自报身份或资料。
- 有资料时填充新账号及仍为默认资料的旧华为账号；保留 FlowMuse 中手动修改过的昵称和上传头像。
- 无资料、旧客户端未授予 `profile` 或资料接口短暂故障时保留现有登录能力；不请求手机号或邮箱，不持久化华为 Access Token。

## 实现方案与关键文件

1. `HuaweiAccountChannel.ets` 使用华为官方 `createAuthorizationWithHuaweiIDRequest()`，传 `scopes=['profile']`、`permissions=['serviceauthcode']`，继续检查 `state`，只向 Dart 返回授权码。
2. `huawei_client.go` 兑换授权码并校验 UnionID 后，仅在华为授予 `profile` scope 时调用华为用户信息接口，读取昵称与头像；只接受长度受限的昵称和 HTTPS 头像地址。资料失败不影响身份校验结果。
3. `account_link_api.go` 和 `account_link_store.go` 在已有业务会话创建前补全默认资料；自定义昵称和本地上传头像不被覆盖。
4. 沿用现有 Flutter 账户模型、头像组件和邮箱登录路径；同步需求与接口文档。

## 验证方案与实施步骤

先跑账号测试基线；实现后覆盖 profile scope 有无、资料缺失/出错、头像 URL 校验与保留手动资料的测试，运行 `go test ./...`、`go vet ./...`、`flutter analyze`、`flutter test`、`flutter build hap`。构建通过仍需真机重新授权并确认头像与昵称实际返回。

依据：[华为获取头像昵称指南](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/account-get-avatar-nickname-V5)、[华为获取用户信息 REST API](https://developer.huawei.com/consumer/en/doc/development/HMSCore-References/get-user-info-0000001060261938)。

## 实施与验证记录

- 原生授权请求已改为 `AuthorizationWithHuaweiIDRequest`，申请 `profile` 和 `serviceauthcode`，Flutter 通道仍只传授权码。
- 服务端只从华为的凭证接口和用户信息接口读取身份与资料；资料接口失败时保留已验证的华为登录。已有默认昵称“华为用户”和远程华为头像可在重新登录时补全或更新；用户手动设置的昵称与上传到 FlowMuse 的头像保留。
- `go test ./...`、`go vet ./...`、`flutter analyze --no-pub` 均通过；`flutter test --no-pub` 为 1790 项通过、6 项既有跳过；`flutter build hap --debug --no-pub` 与 `flutter build hap --no-pub` 均成功。
- PostgreSQL 集成测试使用 `FLOWMUSE_AUTH_TEST_DATABASE_URL` 指向独立 `*_test` 数据库；本机没有运行中的 Docker/PostgreSQL，故相关测试按既有门禁跳过。当前服务端未部署，新资料授权的真机端到端显示仍需在部署后重新登录验证。
