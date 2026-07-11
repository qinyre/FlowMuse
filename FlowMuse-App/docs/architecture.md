# FlowMuse 架构设计文档

> 版本：对应代码提交 `bcce1f9`
> 适用项目：`FlowMuse-App`（Flutter 跨平台笔记 / 白板应用）

---

## 1. 概述

FlowMuse 是一款以"白板 + 笔记"为核心、支持手写笔书写、手写识别、PDF 导入与实时端到端加密协作的跨平台应用，目标平台覆盖 **Android / iOS / 鸿蒙（OHOS）/ 桌面（Windows、macOS、Linux）**。

应用基于 **Flutter** 框架开发，采用 **Feature-First 分层架构**，状态管理使用 **Riverpod 3.x**，路由使用 **go_router**，本地数据持久化基于 **SQLite（sqflite_common）**。

### 1.1 设计目标

| 目标 | 说明 |
|------|------|
| 跨平台一致体验 | 同一套 Dart 业务代码运行于 Android / iOS / 鸿蒙 / 桌面，平台差异收敛到 `shared/storage` 与少量适配层 |
| 可维护性 | 按 feature 切分目录，feature 内部遵循 models / repositories / view_models / views 四层结构 |
| 可扩展的编辑器内核 | 自研编辑器内核 `editor_core`（对外名 **markdraw**），以不可变数据模型 + Result 模式实现 undo/redo 与协作 |
| 安全协作 | 实时协作全程端到端加密（AES-GCM-128），服务端只见密文 |
| 离线优先 | 笔记、笔记本、标签、场景内容全部本地 SQLite 存储，可离线使用 |

### 1.2 技术选型一览

| 关注点 | 技术方案 |
|--------|----------|
| UI 框架 | Flutter（Dart SDK ^3.11.1） |
| 状态管理 | flutter_riverpod ^3.3.2（`Notifier` + `NotifierProvider` / `AsyncNotifier`） |
| 路由 | go_router ^17.3.0 |
| 本地数据库 | sqflite + sqflite_common + sqflite_common_ffi（FFI 用于鸿蒙与桌面） |
| 安全存储 | flutter_secure_storage（+ flutter_secure_storage_ohos） |
| 配置 | flutter_dotenv（`.env`）+ `--dart-define` |
| 实时通信 | socket_io_client |
| 网络 | http（账户/快照），自研 NativeHttpClient（鸿蒙手写识别） |
| 加密 | cryptography（AES-GCM）、crypto（sha256） |
| 编辑器算法 | rough_flutter（手绘风格）、perfect_freehand（笔刷轮廓） |
| PDF | pdfx |
| 其他 | uuid、archive（备份）、google_fonts、lucide_icons_flutter、flutter_colorpicker、re_editor、flutter_svg、super_clipboard |

---

## 2. 系统分层架构

整体采用"展示层 / 领域层 / 数据层"的分层模型，并按 feature 做水平切分。

```
┌─────────────────────────────────────────────────────────────┐
│                         展示层 (Presentation)                  │
│   views/  (页面 ConsumerWidget/ConsumerStatefulWidget)       │
│   widgets/ (可复用组件)                                        │
│   shared/widgets/ (AppShell、SharedSidebar、RightPage…)       │
└───────────────▲─────────────────────────────▲────────────────┘
                │ ref.watch / ref.read          │
┌───────────────┴─────────────┐  ┌─────────────┴──────────────┐
│      状态层 (View Models)     │  │     应用路由 / 主题 (app/)     │
│  Riverpod Notifier / Provider │  │  flow_muse_app、app_router   │
│  library / notebooks / tags / │  │  app_theme、theme_view_model │
│  search / whiteboard / account│  └──────────────────────────────┘
└───────────────▲───────────────┘
                │ 依赖注入（Provider 装配 Repository）
┌───────────────┴─────────────────────────────────────────────┐
│                       领域层 (Domain)                          │
│   models/  不可变值对象：NoteItem、LibraryNotebook、Element…   │
│   editor_core/  场景 / 元素 / 历史 / 序列化 / 渲染 / 输入管线    │
└───────────────▲─────────────────────────────────────────────┘
                │
┌───────────────┴─────────────────────────────────────────────┐
│                        数据层 (Data)                          │
│  repositories/   LibraryRepository、AccountRepository、       │
│                  CollaborationRepository、WhiteboardSceneRepo │
│  shared/storage/ LocalDatabase(SQLite)、LocalSettings、       │
│                  RecentCovers、AuthTokenStore(secure storage) │
└───────────────▼─────────────────────────────────────────────┘
                │
        ┌───────┴────────┬──────────┬───────────┐
        ▼                ▼          ▼           ▼
   本地 SQLite      文件系统      后端 HTTP   Socket.IO 协作服务
  (flowmuse_local.db) (场景/PDF)  (账户/快照)  (实时画板)
```

