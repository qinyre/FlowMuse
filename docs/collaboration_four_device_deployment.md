# FlowMuse 四设备协作部署指南

本文档面向以下测试设备组合：

- 一台有公网 IP 的低性能 Linux 服务器
- 一台 Windows 开发机
- 一台 Android 平板
- 一台鸿蒙平板

目标拓扑：

```text
Android 平板 / 鸿蒙平板
        |
        | http://8.133.4.116:48931
        v
Linux 服务器公网入口
        |
        | frp TCP 转发
        v
Windows 开发机 127.0.0.1:48931
        |
        | Docker Compose
        v
Go 协作后端 + PostgreSQL:5432 + MinIO:9000/9001
```

Linux 服务器只负责维护公网 IP 和请求转发；Go 后端、数据库、对象存储都运行在 Windows 开发机上。

## 1. 端口规划

| 设备 | 端口 | 用途 |
| --- | --- | --- |
| Linux 服务器 | `48217` | frp 控制连接端口 |
| Linux 服务器 | `48931` | 对外暴露 FlowMuse 协作服务 |
| Windows 开发机 | `48931` | Go 协作后端 |
| Windows 开发机 | `5432` | PostgreSQL |
| Windows 开发机 | `9000` | MinIO S3 API |
| Windows 开发机 | `9001` | MinIO 控制台 |

Linux 防火墙和云厂商安全组至少放行 `48217` 和 `48931`。

## 2. Windows 开发机一站式部署后端

进入服务端目录：

```powershell
cd D:\Github\FlowMuse\2024-se-17\FlowMuse-Server
```

创建 `Dockerfile`：

```powershell
@'
FROM golang:1.25-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /out/flowmuse-collab-server ./cmd/flowmuse-collab-server

FROM alpine:3.22
WORKDIR /app
COPY --from=builder /out/flowmuse-collab-server /app/flowmuse-collab-server
EXPOSE 48931
ENTRYPOINT ["/app/flowmuse-collab-server"]
'@ | Set-Content -LiteralPath .\Dockerfile -Encoding UTF8
```

创建 `docker-compose.yml`：

```powershell
@'
services:
  postgres:
    image: postgres:17-alpine
    container_name: flowmuse-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: flowmuse
      POSTGRES_USER: flowmuse
      POSTGRES_PASSWORD: flowmuse_dev_password
    ports:
      - "5432:5432"
    volumes:
      - flowmuse_postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U flowmuse -d flowmuse"]
      interval: 5s
      timeout: 3s
      retries: 20

  minio:
    image: minio/minio:latest
    container_name: flowmuse-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: flowmuse
      MINIO_ROOT_PASSWORD: flowmuse_dev_password
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - flowmuse_minio_data:/data

  minio-init:
    image: minio/mc:latest
    container_name: flowmuse-minio-init
    depends_on:
      - minio
    entrypoint: >
      /bin/sh -c "
      until mc alias set local http://minio:9000 flowmuse flowmuse_dev_password; do sleep 2; done &&
      mc mb --ignore-existing local/flowmuse
      "
    restart: "no"

  collab-server:
    build:
      context: .
    container_name: flowmuse-collab-server
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      minio-init:
        condition: service_completed_successfully
    environment:
      FLOWMUSE_ADDR: ":48931"
      DATABASE_URL: "postgres://flowmuse:flowmuse_dev_password@postgres:5432/flowmuse?sslmode=disable"
      FLOWMUSE_S3_ENDPOINT: "minio:9000"
      FLOWMUSE_S3_BUCKET: "flowmuse"
      FLOWMUSE_S3_ACCESS_KEY_ID: "flowmuse"
      FLOWMUSE_S3_SECRET_ACCESS_KEY: "flowmuse_dev_password"
      FLOWMUSE_S3_USE_SSL: "false"
      FLOWMUSE_ALLOWED_ORIGINS: "*"
    ports:
      - "48931:48931"

volumes:
  flowmuse_postgres_data:
  flowmuse_minio_data:
'@ | Set-Content -LiteralPath .\docker-compose.yml -Encoding UTF8
```

一站式启动 PostgreSQL、MinIO 和 FlowMuse Go 协作后端：

```powershell
docker compose up -d --build
```

查看容器状态：

```powershell
docker compose ps
```

查看后端日志：

