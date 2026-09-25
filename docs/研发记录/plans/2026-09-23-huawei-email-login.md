# 鸿蒙华为账号登录与双端邮箱登录实施计划

日期：2026-09-23

状态：代码实现、本机自动检查、生产后端与 Web 部署已完成。华为应用凭据已配置并通过官方应用级凭证接口验证，生产数据库迁移与接口检查通过。Resend 线上发信及 QQ 实际收件已在前一阶段验证。HAP 构建、签名及双端真机联调待完成；应用凭据有效不等同于鸿蒙用户授权流程已验收。

勘察基线：`main`，`7bdb210`。

## Context

目标是在鸿蒙版 FlowMuse 中增加华为账号登录，并确保鸿蒙、Android 均可使用邮箱登录。用户已确认：**先完成华为登录，之后可绑定邮箱，以便在 Android 登录同一个账号**。邮箱登录沿用项目现有的“邮箱 + 密码”方式。

实施环境：用户已确认**本机不做鸿蒙设备调试**，且已移除本机 DevEco 相关环境。本机侧推进登录代码、服务端配置及可执行的自动化检查；鸿蒙 HAP 构建、签名配置和真机验证由具备工具链与设备的打包、测试电脑完成。恢复本机调试环境或找回旧发布密钥不作为开始代码开发的前置条件；签名与真机验收仍须在宣布鸿蒙登录可用前完成。

已核对的现状：

| 现状 | 代码依据 | 对实施的影响 |
|---|---|---|
| 已有邮箱注册、验证、密码登录、重发邮件、找回密码、退出登录 | `FlowMuse-App/lib/features/account/repositories/account_repository.dart`、`FlowMuse-Server/internal/auth/http_api.go` | 复用现有流程，补双端验证 |
| 登录界面位于设置页的账号区域 | `FlowMuse-App/lib/features/settings/views/settings_page.dart` | 在原入口增加华为登录和账号绑定状态 |
| 服务端已有用户表、会话表、邮件令牌、密码哈希及业务 token | `FlowMuse-Server/internal/auth/user_store.go`、`tokens.go` | 两种登录统一到现有 `users.id` 和会话体系 |
| 用户表强制邮箱和密码非空，客户端也假定邮箱存在 | `users.email/password_hash NOT NULL`、`account_user.dart` | 必须支持只有华为身份的账号 |
| HTTP 鉴权要求 `EmailVerified`，Socket.IO 另有身份入口 | `HTTPAPI.IdentityFromRequest`、`Hub.identityFromSocket` | 将账号身份有效性与邮箱验证状态分开，统一两个入口的判定 |
| 账号请求默认用普通 `http.Client`；项目已有 `HarmonyAwareHttpClient` | `account_repository.dart`、`native_http_client.dart` | 复用既有鸿蒙网络适配，覆盖邮箱与华为两条链路 |
| token 已使用支持 OHOS 的安全存储 facade | `auth_token_store.dart` | 保留存储方式，验证重启恢复和退出清理 |
| 仓库 Compose 邮件配置默认使用 Mailpit，支持通过环境变量接入 Resend；线上已启用 Resend | `FlowMuse-Server/docker-compose.yml`、`.env.example`、线上容器配置 | 发信域名已验证，SMTP 认证通过；注册、重发及找回密码的完整流程仍需验收 |

## 需求与边界

| 能力 | 鸿蒙 | Android |
|---|---|---|
| 邮箱注册、验证、邮箱 + 密码登录、找回密码 | 支持 | 支持 |
| 华为账号授权登录 | 支持 | 不展示入口 |
| 华为首次登录时不填写邮箱 | 支持 | — |
| 为华为账号添加邮箱登录方式 | 在账号设置中验证邮箱并设置密码 | 完成绑定后，用该邮箱和密码登录 |
| 已有邮箱账号添加华为登录方式 | 登录邮箱账号后主动绑定华为账号 | 继续使用邮箱登录 |
| 退出、会话恢复、协作用户身份 | 使用同一套 FlowMuse 账号体系 | 使用同一套 FlowMuse 账号体系 |