### 2.1 目录结构约定

```
lib/
├── main.dart                      # 入口：加载 .env → PencilShader → 主题 → runApp
├── app/                           # 应用层：根组件、路由、主题
│   ├── flow_muse_app.dart         # MaterialApp.router 根
│   ├── app_router.dart            # GoRouter 路由表
│   ├── app_theme.dart             # 主题 → Material 数据
│   ├── app_theme_preset.dart      # 6 套主题预设定义
│   └── view_models/theme_view_model.dart
├── features/                      # 业务特性（水平切分）
│   ├── library/                   # 资料库（笔记 + 索引聚合根）
│   ├── notebooks/                 # 笔记本集合视图
│   ├── tags/                      # 标签集合视图
│   ├── search/                    # 笔记搜索
│   ├── settings/                  # 设置 / 本地备份
│   ├── account/                   # 账户（注册/登录/资料/改密）
│   └── whiteboard/                # 白板编辑器
│       ├── views/  view_models/  repositories/
│       ├── editor_core/           # 自研编辑器内核（markdraw）
│       ├── collaboration/         # 端到端加密实时协作
│       ├── ink_recognition/       # 手写识别
│       └── pdf_note_import/       # PDF 笔记导入
└── shared/                        # 跨 feature 共享
    ├── storage/                   # SQLite、本地设置、安全存储
    ├── widgets/                   # AppShell、SharedSidebar、间距常量
    └── utils/                     # UI 生命周期辅助工具
```

每个 feature 内部遵循统一四层：

| 子目录 | 职责 | 依赖方向 |
|--------|------|----------|
| `models/` | 不可变数据模型（值对象、枚举） | 被各层引用 |
| `repositories/` | 数据访问抽象 + 实现（接口 `abstract interface class` + SQLite/HTTP 实现） | 依赖 models |
| `view_models/` | Riverpod `Notifier`，持有 UI 状态，编排 repository 调用 | 依赖 repository + models |
| `views/`、`widgets/` | Flutter 页面与组件，通过 `ref.watch` 驱动渲染 | 依赖 view_models + models |

依赖方向严格自上而下；跨 feature 通信只通过 `shared/` 或共享的 Riverpod Provider（如 `libraryIndexProvider`）。

---

## 3. 核心模块详解

### 3.1 应用启动流程

`lib/main.dart` 启动序列：

```
main()
 ├─ WidgetsFlutterBinding.ensureInitialized()
 ├─ await dotenv.load(isOptional: true)        # 加载 .env 配置
 ├─ await PencilShader.init()                   # 铅笔纹理 shader（不支持的鸿蒙平台静默降级）
 ├─ await loadSavedThemePreset()                # 从 SQLite 读取持久化主题预设
 └─ runApp(ProviderScope(
        overrides: [initialThemePresetProvider.overrideWithValue(initialThemePreset)],
        child: FlowMuseApp()))
```

`FlowMuseApp` 是无状态 `ConsumerWidget`，watch 主题预设后构造 `MaterialApp.router`，路由器初始位置为 `/library`。

### 3.2 路由与导航壳

路由采用 `ShellRoute` + `AppShell` 的双层组合：