```powershell
docker compose logs -f collab-server
```

本机验证：

```powershell
Invoke-WebRequest -Uri "http://127.0.0.1:48931/health" -UseBasicParsing
```

期望响应内容：

```json
{"status":"ok"}
```

打开 MinIO 控制台：

```text
http://127.0.0.1:9001
```

登录信息：

```text
用户名：flowmuse
密码：flowmuse_dev_password
```

Docker Compose 已通过 `minio-init` 自动创建 bucket：

```text
flowmuse
```

需要停止整套后端时执行：

```powershell
docker compose down
```

需要清空 PostgreSQL 和 MinIO 数据时执行：

```powershell
docker compose down -v
```

## 3. Windows 后端端口说明

Compose 内部服务互联使用容器服务名：

- Go 后端访问 PostgreSQL：`postgres:5432`
- Go 后端访问 MinIO：`minio:9000`
- Windows 主机访问 PostgreSQL：`127.0.0.1:5432`
- Windows 主机访问 MinIO S3 API：`127.0.0.1:9000`
- Windows 主机访问 MinIO 控制台：`http://127.0.0.1:9001`
- Windows 主机访问 FlowMuse 后端：`http://127.0.0.1:48931`

## 4. Linux 服务器配置公网转发

推荐使用 frp。Linux 服务器运行 `frps`，Windows 开发机运行 `frpc`。

### 4.1 Linux 服务器 frps

创建 `frps.toml`：

```toml
bindPort = 48217
```

启动：

```bash
./frps -c ./frps.toml
```

确认 Linux 服务器放行：

```bash
sudo ufw allow 48217/tcp
sudo ufw allow 48931/tcp
```

如果服务器使用云厂商安全组，也要在安全组里放行 `48217/tcp` 和 `48931/tcp`。

### 4.2 Windows 开发机 frpc

创建 `frpc.toml`：

```toml
serverAddr = "8.133.4.116"
serverPort = 48217

[[proxies]]
name = "flowmuse-collab"
type = "tcp"
localIP = "127.0.0.1"
localPort = 48931
remotePort = 48931
```

启动：

```powershell
.\frpc.exe -c .\frpc.toml
```

公网验证：

```powershell
Invoke-WebRequest -Uri "http://8.133.4.116:48931/health" -UseBasicParsing
```

Android 平板和鸿蒙平板也应能在浏览器打开：

```text
http://8.133.4.116:48931/health
```

看到 `{"status":"ok"}` 后再继续客户端测试。

## 5. 构建或运行客户端

客户端协作服务地址由 `FlowMuse-App/.env` 中的 `FLOWMUSE_COLLAB_SERVER_URL` 指定。移动设备不能使用默认的 `127.0.0.1`，必须在构建前把 `.env` 改成 Linux 公网地址。

编辑：

```text
FlowMuse-App/.env
```

直接写入配置：

```powershell
Set-Content -LiteralPath "D:\Github\FlowMuse\2024-se-17\FlowMuse-App\.env" -Value "FLOWMUSE_COLLAB_SERVER_URL=http://8.133.4.116:48931"
```

写入后的内容：

```dotenv
FLOWMUSE_COLLAB_SERVER_URL=http://8.133.4.116:48931
```

`.env` 已作为 Flutter asset 打进安装包；正常构建即可，不需要传 `--dart-define` 或其他构建参数。

### 5.1 Android 平板

在 `FlowMuse-App` 目录运行：

```powershell
cd D:\Github\FlowMuse\2024-se-17\FlowMuse-App
```

运行到已连接的 Android 平板：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" run
```

构建 debug APK：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" build apk --debug
```

产物通常位于：

```text
build\app\outputs\flutter-apk\app-debug.apk
```

### 5.2 鸿蒙平板

