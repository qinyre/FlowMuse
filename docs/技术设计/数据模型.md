# 数据模型

本地数据库 `flowmuse_local.db`,schema 版本 5,开 `PRAGMA foreign_keys = ON`。时间字段都是毫秒时间戳,枚举存 `.name` 字符串,颜色存 ARGB32 整数。

## 表结构

### notes

笔记主表。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT PK | |
| title | TEXT NOT NULL | |
| updated_at | INTEGER NOT NULL | 毫秒 |
| kind | TEXT NOT NULL | `notes` / `pdf` |
| cover_color | INTEGER NOT NULL | ARGB32 |
| note_type | TEXT NOT NULL | `paged` / `unbounded` |
| page_template | TEXT NOT NULL | `blank` / `narrowLine` / `wideLine` / `grid` / `dotGrid` / `tianGrid` / `miGrid` / `narrowVerticalLine` / `wideVerticalLine` / `fourLineGrid` / `ancientBook` |
| page_flow | TEXT NOT NULL | `topToBottom` / `rightToLeft` |
| notebook_id | TEXT | FK → notebooks(id),ON DELETE SET NULL |
| subtitle | TEXT | |
| cover_thumbnail | BLOB | 封面缩略图 |
| deleted_at | INTEGER | 软删除,null = 未删除 |

索引:`notes_notebook_id_index`、`notes_deleted_at_index`。

### notebooks / tags

结构一样。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT PK | `notebook-{uuid}` 或 `tag-{uuid}` |
| name | TEXT NOT NULL | |
| cover_color | INTEGER NOT NULL | |
| cover_image | TEXT | 封面图片路径 |
| created_at | INTEGER NOT NULL | |
| updated_at | INTEGER NOT NULL | |
| sort_order | INTEGER NOT NULL | |

### note_tags

多对多关联。

| 字段 | 说明 |
|------|------|
| note_id | FK → notes,ON DELETE CASCADE |
| tag_id | FK → tags,ON DELETE CASCADE |

复合主键 `(note_id, tag_id)`。索引 `note_tags_tag_id_index`。

### note_scenes

白板场景内容,Excalidraw JSON 字符串。由 `WhiteboardSceneRepository` 读写(`LibraryRepository` 不碰它)。

| 字段 | 类型 | 说明 |
|------|------|------|
| note_id | TEXT PK | FK → notes,ON DELETE CASCADE |
| content | TEXT NOT NULL | Excalidraw JSON |
| updated_at | INTEGER NOT NULL | |

### local_settings

通用 key-value。

| 字段 | 类型 |
|------|------|
| key | TEXT PK |
| value | TEXT NOT NULL |
| updated_at | INTEGER NOT NULL |

布尔值存 `'true'` / `'false'`,列表存 JSON 字符串。已用的 key:`theme_preset`、`shell_sidebar_collapsed`、`flowmuse.guest.username.v3`、`whiteboard.inkRecognitionMode.<noteId>`、`recent_covers_<category>`。

## 级联规则

- 删笔记本 → 其下 notes 的 notebook_id 置 NULL
- 删标签 → 关联 note_tags 级联删
- 删笔记 → note_tags、note_scenes 级联删

## 迁移

`onCreate` / `onUpgrade` / `onOpen` 都调 `_ensureSchema`(全用 `CREATE TABLE IF NOT EXISTS`,幂等)。新增列必须用 `_safeAddColumn`(列已存在则 catch 跳过),**不能**裸 `ALTER TABLE ADD COLUMN`——之前因为这个导致老用户升级时白屏崩过。改 schema 要 bump `databaseVersion` 并在 `onUpgrade` 加 `if (oldVersion < N)` 分支。

## 领域模型

`NoteItem`(`library/models/note_item.dart`)是普通可变类,字段对应 notes 表加 `tagIds: List<String>`(从 note_tags join 来)。有 `isDeleted` getter 和带 `clearNotebook` / `clearDeletedAt` / `clearCoverThumbnail` 清零开关的 copyWith。

`LibraryNotebook` 和 `LibraryTag`(`library_collection.dart`)是 `@immutable`,字段就是上面那七个,结构完全一样。

`LibraryIndex`(`library_index.dart`)是聚合根,持有 notes / notebooks / tags 三个列表。`notesForQuery(query)` 在内存里按条件过滤排序——这是搜索的实际实现,不是 SQL。

## 编辑器元素

`editor_core` 里的 Element 基类(`core/elements/element.dart`)字段多,但关键的是这几个版本控制字段:`version`(每次更新 +1)、`versionNonce`(随机数,version 相同时做次级仲裁)、`seed`(手绘抖动种子,从 id 派生)、`index`(fractional index,z 序)、`updated`(毫秒)。

子类按 type 分:`rectangle` / `ellipse` / `diamond` / `line` / `arrow` / `text` / `freedraw` / `image` / `frame`。line 系列带 points 和箭头,arrow 额外有端点绑定,freedraw 带 pressures,text 有字体和对齐,image 有 fileId 和状态。具体字段看代码,改的时候注意 Excalidraw 编解码要一致。

Scene 持有不可变元素列表和图片文件 map,所有变更返回新 Scene。

## 协作相关

`CollaborationRoom {roomId, roomKey}`,链接格式 `{origin}{path}#room={roomId},{roomKey}`。`EncryptedPayload {encryptedBuffer, iv}`,AES-GCM 密文 + 12 字节 nonce。`CollaborationMessage` 解密后的明文,见 api.md。

## 安全存储

`flutter_secure_storage` 存两类:`flowmuse.auth.token`(账户 token)、`flowmuse.collaboration.ownerKey.{roomId}`(协作房主密钥)。这些不进 SQLite。