- **ShellRoute（壳内路由）**：提供持久化侧边栏外壳，承载主内容页面。
  - `/library`、`/library/unnotebooked`、`/library/untagged`、`/library/trash`
  - `/search`、`/notebooks`、`/notebooks/:notebookId`、`/tags`、`/tags/:tagId`
- **顶层路由（壳外）**：全屏或自带外壳的页面。
  - `/create-note`、`/create-collection`、`/settings`（模态）
  - `/auth/verify-email`、`/auth/reset-password`（深链，邮件回调）
  - `/whiteboard/:noteId`、`/whiteboard/collaboration`（白板 / 协作白板）

页面过渡分四类工厂：`_contentPage`（无过渡）、`_detailPage`（详情右滑）、`_modalPage`（模态）、`_workspacePage`（白板）、`_standalonePage`（独立页）。所有动效在 `MediaQuery.disableAnimationsOf` 为真时禁用（无障碍支持）。

`AppShell`（`shared/widgets/app_shell.dart`）是导航壳的核心，负责侧边栏的三态切换：
- **桌面展开**：宽度 > `820px` 且未折叠且 `showSidebar` → docked 侧边栏
- **桌面折叠 / 窄屏**：隐藏侧边栏，header 显示"打开侧边栏"按钮
- **窄屏**：用 `Scaffold.drawer` 抽屉式侧边栏

折叠状态由 `ShellLayoutViewModel` 持久化到 `local_settings` 表（key `shell_sidebar_collapsed`）。

### 3.3 状态管理：Riverpod 体系

应用广泛使用 Riverpod 的 `Notifier` / `AsyncNotifier` + `Provider` 进行依赖注入与状态分发。核心 Provider 依赖关系：

```
accountViewModelProvider ──────────────┐
   (token / 协作身份 CollaborationIdentity)│
                                        ▼
collaborationConfigProvider ──► collaborationRepositoryProvider
                                        │
libraryRepositoryProvider ──► libraryIndexProvider (AsyncNotifier)
                                  │      │      │
                                  ▼      ▼      ▼
            libraryHomeViewModelProvider │  tagsViewModelProvider
                          notebooksViewModelProvider
                                        │
                                  (编辑器) whiteboardViewModelProvider
```

关键设计：
- **`libraryIndexProvider` 是资料库的单一数据源**（Single Source of Truth）。`LibraryIndexNotifier` 在 `build()` 中调用 `loadIndex()` 一次性把 notes/notebooks/tags/note_tags 读入内存形成 `LibraryIndex` 聚合根，之后所有写操作都走 Notifier 方法（内部调 repository + `refresh()` 重新加载）。
- notebooks、tags、library_home 三个 ViewModel 都 `ref.watch(libraryIndexProvider)`，派生出各自的视图模型。`search_page` 也直接读 `libraryIndexProvider` 做内存过滤。
- **AsyncNotifier 错误传播**：`libraryIndexProvider` 的状态是 `AsyncValue<LibraryIndex>`，UI 用 `asData?.value ?? const LibraryIndex()` 兜底。

### 3.4 白板编辑器内核（editor_core / markdraw）

编辑器内核是平台无关的纯 Dart + Flutter 渲染引擎，架构要点：

**(1) 不可变领域模型 + Result 模式**
- `Scene` 持有不可变 `List<Element>` 与 `Map<String, ImageFile>`，所有变更返回新 Scene。
- 元素基类 `Element` 内置版本控制字段：`version`、`versionNonce`（协作冲突仲裁）、`seed`（手绘抖动种子）、`index`（fractional index，z 序）、`updated`（时间戳）。
- 元素子类：`rectangle / ellipse / diamond / line / arrow / text / freedraw / image / frame`。
- **工具（Tool）不直接修改状态，而是产出 `ToolResult`**（sealed class：AddElement / UpdateElement / RemoveElement / SetSelection / UpdateViewport / SwitchTool / SetClipboard / AddFile / RemoveFile / Compound）。`EditorState.applyResult(result)` 用 switch 表达式把结果折叠成新状态。这种设计天然支持 undo/redo，并解耦交互与状态。

