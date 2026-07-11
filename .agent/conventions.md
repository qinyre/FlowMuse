# conventions.md — 编码与协作约定

> 本文件是 `.agent/` 知识库的一部分,记录项目**怎么做**的约定。
> 配套阅读:`architecture.md`(项目长什么样)、`decisions.md`(为什么这样选)。
> 根目录 `AGENTS.md` 是 Agent 的总入口,本文件是其"编码规范"章节的详细展开。

---

## 1. 命名规范

### 1.1 通用

| 类别 | 约定 | 示例 |
|------|------|------|
| Dart 文件 | snake_case | `library_repository.dart` |
| 类 / 枚举 | PascalCase | `LibraryIndexNotifier`、`NoteType` |
| 方法 / 变量 | camelCase | `loadIndex`、`coverColor` |
| 常量 | lowerCamelCase(实例) / lowerCamelCase(顶层) | `_maxRecentItems`、`databaseVersion` |
| 私有成员 | `_` 前缀 | `_safeAddColumn`、`_database` |

### 1.2 项目特有命名

| 类别 | 约定 | 示例 |
|------|------|------|
| Riverpod Provider | camelCase + `Provider` 后缀 | `libraryIndexProvider` |
| 路由路径常量 | kebab-case,`/` 开头 | `static const createCollection = '/create-collection'` |
| 数据库表名 | snake_case | `note_tags`、`note_scenes` |
| 数据库字段 | snake_case | `cover_color`、`updated_at`、`deleted_at` |
| 实体 ID 前缀 | `实体名-{uuid}` | `notebook-a1b2c3...`、`tag-d4e5f6...` |
| 调试日志前缀 | `[FlowMuseCreateNote]` | `debugPrint('[FlowMuseCreateNote] ...')` |
| 安全存储 key | `flowmuse.*` | `flowmuse.auth.token`、`flowmuse.collaboration.ownerKey.{roomId}` |
| 本地设置 key | 见下方"持久化"小节 | `theme_preset`、`shell_sidebar_collapsed` |

### 1.3 后端(Go)

| 类别 | 约定 | 示例 |
|------|------|------|
| 包名 | 全小写单数 | `collab`、`auth`、`recognition`、`storage` |
| 文件名 | snake_case | `http_api.go`、`room_store.go` |
| 导出标识 | PascalCase 首字母大写 | `RoomStore`、`HandleEvents` |

---

## 2. 目录与文件组织

### 2.1 Feature 内部四层结构(强制)

每个 `lib/features/<feature>/` 必须按以下分层组织,依赖方向严格自上而下:

```
features/<feature>/
├── models/           # 不可变数据模型(@immutable + final + copyWith)
├── repositories/     # 数据访问:abstract interface class + 实现
├── view_models/      # Riverpod Notifier,编排 repository
└── views/            # ConsumerWidget / ConsumerStatefulWidget 页面
    widgets/          # (可选)feature 内可复用组件
```

| 层 | 职责 | 禁止 |
|----|------|------|
| models | 纯数据,无逻辑依赖 | 引用 repository / view_model |
| repositories | 数据 CRUD,接口与实现分离 | 直接调 UI / Provider |
| view_models | 持有 UI 状态,调 repository,被 Provider 暴露 | 直接操作 SQLite(走 repository) |
| views / widgets | 渲染 + 用户交互,通过 `ref.watch/read` 驱动 | 包含业务逻辑(下沉到 view_model) |

### 2.2 跨 feature 通信

- **只通过共享 Provider**通信(如 `libraryIndexProvider`)。
- feature 之间**不直接 import 对方的内部实现**,需要数据时 watch 对方暴露的 Provider。
- 共享能力放 `lib/shared/`(storage / widgets / utils)。

### 2.3 测试镜像源码结构

`FlowMuse-App/test/` 镜像 `lib/` 的目录结构:

```
test/
├── features/library/library_sidebar_test.dart          ↔ lib/features/library/...
├── features/whiteboard/collaboration/                  ↔ lib/features/whiteboard/collaboration/
└── features/whiteboard/editor_core/                    ↔ lib/features/whiteboard/editor_core/
```

测试文件命名:`<被测对象>_test.dart`,放对应目录下。

---

## 3. Dart / Flutter 编码约定

