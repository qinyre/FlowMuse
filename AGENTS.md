# AGENTS.md — FlowMuse Agent 协作规范

> 本文件是给 AI 编码助手（Agent）的项目级指令。任何在此仓库工作的 Agent **必须先完整阅读本文件**，并严格遵守其中的约束。
> 仓库：FlowMuse（武汉大学 2024 级软件工程实训 · 跨平台协同白板）
> 维护者：陈宏宇、任逸青、李天宇

---

## 0. 铁律（先读这一段）

以下规则**没有例外**。违反任何一条都视为任务失败：

1. **动手前必须先勘察**：每次接到任务，先读"勘察清单"（第 2 节），搞清楚现状再写代码。绝不凭记忆或假设直接改。
2. **能复用就绝不重写**：项目已有完善的模块（编辑器内核、资料库 Repository、协作层、导航壳、主题系统等）。需要某能力时，**先找现有实现**，找不到再新建。重复造轮子是最严重的浪费。
3. **新改动不得破坏已有功能**：任何修改完成后，必须按"验证清单"（第 6 节）确认未引入回归。声称"完成"前必须有证据。
4. **对某端的调整不得影响其他端**：本项目跑在 6 个平台（Android / iOS / macOS / Windows / Web / 鸿蒙）。平台特有改动必须收敛在适配层，**禁止污染共享代码**（详见第 5 节）。
5. **Excalidraw 兼容性不可破坏**：白板数据模型、场景 JSON、协作协议必须与 Excalidraw 格式保持兼容（详见 `docs/项目说明/架构约束.md`）。这是产品基石。
6. **数据库迁移必须幂等**：任何 schema 变更必须用 `_safeAddColumn` 等"列已存在则跳过"的方式，**禁止裸 `ALTER TABLE ADD COLUMN`**（详见第 7 节的惨痛教训）。

---

## 1. 项目地图

### 1.1 仓库结构

```
2024-se-17/                       # 仓库根
├── AGENTS.md                     # ← 你正在读
├── .agent/                       # Agent 知识库（详细规范，按需深读）
│   ├── conventions.md            #   编码与协作约定（怎么做）
│   ├── architecture.md           #   架构速览（项目长什么样）
│   ├── decisions.md              #   架构决策记录 ADR（为什么这样选）
│   ├── forbidden_zones.md        #   H10 禁飞区与验收边界
│   └── ai_usage.md               #   项目 AI 使用日志
├── README.md
├── docs/                         # 面向教师与团队的项目文档
│   ├── 项目说明/                    # 需求正文、架构硬约束
│   ├── 项目报告/                    # 成员周报与总结报告
│   ├── 验收材料/                    # Sprint 验收要求、报告与实测附件
│   ├── 技术设计/                    # 架构、接口、数据模型与专题设计
│   └── 研发记录/                    # 计划、调研、排障、归档与许可证
├── FlowMuse-App/                 # Flutter 前端（主工程）
│   ├── lib/                      # Dart 源码（见 1.2）
│   ├── test/                     # 单元测试与 widget 测试
│   ├── ohos/                     # 鸿蒙工程（ArkTS + Platform Channel）
│   ├── tool/vendor/              # 因鸿蒙适配而 fork 的上游包（勿随意改动）
│   ├── pubspec.yaml              # 依赖与 dependency_overrides
│   └── analysis_options.yaml     # lint 规则（flutter_lints）
└── FlowMuse-Server/              # Go 后端（Socket.IO 协作 + REST + 识别）
    ├── cmd/、internal/            # Go 源码
    ├── Dockerfile、docker-compose.yml
    └── go.mod
```

### 1.2 FlowMuse-App/lib 目录（Feature-First 分层）

```
lib/
├── main.dart                     # 启动入口
├── app/                          # 应用层：路由、主题、根组件
├── features/                     # 业务特性（每个 feature 内部四层）
│   ├── library/                  # 资料库（笔记 + 索引聚合根）★核心
│   ├── notebooks/                # 笔记本集合视图
│   ├── tags/                     # 标签集合视图
│   ├── search/                   # 笔记搜索（内存过滤）
│   ├── settings/                 # 设置 / 本地备份
│   ├── account/                  # 账户认证
│   └── whiteboard/               # 白板编辑器
│       ├── editor_core/          # ★自研编辑器内核（对外名 markdraw）
│       ├── collaboration/        # 端到端加密实时协作
│       ├── ink_recognition/      # 手写识别
│       └── pdf_note_import/      # PDF 导入
└── shared/                       # 跨 feature 共享
    ├── storage/                  # SQLite、本地设置、安全存储
    ├── widgets/                  # AppShell、SharedSidebar、间距常量
    └── utils/                    # UI 生命周期辅助工具
```