**(2) 双栈历史管理**
`HistoryManager` 用 `_undoStack` / `_redoStack` 两个 Scene 快照栈（非 diff/patch），`maxDepth = 100`。

**(3) 双序列化格式**
- `.markdraw`：自研人类可读格式（YAML frontmatter + prose/sketch 段落），diff 与 LLM 友好。
- `.excalidraw` / `.json`：Excalidraw JSON 兼容格式，**协作层全程用此格式**做载体，采用容错解析（未知属性产生 `ParseWarning` 而非抛异常）。

**(4) 渲染管线**
两条 `CustomPainter` 路径：`StaticCanvasPainter`（主图层：页面布局、网格、视口剔除、元素渲染、绑定文本）与交互层（选择框、控制柄、激光笔、吸附线、协作光标）。`ElementRenderer` 按 type 分派到 `RoughAdapter`（rough 手绘算法 + perfect_freehand 笔刷轮廓），带路径缓存。

**(5) 平台无关输入管线**
`src/input/` 实现手写笔建模：`PointerEvent` → `StrokeInputNormalizer` → 规范化样本 → `StrokeInputModeler`（OneEuro 自适应低通滤波 + 转角保护 + 压感独立滤波）→ 喂给当前 `Tool`。`InputPolicySelector` 按设备分策略（stylus 用真实压感、touch 无压感、mouse 几乎不滤波）。

### 3.5 端到端加密实时协作

协作模块（`whiteboard/collaboration/`）组合了传输层、加密、场景同步与文件存储：

```
本地编辑 ─► controller.onSceneChanged
        ─► WhiteboardCollaborationAdapter.currentScene()  (Excalidraw JSON)
        ─► CollaborationRepository.broadcastScene
            ├─ SceneReconciler 计算增量元素
            ├─ CollaborationCrypto.encrypt(AES-GCM-128, roomKey)
            └─ SocketIoRealtimeTransport.send → emit('server-broadcast', [roomId, {encryptedBuffer, iv}])

服务端转发 ─► 远端 socket.on('client-broadcast')
         ─► transport.encryptedMessages stream
         ─► repo 解密队列（串行化解密）
         ─► CollaborationMessage (sceneUpdate / mouseLocation / idleStatus / …)
         ─► WhiteboardCollaborationAdapter.applyRemoteScene
         ─► controller.applyRemoteExcalidrawSceneJson → 重绘
```

关键设计：
- **房间密钥**：`roomId`（10 字节随机 hex）+ `roomKey`（base64url 16 字节）。房主额外持有 `ownerKey`，其 sha256 哈希用于结束房间的鉴权。
- **CRDT 风格合并**（`SceneReconciler`）：基于 `version` + `versionNonce` 的 last-writer-wins + fractional index 排序 + 软删除 TTL（1 天）+ 选中/编辑中元素的本地保护（`protectedElementIds`）。
- **增量广播 + 周期全量同步**：正常只发 version 变化的元素，每 20 秒全量重发一次防止增量丢失。
- **异步快照通道**：广播后异步 `PUT /api/rooms/{roomId}/scene`，带乐观锁（`baseSceneVersion/baseSceneHash`，冲突返回 409 时拉远端 reconcile 重试）。
- **图片文件同步**：上传 300ms 防抖，经 `ExcalidrawBinaryCodec` 编码 + roomKey 加密后 `PUT /api/rooms/{roomId}/files/{fileId}`，单文件 10MB 上限。

### 3.6 手写识别

`ink_recognition/` 模块通过 HTTP 调用后端识别服务：
- 触发：用户开 `inkRecognitionMode` + 选可识别笔刷 → `FreedrawTool` 给笔画注入 pending 标记 → 抬笔后 1 秒防抖 → 收集 session 笔画构造 `InkRecognitionRequest`（含 sessionId、strokes、bounds）→ POST `{serverUrl}/api/ink/recognize`（`Authorization: Bearer`，可匿名）。
- 回写：识别成功则 `pushHistory` + `applyResult`（移除原笔画、添加识别出的文字/公式/形状、选中新元素）；失败则回退（清 pending 标记保留原笔画）。
- 网络：鸿蒙走自研 `NativeHttpClient`（鸿蒙原生 HTTP 通道），其他平台走标准 http。

