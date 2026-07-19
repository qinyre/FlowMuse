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
cd ~/FlowMuse
git pull
cd FlowMuse-Server
sudo docker compose up -d --build
sudo docker compose ps
curl -i http://127.0.0.1:48931/health
```

## 配置说明

`.env` 由 `.env.example` 复制而来，目前用于配置：

- MyScript 手写识别密钥；
- 后端 AI 智能排版的 OpenAI 兼容接口密钥与模型。

客户端协作地址在应用侧配置为 `http://124.221.68.239:48931`，后端本身无需为此额外启动代理。

## 生产环境注意事项

- 云防火墙/安全组仅向客户端开放 `48931`；不要对公网开放 `5432`、`9000`、`9001`、`1025`、`8025`。
- `.env` 含密钥，不要提交到 Git 仓库或发送给他人。
- 当前 `docker-compose.yml` 的数据库、MinIO 密码和 CORS 设置是开发默认值；正式长期部署前应替换默认密码，并将 `FLOWMUSE_ALLOWED_ORIGINS` 改为实际 Web 域名。

测试SSH链接