每个 feature 内部遵循统一四层：`models/`（数据模型）→ `repositories/`（数据访问）→ `view_models/`（Riverpod 状态）→ `views/`+`widgets/`（UI）。依赖方向严格自上而下。

### 1.3 关键参考文档

| 文档                        | 用途                                                             |
| --------------------------- | ---------------------------------------------------------------- |
| `.agent/conventions.md`     | **编码与协作约定**（命名、目录、Riverpod、持久化、Git、测试）    |
| `.agent/architecture.md`    | **架构速览**（系统全景、分层、数据流、跨端边界）                 |
| `.agent/decisions.md`       | **架构决策记录 ADR**（为什么这样选,含白屏事故等教训）            |
| `.agent/forbidden_zones.md` | H10 禁飞区、人工讲解要点与测试入口                               |
| `.agent/ai_usage.md`        | 项目 AI 使用日志；验收材料中保留同内容副本供教师查看             |
| `docs/项目说明/项目需求.md` | 产品要做什么（功能需求清单）                                     |
| `docs/项目说明/架构约束.md` | 架构硬约束（Excalidraw 对齐原则）                                |
| `docs/项目报告/*.md`        | 成员周报与过程总结（人类过程材料，非 AI 默认必读）               |
| `docs/验收材料/`            | Sprint 验收要求、质量门禁、AI 日志副本与实测附件（人类验收材料） |
| `docs/技术设计/前端架构.md` | 前端架构设计（分层、模块、跨平台策略）                           |
| `docs/技术设计/接口设计.md` | 接口设计（后端 HTTP/Socket.IO、Repository、Provider）            |
| `docs/技术设计/数据模型.md` | 数据模型（SQLite schema、领域类、元素模型）                      |
| `docs/研发记录/plans/*.md`  | 历次功能实现计划（团队既有的开发流程范例）                       |

---

## 2. 动手前：勘察清单

### 2.0 指令优先级与阅读路由

规则冲突时，按以下顺序执行：用户当次明确要求 → 本 `AGENTS.md` → 与任务直接相关的 `.agent/` 文档 → 设计/计划文档 → 代码与实际配置。文档描述与代码、配置不一致时，**以已验证的代码和配置为准**，并在同一变更中修正文档。

完成本文件的勘察清单后，按任务读取 `.agent/`：

| 任务类型                                               | 必读文档                         |
| ------------------------------------------------------ | -------------------------------- |
| 任意代码改动                                           | `.agent/conventions.md`          |
| 跨 feature、存储、协作或平台改动                       | `.agent/architecture.md`         |
| 数据库、Excalidraw、鸿蒙适配、协作加密或编辑器状态改动 | `.agent/decisions.md` 中对应 ADR |
| H10 冲突合并、AI 排版或跨端同步冲突改动                | `.agent/forbidden_zones.md`      |

`.agent/` 是项目知识库，不替代代码审查；不要只按概述推断文件位置、版本或现有行为。

**接到任何任务后，写第一行代码之前，先完成以下勘察**（按需取用，但第 1-3 项每次必做）：

1. **读最近 git 记录**：`git log --oneline -15` 了解最近改了什么、当前在什么分支、是否有未提交的进行中工作。
2. **确认当前分支与工作区状态**：`git status` + `git branch --show-current`。是否在 feature 分支？工作区是否干净？
3. **定位受影响的模块**：根据任务，找出会改动的 feature 目录与文件。**先读现有实现的完整内容**，不要只看片段就动手。
4. **检查是否已有同类实现**：用 grep/搜索关键词，确认要做的能力是否已存在（见第 3 节"复用优先"）。
5. **查阅相关计划文档**：`docs/研发记录/plans/` 下是否已有同类功能的计划？按既有计划走。
6. **核对需求**：改功能前回看 `docs/项目说明/项目需求.md` 对应条目，确认没有偏离需求。
7. **跨端影响评估**：改动是否触及共享代码？是否影响除目标平台外的其他端？（见第 5 节）

