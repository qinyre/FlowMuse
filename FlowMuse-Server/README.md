# FlowMuse 后端使用说明

本目录提供 FlowMuse 协作、账号、文件与手写识别相关的后端服务。服务通过 Docker Compose 运行。

## 运行环境

- Docker Engine 及 Docker Compose v2
- 生产入口由 Nginx 提供 HTTPS（TCP `443`）；TCP `80` 保留证书验证和旧 Web 入口。后端仍监听 `48931`，旧客户端兼容期间保留原 IP 入口。

## 首次启动

```bash
cd ~/FlowMuse/FlowMuse-Server
cp .env.example .env
sudo docker compose up -d --build
```

检查容器与健康接口：

```bash
sudo docker compose ps
curl -i http://127.0.0.1:48931/health
```

健康接口返回 `HTTP/1.1 200 OK` 与 `{"status":"ok"}` 表示服务已就绪。

## 日常操作

### 启动

```bash
cd ~/FlowMuse/FlowMuse-Server
sudo docker compose up -d
```

### 查看状态

```bash
sudo docker compose ps
```

### 查看日志

```bash
sudo docker compose logs -f collab-server
```

停止查看日志时按 `Ctrl+C`，不会停止服务。

### 停止服务

```bash
sudo docker compose stop
```

该命令保留容器和数据；下次执行 `sudo docker compose up -d` 即可恢复。

### 停止并移除容器

```bash
sudo docker compose down
```

默认不会删除 PostgreSQL 和 MinIO 的 Docker 数据卷。除非确认要清空所有后端数据，不要附加 `-v`。

## 更新部署

代码更新后执行：

```bash
cd ~/FlowMuse-new
git remote set-url origin git@github.com:qinyre/FlowMuse.git
git pull --ff-only
sudo docker compose up -d --build
sudo docker compose ps
curl -i http://127.0.0.1:48931/health
```

## 配置说明

`.env` 由 `.env.example` 复制而来，目前用于配置：

- MyScript 手写识别密钥；
- 后端 AI 智能排版的 OpenAI 兼容接口密钥与模型。

客户端生产地址为 `https://api.flowmuse.cloud`，Nginx 转发至 `http://127.0.0.1:48931`，Go 服务和 Docker 端口无需改成 HTTPS。客户端配置优先级为 `--dart-define=FLOWMUSE_COLLAB_SERVER_URL` > `assets/config/app.env` > 内置回退地址。

### Web 与 HTTPS 部署

- 官网：`https://flowmuse.cloud` / `https://www.flowmuse.cloud`，静态目录 `/var/www/flowmuse`。
- Web 客户端：`https://app.flowmuse.cloud`，Nginx 的 `root` 指向版本化目录 `/var/www/flowmuse-app-releases/<release>/`；原 `/var/www/flowmuse-app` 保留作旧版本回退。
- API：`https://api.flowmuse.cloud`；Socket.IO 使用同一主机的 WSS。
- `FLOWMUSE_ALLOWED_ORIGINS` 必须包含 `https://app.flowmuse.cloud`；迁移期同时保留 `http://app.flowmuse.cloud` 和已有来源。修改后仅重建应用容器使环境变量生效，不重建数据库、MinIO 或数据卷。
- Nginx 需保留 WebSocket Upgrade 转发；API 代理请求体上限至少为 V3 所需的 `16m`，识别读取超时不得短于后端 120 秒上限。
- 证书由 Certbot 管理，`certbot.timer` 自动续期；可执行 `sudo certbot renew --dry-run --no-random-sleep-on-renew` 验证。

Web 构建时显式覆盖旧的 HTTP 构建参数：

```bash
cd FlowMuse-App
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --dart-define=FLOWMUSE_COLLAB_SERVER_URL=https://api.flowmuse.cloud
```

