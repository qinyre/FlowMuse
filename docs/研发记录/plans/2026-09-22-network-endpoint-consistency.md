# 生产网络配置与分享入口一致性修复

## 背景与目标

基线 `b92fece` 已把默认后端切到 `https://api.flowmuse.cloud`，但分享地址、邮件回跳和官网入口仍有旧 GitHub Pages / HTTP 配置。Web 当前使用 hash 路由，生成的房间和邮件链接却使用 path 路由；仅替换域名不能修复直接打开链接。

本次统一官网 `https://flowmuse.cloud`、Web `https://app.flowmuse.cloud`、API / WSS `https://api.flowmuse.cloud`。不改变协作协议、密钥格式、识别 provider 或数据存储，也不重构网络层。

## 实施批次

1. 客户端入口：修正随包/回退分享地址及官网入口，启用 Flutter SDK 的 PathUrlStrategy 并保留 room fragment；兼容已有 `/#/...` 书签与旧房间链接的粘贴解析。配置仍支持 dart-define、随包环境文件及局域网覆盖，处理空白值与末尾斜杠。补 macOS 出站网络 entitlement；核对 Android / OHOS 网络权限不误禁开发 HTTP。
2. 服务端与部署：修正 `.env.example`、Compose 和配置默认公开 Web URL，生产 CORS 明确列出实际来源并保留开发覆盖。现网仅更新公开 URL 等必要配置，不改模型密钥、不升级数据库/对象存储。官网仓库及现网按钮同步 HTTPS。
3. 回归与部署：跑配置、链接、路由、加密相关测试和 Flutter 全量测试/analyze；服务端 go test/vet；构建本地 CanvasKit Web release，备份后切换版本目录。在浏览器核对房间直达/刷新、旧 hash 入口、邮件页面、API CORS、WSS 和官网入口。

## 审计边界

- 账户、识别、快照、附件和 Socket.IO 继续复用 CollaborationConfig；不批量改第三方 HTTPS 地址、Excalidraw 格式中的 source 或历史证据。
- 私有容器间 HTTP / MinIO 内网地址与 Nginx loopback 上游保持不变，TLS 在 Nginx 终止。
- 旧 HTTP Web 入口保留给本地数据导出，暂不强制跳转/HSTS；不清理浏览器数据库。旧客户端需重新安装新构建才会获取新默认值。
- 真实账号邮件不发送、不改密码。验证回跳页面与配置不等于 SMTP 投递验证。macOS entitlement 在 Windows 只能静态核对，不能宣称已实机验证。

## 完成证据

实施后补充提交、自动化检查、部署版本和线上验证结果；回滚保留旧静态版本、Nginx 配置及服务端环境备份。

- 客户端：Flutter analyze 零问题；全量测试 1697 通过、5 跳过；Web release 构建成功（本地 CanvasKit，显式覆盖 API 和分享地址）。路径策略沿用 [Flutter SDK](https://api.flutter.dev/flutter/flutter_web_plugins/PathUrlStrategy-class.html)，`includeHash=true` 防止 room fragment 丢失，非 Web 走 SDK no-op。
- Go：`go test ./...`、`go vet ./...` 均通过。macOS 两份 entitlement 的 XML 出站权限静态断言通过，未宣称 macOS 实机验证。
- 额外修复：游客头像原站缺 CORS，改为固定 OpenMoji 15.1.0 的 jsDelivr HTTPS 地址；HTTP 检查确认 200 且支持 CORS，不下载/复制新素材。
- 全量扫描：业务代码无残留旧 GitHub Pages 生产地址或 IP/HTTP 服务地址；保留明确的迁移 CORS、局域网覆盖和容器内网 HTTP。现网数据库/MinIO/Mailpit 没有发布宿主公网端口，原 API 48931 继续兼容旧客户端。

## 现网实施与复核（2026-09-22）

- FlowMuse 分支 `fix/network-endpoint-consistency`：客户端 `98a9f10`、后端配置 `2e32d31`。官网仓库独立分支 `fix/https-app-links`：`1839adc`；三个应用入口切为 HTTPS，README 移除示例域名。此时均为本地提交，未推送或合并。
- Web 发布目录 `/var/www/flowmuse-app-releases/20260922-network-config`；上传包 SHA-256 `3b89f4d4974bdeba456aa40f094ee38c4fa6559641767d46f8a8e6699f1f6c35`。版本目录切换前核对上传哈希与现网配置未被并发修改。
- 回滚备份 `/opt/flowmuse/backups/network-config-20260922-PiEUiI`：原 Nginx、官网首页、服务端 `.env`、Compose；`server.env` 含密钥，只留服务器受限目录，不入库。压缩前配置另存 `nginx-app.before-gzip.conf`；原静态版本保留，未删除任何用户数据。
- 现网 `FLOWMUSE_PUBLIC_APP_URL` 和 Compose 回退均改为 `https://app.flowmuse.cloud`，只重建 collab-server 容器并验证 `/health` 200。未重建后端镜像（运行时显式环境配置生效）、未重启 PostgreSQL/MinIO/Mailpit，CORS 既有来源保持兼容。
- 真实浏览器：HTTPS secure context；跨域 health 200；JSON POST 预检可达 V3 handler，空载荷返回预期 400 `invalidSchema`，未调用模型；WSS 收到 Engine.IO opening 包；头像 CORS 可读 200；官网三个链接均为 HTTPS。
- 路由：重置密码页直达可见、验证邮箱页将无效测试 token 正确交给 API 拒绝；旧 `/#/settings?section=other` 到新 `/settings?section=other` 且官网入口正确。未发送真实邮件、未修改任何账号。
- 房间：使用独立空白加密测试场景，实际验证 path 直达、旧 hash 链接和刷新均完成客户端 `/join` 200，room fragment 不丢失。测试后结束房间，确认 `ended=true`、场景读取 410，并移除测试会话中的临时凭据；没有接触既有房间。该检查不等价于多设备完整协作回归。
- 静态压缩：原主脚本 10,256,443 字节、CanvasKit 5,687,008 字节均无 gzip。现网仅静态 `location /` 启用 gzip（代理配置不变）；实测传输分别为 2,301,677 / 2,176,546 字节，减少约 77.6% / 61.7%。确认 `Content-Encoding: gzip`、`Vary: Accept-Encoding`，解压后 SHA-256 与发布文件完全一致；普通浏览器页面仍正常。
- HTTP Web 入口仍返回 200，供旧本地数据导出。平板等已安装包未在本次重新安装；更新原生包后才能获取新的分享域名和客户端改动。macOS 未实机验证，SMTP 实际投递及模型识别效果不属于本次验证结果。