> 如果任务较大或涉及多文件，遵循团队既有范式：先在 `docs/研发记录/plans/` 写一份计划文档（参考已有的 `2026-07-*.md` 格式：Context → 需求 → 实现方案 → 关键文件 → 验证方案 → 实施步骤），再动手。

---

## 3. 复用优先（绝不重复造轮子）

项目已沉淀大量成熟模块。**新增能力前，必须先确认是否已有现成实现**：

### 3.1 已有的核心能力（直接用，别重写）

| 需要做什么              | 用什么                                                           | 位置                                                    |
| ----------------------- | ---------------------------------------------------------------- | ------------------------------------------------------- |
| 笔记/笔记本/标签的 CRUD | `LibraryRepository` + `LibraryIndexNotifier`                     | `features/library/repositories/library_repository.dart` |
| 读资料库数据            | watch `libraryIndexProvider`（SSOT，内存聚合根）                 | 同上                                                    |
| 本地 key-value 存储     | `LocalSettingsRepository`（**不是** shared_preferences）         | `shared/storage/local_settings_repository.dart`         |
| 最近封面记录            | `RecentCoversRepository`（复用 local_settings 表）               | `shared/storage/recent_covers_repository.dart`          |
| 数据库访问              | `LocalDatabase.open()`（单例，已处理平台分发）                   | `shared/storage/local_database.dart`                    |
| 白板场景存取            | `WhiteboardSceneRepository`                                      | `features/whiteboard/repositories/`                     |
| 协作房间管理            | `CollaborationRepository`（外观，已组合 transport+crypto+store） | `features/whiteboard/collaboration/repositories/`       |
| 账户认证                | `AccountRepository` + `accountViewModelProvider`                 | `features/account/`                                     |
| 主题切换                | `ThemeViewModel` + `themeViewModelProvider`                      | `app/view_models/theme_view_model.dart`                 |
| 导航/侧边栏壳           | `AppShell` + `ShellRoute`（已处理三态切换）                      | `shared/widgets/app_shell.dart`                         |
| 侧边栏组件              | `SharedSidebar` 系列                                             | `shared/widgets/shared_sidebar.dart`                    |
| 间距/尺寸常量           | `AppSpacing`（统一设计 token）                                   | `shared/widgets/app_spacing.dart`                       |
| 页面骨架                | `RightPageScaffold` + `RightPageHeader`                          | `shared/widgets/right_page.dart`                        |
| UI 安全时机操作         | `runAfterUiFrame` / `runWhenContextStable` 等                    | `shared/utils/ui_lifecycle.dart`                        |
| 锚点弹出菜单            | `showAnchoredPopupMenu`                                          | `shared/utils/ui_lifecycle.dart`                        |
| 编辑器能力              | `MarkdrawController`（导入/导出/场景/识别回调）                  | `features/whiteboard/editor_core/`                      |

### 3.2 状态管理统一用 Riverpod

- **UI 状态**：`Notifier<T>` + `NotifierProvider`
- **异步数据**：`AsyncNotifier<T>` + `AsyncNotifierProvider`（如 `libraryIndexProvider`）
- **依赖注入**：`Provider<T>`（如 `libraryRepositoryProvider`）
- UI 组件用 `ConsumerWidget` / `ConsumerStatefulWidget`，通过 `ref.watch`（重建）/ `ref.read`（一次性）访问。
- **禁止**引入 Provider / Bloc / GetX 等其他状态管理方案。

### 3.3 复用检查流程

写新代码前问自己三个问题：

1. **这个数据/能力，`libraryIndexProvider` 或某个现有 Provider 已经有了吗？** 多数资料库派生数据都能从 `libraryIndexProvider` watch 得到。
2. **这个 UI 模式，`SharedSidebar` / `AppSpacing` / `RightPageHeader` 已经支持了吗？**
3. **这个 repository 方法已经存在吗？** 看接口定义，优先扩展而非新建。

---

## 4. 代码规范

### 4.1 Dart / Flutter 风格