同一账号在两端登录意味着使用相同的服务端用户 ID、资料和协作身份；现有本地笔记仍遵循原来的本地存储、协作与备份机制，本次不增加全量笔记云同步。

首版仅接入华为身份登录，不获取手机号；头像与昵称最初沿用 FlowMuse 现有资料设置。2026-09-26 后续扩展为登录时申请 `profile` 权限并自动填充资料，见 [华为资料同步计划](2026-09-26-huawei-profile-sync.md)。普通华为账号登录的本地指南支持个人和企业开发者，不需要采用仅面向企业开发者的手机号一键登录方案。

## 实现方案

### 1. 统一账号，增加一种登录凭据

继续以 `users.id` 作为唯一业务用户 ID。华为身份和邮箱是进入同一账号的两种凭据，不新建第二套用户、token 或协作身份系统。

- 在 `users` 增加可空的 `huawei_union_id`，建立非空值唯一约束；首版仅对接一个固定华为开发者主体下的应用，不引入通用第三方登录框架。
- UnionID 只接受服务端向华为验证后的结果，保持原始大小写。每个 UnionID 只能绑定一个 FlowMuse 用户。
- `email`、`password_hash` 允许为空；保留已有邮箱唯一约束。纯华为账号不生成虚假邮箱或默认密码。
- 兼容现有响应格式：对尚未绑定邮箱的用户返回 `email: ""`；增加 `huaweiLinked`、`hasPassword` 等实际需要的状态字段，不向客户端暴露数据库里的原始华为身份标识。
- 调整所有涉及邮箱、密码的 SQL 读取、个人资料显示、昵称兜底、修改密码入口，覆盖空值情况。纯华为用户显示“邮箱未绑定”，不显示为登录失败。
- 数据库变更进入现有 `EnsureSchema`，采用幂等 DDL；验证空库初始化、已有用户升级、重复执行。已有用户 ID、密码哈希、会话和房间归属保持有效。

### 2. 鸿蒙原生授权接入

采用本地指南的“使用自定义按钮登录”路线，适配项目已有 Flutter 页面：

1. 在原账号入口增加符合华为视觉规范的“华为账号登录”按钮。
2. Dart 适配层通过 `flow_muse/huawei_account` MethodChannel 调用 ArkTS。
3. ArkTS 使用 `@kit.AccountKit` 的 `HuaweiIDProvider.createLoginWithHuaweiIDRequest()` 和 `AuthenticationController.executeRequest()` 获取授权码。
4. 每次操作生成并核对请求 `state`；处理用户取消、网络错误、系统未登录、重复点击和页面销毁后的回调，不把取消当成登录成功。
5. 授权码传给 FlowMuse 后端；只有后端返回业务会话后，才更新 `AccountViewModel` 并写入安全存储。

在 `EntryAbility.configureFlutterEngine()` 注册通道。平台能力通过适配层提供的可用性状态暴露，页面不散落操作系统判断；未注册通道或不支持的平台返回不可用，Android 保持邮箱入口。

华为应用配置先核对实际包名、应用 Client ID 和服务端 Client Secret，实际使用的签名及公钥指纹由打包环境核对。当前工程 `compatibleSdkVersion` 为 `5.1.0(18)`、`targetSdkVersion` 为 `6.1.1(24)`，须按目标版本核实所用签名要求，不要求在本机新增调试证书。已有发布证书与 Profile 优先保留，配套 `.p12` 由原持有人提供给实际打包环境使用。Client ID 与 APP ID 不同时，按指南配置 entry 模块的 `client_id`。Client Secret 只放在服务端受控配置中。

### 3. 后端验证并复用业务会话

新增华为登录入口，复用现有 Go HTTP 服务：

