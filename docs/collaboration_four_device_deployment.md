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
        | Go 协作后端
        v
Windows 本机 PostgreSQL:45873 + MinIO:45911/45912
```

Linux 服务器只负责维护公网 IP 和请求转发；Go 后端、数据库、对象存储都运行在 Windows 开发机上。

## 1. 端口规划

| 设备 | 端口 | 用途 |
| --- | --- | --- |
| Linux 服务器 | `48217` | frp 控制连接端口 |
| Linux 服务器 | `48931` | 对外暴露 FlowMuse 协作服务 |
| Windows 开发机 | `48931` | Go 协作后端 |
| Windows 开发机 | `45873` | PostgreSQL |
| Windows 开发机 | `45911` | MinIO S3 API |
| Windows 开发机 | `45912` | MinIO 控制台 |

Linux 防火墙和云厂商安全组至少放行 `48217` 和 `48931`。

## 2. Windows 开发机准备存储服务

### 2.1 PostgreSQL

创建一个用于 FlowMuse 的数据库，例如：

```sql
CREATE DATABASE flowmuse;
CREATE USER flowmuse WITH PASSWORD 'flowmuse_dev_password';
GRANT ALL PRIVILEGES ON DATABASE flowmuse TO flowmuse;
```

后端使用的连接串格式：

```text
postgres://flowmuse:flowmuse_dev_password@127.0.0.1:45873/flowmuse?sslmode=disable
```

### 2.2 MinIO

在 Windows 启动 MinIO。示例：

```powershell
$env:MINIO_ROOT_USER="flowmuse"
$env:MINIO_ROOT_PASSWORD="flowmuse_dev_password"
minio.exe server D:\FlowMuseData\minio --address ":45911" --console-address ":45912"
```

打开 MinIO 控制台：

```text
http://127.0.0.1:45912
```

创建 bucket：

```text
flowmuse
```

## 3. Windows 启动 Go 协作后端

进入服务端目录：

```powershell
cd D:\Github\FlowMuse\2024-se-17\FlowMuse-Server
```

设置环境变量：

```powershell
$env:FLOWMUSE_ADDR=":48931"
$env:DATABASE_URL="postgres://flowmuse:flowmuse_dev_password@127.0.0.1:45873/flowmuse?sslmode=disable"
$env:FLOWMUSE_S3_ENDPOINT="127.0.0.1:45911"
$env:FLOWMUSE_S3_BUCKET="flowmuse"
$env:FLOWMUSE_S3_ACCESS_KEY_ID="flowmuse"
$env:FLOWMUSE_S3_SECRET_ACCESS_KEY="flowmuse_dev_password"
$env:FLOWMUSE_S3_USE_SSL="false"
$env:FLOWMUSE_ALLOWED_ORIGINS="*"
```

启动后端：

```powershell
go run .\cmd\flowmuse-collab-server
```

本机验证：

```powershell
Invoke-WebRequest -Uri "http://127.0.0.1:48931/health" -UseBasicParsing
```

期望响应内容：

```json
{"status":"ok"}
```

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

1. Windows 启动 PostgreSQL。
2. Windows 启动 MinIO。
3. Windows 启动 FlowMuse Go 后端。
4. Linux 启动 `frps`。
5. Windows 启动 `frpc`。
6. 两台平板浏览器分别打开 `http://8.133.4.116:48931/health`，确认可访问。
7. Android 平板安装或运行 `.env` 已配置公网地址的 FlowMuse 客户端。
8. 鸿蒙平板安装或运行同一份 `.env` 配置构建出的 FlowMuse 客户端。
9. Android 平板打开白板，点击右上角协作按钮，点击“创建房间”。
10. 复制菜单里显示的房间链接，或复制其中的 `roomId,roomKey`。
11. 鸿蒙平板打开白板，点击右上角协作按钮，在“加入房间”输入框粘贴完整链接、`#room=roomId,roomKey` 或 `roomId,roomKey`，点击“加入”。
12. Android 平板绘制矩形、文本或自由画。
13. 确认鸿蒙平板实时出现同样内容。
14. 鸿蒙平板移动光标、选择元素或绘制内容。
15. 确认 Android 平板能看到远端光标、协作者数量变化和远端内容。
16. 关闭鸿蒙客户端后重新加入同一房间，确认场景能从服务端恢复。

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
