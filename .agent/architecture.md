# architecture.md — 架构速览

> 本文件是 `.agent/` 知识库的一部分,给 Agent 一个**快速建立全局认知**的架构地图。
> 完整设计见 `FlowMuse-App/docs/architecture.md`(前端)与 `FlowMuse-Server/`(后端代码)。
> 本文件只讲"骨架与边界",不讲字段细节(那些在 `FlowMuse-App/docs/data-model.md`)。

---

## 1. 系统全景

FlowMuse 是跨平台协同白板应用,三层架构:

```
┌──────────────────────────────────────────────────────────┐
│              FlowMuse-App (Flutter 前端)                  │
│  6 端:Android / iOS / macOS / Windows / Web / 鸿蒙         │
│  本地 SQLite 离线优先 + 自研编辑器内核 + E2E 加密协作客户端  │
└───────────────┬──────────────────────┬───────────────────┘
                │ HTTP (REST)           │ Socket.IO (WebSocket)
                ▼                       ▼
┌──────────────────────────────────────────────────────────┐
│              FlowMuse-Server (Go 后端)                    │
│  协作房间中转 + 账户认证 + 手写识别代理 + 加密快照存储       │
│  (服务端只见密文,不解密)                                   │
└──────┬──────────────┬───────────────┬────────────────────┘
       │              │               │
       ▼              ▼               ▼
  PostgreSQL 17    MinIO         Mailpit
  (用户/房间元数据) (加密快照/图片) (注册邮件,开发用)
```

### 关键架构特征

1. **离线优先**:所有用户数据本地 SQLite,无网络也能用。
2. **服务端零知识**:协作内容端到端加密,服务端只存密文、只转发密文。
3. **一份 Dart 代码多端运行**:平台差异收敛到适配层(见第 5 节)。
4. **Excalidraw 兼容**:数据模型、场景 JSON、协作协议对齐 Excalidraw(硬约束,见 `docs/architecture_constraints.md`)。

---

## 2. 前端分层架构

```
┌─ 展示层 ─────────────────────────────────────────────────┐
│  views/widgets (ConsumerWidget)  +  shared/widgets(AppShell)│
└───────────▲────────────────────────────▲──────────────────┘
            │ ref.watch/read              │
┌───────────┴──────────┐    ┌────────────┴───────────────┐
│  view_models (Riverpod)│   │  app/(路由/主题/根组件)      │
│  Notifier/AsyncNotifier│   │  flow_muse_app, app_router  │
└───────────▲──────────┘    └────────────────────────────┘
            │ 依赖注入(Provider 装配 Repository)
┌───────────┴─────────────────────────────────────────────┐
│  领域层 models(不可变值对象) + editor_core(编辑器内核)    │
└───────────▲─────────────────────────────────────────────┘
            │
┌───────────┴─────────────────────────────────────────────┐
│  数据层 repositories + shared/storage(SQLite/secure store)│
└───────┬───────────────┬───────────────┬─────────────────┘
        ▼               ▼               ▼
   本地 SQLite      后端 HTTP       Socket.IO
```

### Feature 切分

| Feature | 职责 | 核心文件 |
|---------|------|----------|
| `library` | 笔记/笔记本/标签的索引与 CRUD(资料库聚合根) | `repositories/library_repository.dart` |
| `notebooks` | 笔记本集合视图 | `view_models/notebooks_view_model.dart` |
| `tags` | 标签集合视图 | `view_models/tags_view_model.dart` |
| `search` | 笔记搜索(内存过滤,非 SQL) | `views/search_page.dart` |
| `settings` | 设置 / 本地备份 | `views/settings_page.dart` |
| `account` | 账户认证(注册/登录/资料) | `repositories/account_repository.dart` |
| `whiteboard` | 白板编辑器(含 4 个子模块,见下) | — |

### whiteboard 的四个子模块

| 子模块 | 职责 |
|--------|------|
| `editor_core/` | 自研编辑器内核(对外名 **markdraw**),Excalidraw 风格 |
| `collaboration/` | 端到端加密实时协作(AES-GCM + Socket.IO + CRDT 合并) |
| `ink_recognition/` | 手写识别(HTTP 调后端) |
| `pdf_note_import/` | PDF 作为白板背景导入 |