1. 接收授权码，限制请求体大小、超时和请求频率。
2. 服务端使用自己配置的 Client ID、Client Secret 向华为兑换凭证，再调用凭证解析接口取得可信 UnionID，并按接口返回字段校验应用归属与有效性。
3. UnionID 已绑定时加载原用户；未绑定时在数据库事务中创建无邮箱用户并绑定 UnionID。并发首次登录依靠唯一约束保证只创建一个有效账号。
4. 复用 `writeAuthSession`、`TokenService` 和 `AuthTokenStore`，返回现有 `{token, user}` 结构。
5. 业务鉴权接受“有效业务 token + 活跃会话 + 已验证邮箱或已绑定的可信华为身份”。邮箱登录本身仍要求邮箱已验证，不通过伪造 `emailVerified=true` 放行华为用户。

HTTP `/me`、资料修改、头像、协作 HTTP 和 Socket.IO 的身份判定一起核对，避免出现“登录成功但其他接口认为是游客”。

采用授权码兑换流程，不信任客户端自报的 UnionID、用户 ID 或未经验证的 ID Token。华为授权码只能使用一次、有效期有限，重复或过期时重新授权，不盲目重放。仅用华为凭证完成身份确认，不为登录功能建立长期保存华为 Access Token/Refresh Token 的新体系；应用保持登录继续使用现有 FlowMuse 会话。[官方用户级凭证接口](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/account-api-obtain-user-token)

### 4. 邮箱绑定与已有账号处理

**华为先登录，随后添加新邮箱：**

1. 账号设置显示“绑定邮箱，在其他设备登录”，用户可跳过。
2. 已登录用户输入邮箱，服务端创建专用于绑定的邮件令牌，记录发起用户、目标邮箱、有效期，向目标邮箱发送验证邮件。
3. 邮件页面完成邮箱所有权验证；验证链接只标记该次绑定申请已验证，不自动注册第二个用户、不切换浏览器里的登录账号。
4. 用户回到原 App，设置邮箱登录密码并完成绑定。服务端要求原登录会话、绑定申请归属、目标邮箱证明均有效，在同一事务中写入邮箱与密码哈希并消费申请。
5. 绑定后保持原 `users.id`，Android 用邮箱和密码登录时得到同一个用户。完成后刷新账号状态，华为登录继续可用。

复用现有发信、随机令牌、哈希和邮件页面机制；为 `auth_email_tokens` 增加绑定所需的目标邮箱及验证状态，明确区分注册验证、密码重置和邮箱绑定的 purpose。已验证状态也有有效期；重发使旧申请失效，提交时再次核验邮箱唯一性。密码只在最终确认时提交，邮件或待验证记录中不保存明文密码。

**先有邮箱账号，随后添加华为登录：**

用户在鸿蒙上先用邮箱登录，再在账号设置中点“绑定华为账号”，重新完成华为授权。后端验证当前 FlowMuse 会话和新的华为授权码，把尚未绑定的 UnionID 关联到当前用户。重复绑定同一用户按成功处理，绑定到不同用户时返回明确冲突。

**已经存在两个不同账号时：**

邮箱已属于另一个用户，或华为身份已绑定另一个用户，均提示“该登录方式已绑定其他账号”，保留原账号和数据。首版不自动合并或转移两个已有账号；界面说明应先用希望保留的账号登录，再添加尚未被占用的登录方式。若两个账号都已独立创建，则账号合并是后续单独需求，不能用覆盖邮箱或转移 UnionID 绕过。

首版不提供解绑、换绑已有邮箱或删除最后一种登录方式。新增绑定接口设置过期、一次性消费、重发冷却和请求频率限制，并对错误信息、日志中的凭据进行脱敏。

### 5. 邮箱链路与客户端状态