### 3.1 数据模型

```dart
@immutable
class LibraryNotebook {
  const LibraryNotebook({
    required this.id,
    required this.name,
    // ...
    this.coverImage,  // 可空字段放最后,带默认值或可空
  });

  final String id;
  final String name;
  final String? coverImage;  // 可空用 ?

  LibraryNotebook copyWith({...}) { ... }
}
```

- 用 `@immutable` + `const` 构造 + `final` 字段。
- 可空字段用 `Type?`,不用 `late`(除非 `WhiteboardViewModel._repository` 这种运行时赋值场景)。
- 提供 `copyWith`,可空字段的清零用布尔开关参数(参考 `NoteItem.copyWith` 的 `clearNotebook`/`clearDeletedAt`)。

### 3.2 Repository 模式

```dart
// 接口:abstract interface class(支持 mock 注入)
abstract interface class LibraryRepository {
  Future<LibraryIndex> loadIndex();
  Future<NoteItem> createNote({...});
  // ...
}

// 实现:注入数据库访问函数,便于测试替换
class SqliteLibraryRepository implements LibraryRepository {
  SqliteLibraryRepository(this._openDatabase);
  final Future<Database> Function() _openDatabase;
}

// Provider 装配
final libraryRepositoryProvider = Provider<LibraryRepository>(
  (_) => SqliteLibraryRepository(LocalDatabase.open),
);
```

### 3.3 状态管理(Riverpod)

| 场景 | 用法 |
|------|------|
| UI 状态 | `Notifier<State>` + `NotifierProvider` |
| 异步数据 | `AsyncNotifier<Data>` + `AsyncNotifierProvider`,UI 用 `asData?.value ?? fallback` 兜底 |
| 依赖注入 | `Provider<T>`,在 `build()` 里 `ref.watch` 依赖的 Provider |
| 只读一次 | `ref.read`(事件回调、初始化) |
| 响应式重建 | `ref.watch`(build 方法内) |

**禁止**引入 Provider / Bloc / GetX 等其他状态管理方案。

### 3.4 路由

新增页面在 `lib/app/app_router.dart`:

```dart
// 1. 定义路径常量(AppRoutes 类内)
static const myPage = '/my-page';

// 2. 注册 GoRoute(按页面类型选过渡工厂)
GoRoute(
  path: AppRoutes.myPage,
  pageBuilder: (context, state) {
    return _modalPage(state, const MyPage());  // 或 _contentPage / _detailPage
  },
),
```

过渡类型选择:`_contentPage`(壳内主页面,无过渡) / `_detailPage`(详情,右滑) / `_modalPage`(模态) / `_workspacePage`(白板)。

### 3.5 调试日志

```dart
debugPrint('[FlowMuseCreateNote] LocalDatabase.open path=$databasePath');
```

- 统一 `debugPrint`,带 `[FlowMuseCreateNote]` 前缀。
- **禁止 `print`**。
- 关键流程(数据库打开、协作连接、场景广播)必须有日志。
- 日志、异常信息、测试失败输出和截图中不得出现 token、ownerKey、roomKey、AES 密钥、白板明文或可还原协作密文；排障只记录脱敏标识、长度、状态码或哈希前缀。

### 3.6 异常处理

- 数据库迁移等"可能部分失败"的操作用 try-catch 静默降级(参考 `_safeAddColumn`)。
- HTTP 非 2xx 抛 `StateError`,消息含响应体或状态码。
- 不要吞掉异常而不记日志。

---

## 4. 持久化约定

### 4.1 用什么存什么

| 数据 | 存储 | 说明 |
|------|------|------|
| 笔记/笔记本/标签/关联/场景 | SQLite(`flowmuse_local.db`) | 结构化数据 |
| 应用设置(主题/侧边栏/访客名/最近封面/笔迹开关) | SQLite `local_settings` 表(key-value) | **不是** shared_preferences |
| 账户 token、协作房主密钥 | `flutter_secure_storage` | 敏感数据 |
| 白板场景内容 | SQLite `note_scenes.content`(Excalidraw JSON) | 非独立文件 |

> 虽然 pubspec 依赖了 `shared_preferences`,但 settings/account/theme 三模块实际全部走 `LocalSettingsRepository`(SQLite)。**新设置项也走这里**,不要混用。