- **遵循 `analysis_options.yaml`**（基于 `flutter_lints`）。改动后跑 `flutter analyze`，不得新增 error（warning/info 尽量避免，历史遗留的可不强求）。
- `tool/vendor/**` 已被 analyzer 排除，**不要在那里改业务逻辑**，只做必要的鸿蒙适配。
- 数据模型用 `@immutable` + `final` 字段 + `copyWith`（参考 `LibraryNotebook`、`NotebooksState`）。
- 枚举以 `.name` 字符串存数据库，读取用容错解析（参考 `_enumByName`）。
- 时间统一用毫秒时间戳（`DateTime.millisecondsSinceEpoch`）。
- 路由：新增页面在 `app_router.dart` 注册路径常量 + `GoRoute`，遵循现有的 `_contentPage`/`_detailPage`/`_modalPage` 过渡分类。

### 4.2 命名约定（从代码归纳）

| 类别       | 约定                        | 示例                        |
| ---------- | --------------------------- | --------------------------- |
| 文件名     | snake_case                  | `library_repository.dart`   |
| 类名       | PascalCase                  | `LibraryIndexNotifier`      |
| Provider   | camelCase + `Provider` 后缀 | `libraryIndexProvider`      |
| 路由路径   | kebab-case，`/` 开头        | `/create-collection`        |
| 数据库表   | snake_case                  | `note_tags`                 |
| 数据库字段 | snake_case                  | `cover_color`、`updated_at` |
| ID 前缀    | `实体-{uuid}`               | `notebook-xxx`、`tag-xxx`   |
| 私有方法   | `_` 前缀                    | `_safeAddColumn`            |

### 4.3 调试日志

项目统一用 `debugPrint`，带 `[FlowMuseCreateNote]` 前缀。新增日志遵循此格式，便于过滤。**不要用 `print`**。

### 4.4 错误处理模式

| 场景                      | 做法                                                                       | 示例                                                  |
| ------------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------- |
| Platform Channel 调用     | catch `PlatformException` + `MissingPluginException`，返回 `null` 或默认值 | `try { ... } on PlatformException { return null; }`   |
| 数据库操作                | 让异常向上抛到 ViewModel 层，由 UI 展示 SnackBar                           | `catch (error) { _showCreateError(context, error); }` |
| 非关键初始化（如 shader） | try-catch + 静默降级，**不能阻塞启动**                                     | `try { await init(); } catch (_) { /* 降级 */ }`      |
| 网络请求                  | catch 后区分超时/连接拒绝/其他，分别给用户可理解的提示                     | 见 `ink_recognition_repository.dart`                  |
| 用户操作失败              | 用 `ScaffoldMessenger.showSnackBar` 提示，**不要用 dialog 打断用户**       | 见 `library_sidebar.dart` 的 `_showCreateError`       |
| 不可恢复的致命错误        | 在 `main()` 初始化阶段才允许崩溃，其余位置必须兜底                         | —                                                     |

**禁止**：

- 空 catch 块（`catch (_) {}` 不带日志或恢复逻辑）
- 在 UI 层直接用 `try-catch` 包装大段 Widget build（应在 ViewModel/Repository 层处理）

### 4.5 提交信息约定

观察既有提交，团队用**中文描述**为主，部分带类型前缀：

- 常见前缀：`fix:`、`refactor:`、`merge:`（如 `fix:修复二次创建笔记失败的bug`、`refactor:重构创建集合页面布局`）
- 合并提交：`Merge ...` 或 `merge:合并...到主分支`
- 提交信息用中文，简洁描述"做了什么"。

---

## 5. 跨端约束（对某端的调整不能影响其他端）

### 5.1 平台矩阵

本项目目标平台：**Android / iOS / macOS / Windows / Web / 鸿蒙（OHOS）**。其中鸿蒙最特殊（需 vendor fork + 原生 Platform Channel）。

### 5.2 平台差异必须收敛在适配层

| 差异类型              | 正确做法                                                    | 错误做法                                 |
| --------------------- | ----------------------------------------------------------- | ---------------------------------------- |
| SQLite 实现           | 放在 `shared/storage/local_database_path*.dart`（条件导入） | 在业务代码里写 `if (Platform.isAndroid)` |
| HTTP 通道             | 鸿蒙用 `NativeHttpClient`，其他用 http；通过统一接口封装    | 在调用方判断平台                         |
| 手写笔压感            | 通过 `InputPolicySelector` 按设备分策略                     | 在 Tool 里硬编码设备判断                 |
| 文件选择/保存/PDF渲染 | 鸿蒙走 Platform Channel，封装在 service 层                  | UI 层直接调平台 API                      |
| 路径提供器            | 通过 `dependency_overrides` 指向 vendor 版本                | 在 pubspec 直接锁版本                    |
| shader 不支持         | `PencilShader` 静默降级                                     | 抛异常崩溃                               |

