# 好友与协作邀请上线记录

2026-09-23，用户明确要求「部署然后推送并 merge」。本记录描述已执行的 Web/API 发布；鸿蒙与实体双端验收继续由用户/队员完成，未声称外部安全审计或生产回退演练通过。

## 版本与范围

- 实现提交：`7c6f0d7b93027524ef52c16e44ae135456953e6c`，PR [#51](https://github.com/qinyre/FlowMuse/pull/51)。后续文档提交不改变已部署的应用代码。
- 发布标识：`social-20260923-7c6f0d7`；2026-09-23 19:32（Asia/Shanghai）完成后端与 Web 切换。
- Web：[好友与消息](https://app.flowmuse.cloud/social)；API：`https://api.flowmuse.cloud`。
- 生产开启 `FLOWMUSE_SOCIAL_ENABLED=true` 与 `FLOWMUSE_SOCIAL_INVITATIONS_ENABLED=true`。代码默认值仍为 false；配置比较确认其他设置未变，邮箱、华为登录和现有密钥继续沿用。
- 原生包未发布；此前提供的 Android debug 包指向 loopback 测试环境，不能用它访问生产。鸿蒙队员从本次代码构建，API/分享地址使用上述正式域名。

## 发布操作与备份

1. 保存原 `.env`、生产 Compose、Nginx 配置及服务器源码，执行 PostgreSQL custom-format 全库备份，并用 `pg_restore --list` 检查备份可读取。备份在服务器 `/opt/flowmuse/backups/social-20260923-7c6f0d7/`，目录仅管理员可读，未下载或提交数据库/凭据。
2. 保留旧镜像标签 `flowmuse-server-collab-server:before-social-20260923-7c6f0d7`，对应 image `30d7f531d3ac`；原 Web 目录 `huawei-login-20260923-055108` 保留。
3. 使用 Go 1.25.6 构建 Linux amd64 静态二进制，在现有 Alpine 3.22 运行镜像中替换可执行文件；新镜像 `flowmuse-server-collab-server:social-20260923-7c6f0d7`，image `39910dcfa381`，revision label 指向实现提交。仅重建应用容器，未重建数据库/MinIO 或数据卷。
4. 幂等迁移新增好友/私聊/设备/信封表并扩展邀请字段；确认六张社交表及 `room_invites.request_hash` 存在。发布前后用户与会话数量相同，未植入临时测试账号。
5. Web 使用生产 API/分享域名重新构建，保留本地 CanvasKit 资源和禁用离线缓存设置。上传至 `/var/www/flowmuse-app-releases/social-20260923-7c6f0d7/`，通过 `nginx -t` 后切换 root 并 reload；保留原 HTTP/HTTPS 与代理设置。

## 验证证据

- 发布前实现提交的 push / pull_request 两次 [Quality](https://github.com/qinyre/FlowMuse/actions/runs/35853645887) 均成功；本机完整测试与真实后端邀请闭环见 [阶段验证记录](2026-09-23-social-validation.md)。
- `https://api.flowmuse.cloud/health` 返回 200 / `status=ok`；正式 Web Origin 得到正确 CORS 响应。
- 未登录请求 `/api/social/me` 返回 401，证明社交接口启用且鉴权仍有效；数据库迁移与两个实际运行环境开关已单独核对。
- `/social` 与 `/social/invitations/:id` 返回 Web 入口 200，支持刷新/直达；入口缓存策略为 `no-cache`。
- 经公网 HTTPS 下载的 `main.dart.js` 与构建产物 SHA-256 一致：`b68efe7b2be326c25692eabab90d9af2c56c6ff31f27047d2abfa7c63bbbd061`。
- 正式浏览器保留原账号登录，显示好友码、设备安全入口、好友与消息页面，连接状态为「消息已连接」，证明线上账号读取与实时消息握手正常。未向其他账号发送消息或邀请。
- 应用容器无重启循环，启动日志正常。未在生产执行双账号破坏性用例、修改密码或发送测试邮件。

## 回退

快速关闭社交功能：在受控 `.env` 设置 `FLOWMUSE_SOCIAL_ENABLED=false` 后，仅重新创建应用容器；也可仅关闭 `FLOWMUSE_SOCIAL_INVITATIONS_ENABLED`。

完整应用回退使用上述旧镜像标签与保存的配置，将 Nginx root 恢复为原 Web 目录并检查/reload。保留新增表、列及用户新消息，不自动恢复数据库覆盖新写入；不要退回不兼容纯华为账号的更早版本。部署脚本包含失败时恢复原应用与 Web 配置的路径，但本次部署成功，没有触发或实际演练生产回退。