### 4.2 `local_settings` 已用 key

| key | 含义 |
|-----|------|
| `theme_preset` | 主题预设(枚举 name) |
| `shell_sidebar_collapsed` | 侧边栏折叠(bool 字符串) |
| `flowmuse.guest.username.v3` | 访客用户名 |
| `whiteboard.inkRecognitionMode.<noteId>` | 单笔记迹识别开关 |
| `recent_covers_<category>` | 最近封面(JSON 数组) |

新增 key 用有意义的命名,带版本号后缀(如 `.v3`)便于后续迁移。

### 4.3 数据库迁移铁律

```dart
// ✅ 幂等:列已存在则静默跳过
static Future<void> _safeAddColumn(db, table, column, type) async {
  try {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  } catch (_) {
    debugPrint('[FlowMuseCreateNote] _safeAddColumn: skip $table.$column');
  }
}
```

- 新增列**必须**用 `_safeAddColumn`,**禁止**裸 `ALTER TABLE ADD COLUMN`(详见 `decisions.md` ADR-001)。
- 改 schema 必须 bump `databaseVersion` + 在 `onUpgrade` 加 `if (oldVersion < N)` 分支。
- `onCreate` / `onUpgrade` / `onOpen` 三路径都要保证 schema 正确(最终都调 `_ensureSchema`)。
- 外键级联依赖 `PRAGMA foreign_keys = ON`(已在 `onConfigure` 开启)。

---

## 5. 数据格式约定

| 场景 | 格式 |
|------|------|
| 时间 | 毫秒级 Unix 时间戳(`DateTime.millisecondsSinceEpoch`) |
| SQLite 颜色 | INTEGER(`Color.toARGB32()`) |
| JSON/HTTP 颜色 | `#RRGGBB` 字符串 |
| SQLite 枚举 | `.name` 字符串(如 `'notes'`、`'paged'`) |
| 白板场景 | Excalidraw JSON 兼容格式 |
| 白板文档导出 | `.markdraw`(人类可读) 或 `.excalidraw`/`.json` |
| 协作消息 | AES-GCM-128 加密后的 Excalidraw JSON |
| 本地备份 | `flowmuse-backup.json`(备份格式版本 = 2,与 DB schema 版本独立) |

---

## 6. Git 与提交约定

### 6.1 分支

| 分支 | 用途 |
|------|------|
| `main` | 受保护主干,保持可构建可运行 |
| `feature/<功能>` | 功能开发(如 `feature/create-folder-tag`) |
| 平台探针分支 | 如 `markdraw-harmonyos-probe` |

**不在 main 上直接做大改动**,先开 feature 分支。

### 6.2 提交信息

团队用**中文描述**为主,可选类型前缀:

| 格式 | 场景 | 示例 |
|------|------|------|
| `fix:<描述>` | 修 bug | `fix:修复二次创建笔记失败的bug` |
| `refactor:<描述>` | 重构 | `refactor:重构创建集合页面布局` |
| `<描述>` | 普通功能/优化 | `优化笔记本/标签新建页面UI美观度` |
| `merge:<描述>` | 合并 | `merge:合并feature/xxx到主分支` |
| `Merge ...` | 自动合并 | `Merge branch 'main' of ...` |

提交粒度:一个提交做一件事。

### 6.3 不要提交的文件

`.gitignore` 已忽略(关键项):

| 类型 | 路径 |
|------|------|
| 构建产物 | `**/build/`、`**/.dart_tool/`、`**/coverage/` |
| 鸿蒙签名配置 | `**/ohos/build-profile.json5`(本地签名) |
| 鸿蒙自动生成(忽略) | `GeneratedPluginRegistrant.ets` |
| — | 注意:`tool/vendor/path_provider_ohos/ohos/` 下的 `oh-package-lock.json5` 和 `BuildProfile.ets` **不是**自动生成的,是 vendor fork 的必要构建文件,**必须追踪**(vendor 自带的 `.gitignore` 会误忽略它们,用 `git add -f` 添加) |
| 插件注册 | `**/flutter/generated_plugin_registrant.*` |
| IDE | `.idea/`、`*.iml` |

提交前 `git status` 检查,勿误加自动生成文件。

---

## 7. 跨端开发约定

### 7.1 共享代码禁令