### 3.7 PDF 导入

PDF 导入横跨 feature 层（`pdf_note_import/`）与内核层（`editor_core/src/core/pdf/`）：
- feature 层：`PdfNoteImportService.pickAndStageImport` 选文件 → 创建 NoteItem（kind=pdf）→ 暂存到 `pendingPdfImportProvider` → 跳转白板。
- `PdfNoteConsumer.consume` 在白板页消费 pending payload → 调 `importPdfSource(asBackground: true)`。
- 内核层：`PdfImporter` 调 `PdfPageRenderer`（pdfx 实现）逐页渲染为图片 → 以 ImageElement 形式（`isPdfBackground` 标记）垂直排列加入场景，切到 paged 布局，fit 视口到首页。

### 3.8 账户与后端集成

账户模块（`account/`）通过 HTTP 与后端 `/api/auth/*` 交互（详见接口设计文档）。鉴权使用 `Authorization: Bearer <token>`，token 存于 `flutter_secure_storage`（key `flowmuse.auth.token`）。未登录用户以"访客"身份使用本地功能，参与协同时用生成的访客名（形容词+动物+后缀，头像取 OpenMoji SVG）。

### 3.9 主题系统

- 预设：`AppThemeId` 枚举定义 6 套主题（day / night / system / starryBlue / mistBlue / auroraGreen），每套含 seedColor、brightness、渐变背景三色。
- 渲染：`AppTheme.fromPreset` 用 `ColorScheme.fromSeed` 生成 Material3 主题，自定义 card / iconButton / navigationRail / searchBar 样式。
- 状态：`ThemeViewModel`（Notifier）持久化到 `local_settings.theme_preset`（存枚举 name 字符串），`main.dart` 启动时用 `loadSavedThemePreset()` 注入初始值。
- system 预设：通过 `effectiveAppThemePreset(preset, platformBrightness)` 在运行时跟随系统深浅色。

---

## 4. 跨平台适配策略

### 4.1 平台差异收敛点

| 差异 | 处理位置 | 策略 |
|------|----------|------|
| SQLite 实现 | `shared/storage/local_database_path*.dart` | 条件导入：鸿蒙/桌面用 FFI（`sqfliteFfiInit` + `databaseFactoryFfi`），移动端用原生 sqflite |
| 鸿蒙 SQLite 原生库 | `local_database_path_io.dart` | 动态打开 `libharmony_sqlite.z.so`，调用 `harmony_sqlite_make_global` 提升符号可见性 |
| 数据库目录 | 同上 | 鸿蒙/桌面：`getApplicationSupportDirectory()/databases`；移动端：`getDatabasesPath()` |
| HTTP 通道 | `shared/utils/native_http_client.dart` | 鸿蒙走原生 HTTP 通道，其他平台走标准 http |
| 手写笔压感 | `editor_core/.../harmony_stylus_stroke_smoother.dart` | 鸿蒙手写笔独立平滑处理 |
| 路径提供器 | `dependency_overrides` 指向 `tool/vendor/path_provider_ohos` | 社区版含 ohos 支持 |
| 安全存储 | `flutter_secure_storage_ohos` | 鸿蒙适配版本 |
| shader | `PencilShader` | 不支持的平台（含鸿蒙）静默降级 |
| native-assets hooks | `dependency_overrides: code_assets` 指向 vendor fork | 加 ohos 枚举值，解决 `OS.fromSyntax` 解析异常 |

### 4.2 vendor 目录

`tool/vendor/` 存放因鸿蒙适配而临时 fork 的上游包：
- `code_assets`（加 ohos 枚举）
- `path_provider`（含 ohos 支持的社区版）
- `path_provider_ohos`、`shared_preferences_ohos`