- 用户已选择 Resend 免费方案。复用现有 SMTP 实现，使用 `smtp.resend.com:587`、用户名 `resend`，API Key 作为 SMTP 密码；凭据仅写入服务端受控配置。`notify.flowmuse.cloud` 发信子域名已验证，线上配置已启用，配置步骤见 `FlowMuse-Server/README.md`。不新增邮件 SDK，现阶段不购买付费套餐。
- 保留邮箱加密码、注册邮件验证、重发邮件和找回密码流程；先验证现有代码，再修复实际阻碍双端登录的问题。
- 账号网络请求复用现成 `HarmonyAwareHttpClient`；公共网络适配入口收敛到 `shared/network`，原位置保留兼容导出，避免从账户模块新增对白板内部实现的依赖。不重写网络框架。
- 无密码用户显示“绑定邮箱并设置密码”；已有密码用户显示原“修改密码”。找回密码只面向已验证邮箱。
- 华为授权取消、绑定失败等操作不覆盖当前有效会话，不把已登录用户的 `AccountStatus` 改成导致页面退出账号的失败状态。
- token 写入成功后再完成登录状态切换；验证重启恢复、过期会话处理和退出清理。退出 FlowMuse 不退出设备系统华为账号，也不清理本地笔记。
- 验证真实邮件可到达测试邮箱，公开验证/重置页面在两种设备浏览器中均可打开；邮件在浏览器验证完成后，App 可以刷新状态或重新登录，不以必须自动拉起 App 作为首版前提。

2026-09-23 邮件配置进度：

- Resend 控制台显示发信域名 `Verified`；DNSPod 权威 DNS 和公共 DNS 的三条必需记录均与 Resend 配置匹配。
- 本地 `FlowMuse-Server/.env` 已保存邮件配置，该文件被 Git 忽略；真实密钥未写入样例、文档或源码。
- 线上部署目录 `/opt/flowmuse/source/FlowMuse-Server` 已更新五个 SMTP 变量及 Compose 插值配置。Compose 解析结果确认仅邮件设置变化；重建应用容器后，实际环境变量匹配配置，本机与公开 `/health` 均返回 HTTP 200，数据库、MinIO 和 Mailpit 容器未重建。
- 本机与线上服务器通过 STARTTLS 完成 SMTP 认证（235）。使用线上容器的实际邮件配置发送了一封用户授权的测试邮件，SMTP 服务已接受，用户已确认 QQ 邮箱实际收到；尚未执行注册、重发及找回密码的端到端验收。
- 变更前的服务端 `.env` 与 Compose 已备份到 `/opt/flowmuse/backups/resend-smtp-20260923-043653`，备份目录及文件权限分别为 `0700`、`0600`。

## 关键文件与接口

| 位置 | 计划改动 |
|---|---|
| `FlowMuse-App/lib/features/account/models/account_user.dart` | 无邮箱兼容、登录方式状态、昵称兜底 |
| `FlowMuse-App/lib/features/account/repositories/account_repository.dart` | 华为登录、绑定请求、统一网络适配 |
| `FlowMuse-App/lib/features/account/view_models/account_view_model.dart` | 复用会话状态、取消及绑定失败处理 |
| `FlowMuse-App/lib/features/account/repositories/huawei_account_channel_ohos.dart`（新增） | 原生授权与能力探测，向上返回纯 Dart 类型 |
| `FlowMuse-App/lib/features/settings/views/settings_page.dart` | 鸿蒙登录按钮、绑定入口和账号状态 |
| `FlowMuse-App/lib/features/account/views/`、`app/app_router.dart` | 扩展邮件绑定验证页面，复用已有验证页面结构 |
| `FlowMuse-App/lib/shared/network/`、原 `native_http_client.dart` | 复用并归位现有公共 HTTP 适配，兼容原调用方 |
| `FlowMuse-App/ohos/entry/src/main/ets/channels/HuaweiAccountChannel.ets`（新增） | Account Kit 授权 |
| `FlowMuse-App/ohos/entry/src/main/ets/entryability/EntryAbility.ets`、`module.json5` | 通道注册、必要的 Client ID 配置 |
| `FlowMuse-Server/internal/auth/user_store.go`、`http_api.go` | 数据模型、账号关联、绑定邮件、会话鉴权 |
| `FlowMuse-Server/internal/auth/huawei_client.go`（新增） | 用标准 HTTP 客户端封装华为凭证兑换与解析 |
| `FlowMuse-Server/internal/auth/mailer.go`、`internal/config/config.go`、`cmd/flowmuse-collab-server/main.go` | 邮件内容、华为配置注入 |
| `FlowMuse-Server/internal/collab/hub.go` | 与 HTTP 一致的登录身份识别，不改协作协议 |

接口已实现，字段与错误码见 `docs/技术设计/接口设计.md`：