---

## 3. 数据流:单一数据源(SSOT)

资料库的核心设计是 **`libraryIndexProvider` 作为 SSOT**:

```
SQLite (flowmuse_local.db)
   │ loadIndex() 一次性加载
   ▼
libraryIndexProvider (AsyncNotifier<LibraryIndex>)  ← SSOT
   │ ref.watch
   ├──► libraryHomeViewModelProvider  (首页笔记列表)
   ├──► notebooksViewModelProvider    (笔记本页)
   ├──► tagsViewModelProvider         (标签页)
   └──► search_page                   (搜索,直接读 index 内存过滤)
```

- 所有写操作走 `LibraryIndexNotifier` 的方法(内部调 repository + `refresh()` 重载)。
- 派生 ViewModel 只 watch `libraryIndexProvider`,不直接查数据库。
- **不要**在 ViewModel 里直接 `LocalDatabase.open()`,一律走 repository。

---

## 4. 编辑器内核(editor_core / markdraw)骨架

```
editor_core/src/
├── core/           领域模型
│   ├── elements/   元素类型体系(rectangle/text/freedraw/image/...)
│   ├── scene/      Scene(不可变元素集合 + 命中检测)
│   ├── history/    HistoryManager(双栈快照,undo/redo)
│   ├── serialization/  .markdraw 与 .excalidraw 双格式
│   └── pdf/        PDF 渲染与导入
├── editor/         EditorState + Tool 体系(Tool → ToolResult → 状态折叠)
├── input/          手写笔输入管线(OneEuro 滤波 + 压感 + 转角保护)
├── rendering/      StaticCanvasPainter + 交互层 + rough 手绘风格
└── ui/             MarkdrawController(对外控制器,3679 行)
```

### 关键设计模式

1. **不可变模型 + Result 模式**:Scene/Element 全不可变,Tool 产出 `ToolResult`(sealed class),`EditorState.applyResult` 折叠成新状态。天然支持 undo/redo,解耦交互与状态。
2. **双序列化格式**:`.markdraw`(人类可读,diff 友好)+ `.excalidraw`(协作载体,生态兼容)。
3. **元素内置版本控制**:`version` + `versionNonce` + fractional `index`,支持协作冲突仲裁。
4. **高频输入路径优先**:手写、拖拽和缩放的每次 pointer 更新不得引入同步 I/O、全量场景扫描或不必要的全量点复制；修改输入管线时，应为平滑、压力和延迟补充可重复的回放或单元测试。

---

## 5. 跨平台适配边界

| 差异 | 收敛位置 | 策略 |
|------|----------|------|
| SQLite | `shared/storage/local_database_path*.dart` | 条件导入:移动端原生 sqflite,鸿蒙/桌面 FFI |
| HTTP | `features/whiteboard/ink_recognition/native_http_client.dart` | 鸿蒙走 Platform Channel,其他走 http |
| 手写笔压感 | `editor_core/src/input/` | `InputPolicySelector` 按设备分策略 |
| 文件/PDF | service 层抽象接口 | 鸿蒙 Platform Channel,其他 pdfx/file_picker |
| shader | `PencilShader` | 不支持的平台静默降级 |
| fork 包 | `tool/vendor/` + `dependency_overrides` | code_assets 加 ohos 枚举,path_provider 含 ohos 支持 |

**铁律**:共享代码(`lib/features/*`、`lib/shared/*`)禁止 `Platform.is*` 判断。详见 `conventions.md` 第 7 节。

> ⚠️ **鸿蒙 Flutter 是社区移植版(`flutter_ohos`)**,不是官方 Flutter。部分 API 不支持(FragmentProgram/Shader)、部分插件需 fork(`path_provider`/`shared_preferences`)、路径约定与标准 Flutter 不同(`ohos/` 替代 `android/`/`ios/`)。编写鸿蒙相关代码时需查 `harmonyos-guides/` 确认 API 可用性,不假设现有实现能在鸿蒙直接运行。

---

## 6. 后端架构(FlowMuse-Server)

