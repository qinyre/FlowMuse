# FlowMuse 后端使用说明

本目录提供 FlowMuse 协作、账号、文件与手写识别相关的后端服务。服务通过 Docker Compose 运行。

## 运行环境

- Docker Engine 及 Docker Compose v2
- 对外只需为客户端放行 TCP `48931`

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

客户端协作地址在应用侧配置为 `http://124.221.68.239:48931`，后端本身无需为此额外启动代理。

### V3 识别超时与耗时排查

`/api/ink/smart-layout/recognize/v3` 使用独立的 `FLOWMUSE_LAYOUT_V3_BASE_URL`、`FLOWMUSE_LAYOUT_V3_API_KEY`、`FLOWMUSE_LAYOUT_V3_MODEL` 配置，不改变旧识别链。`FLOWMUSE_LAYOUT_V3_TIMEOUT_SECONDS` 是整数秒，默认 `120`，现已接入生产 handler；显式设为 `60` 就会在 60 秒截止，调整后需重启服务。

配套客户端的单次上限为 130 秒，整次识别上限为 180 秒；后续请求取单次上限与剩余预算的较小值。超时不自动重做，快速网络失败仅在预算足够时重试一次。只更新服务器不能修复旧客户端写死的 45 秒截止，需要同时更新 App。增大时限是避免半途丢弃，不代表模型推理本身变快。

后端 `[recognition-v3]` 短日志记录 `stage / regions / units / request_bytes / prepare_ms / recognition_ms / ok`：`prepare_ms` 包括接收请求和入站校验；`recognition_ms` 包括模型调用及结果解析，不等同于纯推理时间，也不包含响应发送。客户端同前缀记录阶段耗时、请求规模、请求等待耗时和调用次数；不打印完整图片 Base64 或识别正文。真实端到端收益仍需在更新后的设备与服务器上实测。

## 生产环境注意事项

- 云防火墙/安全组仅向客户端开放 `48931`；不要对公网开放 `5432`、`9000`、`9001`、`1025`、`8025`。
- `.env` 含密钥，不要提交到 Git 仓库或发送给他人。
- 当前 `docker-compose.yml` 的数据库、MinIO 密码和 CORS 设置是开发默认值；正式长期部署前应替换默认密码，并将 `FLOWMUSE_ALLOWED_ORIGINS` 改为实际 Web 域名。

测试SSH链接