| 接口 | 用途与鉴权 |
|---|---|
| `POST /api/auth/huawei/login` | 授权码换取 FlowMuse 会话；服务端验证华为身份 |
| `POST /api/auth/huawei/bind` | 当前登录账号绑定华为身份；要求业务会话和新授权码 |
| `POST /api/auth/email-binding/request` | 发起邮箱绑定验证；要求业务会话 |
| `POST /api/auth/email-binding/verify` | 验证邮件令牌，只确认对应目标邮箱的控制权 |
| `POST /api/auth/email-binding/complete` | 要求原账号业务会话、已验证的有效申请、新密码；原子完成绑定 |
| `GET /api/auth/me` | 继续返回用户资料，并增加实际需要的登录方式状态 |

已有邮箱登录、注册、验证、找回密码端点保持兼容；华为能力未配置时只禁用新入口，不阻止现有邮箱服务启动。

## 验证方案

| 场景 | 验收结果 |
|---|---|
| 鸿蒙新用户点击华为登录 | 不要求邮箱；得到正常 FlowMuse 会话，能读取资料并以登录用户身份协作 |
| 同一华为用户重复登录、并发首次登录 | 用户 ID 稳定，不产生重复用户 |
| 取消授权、断网、授权码过期或重复使用、错误应用凭据 | 不生成会话；可继续选择邮箱登录；不丢失已有会话 |
| 鸿蒙与 Android 邮箱注册、验证、登录、重发、找回密码 | 两端流程可用，错误密码和未验证邮箱仍被拒绝 |
| 华为登录后绑定新邮箱并设置密码，再到 Android 登录 | 两端 `/api/auth/me` 返回同一 `user.id`，资料一致 |
| 已有邮箱账号在鸿蒙绑定未占用华为身份 | 后续邮箱、华为两种方式进入同一账号 |
| 目标邮箱/华为身份被其他账号占用 | 返回冲突，不合并、不覆盖、不转移数据 |
| 邮件链接伪造、过期、重复使用，跨用户提交绑定 | 被拒绝；绑定失败事务不留下半完成状态 |
| 纯华为账号编辑昵称、使用头像、重启恢复、退出登录 | 不因空邮箱或无密码崩溃，不显示错误的邮箱验证要求 |
| HTTP 与 Socket.IO 协作身份 | 识别同一用户；原协作权限和密钥机制正常 |
| Android、Web 及其他端加载共享代码 | 不依赖鸿蒙原生实现；Web 邮件页面可直接打开和刷新 |
| 旧数据库升级、空库初始化、重复迁移、旧版邮箱客户端 | 原有用户及接口继续可用 |

开发期间补充最小且有意义的检查：服务端凭证兑换使用 `httptest`，数据库唯一性/绑定事务/迁移用隔离测试 PostgreSQL；Flutter 使用注入的 HTTP 客户端与模拟 MethodChannel，覆盖平台入口、会话更新和错误路径，不在单元测试中调用真实华为服务或发送真实邮件。

集成完成后，在对应工具链环境执行 `flutter analyze`、相关测试及全量 `flutter test`、`go test ./...`、`go vet ./...`，并完成 Android 与 Web 构建，验证邮件页面和共享代码。本机运行可执行的检查；`flutter build hap`、鸿蒙签名和鸿蒙真机验收交由具备项目 Flutter/OHOS 工具链与设备的电脑执行，回传对应代码版本、构建结果和授权登录验证记录。构建通过不能替代鸿蒙与 Android 真机验收。

真实邮件和华为授权联调使用专用测试账号，并记录设备、系统、安装包与服务端版本。首次整体验收前，打包、测试侧需准备匹配的签名材料、一台鸿蒙和一台 Android 设备，服务端需完成应用凭据与可投递的 SMTP 配置。这些是集成验收条件，不阻塞本机先实现代码；未拿到真实验收证据时，明确标记鸿蒙授权链路待验证，不要求用户将鸿蒙设备接到本机。

## 实施步骤