```
FlowMuse-Server/
├── cmd/flowmuse-collab-server/main.go   # 入口
└── internal/
    ├── config/    # 配置(环境变量)
    ├── auth/      # 账户认证(HTTP API / token / 邮件 / user_store)
    ├── collab/    # 协作房间(hub / events / http_api)
    ├── recognition/  # 手写识别代理(myscript)
    └── storage/   # 持久化(room_store / scene_store / file_store)
```

| 组件 | 技术 |
|------|------|
| 语言 | Go 1.25 |
| 实时通信 | zishang520/socket.io + engine.io |
| 数据库 | PostgreSQL 17(pgx 驱动) |
| 对象存储 | MinIO(S3 兼容,存加密快照与图片) |
| 邮件 | Mailpit(开发环境) |
| 部署 | Docker Compose 一站式 |

### 服务端职责边界

服务端是**零知识中转站**:
- 转发协作实时消息(密文,不解密)
- 存储加密快照(密文 + 乐观锁版本号)
- 管理房间元数据、用户账户、文件存储
- 代理手写识别请求(转发给 MyScript)

**服务端永远看不到明文画板内容**。

---

## 7. 启动流程

```
main()
 ├─ WidgetsFlutterBinding.ensureInitialized()
 ├─ dotenv.load(isOptional: true)        # .env 配置
 ├─ PencilShader.init()                  # shader(鸿蒙等静默降级)
 ├─ loadSavedThemePreset()               # 从 SQLite 读主题
 └─ runApp(ProviderScope(
        overrides: [initialThemePresetProvider.overrideWithValue(...)],
        child: FlowMuseApp()))
              │
              ▼  MaterialApp.router
        GoRouter (initialLocation: /library)
              │
              ▼  ShellRoute + AppShell
        LibraryHomePage → ref.watch(libraryIndexProvider) → loadIndex()
```

启动卡顿/白屏排查优先级:
1. **数据库迁移是否崩溃**(onUpgrade 抛异常 → openDatabase 失败)—— 见 `decisions.md` ADR-001
2. PencilShader 是否在不支持平台未降级
3. `loadSavedThemePreset()` 的 SQLite 读取是否异常

---

## 8. 安全边界

| 维度 | 设计 |
|------|------|
| 传输加密 | 协作消息 + 快照全程 AES-GCM-128(roomKey),服务端只见密文 |
| 身份 | 账户 Bearer token;协作房主独立 ownerKey(sha256 哈希校验) |
| 本地敏感数据 | token、ownerKey 存 `flutter_secure_storage` |
| 乐观锁 | 快照 `baseSceneVersion/baseSceneHash`,409 触发 reconcile |
| 软删除 | 笔记默认软删除(`deleted_at`),可恢复 |

---

## 9. 关键依赖关系(改 A 影响 B)

改以下模块时,注意连锁影响:

| 改动 | 影响范围 |
|------|----------|
| `local_database.dart` schema | 全部读 DB 的 repository + 已装用户(迁移路径) |
| `libraryIndexProvider` / `LibraryIndexNotifier` | library/notebooks/tags/search 四个 feature |
| `Element` 基类字段 | 编辑器渲染 + 序列化 + 协作 reconciler + Excalidraw 兼容 |
| `CollaborationMessage` 协议 | 前端协作层 + 后端 `collab/events.go` |
| `AccountUser` 模型 | 前端 account + 后端 `auth/` + 协作身份 |
| `pubspec.yaml` 的 `dependency_overrides` | 全平台构建(尤其鸿蒙) |

---

## 10. 文档导航

| 想了解 | 看 |
|--------|-----|
| 产品做什么 | `REQUIREMENTS.md` |
| 架构硬约束 | `docs/architecture_constraints.md` |
| 前端完整架构 | `FlowMuse-App/docs/architecture.md` |
| 接口(后端/Repository/Provider) | `FlowMuse-App/docs/api.md` |
| 数据模型与 schema | `FlowMuse-App/docs/data-model.md` |
| 历次功能实现计划 | `docs/superpowers/plans/*.md` |
| Agent 总指令 | `AGENTS.md`(根目录) |
| 编码约定 | `.agent/conventions.md` |
| 架构决策记录 | `.agent/decisions.md` |