**铁律：共享代码（`lib/features/*`、`lib/shared/*`）里禁止出现 `Platform.is*` / `if (operatingSystem == ...)` 的分支判断。** 平台差异一律走条件导入或抽象接口 + 平台实现。

### 5.3 改鸿蒙端时的额外注意

- 鸿蒙相关代码在 `FlowMuse-App/ohos/`（ArkTS）与 `tool/vendor/`（fork 包）。
- **自动生成文件**（`GeneratedPluginRegistrant.ets`）已在 `.gitignore` 忽略，**不要提交**。
- **vendor fork 包的必要构建文件**（如 `BuildProfile.ets`、`oh-package-lock.json5`）**必须强制追踪**（上游包的 `.gitignore` 会误忽略它们）：`git add -f <file>`。如果 clone 后缺失这些文件，鸿蒙构建会失败。
- 改 `tool/vendor/` 下的 fork 包时，在 pubspec.yaml 注释里记录"为什么 fork"（已有范例），方便后续上游同步。
- 鸿蒙网络安全：`network_config.json` 显式允许 cleartext HTTP（协作服务是 HTTP）。
- **涉及鸿蒙 API / 原生能力时，先查 `harmonyos-guides/` 目录里的官方文档或联网搜索**，确认有对应的 API 和用法后再写代码，不要凭经验猜测鸿蒙侧的实现。**（harmonyos-guides 目录在项目仓库外，和项目于同级目录下，本地可用）**
- 涉及 `ohos/`、`tool/vendor/`、Platform Channel 或插件注册的改动，提交前必须运行 `cd FlowMuse-App && flutter build hap`；构建通过不等同于真机行为通过，真机验收范围须在提交/MR 中如实记录。

### 5.4 鸿蒙 Platform Channel 开发规范

当需要调用鸿蒙原生 API 时（如文件选择、HTTP 请求），遵循以下模式：

1. **Dart 侧**：新建 `_channel_ohos.dart` 文件，通过 `MethodChannel('flow_muse/<channel_name>')` 封装调用接口，返回纯 Dart 类型（`List`/`Map`/`String`），**不泄露平台类型**。
2. **ArkTS 侧**：在 `ohos/entry/src/main/ets/channels/` 下新建对应的 `.ets` 文件，实现 Channel 处理逻辑。
3. **注册**：在 `EntryAbility.ets` 的 `configureFlutterEngine()` 中注册新 Channel。
4. **容错**：Dart 侧所有 Channel 调用必须 catch `PlatformException` 或 `MissingPluginException`，返回 `null` 或默认值，**绝不能因 Channel 未注册而崩溃**。
5. **权限**：如果原生 API 需要权限，在 `module.json5` 的 `requestPermissions` 中声明，并在 ArkTS 侧做权限检查。

已有参考实现：

- 文件选择：`file_picker_channel_ohos.dart` + `FilePickerChannel.ets`
- HTTP 通道：`native_http_client.dart` + `HttpChannel.ets`
- 语音识别：`speech_recognition_service_io.dart` + `SpeechRecognitionChannel.ets`（通道 `flow_muse/speech_recognition`）

### 5.5 改动前的跨端自检

改完任何共享代码后自问：

- 这个改动在 Android 上行为变了吗？（要变，且是预期的）
- 在鸿蒙上呢？（不能因为安卓的改动而崩）
- 在 Web/桌面呢？（不能引入 dart:io 等不支持的 API）

如果改动只针对某端，**确保它通过抽象层隔离**，其他端走原有路径不受影响。

---

## 6. 验证清单（声称"完成"前必须做）

**禁止没有证据就声称完成。** 每次改动后：

1. **静态检查**：`cd FlowMuse-App && flutter analyze`——不得新增 error。
2. **依赖解析**：改了 pubspec 要跑 `flutter pub get` 确认无冲突。
3. **测试**：`flutter test`——已有测试不能挂。如果改了被测试覆盖的模块，**先跑相关测试**。
   - 涉及 `FlowMuse-Server/` 时，额外运行 `cd FlowMuse-Server && go test ./...` 与 `go vet ./...`。
   - 涉及 Flutter 与服务端共同使用的 HTTP/Socket.IO/协作消息格式时，补充前后端字段兼容性验证；不能只验证其中一端。