`lib/features/*` 和 `lib/shared/*` 内**禁止**:

```dart
// ❌ 禁止:共享代码里的平台判断
if (Platform.isAndroid) { ... }
if (Platform.operatingSystem == 'ohos') { ... }
```

平台差异一律走**条件导入**或**抽象接口 + 平台实现**:

```dart
// ✅ 条件导入(local_database_path.dart)
import 'local_database_path_stub.dart'
    if (dart.library.io) 'local_database_path_io.dart';
```

### 7.2 鸿蒙适配收敛点

| 差异 | 位置 |
|------|------|
| SQLite FFI | `shared/storage/local_database_path_io.dart`(预加载 `libharmony_sqlite.z.so`) |
| HTTP | `features/whiteboard/ink_recognition/native_http_client.dart`(Platform Channel → @ohos.net.http) |
| 手写笔 | `editor_core/src/ui/harmony_stylus_stroke_smoother.dart` + `editor_core/src/input/` |
| 文件选择/保存 | Platform Channel → DocumentViewPicker |
| PDF 渲染 | Platform Channel → PDFKit |
| fork 包 | `tool/vendor/`(改了要在 pubspec 注释说明原因) |

### 7.3 改动后跨端自检

改共享代码后问:
1. Android 行为变了吗?(要变且预期)
2. 鸿蒙会崩吗?(不能)
3. Web/桌面引入了 `dart:io` 等不支持的 API 吗?(不能)

---

## 8. 测试约定

### 8.1 风格

项目用标准 `flutter_test`:

- **单元测试**:纯逻辑断言,不依赖 widget(如 `collaboration_crypto_test.dart` 测加解密往返)。
- **Widget 测试**:用 `ProviderScope` + `MaterialApp.router` 包裹被测组件(如 `library_sidebar_test.dart`)。

### 8.2 覆盖重点

优先为以下写测试:
- 数据访问层(repository 的 CRUD、迁移)
- 纯算法(加密、输入滤波、reconciler 合并)
- 序列化(Excalidraw JSON 编解码)
- 关键交互(widget 行为)

### 8.3 运行

```bash
cd FlowMuse-App
flutter test                    # 全量
flutter test test/features/library/   # 指定目录
```

改动被测试覆盖的模块时,**先跑相关测试**。

---

## 9. UI / 设计约定

### 9.1 设计 token

用 `lib/shared/widgets/app_spacing.dart` 的 `AppSpacing` 常量,不要硬编码尺寸:

| 常量 | 值 | 用途 |
|------|----|------|
| `pageInset` | 32 | 页面内边距 |
| `compactPageInset` | 20 | 紧凑模式 |
| `shellHeaderHeight` | 72 | 侧边栏头部高 |
| `radius` | 8 | 通用圆角 |
| `sectionGap` / `listGap` / `controlGap` | 24/12/8 | 间距梯度 |

### 9.2 组件复用

| 需要 | 用 |
|------|----|
| 侧边栏 | `SharedSidebar` 系列(`SharedSidebarItem`、`SharedSidebarBlock`) |
| 内容页骨架 | `RightPageScaffold` + `RightPageHeader` |
| 导航壳 | `AppShell`(已处理 docked/drawer/折叠三态) |
| 锚点菜单 | `showAnchoredPopupMenu`(非 MenuAnchor) |
| UI 时机操作 | `runAfterUiFrame` / `runWhenContextStable`(避免在 build 中操作 overlay) |

### 9.3 主题

- 6 套预设(`AppThemeId`):day / night / system / starryBlue / mistBlue / auroraGreen。
- 切换走 `themeViewModelProvider.notifier.changePreset`,不要直接改 `MaterialApp.theme`。
- `system` 预设运行时跟随系统深浅色(经 `effectiveAppThemePreset`)。

---

## 10. 静态检查与完成标准

```bash
cd FlowMuse-App
flutter analyze     # 不得新增 error(warning/info 尽量避免)
flutter test        # 已有测试不挂
```

`analysis_options.yaml` 基于 `flutter_lints`,`tool/vendor/**` 已被排除(那里只做鸿蒙适配,不改业务)。

**声称"完成"前必须有证据**:analyze 无 error + 相关 test 通过 + 跨端自检通过。没有验证不算完成。