同样在 `FlowMuse-App` 目录执行 Flutter OHOS 构建或运行命令，并传入同一个公网地址：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" run
```

如果使用 DevEco Studio 安装鸿蒙包，也要确保安装包使用的是修改 `.env` 后重新构建的客户端。

两个平板必须使用同一个 `.env` 配置构建出来的客户端。

## 6. 明文 HTTP 注意事项

当前测试地址是：

```text
http://8.133.4.116:48931
```

Android 9 及以上可能限制明文 HTTP。测试阶段如果无法连接，请检查 Android manifest 是否允许 cleartext traffic。

鸿蒙侧也需要确认应用具备网络访问权限，并允许访问该 HTTP 地址。

长期方案建议在 Linux 上用 Nginx 或 Caddy 提供 HTTPS，再反向代理到 `127.0.0.1:48931` 或 frp 暴露端口。当前阶段为了快速验证协作能力，可以先使用 HTTP 公网 IP。

## 7. 实际协作测试流程

1. Windows 在 `FlowMuse-Server` 目录执行 `docker compose up -d --build`。
2. Windows 执行 `Invoke-WebRequest -Uri "http://127.0.0.1:48931/health" -UseBasicParsing`，确认本机后端可访问。
3. Linux 启动 `frps`。
4. Windows 启动 `frpc`。
5. 两台平板浏览器分别打开 `http://8.133.4.116:48931/health`，确认可访问。
6. Android 平板安装或运行 `.env` 已配置公网地址的 FlowMuse 客户端。
7. 鸿蒙平板安装或运行同一份 `.env` 配置构建出的 FlowMuse 客户端。
8. Android 平板打开白板，点击右上角协作按钮，点击“创建房间”。
9. 复制菜单里显示的房间链接，或复制其中的 `roomId,roomKey`。
10. 鸿蒙平板打开白板，点击右上角协作按钮，在“加入房间”输入框粘贴完整链接、`#room=roomId,roomKey` 或 `roomId,roomKey`，点击“加入”。
11. Android 平板绘制矩形、文本或自由画。
12. 确认鸿蒙平板实时出现同样内容。
13. 鸿蒙平板移动光标、选择元素或绘制内容。
14. 确认 Android 平板能看到远端光标、协作者数量变化和远端内容。
15. 关闭鸿蒙客户端后重新加入同一房间，确认场景能从服务端恢复。

## 8. 故障排查

### 8.1 `/health` 本机可访问，公网不可访问

优先检查：

- Linux 防火墙是否放行 `48931/tcp`
- 云服务器安全组是否放行 `48931/tcp`
- `frps` 是否正在运行
- `frpc` 是否连接成功
- `frpc.toml` 的 `localPort` 是否是 `48931`

### 8.2 公网 `/health` 可访问，客户端无法创建房间

优先检查：

- `FlowMuse-App/.env` 是否已经改成 `FLOWMUSE_COLLAB_SERVER_URL=http://8.133.4.116:48931`
- 修改 `.env` 后是否重新构建并安装了客户端
- 移动系统是否拦截明文 HTTP
- Go 后端日志是否有 Socket.IO 连接错误
- frp 是否支持并稳定转发长连接

### 8.3 能创建房间，但另一台设备加入失败

优先检查：

- 是否粘贴了完整房间信息，必须包含 `roomId` 和 `roomKey`
- 可接受格式为完整链接、`#room=roomId,roomKey`、`roomId,roomKey`
- 两台设备是否连接到同一个公网服务地址
- 房间链接中的 `roomKey` 长度是否完整

### 8.4 能加入房间，但画面不同步

优先检查：

- Windows 后端日志是否持续运行，没有崩溃
- PostgreSQL 是否可写
- MinIO bucket 是否存在且凭据正确
- 两台客户端是否都是最新构建
- 是否误用旧客户端，旧客户端没有“加入房间”输入框

### 8.5 图片同步异常

图片文件走 MinIO。优先检查：

- `FLOWMUSE_S3_ENDPOINT`
- `FLOWMUSE_S3_BUCKET`
- `FLOWMUSE_S3_ACCESS_KEY_ID`
- `FLOWMUSE_S3_SECRET_ACCESS_KEY`
- `FLOWMUSE_S3_USE_SSL=false`
- `docker compose ps` 中 `minio-init` 是否已经成功退出

## 9. 当前测试结论标准

一次有效的四设备协作验收应同时满足：

- 两台平板都能访问公网 `/health`
- Android 平板能创建房间
- 鸿蒙平板能通过输入框加入同一房间
- 任一平板创建的新元素能出现在另一台平板
- 协作者数量能变化
- 远端光标或选择状态能显示
- 断开后重进同一房间能恢复已有场景

满足以上条件，即可认为当前公网转发架构下的 FlowMuse 实际协作链路可用。