4. **受影响功能回归**：手动或在脑中过一遍改动影响的用户流程，确认没破坏。例如改了 `libraryIndexProvider`，要确认笔记列表、笔记本页、标签页、搜索页都正常。
5. **跨端影响**：按 5.5 自检。
6. **数据库迁移**：如果改了 schema（见第 7 节），必须同时验证"全新安装"（onCreate）和"旧版本升级"（onUpgrade）两条路径。

> 测试目录在 `FlowMuse-App/test/`，遵循 `test/` 镜像 `lib/` 结构的约定。新增功能尽量补测试。

### 6.1 测试编写规范

| 规则      | 说明                                                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 目录结构  | `test/` 镜像 `lib/` 目录结构：`lib/features/library/repositories/foo.dart` → `test/features/library/repositories/foo_test.dart` |
| 命名      | 测试文件 `*_test.dart`；测试描述用中文；关键场景用 Given-When-Then 注释分段                                                     |
| 覆盖率    | 不要求 100%，但 **Repository 层和工具函数必须有测试**；UI widget 测试覆盖关键交互路径即可                                       |
| 独立运行  | 每个 `test()` 用例不依赖其他用例的执行结果，**不得共享可变状态**                                                                |
| Mock 隔离 | 数据库/网络/Platform Channel 用 mock 隔离，单元测试**不访问真实的文件系统或网络**                                               |
| 运行      | 提交前跑全量 `flutter test`；开发中可用 `flutter test --name="关键词"` 只跑相关测试                                             |

---

## 7. 数据库迁移（重点：曾因此导致全平台白屏崩溃）

### 7.1 惨痛教训

提交 `bcce1f9` 曾导致 Android 和鸿蒙端**一打开就白屏崩溃**，根因是 `local_database.dart` 的 `onUpgrade` 里用了**裸 `ALTER TABLE ADD COLUMN`**：

```dart
// ❌ 错误：列已存在时 SQLite 抛 "duplicate column name"，导致 openDatabase 失败 → 启动崩溃
await db.execute('ALTER TABLE notes ADD COLUMN cover_thumbnail BLOB');
```

旧版本数据库（schema v2）的 `notes` 表已有 `cover_thumbnail` 列，升级时重复添加直接崩溃。修复（提交 `9552520`）改用幂等的 `_safeAddColumn`：

```dart
// ✅ 正确：列已存在则 catch 静默跳过
static Future<void> _safeAddColumn(db, table, column, type) async {
  try {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  } catch (_) {
    debugPrint('... skip $table.$column (already exists)');
  }
}
```

### 7.2 迁移铁律

1. **新增列必须用 `_safeAddColumn`**，禁止裸 `ALTER TABLE ADD COLUMN`。
2. **schema 变更三路径都要覆盖**：`onCreate`（新装）、`onUpgrade`（升级）、`onOpen`（每次打开）。三者最终都调 `_ensureSchema`（用 `CREATE TABLE IF NOT EXISTS`，幂等）。
3. **版本号递增**：改 schema 要 bump `databaseVersion`，并在 `onUpgrade` 里加 `if (oldVersion < N)` 分支。
4. **升级路径要全**：从任意旧版本都能升到最新。不要假设用户从上一版本升。
5. **外键依赖**：`PRAGMA foreign_keys = ON` 已在 `onConfigure` 开启，删除实体的级联规则（SET NULL / CASCADE）依赖它。

---

## 8. Git 工作流

### 8.1 分支模型

- `main`：受保护的主分支，保持可构建、可运行。
- `feature/<功能名>`：功能开发分支（如 `feature/create-folder-tag`、`feature/ui-design`）。
- 平台适配分支：如 `markdraw-harmonyos-probe`（鸿蒙探针）。
- **不要直接在 main 上做大改动**。先开 feature 分支。

### 8.2 合并

- feature 分支完成后合并到 main，合并提交用中文描述（如 `merge:合并feature/xxx到主分支`）。
- 合并前确认与 main 最新（先 rebase 或 merge main 进 feature 分支解决冲突）。

### 8.3 Merge Request（MR）规范