| 顺序 | 工作 | 阶段完成标志 |
|---|---|---|
| 1 | 核对 AGC 应用参数，复核现有邮箱、网络、安全存储和邮件实现；打包、测试侧并行准备签名与设备 | 现有实现与待配置项有记录，代码开发不等待本机鸿蒙调试环境 |
| 2 | 扩展用户模型、幂等迁移和鉴权；实现服务端华为授权码兑换 | 模拟华为响应与隔离数据库测试通过，邮箱旧流程保持可用 |
| 3 | 接入鸿蒙 Account Kit 通道与原登录页 | 鸿蒙真机首次及重复华为登录通过，Android 保持邮箱入口 |
| 4 | 实现邮箱验证后绑定、设置密码及邮箱账号绑定华为 | “鸿蒙华为登录 → 绑定邮箱 → Android 邮箱登录同一用户”通过 |
| 5 | 完成安全边界、旧用户升级、HTTP/Socket.IO 及多端回归，补文档和演示 | 自动检查、双端真机、专用测试邮箱均有证据 |

落地代码时使用功能分支。发布顺序为兼容性后端与数据库变更、Web 邮件页面、原生客户端。保留既有邮箱入口；如需回退，先关闭新登录入口并回退到兼容新 schema 的服务版本，不删除华为身份数据，也不能把有无邮箱用户的数据库直接交给仍强制非空读取的旧服务。

实施后同步 `docs/项目说明/项目需求.md`、`docs/技术设计/接口设计.md`、`docs/技术设计/数据模型.md` 及新增通道说明。比赛演示建议用真实流程展示鸿蒙授权与双端同一账号，避免把本地笔记自动同步作为本次登录功能的承诺。

## 2026-09-23 实现与验证记录

实现分支：`feature/huawei-email-login`。复用既有账号、会话、邮件、安全存储和鸿蒙 HTTP 实现，无新增依赖。

- 已完成无邮箱用户模型、幂等 PostgreSQL 迁移、华为授权码兑换与 token-info 核验、两种方向的登录方式绑定、统一 HTTP/Socket.IO 身份判定。
- 已完成 Account Kit 原生通道、平台能力探测、登录与绑定入口、Web 邮件确认页面。资料更新用 PUT，同时服务端兼容旧 PATCH。取消和绑定失败保留原会话，安全存储写入串行化，晚到的登录/恢复响应不会覆盖退出或新登录。
- `go test ./...`、`go vet ./...` 通过。隔离 PostgreSQL 17 测试覆盖空库/旧库/重复迁移、旧密码保留、并发首次登录、并发一次性绑定、原账号原会话校验、过期/重放/重发、占用冲突、撤销会话、HTTP 身份与资料更新。测试容器已移除，生产 `/health` 仍为 200。
- Flutter 全量测试 1735 项通过、5 项跳过；账号/网络/路由专项 12 项通过。账号页面覆盖有/无原生能力、纯华为与邮箱账号，邮件绑定页面不切换浏览器会话。
- Web release 构建通过并已部署：`FlowMuse-App/build/web`；Android debug 构建通过：`FlowMuse-App/build/app/outputs/flutter-apk/app-debug.apk`，尚未分发安装。构建产物使用生产 API/分享域名。
- `flutter analyze` 无新增问题；现有 `build/nav_compact_screenshot_test.dart:199` 有一条 `invalid_use_of_protected_member` 警告，与本次实现无关。
- 1280×1100 账号页面已用真实 Flutter widget 加模拟账号进行渲染检查，图像为 `FlowMuse-App/build/huawei-email-harmony.png` 与 `huawei-email-huawei-only.png`；这不是鸿蒙真机授权证据。

### 合并前复核

2026-09-23 在 `feature/huawei-email-login` 重新执行：

- `go test ./...`、`go vet ./...` 通过。数据库集成用例本轮未配置隔离数据库而跳过；空库、旧库和并发绑定的实际验证记录见上文。
- `flutter test --no-pub --reporter expanded`：1735 项通过、5 项既有跳过项。
- `flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos`：无 error，仅上述本地 `build/nav_compact_screenshot_test.dart` 历史 warning。
- `flutter build hap --no-pub`：因本机没有 Hmos SDK 未能执行构建，仍需在打包电脑完成 HAP 与鸿蒙真机验收。
- UI 证据已归档为[登录入口](../evidence/huawei-email-login/login.png)和[纯华为账号绑定邮箱](../evidence/huawei-email-login/email-binding.png)。两图来自真实 Flutter widget 渲染与模拟账号状态，不代表设备授权成功。

