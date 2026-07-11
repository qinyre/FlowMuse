# FlowMuse 数据模型设计文档

> 版本：对应代码提交 `bcce1f9`
> 本文档覆盖：本地 SQLite 数据库 schema、领域数据模型类、编辑器元素模型、协作数据模型、配置模型。

---

## 目录

1. [SQLite 数据库总览](#1-sqlite-数据库总览)
2. [数据库表定义](#2-数据库表定义)
3. [领域数据模型（Dart 类）](#3-领域数据模型dart-类)
4. [编辑器元素模型](#4-编辑器元素模型)
5. [协作数据模型](#5-协作数据模型)
6. [账户数据模型](#6-账户数据模型)
7. [枚举定义汇总](#7-枚举定义汇总)
8. [存储约定](#8-存储约定)

---

## 1. SQLite 数据库总览

| 属性 | 值 |
|------|----|
| 数据库文件名 | `flowmuse_local.db` |
| Schema 版本 | **4**（当前） |
| 外键约束 | 启用（`PRAGMA foreign_keys = ON`，在 `onConfigure` 设置） |
| 字符编码 | UTF-8 |
| 时间字段 | 毫秒级 Unix 时间戳（`DateTime.millisecondsSinceEpoch`，INTEGER） |
| 枚举字段 | 以 `.name` 字符串存储（TEXT），读取时容错解析 |
| 颜色字段 | `Color.toARGB32()`（INTEGER，含 alpha） |

**版本迁移历史：**

| 版本 | 变更 |
|------|------|
| v1 → v2 | 增加 `notes.cover_thumbnail BLOB`（注释说明已存在） |
| v2 → v3 | `notebooks`、`tags` 增加 `cover_image TEXT`（通过 `_safeAddColumn` 幂等添加） |
| v3 → v4 | （预留） |

迁移策略：`onCreate` / `onUpgrade` / `onOpen` 均调用 `_ensureSchema`（全部用 `CREATE TABLE IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS`），保证 schema 自愈幂等。

**平台实现分发：**

| 平台 | SQLite 实现 | 数据库目录 |
|------|-------------|-----------|
| Android / iOS / macOS | 原生 `sqflite.databaseFactory` | `getDatabasesPath()` |
| 鸿蒙 OHOS | FFI（预加载 `libharmony_sqlite.z.so`） | `getApplicationSupportDirectory()/databases` |
| Windows / Linux | FFI（`sqfliteFfiInit`） | `getApplicationSupportDirectory()/databases` |

---

## 2. 数据库表定义

### 2.1 `notes` — 笔记主表

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | TEXT | PRIMARY KEY | 笔记 ID |
| `title` | TEXT | NOT NULL | 标题 |
| `updated_at` | INTEGER | NOT NULL | 更新时间（毫秒） |
| `kind` | TEXT | NOT NULL | 笔记类型（`notes` / `pdf`，对应 `LibraryFilter`） |
| `cover_color` | INTEGER | NOT NULL | 封面色（ARGB32） |
| `note_type` | TEXT | NOT NULL | 笔记排版（`paged` / `unbounded`，`NoteType`） |
| `page_template` | TEXT | NOT NULL | 页面模板（`blank`/`narrowLine`/`wideLine`/`grid`/`dotGrid`，`PageTemplate`） |
| `notebook_id` | TEXT | 可空 | 所属笔记本，FK → `notebooks(id)` ON DELETE SET NULL |
| `subtitle` | TEXT | 可空 | 副标题 |
| `cover_thumbnail` | BLOB | 可空 | 封面缩略图二进制 |
| `deleted_at` | INTEGER | 可空 | 软删除时间（null = 未删除） |

索引：
- `notes_notebook_id_index` ON `notes(notebook_id)`
- `notes_deleted_at_index` ON `notes(deleted_at)`

### 2.2 `notebooks` — 笔记本集合

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | TEXT | PRIMARY KEY | 格式 `notebook-{uuid}` |
| `name` | TEXT | NOT NULL | 名称 |
| `cover_color` | INTEGER | NOT NULL | 封面色 |
| `cover_image` | TEXT | 可空 | 封面图片资源路径（v3 新增） |
| `created_at` | INTEGER | NOT NULL | 创建时间 |
| `updated_at` | INTEGER | NOT NULL | 更新时间 |
| `sort_order` | INTEGER | NOT NULL | 排序序号 |

### 2.3 `tags` — 标签

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | TEXT | PRIMARY KEY | 格式 `tag-{uuid}` |
| `name` | TEXT | NOT NULL | 名称 |
| `cover_color` | INTEGER | NOT NULL | 封面色 |
| `cover_image` | TEXT | 可空 | 封面图片路径（v3 新增） |
| `created_at` | INTEGER | NOT NULL | 创建时间 |
| `updated_at` | INTEGER | NOT NULL | 更新时间 |
| `sort_order` | INTEGER | NOT NULL | 排序序号 |

### 2.4 `note_tags` — 笔记-标签关联（多对多）

| 字段 | 类型 | 约束 |
|------|------|------|
| `note_id` | TEXT | NOT NULL, FK → `notes(id)` ON DELETE CASCADE |
| `tag_id` | TEXT | NOT NULL, FK → `tags(id)` ON DELETE CASCADE |

主键：复合主键 `PRIMARY KEY(note_id, tag_id)`

索引：`note_tags_tag_id_index` ON `note_tags(tag_id)`

### 2.5 `note_scenes` — 白板场景内容

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `note_id` | TEXT | PRIMARY KEY, FK → `notes(id)` ON DELETE CASCADE | 笔记 ID |
| `content` | TEXT | NOT NULL | Excalidraw JSON 字符串 |
| `updated_at` | INTEGER | NOT NULL | 更新时间 |

索引：`note_scenes_updated_at_index` ON `note_scenes(updated_at)`

> 注：该表由 `WhiteboardSceneRepository` 读写，`LibraryRepository` 不直接操作。

### 2.6 `local_settings` — 键值设置

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `key` | TEXT | PRIMARY KEY | 设置键 |
| `value` | TEXT | NOT NULL | 设置值（布尔存 `'true'`/`'false'`，列表存 JSON 字符串） |
| `updated_at` | INTEGER | NOT NULL | 更新时间 |

**已使用的 key 清单：**

| key | 值类型 | 含义 | 写入位置 |
|-----|--------|------|----------|
| `theme_preset` | String（枚举 name） | 主题预设 ID | `theme_view_model.dart` |
| `shell_sidebar_collapsed` | bool 字符串 | 侧边栏是否折叠 | `app_shell.dart` |
| `flowmuse.guest.username.v3` | String | 访客用户名 | `account_view_model.dart` |
| `whiteboard.inkRecognitionMode.<noteId>` | bool 字符串 | 单篇笔记的笔迹识别开关 | `whiteboard_page.dart` |
| `recent_covers_<category>` | JSON 数组 | 最近使用的封面（最多 6 个） | `recent_covers_repository.dart` |

> 注：账户 token 与协作房主密钥**不**存于此表，存于 flutter_secure_storage。

### 2.7 实体关系图（ER）

```
┌───────────┐  1    N ┌────────┐
│ notebooks │─────────│ notes  │  notebook_id (SET NULL)
└───────────┘         └────┬───┘
     ▲                     │ 1
     │                     │
     │ N                   │ N
┌────┴─────┐  N    N ┌─────┴──────┐
│ note_tags │────────│ note_scenes │  note_id (CASCADE)
└────┬─────┘         └────────────┘
     │ N
     │
     ▼ 1
┌───────────┐
│   tags    │
└───────────┘

local_settings: 独立 key-value 表，无外键关系
```

**级联规则（依赖 `PRAGMA foreign_keys = ON`）：**
- 删除 `notebooks` 行 → 其下 `notes.notebook_id` 置 NULL
- 删除 `tags` 行 → 关联 `note_tags` 级联删除
- 删除 `notes` 行 → `note_tags`、`note_scenes` 级联删除

---

## 3. 领域数据模型（Dart 类）

### 3.1 NoteItem — 笔记

> 文件：`lib/features/library/models/note_item.dart`（普通类，非 immutable）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `id` | `String` | 必填 | |
| `title` | `String` | 必填 | |
| `updatedAt` | `DateTime` | 必填 | |
| `kind` | `LibraryFilter` | 必填 | all/notes/pdf |
| `coverColor` | `Color` | 必填 | |
| `noteType` | `NoteType` | `unbounded` | paged/unbounded |
| `pageTemplate` | `PageTemplate` | `blank` | |
| `notebookId` | `String?` | null | |
| `tagIds` | `List<String>` | `[]` | |
| `subtitle` | `String?` | null | |
| `deletedAt` | `DateTime?` | null | |
| `coverThumbnailBytes` | `Uint8List?` | null | |

**计算 getter：** `isDeleted`（`deletedAt != null`）、`date`（格式 `yyyy/MM/dd`）
**方法：** `copyWith(...)`，含三个清零开关 `clearNotebook` / `clearDeletedAt` / `clearCoverThumbnail`

### 3.2 LibraryNotebook / LibraryTag — 笔记本 / 标签

> 文件：`lib/features/library/models/library_collection.dart`（`@immutable`）

两者字段结构完全一致：

| 字段 | 类型 |
|------|------|
| `id` | `String` |
| `name` | `String` |
| `coverColor` | `Color` |
| `coverImage` | `String?` |
| `createdAt` | `DateTime` |
| `updatedAt` | `DateTime` |
| `sortOrder` | `int` |

### 3.3 LibraryIndex — 资料库聚合根

> 文件：`lib/features/library/models/library_index.dart`

| 字段 | 类型 | 说明 |
|------|------|------|
| `notes` | `List<NoteItem>` | 全部笔记（含已删除） |
| `notebooks` | `List<LibraryNotebook>` | |
| `tags` | `List<LibraryTag>` | |

**计算 getter：**
- `unnotebookedCount`：未删除且 `notebookId == null` 的笔记数
- `untaggedCount`：未删除且 `tagIds.isEmpty` 的笔记数
- `activeNotes`：未删除笔记
- `deletedNotes`：已删除笔记

**方法：**
- `notesForQuery(LibraryQuery query)` — 内存过滤 + 排序
- `countNotesInNotebook(id)` / `countNotesWithTag(tagId)`
- `notebookNameOf(notebookId)` / `tagsOfNote(note)`

**`notesForQuery` 过滤规则：**
1. `onlyDeleted` 与 `item.isDeleted` 一致
2. `filter != all` 时 `item.kind` 匹配
3. `notebookId != null` 时匹配；`onlyUnnotebooked` 时为 null
4. `onlyUntagged` 时 `tagIds` 为空
5. `tagIds`（必含集）全部出现
6. `queryText` 非空时匹配 `title` 或 `subtitle` 子串（不区分大小写）
7. 按 `sortField`（updatedAt/title）+ `sortDirection` 排序

### 3.4 LibraryQuery — 查询条件

> 文件：`lib/features/library/models/library_query.dart`

| 字段 | 类型 | 默认值 |
|------|------|--------|
| `queryText` | `String` | `''` |
| `filter` | `LibraryFilter` | `all` |
| `notebookId` | `String?` | null |
| `tagIds` | `List<String>` | `[]` |
| `onlyUnnotebooked` | `bool` | `false` |
| `onlyUntagged` | `bool` | `false` |
| `onlyDeleted` | `bool` | `false` |
| `sortField` | `LibrarySortField` | `updatedAt` |
| `sortDirection` | `LibrarySortDirection` | `descending` |

---

## 4. 编辑器元素模型

> 文件：`lib/features/whiteboard/editor_core/src/core/elements/`
> 所有元素基于不可变值对象，内置版本控制支持协作冲突仲裁。

### 4.1 Element 基类（共有字段）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `id` | `String` | 必填 | 元素 ID（`ElementId`） |
| `type` | `String` | 必填 | 类型标识（子类固定） |
| `x` | `double` | 必填 | 左上角 X |
| `y` | `double` | 必填 | 左上角 Y |
| `width` | `double` | 必填 | 宽度 |
| `height` | `double` | 必填 | 高度 |
| `angle` | `double` | `0.0` | 旋转角度（弧度） |
| `strokeColor` | `String` | `'#000000'` | 描边色（hex） |
| `backgroundColor` | `String` | `'transparent'` | 填充色 |
| `fillStyle` | `FillStyle` | `solid` | solid/hachure/crossHatch/zigzag |
| `strokeWidth` | `double` | `2.0` | 描边宽度 |
| `strokeStyle` | `StrokeStyle` | `solid` | solid/dashed/dotted |
| `roughness` | `double` | `1.0` | 手绘粗糙度 |
| `opacity` | `double` | `1.0` | 不透明度（0-1） |
| `roundness` | `Roundness?` | null | 圆角 |
| `seed` | `int` | 由 id 哈希派生 | 手绘抖动种子 |
| `version` | `int` | `1` | 版本号（每次更新 +1，协作仲裁用） |
| `versionNonce` | `int` | 随机 | 版本随机数（version 相同时的次级仲裁） |
| `isDeleted` | `bool` | `false` | 软删除标记 |
| `groupIds` | `List<String>` | `[]` | 所属分组 |
| `frameId` | `String?` | null | 所属画框 |
| `boundElements` | `List<BoundElement>` | `[]` | 绑定的元素（如容器绑定的文本） |
| `updated` | `int` | 必填 | 更新时间戳（毫秒） |
| `link` | `String?` | null | 超链接 |
| `locked` | `bool` | `false` | 是否锁定 |
| `index` | `String?` | null | fractional index（z 序排序） |
| `customData` | `Map<String,Object?>?` | null | 扩展数据（笔刷类型、PDF 背景标记等） |

### 4.2 元素子类

| 类 | type 值 | 特有字段 |
|----|---------|----------|
| `RectangleElement` | `rectangle` | （仅基类字段） |
| `EllipseElement` | `ellipse` | （仅基类字段） |
| `DiamondElement` | `diamond` | （仅基类字段，菱形由包围盒推导） |
| `LineElement` | `line` | `points: List<Point>`、`startArrowhead: Arrowhead?`、`endArrowhead: Arrowhead?`、`closed: bool` |
| `ArrowElement` | `arrow` | 继承 Line + `startBinding: PointBinding?`、`endBinding: PointBinding?`、`arrowType: ArrowType` |
| `TextElement` | `text` | `text`、`fontSize`、`fontFamily`、`textAlign`、`verticalAlign`、`containerId: String?`、`lineHeight`、`autoResize` |
| `FreedrawElement` | `freedraw` | `points: List<Point>`、`pressures: List<double>`、`simulatePressure: bool`、`isComplete: bool`（运行时） |
| `ImageElement` | `image` | `fileId: String`、`mimeType: String`、`status: ImageStatus`、`crop: ImageCrop?`、`imageScale: double` |
| `FrameElement` | `frame` | `label: String`（默认"画框"） |

**关联类型：**
- `BoundElement { id, type }` — 绑定引用
- `PointBinding { elementId, fixedPoint(Point) }` — 箭头端点绑定（fixedPoint 为归一化坐标）
- `ImageCrop { x, y, width, height }` — 图片裁剪
- `ImageStatus`：`saved` / `pending` / `error`
- `Arrowhead`：12 种（arrow/bar/dot/triangle 及 outline/circle/diamond 变体、三种 crowfoot ER 记号）
- `ArrowType`：`sharp` / `round` / `sharpElbow` / `roundElbow`

### 4.3 Scene — 场景

> 文件：`src/core/scene/scene.dart`（不可变）

| 组成 | 说明 |
|------|------|
| `List<Element> _elements` | 不可变元素列表 |
| `Map<String, ImageFile> files` | 图片二进制（按 fileId） |

视图：`elements`（含已删除）、`activeElements`（过滤已删除）、`orderedElements`（按 fractional index 排序）

操作（全部返回新 Scene）：`addElement` / `removeElement` / `updateElement`（自动 `bumpVersion`）/ `softDeleteElement`

---

## 5. 协作数据模型

### 5.1 CollaborationRoom — 协作房间

> 文件：`lib/features/whiteboard/collaboration/models/collaboration_room.dart`

| 字段 | 类型 | 说明 |
|------|------|------|
| `roomId` | `String` | 10 字节随机 hex（20 字符） |
| `roomKey` | `String` | base64url 16 字节（22 字符，无 padding） |

**链接格式：** `{origin}{path}#room={roomId},{roomKey}`
**校验正则：** `^([a-zA-Z0-9_-]+),([a-zA-Z0-9_-]{22})$`

### 5.2 CollaborationRoomMetadata

| 字段 | 类型 | 说明 |
|------|------|------|
| `roomId` | `String` | |
| `ownerId` | `String?` | 房主 ID |
| `role` | `CollaborationRoomRole` | owner/editor/unknown（从 `memberRole` 映射） |
| `ended` | `bool` | 是否已结束 |
| `endedBy` | `String?` | 结束者 |
| `endedAt` | `int?` | 结束时间 |

### 5.3 EncryptedPayload — 加密载荷

> 文件：`models/encrypted_payload.dart`

| 字段 | 类型 | 说明 |
|------|------|------|
| `encryptedBuffer` | `Uint8List` | AES-GCM 密文（含末尾 16 字节 MAC） |
| `iv` | `Uint8List` | 12 字节随机 nonce |

支持 Uint8List / List / base64 互转。

### 5.4 CollaborationMessage — 应用层消息

> 文件：`models/collaboration_message.dart`
> 格式：`{ type: <wireName>, payload: {...} }`

| 类型枚举 | wireName | payload 关键字段 |
|----------|----------|-------------------|
| `sceneInit` | `SCENE_INIT` | `elements: List<Map>` |
| `sceneUpdate` | `SCENE_UPDATE` | `elements: List<Map>` |
| `mouseLocation` | `MOUSE_LOCATION` | `socketId, pointer{x,y,tool}, button, selectedElementIds, username` |
| `idleStatus` | `IDLE_STATUS` | `socketId, userState, username` |
| `userVisibleSceneBounds` | `USER_VISIBLE_SCENE_BOUNDS` | `socketId, username, sceneBounds{x,y,width,height}` |

### 5.5 在线状态模型

| 类 | 字段 |
|----|------|
| `CollaboratorPresence` | `socketId, username, userId?, avatarUrl?, isGuest, pointer, button, selectedElementIds, sceneBounds, idleState, isCurrentUser` |
| `RoomCollaborator` | `socketId, username, isGuest, role, userId?, avatarUrl?` |

---

## 6. 账户数据模型

### 6.1 AccountUser

> 文件：`lib/features/account/models/account_user.dart`

| 字段 | 类型 | JSON key | 默认值 |
|------|------|----------|--------|
| `id` | `String` | `id` | 必填 |
| `email` | `String` | `email` | 必填 |
| `displayName` | `String` | `displayName` | 必填 |
| `avatarUrl` | `String` | `avatarUrl` | `''` |
| `registeredAt` | `int` | `registeredAt` | `0` |
| `emailVerified` | `bool` | `emailVerified` | `false` |
| `emailVerifiedAt` | `int` | `emailVerifiedAt` | `0` |
| `updatedAt` | `int` | `updatedAt` | `0` |

计算 getter `collaboratorName`：displayName 非空用 displayName，否则 email。

### 6.2 AuthSession

> 文件：`lib/features/account/models/auth_session.dart`

| 字段 | 类型 |
|------|------|
| `token` | `String` |
| `user` | `AccountUser` |

### 6.3 CollaborationIdentity

> 文件：`lib/features/account/models/collaboration_identity.dart`

| 字段 | 类型 | 说明 |
|------|------|------|
| `username` | `String` | |
| `isGuest` | `bool` | |
| `userId` | `String?` | 访客为 null |
| `avatarUrl` | `String?` | |
| `token` | `String?` | 访客为 null |

构造：`fromUser(user, token)`（已登录）、`guest(username)`（访客）

---

## 7. 枚举定义汇总

### 7.1 资料库枚举

| 枚举 | 文件 | 值 |
|------|------|----|
| `LibraryFilter` | `note_item.dart` | `all, notes, pdf` |
| `LibraryViewMode` | `note_item.dart` | `grid, list` |
| `NoteType` | `note_item.dart` | `paged, unbounded` |
| `PageTemplate` | `note_item.dart` | `blank, narrowLine, wideLine, grid, dotGrid` |
| `LibrarySpecialView` | `library_special_view.dart` | `none, unnotebooked, untagged, trash` |
| `LibrarySortField` | `library_query.dart` | `updatedAt, title` |
| `LibrarySortDirection` | `library_query.dart` | `ascending, descending` |

### 7.2 编辑器枚举

| 枚举 | 说明 |
|------|------|
| `ToolType` | `hand, select, rectangle, diamond, ellipse, arrow, line, freedraw, text, frame, eraser, laser` |
| `FillStyle` | `solid, hachure, crossHatch, zigzag` |
| `StrokeStyle` | `solid, dashed, dotted` |
| `ArrowType` | `sharp, round, sharpElbow, roundElbow` |
| `ImageStatus` | `saved, pending, error` |
| `StrokeInputKind` | `stylus, invertedStylus, touch, mouse, unknown` |

### 7.3 账户 / 协作枚举

| 枚举 | 值 |
|------|----|
| `AccountStatus` | `loading, guest, authenticated, verificationRequired, failed` |
| `CollaborationRoomRole` | `owner, editor, unknown` |
| `RealtimeConnectionStatus` | （传输层状态机：idle/connecting/initializing/connected/reconnecting/disconnected/failed） |

### 7.4 主题枚举

| 枚举 | 值 |
|------|----|
| `AppThemeId` | `day, night, system, starryBlue, mistBlue, auroraGreen` |

---

## 8. 存储约定

### 8.1 ID 生成规则

| 实体 | 格式 |
|------|------|
| 笔记本 | `notebook-{uuid v4}` |
| 标签 | `tag-{uuid v4}` |
| 协作房间 | 10 字节 `Random.secure` hex（20 字符） |
| 房间密钥 | 16 字节 `Random.secure` base64url（22 字符） |
| PDF 图片 fileId | `pdf-{sha1(pageBytes)[:12]}` |
| 编辑器元素 | UUID（`versionNonce` 用 `Random` 整数） |

### 8.2 颜色存储

| 场景 | 格式 |
|------|------|
| SQLite | INTEGER（`Color.toARGB32()`） |
| Excalidraw JSON / HTTP | `#RRGGBB` 字符串（不含 alpha） |
| `.markdraw` 文件 | 命名色 / hex |

### 8.3 时间存储

所有时间字段统一为**毫秒级 Unix 时间戳**（INTEGER / int），转换：`_timestamp(date) = date.millisecondsSinceEpoch`，`_date(ms) = DateTime.fromMillisecondsSinceEpoch(ms)`。

### 8.4 序列化格式

| 数据 | 格式 |
|------|------|
| 白板场景（本地） | Excalidraw JSON 字符串（存 `note_scenes.content`） |
| 白板文档（导出） | `.markdraw`（人类可读）或 `.excalidraw`/`.json`（兼容） |
| 协作实时消息 | AES-GCM-128 加密后的 Excalidraw JSON |
| 最近封面 | JSON 数组字符串（存 `local_settings`） |
| 本地备份 | `flowmuse-backup.json`（6 张表 + 版本元数据，备份格式版本 = 2） |

### 8.5 安全存储（flutter_secure_storage）

| key 前缀 | 内容 |
|----------|------|
| `flowmuse.auth.token` | 账户 token |
| `flowmuse.collaboration.ownerKey.{roomId}` | 协作房主密钥 |

---

## 附录：数据模型文件索引

| 模型 | 文件 |
|------|------|
| NoteItem | `lib/features/library/models/note_item.dart` |
| LibraryNotebook / LibraryTag | `lib/features/library/models/library_collection.dart` |
| LibraryIndex | `lib/features/library/models/library_index.dart` |
| LibraryQuery | `lib/features/library/models/library_query.dart` |
| Element 基类 + 子类 | `lib/features/whiteboard/editor_core/src/core/elements/` |
| Scene | `lib/features/whiteboard/editor_core/src/core/scene/scene.dart` |
| CollaborationRoom | `lib/features/whiteboard/collaboration/models/collaboration_room.dart` |
| CollaborationMessage | `lib/features/whiteboard/collaboration/models/collaboration_message.dart` |
| EncryptedPayload | `lib/features/whiteboard/collaboration/models/encrypted_payload.dart` |
| AccountUser | `lib/features/account/models/account_user.dart` |
| 数据库 schema | `lib/shared/storage/local_database.dart` |
