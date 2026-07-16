# 架构说明

FlowMuse 是一个跨平台手写白板 / 笔记应用,跑在 Android、iOS、鸿蒙和桌面端。一份 Dart 代码多端运行,本地 SQLite 离线优先,白板内核自研(内部叫 markdraw),协作走端到端加密。后端用 Go,只做账户认证、协作消息中转和加密快照存储——服务端永远看不到画板明文。

## 目录结构

业务代码按 feature 切分,每个 feature 内部固定四层:

```
lib/features/<feature>/
├── models/           数据模型,不可变
├── repositories/     数据访问,interface + 实现
├── view_models/      Riverpod Notifier
└── views/            页面和组件
```

依赖只能自上而下。feature 之间不互相 import 内部实现,要共享数据就通过暴露出来的 Provider(比如 `libraryIndexProvider`)。跨 feature 的通用东西放 `lib/shared/`(数据库、通用组件、工具函数)。

主要的 feature:`library`(资料库,笔记和集合的索引)、`notebooks` / `tags`(集合视图)、`search`、`settings`、`account`、`whiteboard`。其中 whiteboard 最大,下面挂了五个子模块:编辑器内核 `editor_core`、实时协作 `collaboration`、手写识别 `ink_recognition`、PDF 导入 `pdf_note_import`、语音识别 `speech_recognition`。

## 状态管理

全用 Riverpod。UI 状态用 `Notifier`,异步数据用 `AsyncNotifier`,依赖注入用 `Provider`。页面是 `ConsumerWidget` / `ConsumerStatefulWidget`,通过 `ref.watch` 重建、`ref.read` 取一次。不要引入别的状态管理方案。

资料库这块有个关键设计:**`libraryIndexProvider` 是唯一数据源**。它在 build 时把 notes / notebooks / tags / 关联一次性读进内存,组成 `LibraryIndex` 聚合根。首页、笔记本页、标签页、搜索页全 watch 它来派生数据。所有写操作走 `LibraryIndexNotifier` 的方法,内部调完 repository 再 `refresh()` 重载。所以——不要在 ViewModel 里直接 `LocalDatabase.open()`,一律走 `libraryIndexProvider`。搜索也是内存子串匹配,不走 SQL。

## 白板内核

`editor_core` 是平台无关的纯 Dart 引擎,核心思路是**不可变模型 + Result 模式**。Scene 和 Element 都是不可变的,工具(Tool)不直接改状态,而是产出一个 `ToolResult`,`EditorState.applyResult` 把它折叠成新状态。这样 undo/redo(快照栈)和协作合并(每个元素带 version 和 versionNonce,做 last-writer-wins)都自然而然能支持。

序列化有两套格式:`.markdraw`(自研,人类可读,diff 友好)和 `.excalidraw` / `.json`(兼容 Excalidraw,协作传输用它)。数据模型、场景 JSON 必须和 Excalidraw 兼容,这是硬约束(见仓库根 `docs/architecture_constraints.md`)——改 Element 字段时要保证编解码往返一致。

输入处理是一条独立的流水线:PointerEvent 归一化 → OneEuro 自适应滤波(带转角保护和压感独立滤波)→ 喂给当前 Tool。不同设备(手写笔/触摸/鼠标)的滤波参数由 `InputPolicySelector` 分策略。

语音转文字通过统一 `SpeechRecognitionService` 接入：Android 与鸿蒙共用 `flow_muse/speech_recognition` Platform Channel，Web 使用浏览器 SpeechRecognition。中间结果只保存在 `MarkdrawEditor` 的临时 UI 状态，最终结果经 `MarkdrawController.insertPlainText()` 创建一个普通 `TextElement`，因此不改变 Excalidraw 格式和协作协议。默认不保存录音，其他平台缺少原生实现时安全降级为 unavailable。

## 协作

端到端加密。房间链接里带 roomId 和 roomKey(`#room=roomId,roomKey`),所有实时消息和快照用 roomKey 做 AES-GCM-128 加密,服务端只转发和存密文。房主额外有个 ownerKey,它的 sha256 哈希存服务端,用来鉴权"结束房间"。

实时通信用 socket_io_client。正常只广播 version 变化的增量元素,每 20 秒全量重发一次防止丢消息。快照异步存服务端,带乐观锁(baseSceneVersion + baseSceneHash),冲突返回 409 就拉远端 reconcile 重试。新成员加入时主动把最新场景推给对方。

## 跨平台

平台差异全部收敛在适配层,共享代码里**禁止**写 `Platform.isAndroid` / `Platform.operatingSystem == 'ohos'` 这种判断。具体收敛点:

- SQLite:移动端用原生 sqflite,鸿蒙和桌面用 FFI。分发逻辑在 `shared/storage/local_database_path*.dart`(条件导入)。鸿蒙要先加载 `libharmony_sqlite.z.so`。
- HTTP:鸿蒙走自研 `NativeHttpClient`(Platform Channel),其他平台走标准 http。
- 服务卡片：鸿蒙通过 FormExtensionAbility + ArkTS 动态卡片承载最近白板入口；Flutter 侧只负责把 noteId/title/updatedAt 通过 flow_muse/service_widget 通道推送给 ArkTS，并在启动时消费 resumeLastWhiteboard action。
- 手写笔、文件选择、PDF 渲染、语音识别:鸿蒙走 Platform Channel,其他平台用原生能力或现成插件。
- Flutter 上游有几个包不认识 `ohos`,所以在 `tool/vendor/` 下放了 fork 版本,通过 pubspec 的 `dependency_overrides` 覆盖。`tool/vendor/` 只做适配,不放业务逻辑。

## 启动

`main.dart` 的顺序:初始化 binding → 加载 .env → PencilShader(不支持的端静默降级)→ 从 SQLite 读主题预设 → `runApp`。初始路由是 `/library`。路由用 go_router,主内容页包在 `ShellRoute` + `AppShell` 里(带侧边栏),白板和设置页是顶层路由。

排查启动白屏优先看两处:数据库迁移有没有崩(`onUpgrade` 里抛异常会让 `openDatabase` 失败),以及 PencilShader 有没有在鸿蒙上正常降级。

## 数据持久化

本地数据库 `flowmuse_local.db`,schema 版本 4,开 `PRAGMA foreign_keys = ON`。表有 notes / notebooks / tags / note_tags / note_scenes / local_settings。详细字段见 [data-model.md](./data-model.md)。

应用设置(主题、侧边栏状态、访客名、最近封面)存在 `local_settings` 这张 key-value 表里,**不是** shared_preferences。敏感数据(token、协作房主密钥)存 `flutter_secure_storage`。

## 后端

Go 写的,跑在 Docker Compose 里(PostgreSQL + MinIO + Mailpit)。Socket.IO 用 zishang520 的实现。服务端是零知识中转:转发协作密文、存加密快照、管账户和房间元数据、代理手写识别请求(转发给 MyScript)。完整接口见 [api.md](./api.md)。
