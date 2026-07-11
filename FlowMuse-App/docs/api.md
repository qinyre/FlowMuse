# 接口说明

后端服务地址从配置来:`--dart-define=FLOWMUSE_COLLAB_SERVER_URL` > `.env` > 默认值 `http://8.133.4.116:48931`。

## 账户认证

所有接口前缀 `/api/auth`,JSON body,需要登录的带 `Authorization: Bearer <token>`,超时 20 秒。

| 方法 | 路径 | 鉴权 | 说明 |
|------|------|------|------|
| POST | `/register` | 否 | body `{email, password, displayName}`,返回 `{user}` |
| POST | `/login` | 否 | body `{email, password}`,返回 `{token, user}` |
| POST | `/verify-email` | 否 | body `{token}`,返回 `{token, user}` |
| POST | `/resend-verification` | 否 | body `{email}` |
| GET | `/me` | 是 | 返回 `{user}`;401/403 时客户端清 token |
| PATCH | `/me` | 是 | body `{displayName}` |
| POST | `/me/avatar` | 是 | **原始字节**,Content-Type 是图片 mimeType,不是 JSON |
| POST | `/change-password` | 是 | body `{oldPassword, newPassword}`,成功后清 token |
| POST | `/request-password-reset` | 否 | body `{email}` |
| POST | `/reset-password` | 否 | body `{token, newPassword}`,成功后清 token |
| POST | `/logout` | 是 | 空 body,无论响应都清 token |

`user` 对象:`{id, email, displayName, avatarUrl, registeredAt, emailVerified, emailVerifiedAt, updatedAt}`。时间字段是毫秒时间戳。`avatarUrl` 不是 http 开头时客户端会拼成绝对地址。

token 存在 `flutter_secure_storage`,key `flowmuse.auth.token`。

## 协作房间 REST

鉴权同上。快照接口 15 秒超时,文件接口 20 秒。

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/rooms` | 创建房间,body `{roomId, ownerKeyHash}` |
| POST | `/api/rooms/{roomId}/scene` | 创建加密快照,body `{sceneVersion, sceneHash, ownerKeyHash, encryptedBuffer, iv}`(base64) |
| GET | `/api/rooms/{roomId}/scene` | 取快照,返回同上结构 |
| PUT | `/api/rooms/{roomId}/scene` | 存快照,带乐观锁 `{baseSceneVersion, baseSceneHash, ...}`,冲突返回 **409** |
| GET | `/api/rooms/{roomId}/access` | 房间元信息 |
| POST | `/api/rooms/{roomId}/join` | 加入 |
| POST | `/api/rooms/{roomId}/end` | 结束(仅房主),body `{ownerKey}`,401/403 鉴权失败 |
| PUT | `/api/rooms/{roomId}/files/{fileId}` | 上传图片,`application/octet-stream`,单文件 10MB |
| GET | `/api/rooms/{roomId}/files/{fileId}` | 下载图片 |

HTTP 状态码:410 房间已结束,404 不存在,409 版本冲突。

## 协作 Socket.IO 协议

websocket 优先,polling 降级,自动重连。已登录用户用 `Authorization` header + auth token;游客用 query 带 guestName / guestAvatarUrl。

客户端发:

| 事件 | 载荷 |
|------|------|
| `join-room` | roomId(重连自动重发) |
| `server-broadcast` | `[roomId, {encryptedBuffer, iv}]` 持久化消息 |
| `server-volatile-broadcast` | `[roomId, {encryptedBuffer, iv}]` 易失(光标/在线状态,可丢) |
| `leave-room` | roomId |
| `end-room` | `{roomId, ownerKey}` |

客户端收:`init-room`、`first-in-room`、`new-user`、`room-user-change`、`room-error`、`room-ended`、`client-broadcast`(其他人的协作消息)。

业务消息解密后是 JSON `{type, payload}`:

| type | 用途 |
|------|------|
| `SCENE_INIT` | 全量场景(新成员加入时) |
| `SCENE_UPDATE` | 增量元素 |
| `MOUSE_LOCATION` | 光标和选区(易失) |
| `IDLE_STATUS` | 在线状态(易失) |
| `USER_VISIBLE_SCENE_BOUNDS` | 可视区域(易失) |

`elements` 是 Excalidraw 元素 JSON 数组。

## 手写识别

POST `{serverUrl}/api/ink/recognize`,body 是 `{sessionId, hint:"auto", strokes:[{id, points:[{x,y,t?}]}], bounds:{x,y,width,height}}`。返回 `{elements:[{type, text?, latex?, x, y, width, height, points?}]}`。鸿蒙用 NativeHttpClient(8s 连接 / 15s 读取),其他平台用标准 http。无 token 可匿名调用。

## 数据层接口

这层不逐个列了,代码里有完整定义。几个要点:

`LibraryRepository`(`features/library/repositories/library_repository.dart`)是资料库的接口,SQLite 实现。`loadIndex()` 一次性读全部,其余是 CRUD。对应的 `LibraryIndexNotifier`(provider `libraryIndexProvider`)是 AsyncNotifier,每个写方法调完 repository 会 `refresh()`。

`WhiteboardSceneRepository` 读写 `note_scenes` 表,内容是 Excalidraw JSON 字符串。

`CollaborationRepository` 是协作层的外观,组合了 transport + 加密 + 场景存储 + reconciler。对外暴露 `startNewRoom` / `joinRoom` / `broadcastScene` / `stopCollaboration` / `endRoom`,以及一堆 Stream(消息、成员变化、连接状态、错误)。

`LocalSettingsRepository` 是 `local_settings` 表的 key-value 包装,`readString` / `writeString` / `readBool` / `writeBool`。`RecentCoversRepository` 复用同一张表,key 形如 `recent_covers_notebooks`,value 是 JSON 数组。

## 通用约定

时间是毫秒时间戳。ID 生成:笔记本 `notebook-{uuid}`、标签 `tag-{uuid}`、房间 10 字节随机 hex、房间密钥 base64url 16 字节、PDF 图片 fileId `pdf-{sha1[:12]}`。颜色在 SQLite 里是 ARGB32 整数,在 JSON 里是 `#RRGGBB`。枚举存 `.name` 字符串。HTTP 非 2xx 抛 `StateError`。