1. **MR 标题**：中文简述做了什么（如 `feat: 笔记本/标签封面图片选择`），与提交风格一致。
2. **MR 描述**必须包含：
   - **做了什么**（变更摘要）
   - **影响范围**（改了哪些模块/文件）
   - **跨端影响**（是否涉及平台特定代码、是否已在对应端验证）
   - **数据库变更**（如果有 schema 改动，写清楚升级路径）
   - **截图/录屏**（UI 改动必须附）
3. **Review 重点**：
   - 是否遵循"复用优先"（有没有重复造轮子）
   - 共享代码中是否有平台判断（违反铁律）
   - 数据库迁移是否幂等（`_safeAddColumn`）
   - 自动生成文件是否误提交
4. **合并前**：本地确认 `flutter analyze` 通过 + `flutter test` 通过 + 与最新 main 无冲突。

### 8.4 提交粒度

- 一个提交做一件事，描述清晰。
- 提交前确认没有把自动生成文件（build/、.dart_tool/、ohos 生成文件）误加进来。

---

## 9. 协作与安全约定

- **端到端加密**：协作的实时消息与快照全程 AES-GCM-128 加密，服务端只见密文。改协作层时**不得**让明文落库或明文传输。
- **token 安全**：账户 token 存 `flutter_secure_storage`（key `flowmuse.auth.token`），**不要**存到 `local_settings` 表或明文文件。
- **日志与测试脱敏**：不得向 `debugPrint`、异常消息、测试失败输出、截图或提交记录写入 token、ownerKey、roomKey、AES 密钥、白板明文或可还原的协作密文。排障日志只记录脱敏后的标识、长度、状态码或哈希前缀。
- **乐观锁**：协作快照用 `baseSceneVersion/baseSceneHash`，冲突返回 409 时走 reconcile 重试，不要直接覆盖。
- **软删除优先**：笔记删除默认软删除（置 `deleted_at`），可恢复；物理删除才级联。

---

## 10. 文档同步要求

代码改动后，**改变了对外行为、架构边界、数据格式或开发约束时**，相关文档必须同步更新；纯局部实现修复不为凑文档而重复描述。文档以准确反映现状为目标，不能复制过期实现细节：

| 改动类型              | 需更新的文档                                |
| --------------------- | ------------------------------------------- |
| 新增功能/用户可见变更 | `docs/项目说明/项目需求.md`（更新功能清单） |
| 架构变更/新模块       | `docs/技术设计/前端架构.md`                 |
| 新 API 端点/协议变更  | `docs/技术设计/接口设计.md`                 |
| 数据模型/表结构变更   | `docs/技术设计/数据模型.md`                 |
| 新增 Platform Channel | 在本 `AGENTS.md` 5.4 节补充引用             |
| 项目级流程/规范调整   | 本 `AGENTS.md`                              |
| 重大实现决策          | `docs/研发记录/plans/` 新建计划文档         |

**原则**：改了代码就要能找到对应的文档说明。文档不在多，在**准确反映现状**。过期文档比没有文档更危险。

---

## 11. 当你不确定时

- **不确定是否有现成实现** → 先 grep / 用 Explore agent 搜，再决定新建。
- **不确定改动是否影响其他端** → 按 5.5 自检，拿不准就在计划里标注"需跨端验证"并提示用户。
- **不确定需求边界** → 回看 `docs/项目说明/项目需求.md` 和 `docs/项目说明/架构约束.md`。
- **不确定架构是否合适** → 查 `docs/研发记录/plans/` 是否有同类先例，或参考 `docs/技术设计/前端架构.md`。
- **遇到 3 次修复都失败** → 停下来，这大概率是架构问题而非 bug，向用户说明并讨论方案，不要继续盲目打补丁。

---

## 附：Agent 工作流速查

```
接到任务
  ↓
读 git log / git status / 定位模块（第 2 节）
  ↓
读现有实现 + 查复用可能（第 3 节）
  ↓
（大任务）写计划文档 → （小任务）直接动手
  ↓
遵循代码规范（第 4 节）+ 跨端约束（第 5 节）+ 错误处理模式（第 4.4 节）
  ↓
验证清单全过（第 6 节）+ 测试规范（第 6.1 节）
  ↓
flutter analyze 无 error + flutter test 通过
  ↓
同步对应文档（第 10 节）
  ↓
提交（中文描述，第 4.5 节）
```
