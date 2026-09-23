# 协作邀请测试与鸿蒙交接

分支 `feature/friends-collaboration`，PR [#51](https://github.com/qinyre/FlowMuse/pull/51)。本次实现设备安全卡、定向加密邀请、拒绝/撤销、新设备补发及安全加入白板。生产未合并、未部署，两个社交开关仍默认关闭。

## 当前电脑直接试用

临时预览已启用独立数据库与文件存储，仅监听本机。保持后端、Web 服务及 SSH 转发进程运行；测试数据可丢弃，服务停止/电脑休眠或隧道断开后需重新启动。此入口不使用生产账号和邮件服务。

| 角色 | 浏览器地址 | 测试邮箱 | 测试密码 |
|---|---|---|---|
| A | <http://127.0.0.1:18344/social> | `invite-a@example.test` | `PreviewInvite26!` |
| B | <http://localhost:18344/social> | `invite-b@example.test` | `PreviewInvite26!` |

两个 Web 地址连接同一测试后端，但浏览器本地存储互相隔离，可同时登录 A/B。测试账号已经互为好友。密码只用于一次性预览数据库，不能用于任何正式部署。A 的浏览器设备已登记；自动联调产生的已撤销设备与失效邀请属于测试痕迹。

Android 本地联调包：`FlowMuse-App/build/app/outputs/flutter-apk/app-debug.apk`，API 指向 `http://127.0.0.1:18343`。USB 连接这台电脑后运行 `adb reverse tcp:18343 tcp:18343`，再安装 APK；离开转发环境不会连到正式 API。不能将此包当作正式发布包。

## 最短验收流程

1. 两端分别进入「好友与消息 → 我的设备安全 → 登记并复制本机安全卡」。通过当面、可信外部聊天等渠道互换卡片；不要把服务器设备列表本身当作验证证据。
2. 各自打开对方的聊天，点「核验好友设备」，粘贴收到的完整卡片，核对好友码与完整指纹后确认信任。双方都要完成；换设备需再核验。
3. A 打开本地笔记，创建协作房间。保持白板打开，点白板的「好友与消息」，选择 B，再点「邀请协作当前白板 → 发送邀请」。弹层关闭后白板应仍在线。
4. B 在邀请卡点「查看并加入 → 接受并加入白板」。双方各画一笔。加入失败只保留 accepted，真正加入后才显示「已加入过白板」。邀请路由地址只包含邀请编号。
5. A 再次打开聊天，确认房间未结束。B 打开其他白板时接受邀请，取消退出对话应保持旧白板；确认退出则先保存，房主必须先确认结束旧房间。
6. B 使用另一浏览器/设备登录同一账号，登记新设备；旧卡应提示本机无信封。A 核验 B 的新安全卡后，在原邀请点「补发新设备」，选择新设备；B 重试可加入，不新增第二张聊天卡。已收到过信封的设备无需补发。
7. 分别验证拒绝、撤销、过期、A 结束房间、删除好友、屏蔽、断网重试、退出后换账号。旧邀请不得给第三个账号领取；换号后旧操作结果不能落到新账号。已解密的旧 roomKey 无法通过撤销邀请追回。

## 在队员电脑搭建相同测试环境

需要 Docker Compose、项目 Flutter 工具链和 Python。以下操作只针对本文件中的独立测试项目，不使用默认开发 Compose 的固定容器名、卷或生产配置。

```sh
# 在 FlowMuse-Server 目录运行；本机 18343/18345 必须空闲
docker compose -p flowmuse-invite-test -f docker-compose.social-test.yml up -d --build

# 在 FlowMuse-App 目录运行（把这一行完整执行）
flutter pub get
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none --dart-define=FLOWMUSE_COLLAB_SERVER_URL=http://127.0.0.1:18343 --dart-define=FLOWMUSE_SHARE_ORIGIN=http://127.0.0.1:18344
python tool/serve_web_preview.py
```

首次进入分别注册两个 `@example.test` 账号；打开 <http://127.0.0.1:18345> 的 Mailpit 收件箱完成测试邮箱验证，再互加好友。邮件只在测试容器内保存，不向外投递。该 Compose 使用临时内存存储，停止/重建存储容器会丢失测试数据。

测试完毕，在 `FlowMuse-Server` 运行以下命令仅停止并移除这套测试容器：

```sh
docker compose -p flowmuse-invite-test -f docker-compose.social-test.yml down
```

如使用团队已有的 HTTPS 测试环境，服务器同时启用 `FLOWMUSE_SOCIAL_ENABLED=true` 和 `FLOWMUSE_SOCIAL_INVITATIONS_ENABLED=true`；所有客户端的 `FLOWMUSE_COLLAB_SERVER_URL` 必须是相同 origin，重新构建后再交换安全卡。原生产 App/API 地址上的版本仍不包含本次改动。

## 鸿蒙队员重点验证

- 使用本分支与原发布/调试签名配置打包；本次未改证书或恢复此电脑的 DevEco。构建前把 API 指向团队测试环境，或配置设备到测试电脑的端口转发。
- 华为账号登录后登记设备、双向核验，与 Web/Android 真实交换邀请。检查纯华为账号无需邮箱也能完成好友与邀请。
- 强退、重启、退出再登录：设备公钥/指纹保持一致；撤销本机后重新登记产生新身份，旧安全卡失效。卸载或安全存储丢失需要重新登记/核验。
- 鸿蒙设备作为发送者和接收者各测一次；变更安全卡一位、公钥不匹配、邀请到期时必须拒绝；不得退回明文传递 roomKey。
- 验证 HTTPS/Socket 重连、窄屏/分屏、键盘输入与复制安全卡，实际画笔/撤销/图片同步和返回时本地保存。
- 回传客户端与服务端 commit、设备/系统/SDK 版本、每步结果及脱敏录屏。不要录入 token、私钥或真实白板密钥。

## 可复跑的自动检查

```sh
flutter test --no-pub test/features/social
# 使用当前电脑提供的临时 fixture 账号、有效好友关系与 loopback 后端
flutter test --no-pub --dart-define=FLOWMUSE_SOCIAL_TEST_URL=http://127.0.0.1:18343 test/features/social/invitation_http_integration_test.dart
```

后一个测试真实走 Dart → HTTP API → PostgreSQL/Socket.IO，覆盖公钥登记、安全卡、加密邀请、解密、成员角色、joined 回报、新设备补发、卡片去重和撤销；只允许 loopback 地址。一般单元测试不自动启用此测试。密码互测工具和范围见 [阶段验证记录](2026-09-23-social-validation.md)。