### 生产部署记录

- 用户授权接入密钥并部署后，已将应用 `6917611606499874343` 的 `FLOWMUSE_HUAWEI_CLIENT_ID` 和 `FLOWMUSE_HUAWEI_CLIENT_SECRET` 写入服务器 `/opt/flowmuse/source/FlowMuse-Server/.env`，权限为 `0600`。使用[华为官方应用级凭证接口](https://developer.huawei.com/consumer/en/doc/harmonyos-references/account-api-obtain-app-token)验证返回 200；凭据及返回 token 不写入仓库、客户端或日志。新增 `.dockerignore` 排除私有环境文件，本次构建包仅包含明确选取的源码与构建文件。
- 部署前逐文件核对线上 Go 源码与 `7bdb210` 一致。备份目录为 `/opt/flowmuse/backups/huawei-login-20260923-055108`，包含 PostgreSQL 自定义格式备份、原配置、源码、Nginx 配置及验证记录；已验证备份可被 `pg_restore --list` 读取。旧镜像保留为 `flowmuse-server-collab-server:before-huawei-20260923-055108`。回退仍须遵守上文的新 schema 兼容性要求。
- 新后端镜像为 `flowmuse-server-collab-server:huawei-login-20260923-055108`（SHA-256 前缀 `30d7f531d3ac`），只重建应用容器。已核对除新增华为凭据外，原生产 Compose、邮件与其他业务环境变量一致；数据库、MinIO 容器和数据卷未重建。
- 生产迁移已完成：邮箱、密码及华为身份允许空值，华为身份唯一索引、邮件绑定字段已验证。迁移前后账号数据摘要一致；HTTPS/旧 HTTP 健康检查为 200，Socket.IO polling 握手为 200，API/Web 两域名的 WSS Upgrade 为 101，Web 跨域预检为 204。新增授权入口拒绝空码（400）和真实华为服务判定的无效码（401）；绑定接口拒绝未登录请求，伪造邮件 token 返回 400。
- Web 发布目录为 `/var/www/flowmuse-app-releases/huawei-login-20260923-055108`。Nginx 配置检查通过并已 reload；首页、邮件验证深链、`main.dart.js`、`flutter_bootstrap.js` 的线上内容哈希与构建产物一致。原 HTTP 入口、HTTPS、代理与压缩配置保留。本轮浏览器控制工具读取超时，未完成部署后的浏览器画面检查；前一阶段 Flutter widget 渲染检查证据仍保留。

待完成验收：在具备环境的打包电脑执行 `flutter build hap`，使用与 AGC 应用匹配的证书/指纹。核验实际 Account Kit 授权、取消、断网、恢复、Socket.IO 协作，再完成“鸿蒙华为登录 → 绑定邮箱 → 安卓邮箱登录同一用户”。本机不恢复 DevEco 或寻找发布私钥。

## 技术文档依据

本地目录：`D:/Program/HarmonyOS/harmonyos-guides/应用服务/Account Kit（华为账号服务）/`。

- `登录/account-quick-login-overview.md`：普通账号登录与手机号一键登录的区别，UnionID/OpenID 用途。
- `登录/华为账号登录（获取UnionID-OpenID）/account-unionid-login-api.md`：自定义按钮、原生 API、state、客户端与服务端流程。
- `开发准备/account-client-id.md`：应用 Client ID 的获取和配置条件。
- `开发准备/account-sign-fingerprints.md`：签名与公钥指纹要求，实施时按实际 SDK/工具版本复核。
- [华为官方：获取用户级凭证](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/account-api-obtain-user-token)：2026-09-23 联网核对授权码兑换要求；其他细节以上述本地指南与实施时的官方接口文档为准。
