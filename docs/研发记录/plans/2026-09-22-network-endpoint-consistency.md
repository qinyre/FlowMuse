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