这些覆盖通过 `pubspec.yaml` 的 `dependency_overrides` 生效，后续上游更新时需手动同步。

---

## 5. 数据与存储架构

应用采用**离线优先**策略，所有用户数据本地 SQLite 存储，后端仅负责账户认证与协作数据中转。

### 5.1 本地数据库

数据库文件 `flowmuse_local.db`，当前 schema 版本 **4**，开启 `PRAGMA foreign_keys = ON`。核心表（完整字段见数据模型设计文档）：

| 表 | 用途 |
|----|------|
| `notes` | 笔记主表（含软删除 `deleted_at`、封面缩略图 BLOB） |
| `notebooks` | 笔记本集合 |
| `tags` | 标签 |
| `note_tags` | 笔记-标签多对多关联 |
| `note_scenes` | 白板场景内容（Excalidraw JSON 字符串） |
| `local_settings` | 通用 key-value 设置（主题、侧边栏、访客名、最近封面、笔迹识别开关） |

迁移策略：`onUpgrade` 用幂等的 `_safeAddColumn`（列已存在则静默跳过），`onCreate`/`onUpgrade`/`onOpen` 都调用 `_ensureSchema`（`CREATE TABLE IF NOT EXISTS`）保证 schema 自愈。

### 5.2 安全存储

`flutter_secure_storage` 仅存放账户 token（key `flowmuse.auth.token`）与协作房主密钥（key 前缀 `flowmuse.collaboration.ownerKey.`）。

### 5.3 文件系统

- 白板场景：存于 SQLite `note_scenes.content`（非独立文件）。
- 备份：导出为 `flowmuse-backup.json`（含 6 张表数据 + 版本元数据，备份格式版本 = 2）。

---

## 6. 安全设计

| 维度 | 设计 |
|------|------|
| 传输加密 | 协作实时消息与快照全程 AES-GCM-128（roomKey），服务端只见密文 |
| 身份鉴权 | 账户 token（Bearer）；协作房主用独立 ownerKey（sha256 哈希校验） |
| 本地敏感数据 | token、ownerKey 存 secure storage |
| 乐观锁 | 协作快照用 `baseSceneVersion/baseSceneHash`，冲突返回 409 触发 reconcile |
| 输入校验 | 创建笔记/标签时校验 notebookId/tagIds 有效性，无效则丢弃 |
| 软删除 | 笔记删除默认软删除（`deleted_at`），可恢复；物理删除走级联 |

---

## 7. 关键架构特征总结

1. **不可变领域模型 + Result 模式**贯穿编辑器内核，状态变更集中、可追溯，天然支持 undo/redo 与协作合并。
2. **单一数据源（SSOT）**：`libraryIndexProvider` 作为资料库内存索引的 SSOT，各视图模型派生自它，避免多处重复查询。
3. **平台差异最小化**：通过条件导入 + vendor fork + 适配层，将鸿蒙/桌面差异收敛到 `shared/storage` 与少量工具类。
4. **端到端加密协作**：自研 CRDT 风格合并 + AES-GCM 加密 + 乐观锁快照，实现安全且高可用的实时协作。
5. **Feature-First + 四层结构**：模块边界清晰，feature 间通过共享 Provider 解耦，便于团队并行开发。

---

## 附录：核心文件索引

| 模块 | 关键文件 |
|------|----------|
| 启动 | `lib/main.dart` |
| 应用层 | `lib/app/flow_muse_app.dart`、`app_router.dart`、`app_theme.dart`、`app_theme_preset.dart` |
| 资料库 | `lib/features/library/repositories/library_repository.dart` |
| 笔记本/标签 | `lib/features/notebooks/view_models/notebooks_view_model.dart`、`lib/features/tags/view_models/tags_view_model.dart` |
| 白板内核 | `lib/features/whiteboard/editor_core/src/` |
| 协作 | `lib/features/whiteboard/collaboration/` |
| 数据层 | `lib/shared/storage/local_database.dart` |
| 导航壳 | `lib/shared/widgets/app_shell.dart`、`shared_sidebar.dart` |