`--no-web-resources-cdn` 让 CanvasKit 等渲染资源使用随包文件，避免 Google CDN 不可达导致白屏；保持现有不启用 Flutter 离线缓存的策略，静态入口返回 `Cache-Control: no-cache`，避免缓存旧的 HTTP 构建配置。

部署前备份已有静态目录，并在浏览器验证加载、API 和 WSS。仅修改服务器上的 `app.env` 不能覆盖旧 Web 包编译进去的 `--dart-define`。HTTP 与 HTTPS 的 IndexedDB/本地笔记不共享；保留原 HTTP 入口供用户导出备份，不配置强制跳转或 HSTS，待迁移完成后另行收口。

### V3 识别超时与耗时排查

`/api/ink/smart-layout/recognize/v3` 使用独立的 `FLOWMUSE_LAYOUT_V3_BASE_URL`、`FLOWMUSE_LAYOUT_V3_API_KEY`、`FLOWMUSE_LAYOUT_V3_MODEL` 配置，不改变旧识别链。`FLOWMUSE_LAYOUT_V3_TIMEOUT_SECONDS` 是整数秒，默认 `120`，现已接入生产 handler；显式设为 `60` 就会在 60 秒截止，调整后需重启服务。

配套客户端的单次上限为 130 秒，整次识别上限为 180 秒；后续请求取单次上限与剩余预算的较小值。超时不自动重做，快速网络失败仅在预算足够时重试一次。只更新服务器不能修复旧客户端写死的 45 秒截止，需要同时更新 App。增大时限是避免半途丢弃，不代表模型推理本身变快。

后端 `[recognition-v3]` 短日志记录 `stage / regions / units / request_bytes / prepare_ms / recognition_ms / ok`：`prepare_ms` 包括接收请求和入站校验；`recognition_ms` 包括模型调用及结果解析，不等同于纯推理时间，也不包含响应发送。客户端同前缀记录阶段耗时、请求规模、请求等待耗时和调用次数；不打印完整图片 Base64 或识别正文。真实端到端收益仍需在更新后的设备与服务器上实测。

V3 对已实测支持的 `doubao-seed-2-1-turbo-260628` 型号发送 `reasoning_effort: "minimal"`，减少转写/结构任务的额外思考；其他型号不发送该字段，沿用上游默认行为。不更换模型、不限制输出 token、不改变现有超时和校验，也不改 V1。合成小样本已验证参数可用，但速度和真实手写准确度仍需实机复测，不能将其视为消除所有超时的保证。

每次上游调用另有 `[recognition-v3] provider` 日志：`stage / effort / phase / http_status / reused / connect_ms / send_ms / wait_ms / receive_ms / total_ms / response_bytes / ok / timeout / canceled`。`connect_ms` 是获得首个连接的等待（含连接池、DNS、TCP、TLS）；`send_ms` 是获连接到首次成功发完请求；`wait_ms` 是发完到首个响应字节，含网络、上游排队和生成，**不能当成纯推理时间**；`receive_ms` 是首字节到读完响应体。未进入的阶段记 `-1`，进入后未完成则记截至失败时的耗时，`phase` 表示结束位置。`total_ms` 含传输与外层响应解析；`ok` 只表示 provider 调用成功，业务结果是否通过还需看下一条 handler 日志。不记录 URL、密钥、请求或响应正文。服务重启后，可用 `sudo docker logs --since 10m flowmuse-collab-server 2>&1 | grep -F '[recognition-v3]'` 查看。

## 生产环境注意事项

- 云防火墙/安全组开放生产 HTTPS 所需的 `80`、`443`；旧客户端仍需直连时保留 `48931`。不要对公网开放 `5432`、`9000`、`9001`、`1025`、`8025`。
- `.env` 含密钥，不要提交到 Git 仓库或发送给他人。
- 当前 `docker-compose.yml` 的数据库、MinIO 密码和 CORS 设置是开发默认值；正式长期部署前应替换默认密码，并将 `FLOWMUSE_ALLOWED_ORIGINS` 改为实际 Web 域名。

测试SSH链接
