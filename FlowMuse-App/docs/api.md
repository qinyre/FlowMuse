# FlowMuse 接口设计文档

> 版本：对应代码提交 `bcce1f9`
> 本文档覆盖三类接口：**后端 HTTP/Socket.IO 接口**、**应用内 Riverpod Provider / Repository 接口**、**编辑器内核对外接口**。

---

## 目录

1. [后端服务接口](#1-后端服务接口)
   - 1.1 [账户认证 API](#11-账户认证-api)
   - 1.2 [协作房间 REST API](#12-协作房间-rest-api)
   - 1.3 [协作房间 Socket.IO 实时协议](#13-协作房间-socketio-实时协议)
   - 1.4 [手写识别 API](#14-手写识别-api)
2. [应用内 Repository 接口](#2-应用内-repository-接口)
   - 2.1 [LibraryRepository](#21-libraryrepository)
   - 2.2 [WhiteboardSceneRepository](#22-whiteboardscenerepository)
   - 2.3 [CollaborationRepository](#23-collaborationrepository)
   - 2.4 [AccountRepository](#24-accountrepository)
   - 2.5 [本地存储 Repository](#25-本地存储-repository)
3. [Riverpod Provider 清单](#3-riverpod-provider-清单)
4. [编辑器内核对外接口](#4-编辑器内核对外接口)
5. [通用约定](#5-通用约定)

---

## 1. 后端服务接口

### 1.0 服务地址与配置

后端服务地址由 `CollaborationConfig.fromEnvironment`（`lib/features/whiteboard/collaboration/collaboration_config.dart`）决定，优先级：

```
--dart-define=FLOWMUSE_COLLAB_SERVER_URL
  > .env 文件中的 FLOWMUSE_COLLAB_SERVER_URL
    > 硬编码默认值 http://8.133.4.116:48931
```

分享来源（`FLOWMUSE_SHARE_ORIGIN`）同样支持 dart-define / dotenv 配置。

### 1.1 账户认证 API

> 文件：`lib/features/account/repositories/account_repository.dart`
> 所有路径前缀：`/api/auth`
> Content-Type：`application/json`（头像上传除外）
> 鉴权：`Authorization: Bearer <token>`（标注"是"的接口）
> 统一超时：20 秒（`_requestTimeout`）

#### POST `/api/auth/register` — 注册

| 项 | 值 |
|----|----|
| 鉴权 | 否 |
| 请求体 | `{ "email": string, "password": string, "displayName": string }` |
| 响应体 | `{ "user": AccountUser }` |
| Repository 方法 | `register(email, password, displayName)` |

#### POST `/api/auth/verify-email` — 邮箱验证

| 项 | 值 |
|----|----|
| 鉴权 | 否 |
| 请求体 | `{ "token": string }` |
| 响应体 | `{ "token": string, "user": AccountUser }`（AuthSession） |
| 副作用 | 成功后写入 token 到 secure storage |
| Repository 方法 | `verifyEmail(token)` |

#### POST `/api/auth/resend-verification` — 重发验证邮件

| 项 | 值 |
|----|----|
| 鉴权 | 否 |
| 请求体 | `{ "email": string }` |
| 响应体 | 仅状态码（200-299 视为成功） |
| Repository 方法 | `resendVerification(email)` |

#### POST `/api/auth/login` — 登录

| 项 | 值 |
|----|----|
| 鉴权 | 否 |
| 请求体 | `{ "email": string, "password": string }` |
| 响应体 | `{ "token": string, "user": AccountUser }`（AuthSession） |
| 副作用 | 成功后写入 token |
| Repository 方法 | `login(email, password)` |

#### GET `/api/auth/me` — 获取当前用户

| 项 | 值 |
|----|----|
| 鉴权 | 是 |
| 请求体 | 无 |
| 响应体 | `{ "user": AccountUser }` |
| 特殊处理 | 401/403 时清 token 并返回 null；其他非 2xx 抛 `StateError` |
| Repository 方法 | `loadCurrentUser()` |

#### PATCH `/api/auth/me` — 更新资料

| 项 | 值 |
|----|----|
| 鉴权 | 是 |
| 请求体 | `{ "displayName": string }` |
| 响应体 | `{ "user": AccountUser }` |
| Repository 方法 | `updateProfile(displayName)` |

#### POST `/api/auth/me/avatar` — 上传头像

| 项 | 值 |
|----|----|
| 鉴权 | 是 |
| Content-Type | `<mimeType>`（如 `image/png`、`image/jpeg`、`image/webp`、`image/gif`） |
| 请求体 | 原始二进制字节（**非 JSON**） |
| 请求头 | 含 `Content-Length` |
| 响应体 | `{ "user": AccountUser }` |
| Repository 方法 | `uploadAvatar(bytes, mimeType)` |

#### POST `/api/auth/change-password` — 修改密码

| 项 | 值 |
|----|----|
| 鉴权 | 是 |
| 请求体 | `{ "oldPassword": string, "newPassword": string }` |
| 响应体 | 仅状态码 |
| 副作用 | 成功后清 token（强制重新登录） |
| Repository 方法 | `changePassword(oldPassword, newPassword)` |

#### POST `/api/auth/request-password-reset` — 请求重置密码

| 项 | 值 |
|----|----|
| 鉴权 | 否 |
| 请求体 | `{ "email": string }` |
| 响应体 | 仅状态码 |
| Repository 方法 | `requestPasswordReset(email)` |

#### POST `/api/auth/reset-password` — 重置密码

| 项 | 值 |
|----|----|
| 鉴权 | 否 |
| 请求体 | `{ "token": string, "newPassword": string }` |
| 响应体 | 仅状态码 |
| 副作用 | 成功后清 token |
| Repository 方法 | `resetPassword(token, newPassword)` |

#### POST `/api/auth/logout` — 登出

| 项 | 值 |
|----|----|
| 鉴权 | 是 |
| 请求体 | 空 JSON `{}` |
| 响应体 | 仅状态码 |
| 副作用 | 无论响应如何都清本地 token |
| Repository 方法 | `logout()` |

#### AccountUser 对象结构

```jsonc
{
  "id": "string",
  "email": "user@example.com",
  "displayName": "用户昵称",
  "avatarUrl": "/path/avatar.svg",   // 默认 ""
  "registeredAt": 1700000000000,      // 毫秒时间戳，默认 0
  "emailVerified": true,
  "emailVerifiedAt": 1700000000000,   // 默认 0
  "updatedAt": 1700000000000          // 默认 0
}
```

`avatarUrl` 若非 `http` 开头，客户端会拼接成 `{serverUri}{avatarUrl}`。

---

### 1.2 协作房间 REST API

> 文件：`lib/features/whiteboard/collaboration/services/encrypted_scene_store.dart`、`collaboration_file_store.dart`
> 鉴权：`Authorization: Bearer <token>`
> 快照接口超时 15 秒；文件接口超时 20 秒

#### POST `/api/rooms` — 创建房间元数据

| 项 | 值 |
|----|----|
| 请求体 | `{ "roomId": string, "ownerKeyHash": string }` |
| 响应 | 2xx 成功 |

#### POST `/api/rooms/{roomId}/scene` — 创建加密场景快照

| 项 | 值 |
|----|----|
| 请求体 | `{ "sceneVersion": int, "sceneHash": string, "ownerKeyHash": string, "encryptedBuffer": base64, "iv": base64 }` |
| 响应 | 2xx 成功 |

#### GET `/api/rooms/{roomId}/scene` — 加载场景快照

| 项 | 值 |
|----|----|
| 响应体 | `{ "encryptedBuffer": base64, "iv": base64, "sceneVersion": int, "sceneHash": string }` |
| 客户端动作 | 用 roomKey 解密 |

#### PUT `/api/rooms/{roomId}/scene` — 保存场景（带乐观锁）

| 项 | 值 |
|----|----|
| 请求体 | `{ "baseSceneVersion": int, "baseSceneHash": string, "ownerKeyHash": string, "encryptedBuffer": base64, "iv": base64 }` |
| 冲突响应 | HTTP 409（版本冲突，客户端拉远端 reconcile 后重试） |

#### GET `/api/rooms/{roomId}/access` — 房间访问信息

| 项 | 值 |
|----|----|
| 响应体 | 房间 metadata（含 `memberRole` 等） |

#### POST `/api/rooms/{roomId}/join` — 加入房间

| 项 | 值 |
|----|----|
| 响应 | 服务端记录成员 |

#### POST `/api/rooms/{roomId}/end` — 结束房间（仅房主）

| 项 | 值 |
|----|----|
| 请求体 | `{ "ownerKey": string }` |
| 错误响应 | 401/403 鉴权失败；410 房间已结束；404 房间不存在 |

#### PUT `/api/rooms/{roomId}/files/{fileId}` — 上传协作图片

| 项 | 值 |
|----|----|
| Content-Type | `application/octet-stream` |
| 请求体 | `ExcalidrawBinaryCodec.compressData` 编码的二进制（含加密 dataURL + metadata） |
| 限制 | 单文件 10MB |
| 超时 | 20 秒 |

#### GET `/api/rooms/{roomId}/files/{fileId}` — 下载协作图片

| 项 | 值 |
|----|----|
| 响应体 | 编码二进制，客户端 `decompressData` 解出 dataURL + mimeType → `ImageFile` |

---

### 1.3 协作房间 Socket.IO 实时协议

> 文件：`lib/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart`
> 传输方式：websocket（优先）/ polling（降级），启用自动重连
> 认证：已登录用户用 header `Authorization: Bearer {token}` + auth `{token}`；游客用 query `guestName` / `guestAvatarUrl`
| 连接/join 超时 | 各 10 秒 |

**客户端 → 服务端（emit）：**

| 事件名 | 载荷 | 用途 |
|--------|------|------|
| `join-room` | `roomId` | 加入房间（重连时自动重发） |
| `server-broadcast` | `[roomId, { encryptedBuffer, iv }]` | 持久化广播（普通消息，触达后落库） |
| `server-volatile-broadcast` | `[roomId, { encryptedBuffer, iv }]` | 易失广播（光标/在线状态，可丢弃） |
| `leave-room` | `roomId` | 离开房间 |
| `end-room` | `{ roomId, ownerKey }` | 房主结束房间 |

**服务端 → 客户端（on）：**

| 事件名 | 载荷 | 用途 |
|--------|------|------|
| `init-room` | — | 服务端要求重新 join |
| `first-in-room` | — | 本 socket 是房间第一个成员 |
| `new-user` | `socketId` / obj | 新成员加入 |
| `room-user-change` | `list` | 房间成员列表变化 |
| `room-error` | — | 房间错误 |
| `room-ended` | metadata | 房间被房主结束 |
| `client-broadcast` | `[encryptedBuffer, iv]` | 收到的协作消息（其他客户端广播） |

**应用层消息（解密后明文 JSON）：**

> 文件：`lib/features/whiteboard/collaboration/models/collaboration_message.dart`
> 格式：`{ "type": <wireName>, "payload": {...} }`

| 类型 | wireName | 通道 | payload |
|------|----------|------|---------|
| 场景初始化 | `SCENE_INIT` | 持久化 | `{ elements: [...] }` |
| 场景增量更新 | `SCENE_UPDATE` | 持久化 | `{ elements: [...] }` |
| 实时光标 | `MOUSE_LOCATION` | 易失 | `{ socketId, pointer:{x,y,tool}, button, selectedElementIds, username, userId?, avatarUrl? }` |
| 在线状态 | `IDLE_STATUS` | 易失 | `{ socketId, userState(idle/away/active), username }` |
| 可视区域 | `USER_VISIBLE_SCENE_BOUNDS` | 易失 | `{ socketId, username, sceneBounds:{x,y,width,height} }` |

`elements` 为 Excalidraw 元素 JSON 数组。

---

### 1.4 手写识别 API

> 文件：`lib/features/whiteboard/ink_recognition/ink_recognition_repository.dart`
> 端点：`POST {serverUrl}/api/ink/recognize`

**请求体（InkRecognitionRequest）：**

```jsonc
{
  "sessionId": "string",
  "hint": "auto",
  "strokes": [
    {
      "id": "stroke-1",
      "points": [
        { "x": 100.0, "y": 200.0, "t": 1234 },
        { "x": 105.0, "y": 202.0, "t": 1240 }
      ]
    }
  ],
  "bounds": { "x": 100, "y": 200, "width": 50, "height": 30 }
}
```

**响应体（InkRecognitionResult）：**

```jsonc
{
  "elements": [
    {
      "type": "text",            // 或 formula/shape 等
      "text": "你好",            // type=text 时
      "latex": "E=mc^2",         // type=formula 时
      "x": 100, "y": 200, "width": 50, "height": 30,
      "points": [...]            // shape 时
    }
  ]
}
```

| 项 | 值 |
|----|----|
| 鉴权 | `Authorization: Bearer <token>`（无 token 则匿名，2 秒超时兜底） |
| 客户端 | 鸿蒙用 `NativeHttpClient`，其他平台用标准 http |
| 连接超时 | 8 秒；读取超时 15 秒 |
| 错误处理 | 非 2xx 抛 `StateError`，调用方回退（保留原笔画） |

---

## 2. 应用内 Repository 接口

### 2.1 LibraryRepository

> 文件：`lib/features/library/repositories/library_repository.dart`
> 接口：`abstract interface class LibraryRepository`
> 实现：`SqliteLibraryRepository`（注入 `Future<Database> Function()`）
> Provider：`libraryRepositoryProvider`

**索引加载**

| 方法 | 返回 | 说明 |
|------|------|------|
| `loadIndex()` | `Future<LibraryIndex>` | 一次性加载 notes（按 updated_at DESC）、notebooks（按 sort_order ASC）、tags（按 sort_order ASC）、note_tags，组装为内存聚合根 |

**笔记操作**

| 方法 | 返回 | 说明 |
|------|------|------|
| `createNote({kind, noteType, pageTemplate, title?, subtitle?, notebookId?, tagIds})` | `Future<NoteItem>` | 事务内创建；空标题用默认"未命名笔记"；notebookId/tagIds 无效则丢弃；颜色按时间轮选 |
| `ensureNote(noteId)` | `Future<void>` | 不存在则用默认值插入 |
| `renameNote(noteId, title)` | `Future<void>` | 空 trim 后不操作 |
| `renameSubtitle(noteId, subtitle?)` | `Future<void>` | 更新副标题 |
| `touchNote(noteId, {coverThumbnailBytes?, clearCoverThumbnail})` | `Future<void>` | 更新 updated_at 及封面缩略图 |
| `deleteNotes(noteIds)` | `Future<void>` | 软删除（置 deleted_at） |
| `restoreNotes(noteIds)` | `Future<void>` | 恢复（deleted_at = null） |
| `deleteNotesForever(noteIds)` | `Future<void>` | 物理删除（级联） |
| `moveNotesToNotebook(noteIds, notebookId?)` | `Future<void>` | 校验后批量更新 notebook_id |
| `addTagsToNotes(noteIds, tagIds)` | `Future<void>` | 笛卡尔插入 note_tags（ignore 冲突） |
| `removeTagFromNotes(noteIds, tagId)` | `Future<void>` | 删除 note_tags 行 |
| `setNoteTags(noteId, tagIds)` | `Future<void>` | 全量替换某 note 的标签集 |

**笔记本操作**

| 方法 | 返回 | 说明 |
|------|------|------|
| `createNotebook({name?, coverColor?, coverImage?})` | `Future<LibraryNotebook>` | id=`notebook-{uuid}`；空名用"新建笔记本 {n}"；颜色按 sortOrder 轮选 |
| `renameNotebook(notebookId, name)` | `Future<void>` | |
| `recolorNotebook(notebookId, color)` | `Future<void>` | |
| `deleteNotebook(notebookId)` | `Future<void>` | 删除行，其下 notes 的 notebook_id 置 null |

**标签操作**

| 方法 | 返回 | 说明 |
|------|------|------|
| `createTag({name?, coverColor?, coverImage?})` | `Future<LibraryTag>` | id=`tag-{uuid}`；空名用"新建标签 {n}" |
| `renameTag(tagId, name)` | `Future<void>` | |
| `recolorTag(tagId, color)` | `Future<void>` | |
| `deleteTag(tagId)` | `Future<void>` | 删除行，note_tags 级联删除 |

**LibraryIndexNotifier（AsyncNotifier，provider `libraryIndexProvider`）**

`build()` 调 `loadIndex()`。每个写方法转发到 repository 后执行 `refresh()`（重载整个索引）。方法集与上述 repository 一一对应。

---

### 2.2 WhiteboardSceneRepository

> 文件：`lib/features/whiteboard/repositories/whiteboard_scene_repository.dart`
> 接口：`WhiteboardSceneRepository`

| 方法 | 返回 | 说明 |
|------|------|------|
| `loadScene(noteId)` | `Future<String>` | 从 `note_scenes` 表读取 Excalidraw JSON |
| `saveScene(noteId, content)` | `Future<void>` | upsert（`ConflictAlgorithm.replace`） |

实现：`SqliteWhiteboardSceneRepository`（生产）、`InMemoryWhiteboardSceneRepository`（测试）。默认实例 `defaultWhiteboardSceneRepository`。

---

### 2.3 CollaborationRepository

> 文件：`lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`
> 协作层外观，组合 transport + sceneStore + fileStore + crypto + reconciler

**生命周期方法：**

| 方法 | 说明 |
|------|------|
| `startNewRoom(initialScene)` | 生成 roomId/roomKey/ownerKey，存加密快照，持久化 ownerKey，连接 transport，发 sceneInit |
| `joinRoom(room, localScene)` | 拉远端快照解密，reconcile 本地，返回合并后 scene + metadata |
| `stopCollaboration()` | 自己离开 |
| `endRoom()` | 房主结束（需 ownerKey） |
| `broadcastScene(scene, mode)` | 广播场景（initial/syncAll/增量） |

**暴露的 Stream：**

| Stream | 内容 |
|--------|------|
| `encryptedMessages(room)` | 解密后的协作消息流 |
| `newUsers` | 新成员加入事件 |
| `roomUsers` | 成员列表变化 |
| `roomEnded` | 房间结束事件 |
| `firstInRoom` | 本 socket 是房间首个 |
| `connectionStatus` | 连接状态机 |
| `errors` | 合并的错误流 |
| `fileStatusScenes` | 文件上传/下载状态 |

---

### 2.4 AccountRepository

见 [1.1 账户认证 API](#11-账户认证-api)，Repository 方法与后端接口一一对应。额外提供：
- `readToken()`：从 secure storage 读 token（不请求网络）
- `resolveAvatarUrl(avatarUrl)`：拼接绝对 URL

---

### 2.5 本地存储 Repository

#### LocalSettingsRepository
> 文件：`lib/shared/storage/local_settings_repository.dart`
> 表：`local_settings(key PRIMARY KEY, value TEXT, updated_at INTEGER)`

| 方法 | 说明 |
|------|------|
| `readString(key)` / `writeString(key, value)` | 读写字符串（upsert） |
| `readBool(key)` / `writeBool(key, value)` | 布尔（存 `'true'`/`'false'`） |

全局实例 `defaultLocalSettingsRepository`。

#### RecentCoversRepository
> 文件：`lib/shared/storage/recent_covers_repository.dart`
> 复用 `local_settings` 表，key 形如 `recent_covers_{category}`，value 为 JSON 数组

| 方法 | 说明 |
|------|------|
| `getRecentCovers(category)` | 读最近封面（最多 6 个） |
| `addRecentCover(category, type, value)` | 去重后插入头部，裁剪到 6 个 |
| `clearRecentCovers(category)` | 清除某分类 |

`RecentCoverItem { type: 'color'|'image', value: string, timestamp: int }`。

#### AuthTokenStore
> 文件：`lib/features/account/repositories/auth_token_store.dart`
> 存储后端：flutter_secure_storage，key `flowmuse.auth.token`

| 方法 | 说明 |
|------|------|
| `readToken()` / `writeToken(token)` / `clear()` | |

---

## 3. Riverpod Provider 清单

| Provider | 类型 | 职责 |
|----------|------|------|
| `libraryRepositoryProvider` | `Provider<LibraryRepository>` | 装配 SQLite 实现 |
| `libraryIndexProvider` | `AsyncNotifierProvider<LibraryIndexNotifier, LibraryIndex>` | 资料库内存索引 SSOT |
| `libraryHomeViewModelProvider` | `NotifierProvider<LibraryHomeViewModel, LibraryHomeState>` | 首页 UI 状态 |
| `notebooksViewModelProvider` | `NotifierProvider<NotebooksViewModel, NotebooksState>` | 笔记本页状态 |
| `tagsViewModelProvider` | `NotifierProvider<TagsViewModel, TagsState>` | 标签页状态 |
| `searchViewModelProvider`（隐式，页面内） | `Notifier<SearchState>` | 搜索框状态（查询/范围） |
| `accountViewModelProvider` | `NotifierProvider<AccountViewModel, AccountState>` | 账户状态 |
| `themeViewModelProvider` | `NotifierProvider<ThemeViewModel, AppThemePreset>` | 当前主题预设 |
| `initialThemePresetProvider` | `Provider<AppThemePreset>` | 启动注入的初始预设 |
| `collaborationConfigProvider` | `Provider<CollaborationConfig>` | 协作服务配置 |
| `collaborationRepositoryProvider` | `Provider<CollaborationRepository>` | 协作总控装配 |
| `whiteboardSceneRepositoryProvider` | `Provider<WhiteboardSceneRepository>` | 场景存储 |
| `whiteboardViewModelProvider` | `NotifierProvider<WhiteboardViewModel, WhiteboardState>` | 白板状态 |
| `pendingPdfImportProvider` | `Notifier<PdfNoteImportPayload?>` | 待导入 PDF 暂存 |

---

## 4. 编辑器内核对外接口

> 内核对外名 **markdraw**，barrel 文件 `editor_core/markdraw.dart`

### 4.1 MarkdrawController（核心控制器）

| 方法 / 回调 | 说明 |
|-------------|------|
| `importPdfPages(...)` | 导入 PDF 页面为背景 ImageElement |
| `importPdfSource(..., asBackground)` | PDF 导入入口 |
| `serializeExcalidrawSceneJson()` | 导出当前场景为 Excalidraw JSON（协作用） |
| `applyRemoteExcalidrawSceneJson(scene)` | 应用远端场景（协作回写） |
| `onSceneChanged` 回调 | 场景变更通知（白板页接协作广播） |
| `onRecognizeInk` 回调 | 手写识别触发（接 InkRecognitionRepository） |
| `inkRecognitionMode` | 是否开启笔迹识别 |

### 4.2 WhiteboardCollaborationAdapter（协作桥接）

> 文件：`collaboration/services/whiteboard_collaboration_adapter.dart`

| 方法 | 说明 |
|------|------|
| `currentScene()` | 从 controller 取 Excalidraw 场景 |
| `applyRemoteScene(scene)` | 应用远端场景到 controller |
| `selectedElementIds()` | 当前选中元素（reconcile 时保护） |
| `protectedElementIds()` | 选中 + 编辑中文本/帧标签 id |
| `pointerPayload(offset)` | 光标位置载荷 |
| `visibleSceneBounds(canvasSize)` | 可视区域 |

### 4.3 Scene / Element 模型

详见[数据模型设计文档](./data-model.md)。

---

## 5. 通用约定

### 5.1 时间戳

所有时间字段统一为 **毫秒级 Unix 时间戳**（`DateTime.millisecondsSinceEpoch`）。

### 5.2 ID 生成

| 实体 | ID 格式 |
|------|---------|
| 笔记 | 调用方传入（`ensureNote` 兜底） |
| 笔记本 | `notebook-{uuid}` |
| 标签 | `tag-{uuid}` |
| 协作房间 | 10 字节随机 hex（20 字符） |
| 房间密钥 | base64url 16 字节（22 字符） |
| PDF fileId | `pdf-{sha1(pageBytes)[:12]}` |

### 5.3 颜色存储

颜色在数据库中以 `INTEGER`（`Color.toARGB32()`）存储；在 Excalidraw JSON / HTTP 中以 `#RRGGBB` 字符串存储。

### 5.4 枚举存储

数据库中枚举字段以 `.name` 字符串存储（如 `kind = 'notes'`），读取时容错解析（无法匹配回退默认值）。

### 5.5 错误处理

- HTTP 非 2xx：抛 `StateError`（消息为响应体或"X：HTTP 状态码"）
- 协作快照冲突：HTTP 409 → 客户端拉远端 reconcile 重试
- 房间已结束：HTTP 410；房间不存在：HTTP 404
- 鉴权失败：HTTP 401/403（账户接口清 token，协作接口拒绝操作）

---

## 附录：接口文件索引

| 接口类别 | 文件 |
|----------|------|
| 账户 HTTP | `lib/features/account/repositories/account_repository.dart` |
| Token 存储 | `lib/features/account/repositories/auth_token_store.dart` |
| 协作 REST | `lib/features/whiteboard/collaboration/services/encrypted_scene_store.dart`、`collaboration_file_store.dart` |
| 协作 Socket.IO | `lib/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart` |
| 协作总控 | `lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart` |
| 协作消息协议 | `lib/features/whiteboard/collaboration/models/collaboration_message.dart` |
| 手写识别 | `lib/features/whiteboard/ink_recognition/ink_recognition_repository.dart` |
| 资料库 | `lib/features/library/repositories/library_repository.dart` |
| 本地设置 | `lib/shared/storage/local_settings_repository.dart` |
| 最近封面 | `lib/shared/storage/recent_covers_repository.dart` |
