# 协作补同步拥堵修复

## Context

10 月 21 日已复现：迟到摘要导致数据已一致的两端误发整页；约 395KB 双向大包使实时帧 P95 从 33ms 升到 2186ms。用户要求修复后部署后端与正式 Web，平板未连接，本轮不安装。

## 实现范围

1. 保留既有 AES-GCM、Socket.IO ACK、元素级 LWW 与删除墓碑，不改存储 schema。
2. 在加密 SYNC_STATUS 的可选字段中交换元素版本摘要；发现差异后请求当前版本目录，只补对端缺失或较旧的元素。迟到摘要不再直接触发整页重发。
3. 使用既有 SCENE_UPDATE，按约 16KiB 的消息预算分批补偿与初始化；批次之间让出执行机会。单个超限元素保持完整，不能截断点或压感数据。
4. 为同一对端的自动补偿请求加冷却；旧端仍使用有频率限制的兼容补偿，不要求服务端解密，也不改变现有笔画格式。
5. 修改点集中于共享 CollaborationRepository、对应测试和接口文档。服务端继续转发密文，部署与 Web 来自同一已验证提交。

## 验证

- 先加入会在旧实现失败的迟到摘要回归测试。
- 验证真实漏收、删除墓碑、同版本不同 nonce、多人定向补偿、异常版本目录、旧端兼容和换房清理。
- 验证大历史场景只补缺失元素，强制补偿与初始化不会把普通多元素场景合成单个大包。
- Flutter 全量测试和 analyze；Go test ./... 与 go vet ./...；公网隔离房间验证版本修复与持续实时帧的相互影响。
- 部署保留旧镜像、Web 目录和 Nginx 配置；检查正式入口文件哈希和 API 健康。

## 交付边界

平板未连接，不宣称 Android/Web 真机连续书写已通过；旧 APK 不会因 Web 更新自动获得客户端修复。H10 责任人、人工审查人待项目团队指定，本轮保留代码、命令与测试证据供审查。

## 2026-10-22 验证结果

- 旧实现新增回归用例先失败，修复后通过；协作目录共 140 项通过（新增摘要、补偿、分包等测试所在文件共 11 项）。Flutter 全量 1825 项通过、5 项跳过；最终 `flutter analyze --no-pub` 无问题。
- Go `test ./...`、`vet ./...` 通过。服务端业务代码未修改，重新构建部署用于版本一致和可追溯。
- 公网隔离双端使用真实 Repository、Socket.IO 和加密存储：150 个元素共 406795 字节，漏收一项仅补发一个 2830 字节消息；强制双向补偿共 50 个批次，最大密文帧 16348 字节，确认重试为 0。
- 最终同轮实时预览延迟 P95：基线 47ms，单项补偿期间 98ms，双向全量分批期间 285ms（最大 349ms）。实时预览允许丢帧，不能将帧计数当作最终元素丢失率；这些数值不含真实平板输入或 Web 绘制，不能据此承诺实机体验。
- 证据位于本地忽略目录 `FlowMuse-App/build/repair-*.log`、`repair-public-e2e-receipt.json`。Chrome 单元测试未执行成功：Windows Flutter 测试资源路由对 CanvasKit 返回 404，提供本机同版本资源后仍未加载测试套件，已停止该尝试；不能计为通过。正式 Web 另做 release 构建和部署后加载检查。

## 正式发布与回退记录

- 应用和服务端构建提交：`c8504b4aba6ac176885d5805ec0286c526c80953`；分支 `fix/collaboration-fluidity` 已推送。以下记录提交只补文档，不改变已发布业务代码。
- 正式入口：`https://app.flowmuse.cloud/library`；两个实验开关均开启，分享源为正式域名。旧 `/wet-ink-v2/library` 返回 302 到 `/library`，避免混用旧测试包。
- Web 目录：`/var/www/flowmuse-app-releases/collaboration-repair-20261022-c8504b4`；公网 `main.dart.js` SHA256：`97a30c5cc642ef092701796c76c8265d25d096a261f36394ad723928a88cd8d1`，与本机构建相同，gzip 与 no-cache 生效。
- 后端镜像：`flowmuse-collab:repair-c8504b4`，镜像 ID `sha256:913548a59b63bffbba972e7c7c449d8358b5e2a6c7120b03fdecabfa13e35ad8`；只重建协作服务，运行环境、端口、挂载、网络与重启策略已逐项比对保留，健康接口 200、重启计数 0。数据库与文件存储未回退或清理。
- 部署后的公网双端与 11 项回归共 12 项测试通过。相同 406795 字节历史场景：单项补偿 2830 字节，50 个全量批次最大帧 16348 字节，重试 0。延迟 P95：基线 201ms（最大 307ms，含本轮瞬时波动）、单项补偿 27ms、双向分批补偿 181ms（最大 285ms）。与发布前的数值分别保留，不能把跨轮差异归因于服务端代码改动。
- 使用独立 Playwright 会话检查正式 Web：资料库截图正常，Flutter 已初始化，控制台错误 0。启动截图 `FlowMuse-App/build/repair-formal-web-startup.png`；完整回执 `FlowMuse-App/build/repair-deployment-receipt.json`。
- 后端部署文件位于 `/opt/flowmuse/releases/collaboration-repair-20261022-c8504b4/`。回退到发布前镜像使用同目录 `rollback.override.json`，与 `/opt/flowmuse/source/FlowMuse-Server/docker-compose.yml` 配合执行 `up -d --no-deps --no-build collab-server`。Nginx 发布前配置保存为 `/etc/nginx/sites-available/flowmuse-app.before-repair-20261022-c8504b4`，恢复时先检查配置再 reload。上一版和九月版镜像、Web 目录及 Git 分支均保留。
- 平板本轮未连接、未覆盖安装；旧客户端仍会走兼容补偿，单个超长元素也仍可能超过分包预算。Android/Web 真机连续书写、长笔画和多人压力体验尚未验证。
