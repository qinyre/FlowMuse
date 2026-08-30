# decisions.md — 架构决策记录(ADR)

> 本文件是 `.agent/` 知识库的一部分,记录项目中**为什么这样选**的关键决策。
> 每条 ADR 记录:背景 → 决策 → 理由 → 后果。Agent 在改动相关模块前应先读对应 ADR。
> 新增重要技术决策时,按 ADR-NNN 追加到末尾。

---

## ADR-001:数据库迁移必须幂等(`_safeAddColumn`)

- **状态**:已采纳
- **日期**:2026-07-11
- **关联提交**:`bcce1f9`(引入缺陷)、`9552520`(修复)

### 背景

提交 `bcce1f9` 给 `local_database.dart` 的 `onUpgrade` 加了版本迁移逻辑,用裸 `ALTER TABLE ADD COLUMN`:

```dart
// 当时的写法
if (oldVersion < 4) {
  await db.execute('ALTER TABLE notes ADD COLUMN cover_thumbnail BLOB');
}
```

但旧版本(schema v2)的 `notes` 表**已有 `cover_thumbnail` 列**。SQLite 在列已存在时执行 `ALTER TABLE ADD COLUMN` 会抛 `duplicate column name`。该异常发生在 `onUpgrade` 回调内,导致 `openDatabase()` 整个 Future 抛错。

### 后果(事故)

- `LocalDatabase.open()` 失败 → `loadIndex()` 抛错 → `libraryIndexProvider` 进入 error 状态
- 表现:**Android 和鸿蒙端一打开就白屏/卡在启动界面**
- iOS/macOS/Web 因 schema 路径不同可能未触发,但逻辑缺陷相同

### 决策

新增列统一用幂等封装 `_safeAddColumn`,禁止裸 `ALTER`:

```dart
static Future<void> _safeAddColumn(db, table, column, type) async {
  try {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  } catch (_) {
    debugPrint('[FlowMuseCreateNote] _safeAddColumn: skip $table.$column');
  }
}
```

### 理由

- `CREATE TABLE IF NOT EXISTS` 已幂等,但 `ALTER TABLE ADD COLUMN` 没有 `IF NOT EXISTS` 语法。
- 老用户升级是高频路径,迁移必须对"已部分具备 schema"的库健壮。

### 遗留约束

1. 所有 schema 变更必须用 `_safeAddColumn`。
2. 必须同时验证 onCreate(全新安装)、onUpgrade(老用户升级)、onOpen(每次打开)三路径。
3. 改 schema 必须 bump `databaseVersion` + 加 `if (oldVersion < N)` 分支。
4. **不要假设用户从上一版本升级**——要从任意旧版本都能升上来。

---

## ADR-002:Excalidraw 格式兼容是不可破坏的硬约束

- **状态**:已采纳(持续生效)
- **来源**:`docs/项目说明/架构约束.md`

### 背景

FlowMuse 的白板内核自研(对外名 markdraw),但产品定位要求与 Excalidraw 生态互通(导入/导出/协作)。

### 决策

数据模型、场景 JSON、元素字段、版本字段、顺序字段、删除保留策略**优先与 Excalidraw 保持兼容**。

### 理由

- 用户可无缝导入/导出 Excalidraw 文件。
- 协作协议对齐 Excalidraw,降低协议设计风险。
- 手绘视觉风格**不是**强制目标,可做符合产品定位的非手绘渲染,但不得破坏数据兼容。

### 遗留约束

- 改 `Element` 基类或子类字段时,必须保证 Excalidraw JSON 编解码往返一致。
- 协作消息的 `elements` 必须是 Excalidraw 元素 JSON。
- 序列化采用容错解析(未知属性产生 `ParseWarning` 而非抛异常)。

---

## ADR-003:鸿蒙适配通过 vendor fork + dependency_overrides,不改上游包

- **状态**:已采纳
- **关联文件**:`FlowMuse-App/pubspec.yaml`、`FlowMuse-App/tool/vendor/`

### 背景

鸿蒙(OHOS)作为目标平台,但 Flutter 上游多个包不认识 `ohos` 这个 OS 标识:

- `code_assets` 包在 `OS.fromSyntax` 解析 `ohos` 时抛 `FormatException`。
- `path_provider` 上游无 ohos 实现。

### 决策

在 `tool/vendor/` 下放 fork 版本,通过 `pubspec.yaml` 的 `dependency_overrides` 覆盖:

```yaml
dependency_overrides:
  code_assets:
    path: tool/vendor/code_assets      # 仅加了一个 ohos 枚举值
  path_provider:
    path: tool/vendor/path_provider    # 含 ohos 支持的社区版
  path_provider_ohos:
    path: tool/vendor/path_provider_ohos
```

### 理由

- 改动最小(fork 只加 ohos 枚举值,对其他平台零影响)。
- 避免 fork 整个 Flutter SDK。
- 上游更新时可手动同步 vendor 目录。

### 遗留约束

- `tool/vendor/` 只做鸿蒙适配,**不放业务逻辑**(且已被 analyzer 排除)。
- 改 fork 包时必须在 `pubspec.yaml` 注释里记录原因,方便后续同步。
- 上游官方支持 ohos 后,需评估移除 override。

---

## ADR-004:鸿蒙探针分支(probe)合并到 main 时按功能重写,不直接 cherry-pick

- **状态**:已采纳(一次性决策,记录为范式)
- **来源**:`docs/研发记录/archive/probe-to-main-migration-audit.md`(2026-07-09)

### 背景

`markdraw-harmonyos-probe` 分支积累了大量鸿蒙实验性代码(手写笔、PDF、文件通道、持久化等),但其中很多与 main 的架构演进冲突(如 probe 用 JSON 文件存储,main 已统一到 SQLite)。

### 决策

合并时**逐提交审计**,按四类处理:

| 处理结果 | 含义 |
|----------|------|
| 跳过 | 已被 main 更优方案取代(如临时 OHOS stub) |
| main 已有 | 不重复迁移 |
| 重写迁移 | 与 main 架构冲突时按功能重写,不直接 cherry-pick |
| 文档迁移 | 文档类直接迁移 |

### 理由

- probe 分支的实验代码质量参差,直接合并会引入技术债。
- main 架构已演进(如 `CanvasLayout`、统一 SQLite),probe 旧实现需适配新架构。

### 范式价值

未来合并长期分歧分支时,沿用此原则:**逐提交审计 → 按 main 现状决定处理方式 → 冲突的按功能重写**。

---

## ADR-005:平台差异收敛在适配层,共享代码禁止 `Platform.is*`

- **状态**:已采纳

### 背景

一份 Dart 代码跑 6 个平台。早期若在业务代码里散落平台判断,会导致维护困难和跨端回归。

### 决策

平台差异一律走**条件导入**或**抽象接口 + 平台实现**:

| 差异类型 | 机制 | 示例 |
|----------|------|------|
| 编译期差异 | 条件导入(`if dart.library.io`) | `local_database_path*.dart` |
| 运行期差异 | 抽象接口 + 多实现 + 工厂选择 | `InputPolicySelector` 按设备选输入策略 |
| 鸿蒙原生能力 | Platform Channel + service 层封装 | `NativeHttpClient`、PDF/文件通道 |

### 理由

- 共享代码保持纯净,平台逻辑集中可维护。
- 新增平台时只加适配层,不动业务。

### 遗留约束

`lib/features/*` 和 `lib/shared/*` 内**禁止** `Platform.isAndroid` / `Platform.operatingSystem == 'ohos'` 等判断。平台分支必须在适配层内。

---

## ADR-006:本地存储统一用 SQLite(sqflite),应用设置用 `local_settings` 表而非 shared_preferences

- **状态**:已采纳

### 背景

项目早期(probe 分支)鸿蒙曾尝试文件式 key-value 存储(`AppKeyValueStore`)。但 main 架构选定了 SQLite 作为统一本地存储。

### 决策

- 笔记/笔记本/标签/场景:SQLite 结构化表。
- 应用设置(主题、侧边栏、访客名、最近封面等):SQLite 的 `local_settings` 表(key-value TEXT)。
- 敏感数据(token、ownerKey):`flutter_secure_storage`。

**不使用 shared_preferences**(虽然 pubspec 有依赖)。

### 理由

- 单一存储后端(SQLite)简化数据层,避免两套存储混用。
- `local_settings` 表支持 JSON 复杂值(如最近封面列表),shared_preferences 不便。
- 鸿蒙的 `shared_preferences_ohos` 适配成本高,统一 SQLite 更省事。
- 备份/恢复只需覆盖 SQLite 一处(`flowmuse-backup.json` 含 6 张表)。

### 遗留约束

- 新增应用设置项走 `LocalSettingsRepository`,不要引入 shared_preferences 调用。
- 备份格式版本(=2)与 DB schema 版本(当前为=5)是两个独立常量,勿混淆。

---

## ADR-007:协作层端到端加密,服务端零知识

- **状态**:已采纳

### 背景

协作场景涉及用户画板内容(可能敏感)。服务端需要转发和持久化数据,但不应该能读取内容。

### 决策

- 所有实时消息和快照用 **AES-GCM-128** 加密(roomKey 派生自房间链接)。
- 服务端只接收、转发、存储密文,永远无法解密。
- 房主额外持有 ownerKey(sha256 哈希后存服务端,用于结束房间的鉴权)。

### 理由

- 安全性:即使服务端被入侵或日志泄露,画板内容不暴露。
- 信任最小化:用户无需信任服务端运维方。

### 遗留约束

- 改协作层时不得让明文落库或明文传输。
- 加密相关改动必须跑 `collaboration_crypto_test.dart`。
- roomKey 只存在于客户端(链接 fragment `#room=roomId,roomKey`),不发给服务端。

---

## ADR-008:编辑器用不可变模型 + ToolResult 模式,而非直接状态修改

- **状态**:已采纳

### 背景

白板编辑器需要支持 undo/redo、实时协作合并、状态快照。若工具直接修改状态,这些能力都难实现。

### 决策

- `Scene` / `Element` / `EditorState` 全部不可变,变更返回新对象。
- `Tool`(工具)不直接改状态,而是产出 `ToolResult`(sealed class)。
- `EditorState.applyResult(result)` 用 switch 表达式把 result 折叠成新状态。
- `HistoryManager` 存 Scene 快照(非 diff),undo/redo 靠快照切换。

### 理由

- 天然支持 undo/redo(快照栈)。
- 天然支持协作合并(每个元素带 version/versionNonce,可做 last-writer-wins)。
- 解耦交互逻辑(Tool)与状态管理(EditorState),可独立测试。

### 遗留约束

- 新增元素类型时,要同时更新:Element 子类 + 序列化 + 渲染 + ToolResult 处理 + Excalidraw 编解码。
- 不要在 Tool 里直接持有可变状态,所有变更通过 ToolResult 表达。

---

## ADR-009:资料库用内存聚合根(SSOT),搜索在内存过滤而非 SQL

- **状态**:已采纳

### 背景

资料库有笔记、笔记本、标签、关联四类数据,首页、笔记本页、标签页、搜索页都要读。若每页各自查 SQL,会有重复查询和数据不一致。

### 决策

- `LibraryIndexNotifier`(provider `libraryIndexProvider`)在 `build()` 时 `loadIndex()` 一次性把全量数据读入内存,组装为 `LibraryIndex` 聚合根。
- 所有写操作走 Notifier 方法(内部调 repository + `refresh()` 重新加载)。
- 笔记本页、标签页、首页、搜索页都 `ref.watch(libraryIndexProvider)` 派生数据。
- 搜索(`LibraryIndex.notesForQuery`)在内存做子串匹配过滤,不查 SQL。

### 理由

- 单一数据源(SSOT),避免多查询导致的不一致。
- 搜索响应快(纯内存操作)。
- 写后自动 refresh,UI 自动更新。

### 遗留约束

- **不要**在 ViewModel 里直接 `LocalDatabase.open()`,一律走 `libraryIndexProvider`。
- 笔记量极大时可能需评估分页/索引,但当前规模内存方案足够。

---

## ADR-010:数据库用 `sqflite_common` + FFI 路径,而非标准 `sqflite`

- **状态**:已采纳
- **关联文件**:`lib/shared/storage/local_database_path*.dart`、`lib/shared/storage/local_database.dart`、`pubspec.yaml`

### 背景

标准 `sqflite` 包只支持 Android/iOS/macOS,不支持鸿蒙(OHOS)和 Windows。本项目需要所有 6 个平台访问同一套 SQLite 数据库。

### 决策

使用 `sqflite_common`(平台无关的 sqflite 抽象层),通过**条件导入**为不同平台提供数据库工厂:

```text
local_database_path.dart           # 条件导出(编译期选择)
├─ local_database_path_stub.dart   # Web:返回 stub 工厂
└─ local_database_path_io.dart     # 移动端/桌面/鸿蒙:FFI 或原生 sqflite
```

鸿蒙端额外预加载 `libharmony_sqlite.z.so`(FFI 模式),这在 `local_database_path_io.dart` 中处理。

### 理由

- 条件导入在**编译期**完成分支选择,零运行时开销。
- `sqflite_common` 的 API 与标准 `sqflite` 一致,上层 `LocalDatabase` 无需感知平台差异。
- 避免了为每个平台维护独立的数据库实现。

### 遗留约束

1. 数据库迁移逻辑(`onUpgrade`/`onCreate`)对所有平台**完全相同**,不要在此引入平台判断。
2. 鸿蒙端需要确保 `libharmony_sqlite.z.so` 在 native libs 中。
3. 改 schema 后必须在 Android + 鸿蒙两端验证(onCreate + onUpgrade)。

---

## ADR-011:PencilShader 在不支持平台静默降级,不阻塞启动

- **状态**:已采纳
- **日期**:2026-07-11
- **关联文件**:`lib/main.dart`、`lib/features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart`

### 背景

`PencilShader` 依赖 `FragmentProgram.fromAsset()` 加载 GLSL shader。但鸿蒙(`flutter_ohos`)不支持 FragmentProgram,部分桌面/Web 环境也可能加载失败。早期代码直接 `await PencilShader.init()` 无保护,在鸿蒙上会卡死启动流程。

### 决策

```dart
// main.dart
try {
  await PencilShader.init();
} catch (_) {
  // 平台不支持 shader,静默降级为无 pencil 纹理的渲染
}
```

### 理由

- 铅笔纹理是视觉增强,不是核心功能,不可因非关键特性阻塞启动。
- `FragmentProgram.fromAsset()` 在某些平台**挂起不抛异常**(已知 flutter_ohos 行为),需额外加 `.timeout()` 保护。
- 降级后编辑器渲染正常,只是少一层纹理特效。

### 遗留约束

- `PencilShader.init()` 必须在 `WidgetsFlutterBinding.ensureInitialized()` 之后调用。
- 不要删除 try-catch:未来新平台可能再次触发此问题。
- 改为可等待的 Future 后不要再移除保护逻辑。

---

## ADR-012:鸿蒙安全存储必须使用支持 OHOS 的 Dart facade

- **状态**:已采纳
- **日期**:2026-07-11
- **关联文件**:`lib/features/whiteboard/collaboration/repositories/collaboration_owner_key_store.dart`

### 背景

鸿蒙端创建协作房间时，服务端房间和初始场景已创建成功，但保存房主密钥时抛出 `Unsupported operation: unsupported_platform`。项目虽已注册 `flutter_secure_storage_ohos` 原生插件，协作代码却导入标准 `flutter_secure_storage` Dart facade；该 facade 不识别 `Platform.operatingSystem == 'ohos'`。

### 决策

对需要在鸿蒙运行的安全存储调用，使用 `flutter_secure_storage_ohos` 的 Dart facade。保留标准 `flutter_secure_storage` 依赖，使 Android、iOS、桌面和 Web 的既有插件注册与实现不变。

### 理由

- 原生插件已注册不代表 Dart 侧会选择该实现；facade 的平台分发同样是运行链路的一部分。
- OHOS facade 保持同一安全存储平台接口，并增加 `ohos` 选项分支，改动可收敛到实际调用点。
- 不全局替换或移除标准包，避免影响账户 token 和其他端的既有安全存储路径。

### 遗留约束

1. 新增需要在鸿蒙执行的 token、密钥或其他安全存储读写前，必须确认导入的 Dart facade 支持 `ohos`。
2. 不得仅因已添加/注册 OHOS 插件就假定安全存储可用；必须验证一次读写。
3. 调整安全存储依赖或 facade 时，验证 Android/桌面已有读写路径及鸿蒙创建房间后重进仍具房主权限。

---

## ADR-013:协作冲突解决用 LWW 而非 CRDT，ACK 走原生 Socket.IO

- **状态**:已采纳
- **日期**:2026-07-12
- **关联**:`docs/研发记录/research/collaboration/codex-best.md`、`SceneReconciler._shouldKeepLocal`

### 背景

协作实时同步出现卡顿和丢同步。调研阶段产出三份 AI 研究文档（claude/codex/zcode-best），在冲突解决机制上有关键分歧：LWW（Last-Writer-Wins）vs CRDT（无冲突复制数据类型）。同时需要确认 Dart 端 `socket_io_client 3.1.6` 是否支持 CSR（Connection State Recovery）和 ACK。

### 决策

- 冲突解决采用**元素级 LWW**（version 降序 + versionNonce 升序），不引入 CRDT。
- ACK 走 Socket.IO 原生 `EmitWithAck`，不自建 ACK 协议。
- Go 服务端用 `zishang520/socket.io v2.5.0`，原生支持 CSR 和 permessage-deflate。
- 选定 `codex-best.md` 为主线方案，吸纳 zcode-best 的性能项（Dirty Set、增量广播）和 claude-best 的运行环境补强。

### 理由

- LWW 实现简单、与 Excalidraw 的 version/versionNonce 字段天然契合；CRDT 需引入额外的 OpSet 和 tombstone 管理，复杂度过高。
- 通过 `socket_io_client 3.1.6` 源码验证：`_pid`/`recovered`/`_lastOffset` 均已实现（推翻了早期 grep 零匹配导致的误判），CSR 可用。
- ACK 走原生 API 避免自建协议的可靠性和乱序问题。

### 遗留约束

- 改 `SceneReconciler._shouldKeepLocal` 时必须同时更新 `ChangeAccumulator._shouldReplace`，二者比较逻辑必须一致（version + versionNonce）。
- 不要引入 CRDT 库或 OpSet 结构。
- CSR 作为 POC 验证，若实际恢复率不达标再考虑自建 resume 机制。

---

## ADR-014:鸿蒙图片选择用 `photoAccessHelper.PhotoViewPicker`，不用 `picker.DocumentViewPicker`

- **状态**:已采纳
- **日期**:2026-07-14
- **关联**:`ohos/entry/src/main/ets/file/FilePickerChannel.ets`、`lib/features/whiteboard/editor_core/src/ui/file_picker_channel_ohos.dart`

### 背景

工具栏「导入图片」在鸿蒙端点击后，系统弹出「文件管理 / 相册」来源选择界面，而非直接进入相册。根因是使用了 `@kit.CoreFileKit` 的 `picker.DocumentViewPicker`——它是通用文件选择器，会同时列出文件管理和图库两个入口。

### 决策

- 新增 `pickImage` 通道方法，使用 `@kit.MediaLibraryKit` 的 `photoAccessHelper.PhotoViewPicker` 打开图库。
- 保留原有 `pickFiles`（`DocumentViewPicker`）供通用文件选择（PDF 导入、备份导入等）使用。
- `PhotoViewPicker` 按 MIME 类型过滤（`PhotoViewMIMETypes.IMAGE_TYPE`），不接受后缀过滤器。

### 理由

- `PhotoViewPicker` 是系统图库选择器，调用后直接进入相册，无来源选择弹窗。
- `DocumentViewPicker` 仍用于非图片场景（PDF、markdraw 文件），不能全局替换。
- 该 API 是系统 picker，运行在系统进程中，无需申请额外权限。

### 遗留约束

- `PhotoViewPicker`、`PhotoSelectOptions`、`PhotoViewMIMETypes` 均属于 `@kit.MediaLibraryKit` 的 `photoAccessHelper` 命名空间，**不是** `@kit.CoreFileKit` 的 `picker` 命名空间。新增代码时不要混淆。
- `.ets` 原生改动热重载不生效，必须全量重编 HarmonyOS 工程。
- 媒体 URI 不能在 picker 回调内直接 `fileIo.openSync`，需 `await select()` 解开后再读取。

---

## ADR-015:安卓图片选择用 `startActivityForResult` + Photo Picker，不用 `ActivityResultContracts`

- **状态**:已采纳
- **日期**:2026-07-14
- **关联**:`android/app/src/main/kotlin/com/example/flowmuse/MainActivity.kt`、`lib/features/whiteboard/editor_core/src/ui/image_picker_channel.dart`

### 背景

安卓端「导入图片」通过 `file_picker` 插件的 `FileType.image` 实现，该插件走 `ACTION_PICK` + MediaStore Images，在部分国产 ROM 上仍会弹出来源选择。尝试用 Jetpack `ActivityResultContracts.PickVisualMedia` 改造，但 Kotlin 编译报 `Unresolved reference 'registerForActivityResult'`——Flutter 的 `FlutterActivity` 继承链锁定的 `androidx.activity` 版本无法解析该方法。

### 决策

- 安卓端新增 `flow_muse/image_picker` MethodChannel，在 `MainActivity` 中用 `startActivityForResult` + `onActivityResult` 处理。
- API ≥ 33（Android 13）用 `Intent("android.provider.action.PICK_IMAGES")` 启动系统 Photo Picker。
- API < 33 降级为 `ACTION_PICK` + MediaStore Images。
- 不引入 `androidx.activity:activity` 显式依赖，不使用 `ActivityResultContracts`。

### 理由

- `startActivityForResult` + `onActivityResult` 是 Android 经典 API，所有 API 级别原生支持，零额外依赖。
- `ACTION_PICK_IMAGES`（Android Photo Picker）直接进相册，不弹来源选择，且无需 `READ_MEDIA_IMAGES` 权限。
- `ActivityResultContracts` 虽然更现代，但在 Flutter 的 `FlutterActivity` 继承链下编译不通过，强行加依赖有版本冲突风险。

### 遗留约束

- `onActivityResult` 已被标记 `@Deprecated`，但这是 Flutter Activity 下最可靠的方式，**不要**为了消除 deprecation 警告而换回 `ActivityResultContracts`（除非 Flutter 升级后继承链变化）。
- 新增需要 Activity Result 的功能时，使用不同的 `requestCode` 常量避免冲突。
- Dart 端通过 `pickImageFromGallery()` 统一调用，鸿蒙走 `PhotoViewPicker` 通道、安卓走此通道，其他平台降级到 `file_picker`。

---

## ADR-016:网盘备份选定坚果云 WebDAV，不选百度网盘 OAuth

- **状态**:已采纳（待实施）
- **日期**:2026-07-15
- **关联**:`lib/features/settings/views/settings_page.dart`（cloudBackup 占位分区）

### 背景

设置页「网盘备份」分区为占位状态。选型阶段对比了三条路径：百度网盘开放 API、坚果云 WebDAV、自建服务器备份。百度网盘需要申请 AppKey + OAuth 2.0 授权码流程 + 移动端自定义 URL Scheme 回调，准入门槛和移动端适配成本高。自建方案需要扩后端 + 占服务器存储。

### 决策

- 网盘备份目标选定**坚果云 WebDAV**。
- 用户在设置页填入坚果云账号 + 应用密码，通过 WebDAV 协议上传加密备份。
- 不对接百度网盘，不自建服务器备份接口。

### 理由

- WebDAV 本质是 HTTP 扩展（PUT/GET/PROPFIND/MKCOL），项目已大量用 `http.Client()`，甚至可不引第三方包自写薄客户端。
- 坚果云无准入门槛，注册即用，用户生成「应用密码」即可，无需 OAuth、无需 AppKey 审核。
- 加密复用已有 `CollaborationCrypto`（AES-GCM-128），服务器零知识。
- 恢复逻辑复用 `LocalBackupRepository.importBackup()`（整库覆盖恢复）。
- 百度网盘的 OAuth 审核不确定、移动端回调 URL 在鸿蒙端兼容性未验证，风险过高。

### 遗留约束

- 现有本地备份**不含 `.scene` 溢出文件**（场景 >1MB 落到 `databases/scenes/` 目录），网盘备份必须补上这部分，打包格式为「6 张表 JSON + scenes 目录 → zip → 加密 → 上传」。
- 坚果云免费账户有流量限制（上传 1GB/月），需在 UI 提示用户。
- 凭证（邮箱 + 应用密码）用 `flutter_secure_storage` 存储，不存明文。
- 实施前需确认大文件上传的断点/重试机制。

---

## ADR-017:房主退出协作只能结束房间，不允许单独退出

- **状态**:已采纳
- **日期**:2026-07-14
- **关联**:`lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`、`lib/features/whiteboard/views/whiteboard_page.dart`

### 背景

协作房间有两种离开方式：「退出房间」（leave，仅断开本地连接，房间保留）和「结束协作」（end，调 HTTP `POST /rooms/{id}/end`，服务器标记 ended，所有成员被踢出）。房主此前可以通过三选一对话框选择「仅自己退出」，导致房间残留、其他成员无法继续协作但房间未关闭。

### 决策

- 房主的协作下拉菜单**不显示「退出房间」**，只显示「结束协作」。
- 房主按返回键触发离开时，直接走「结束协作」流程（弹出结束确认框），不提供「仅自己退出」选项。
- 普通成员不受影响，仍只有「退出房间」。

### 理由

- 房主是房间的唯一管理者（持有 ownerKey），房主单独退出后房间无法被结束，成为孤儿房间。
- 从产品语义上，房主「离开」等价于「不再管理这个房间」，应直接结束协作。
- 普通成员退出不影响房间存续，保持原有 leave 行为。

### 遗留约束

- 判断房主用 `CollaborationRoomMetadata.isOwner`（基于 `role == owner`），**不要**用 `ownerId` 比对当前用户 ID。
- 若未来支持「转让房主」功能，需重新评估此约束（转让后原房主变为普通成员，可退出）。

---

## ADR-018:协作创建者元数据经现有加密 presence 可选字段同步

- **状态**:已采纳
- **日期**:2026-08-26
- **关联**:`lib/features/whiteboard/collaboration/models/collaboration_message.dart`、`docs/研发记录/plans/2026-08-25-issue-8-collaboration-ownership-focus.md`

### 背景

Issue #8 需要元素创建者分组视图（归属显示与聚焦）。游客没有稳定 userId，socketId 在重连后会变化；若不在加密 payload 中广播稳定 creatorKey，游客头像与远端湿墨无法与重连前的元素关联。

### 决策

- `MOUSE_LOCATION`/`IDLE_STATUS`/`USER_VISIBLE_SCENE_BOUNDS` 三类消息的 AES-GCM 正文增加可选 `creatorKey`；不新增消息类型、不改 Socket.IO 事件、服务端零改动。
- 归属存于 `customData.flowMuse.collaborationOwner`（v1 schema：version/creatorKey/displayName/isGuest），仅用于显示，不参与权限、锁定或鉴权。
- 旧客户端忽略新字段；新客户端面对缺字段 presence 降级（禁用按作者聚焦、远端湿墨 fail-open 全亮）。
- 外部导出（.markdraw/.excalidraw/.json/库文件/PNG tEXt/SVG comment/分享）一律剥离该字段；内部 SQLite 与协作密文保留。

### 理由

- 复用现有加密通道，服务端保持零知识，无 schema/协议升级成本。
- 可选字段对旧客户端字节级兼容（缺省不写键）。
- creatorKey 可被客户端伪造，故严格限定为显示元数据。

### 遗留约束

- 改 presence payload 或 owner schema 时必须跑 `collaboration_message_test.dart`、`collaboration_owner_sync_test.dart` 与 `scene_reconciler_owner_test.dart`。
- analyze/format 门禁按 Issue 8 计划 v4 §13 固化（machine 格式 multiset 差 + 空值守卫）。
- `_shouldKeepLocal`/`_shouldReplace` 的 LWW 比较规则不得随归属逻辑改动（ADR-013）。

---

## ADR-019:手写转文字文本框紧包裹文字，识别产物样式优先于 sticky 默认样式

- **状态**:已采纳
- **日期**:2026-08-27
- **关联**:Issue #9、`editor_core/src/recognition/ink_text_sizing.dart`、`markdraw_controller.dart`（`_measuredTextElement`/`_elementFromRecognizedInk`/`applyResult`）、`docs/研发记录/specs/2026-08-27-issue-9-ink-text-box-sizing.md`

### 背景

手写转文字（自动 1 秒识别 + 手动"转文字"）生成的 `TextElement` 此前字号固定 20、尺寸取 `max(文本测量, 笔迹包围盒)` 只增不减，文本框远大于实际文字（Issue #9）。且 `applyDefaultStyleToElement` 的 sticky 默认样式会覆盖识别产物——用户改过一次字号/笔色后，"字号跟随手写"与"红笔出红字"会静默失效；自动识别入口在 freedraw 创建工具下转换时，`applyResult` 会对结果**二次**套用 sticky 样式且无重测量，紧框后表现为框/字号失配。

### 决策

- 横排文本框由 `TextRenderer.measure` 紧包裹（宽 = 测量宽+4、高 = max(测量高, 字号×行高)），垂直居中于笔迹包围盒；笔迹盒不再作横排尺寸下限。
- 字号由 `InkTextSizing.estimateFontSize` 从笔迹反推：高度主信号（CJK 0.9 / 拉丁 0.72 系数按占比插值），单个 CJK 扁平字迹宽度兜底（限幅 160），clamp 12–400；math 与智能排版公式分支一致（clamp 16–40）。
- 识别/锚点字号与源笔迹颜色**优先于 sticky 默认**：`_measuredTextElement` 在套用默认样式后写回；两条转换入口经 `applyResult(..., applyDefaultStyle: false)` 应用结果，跳过二次样式化。
- math（latex 源码测量 ≠ `Math.tex` display 渲染）不参与紧包裹：框不小于笔迹盒且高度含 2.4em 防裁剪余量；竖排模板锚点分支保持旧语义（字符数×行高）。

### 理由

- 笔迹高度是一次性信息，转换后不可再得，必须在此刻定字号；sticky 默认面向键入文本，两者语义不同层。
- 紧框即命中框，顺带修复"空白大框可点选"的怪异；`TextBoundsValidator` 只扩不缩，加载与协作同步不受影响。
- 替代方案"抽公共字号函数统一智能排版"被否：智能排版有 A4 占位体系依赖（clamp 12–48），统一化列为后续跟进，本议题不波及。

### 遗留约束

- 改字号估算或紧包裹公式必须跑 `ink_to_text_box_sizing_test.dart`（15 例，含 freedraw 激活态自动路径回归）。
- 新增转换入口必须传 `applyDefaultStyle: false` 并传入源笔迹主导色，否则 sticky 样式会覆盖识别产物。
- 服务端 JIIX 多元素相对坐标缺陷与智能排版路径同款 max 缺陷为已知问题，修复时需另行评审（见设计稿 §2）。

## ADR-020:五种笔刷渲染差异收敛为 BrushRenderProfile 单一真源,压感灵敏度创建时烘焙

- **状态**:已采纳
- **日期**:2026-08-28
- **关联**:Issue #5、`editor_core/src/core/elements/brush_render_profile.dart`、`editor_core/src/core/elements/element_visual_bounds.dart`、`editor_core/src/rendering/rough/freedraw_renderer.dart`、`markdraw_controller.dart`(`_encodeStrokePressure`)、`docs/研发记录/plans/2026-08-28-issue-5-pen-effects.md`

### 背景

五种笔刷此前共用同一 perfect_freehand 渲染管线,只有颜色/粗细不同,肉眼难辨(Issue #5);压感灵敏度是渲染期全局变量,改设置会改观已有笔迹,协作端之间还会漂移;命中/导出边界按几何 bbox 计算,宽笔(荧光笔)外缘选不中、导出裁边;Raster/SVG/边界三处各自维护宽度定义,已经漂移过。

### 决策

- 新增 `BrushRenderProfile.forType` 作为五笔渲染配置单一真源(sizeScale/opacityScale/thinningBase+Span/simulatedThinning/taper 距离/capStyle/compositeMode),Raster(含本地/远端湿墨)与 SVG 导出、命中边界共用。
- 压感灵敏度在笔迹创建时由 `_encodeStrokePressure` 烘焙进点序列,`customData.flowMuse.pressureEncoding="1"` 标记;渲染端对带标记笔迹按全灵敏度重放,旧笔迹按出厂默认灵敏度;全局灵敏度的渲染依赖删除(工具栏滑块仅对压感笔形可见,偏好仍保留)。
- 收锋(taper)按绝对距离判据(距端点 1×size 内 65%、2×size 内 85%),远端湿墨分段描边用 FreedrawTaperPhase(full/headOnly/tailOnly/none)保证整笔收针不被分段破坏。
- 荧光笔用包原生平头端帽(StrokeEndOptions cap:false)+ BlendMode.darken(禁 multiply/modulate,其 alpha 语义会吞噬透明层);铅笔纹理走构建期编译的 Fragment Shader(pubspec `shaders:` 段),不支持的端降级为确定性颗粒 Path(收锋区跳过)。
- 可视边界收敛 `elementVisualBounds`(size×(0.5+maxThinning×0.5)+2),Scene 命中/sceneBounds/ExportBounds/湿墨 margin 共用,删除 kMaxBrushSizeScale 第二套宽度表。

### 理由

- 单一真源避免 Raster/SVG/边界三处漂移(此前并存的三套宽度定义正是历史缺陷根源)。
- 创建时烘焙把灵敏度从全局渲染态变为笔迹自身属性:历史笔迹观感稳定、跨端一致;编码/重放互逆性经包源码验算并有用例守护。
- darken 在 Flutter/Canvas 与 SVG mix-blend-mode 两侧语义一致且 alpha 行为可控;深底变弱是混合数学的预期,不作特判。

### 遗留约束

- 新增笔形必须在 `BrushRenderProfile.forType` 补分支;渲染器/导出/边界层禁止按 brushType 写特判。
- 改 thinning/taper/边界公式必须跑 `brush_geometry_test.dart`、`freedraw_svg_renderer_test.dart`、`scene_freedraw_hit_test.dart`、`brush_integration_test.dart`(A1–A4/A15/A19/A20/A21 断言)与视觉矩阵门禁 `brush_visual_matrix_test.dart`。
- 压感编码只发生在 `MarkdrawController._encodeStrokePressure` 唯一入口;新增创建路径必须传编码后压力,不得在渲染端二次调制。
- freedraw 的 `points` 相对元素原点 `(x,y)`(渲染/SVG 导出按 points+(x,y) 还原绝对坐标);构造元素时 bbox 字段必须与点位一致,否则导出被裁。

## ADR-021:笔刷渲染双版本 BrushRenderVersion,family 为 core 纯枚举,自然介质 v2 走独立共享采样渲染链

- **状态**:已采纳
- **日期**:2026-08-30
- **关联**:计划 `docs/研发记录/plans/2026-08-30-pencil-brush-natural-media-redesign.md`、`editor_core/src/core/elements/brush_type.dart`(BrushRenderVersion/strokeRendererFamilyFor)、`editor_core/src/rendering/element_renderer.dart`(唯一 dispatch)、`editor_core/src/rendering/natural_media/*`(sampler/渲染器/缓存)、`rendering/export/svg_element_renderer.dart`、`collaboration/models/live_ink_chunk.dart`(LiveInkStyle.renderVersion)、分支 `feature/pencil-brush-natural-media-plan-v2`(732fa68…059bed0)

### 背景

T0 目标纸(用户确认)锁定 HB 铅笔与软头毛笔的自然介质质感:颗粒、浓淡、提按、毫丝、墨落,v1 perfect_freehand 管线原理上给不出。但圆珠笔/钢笔/荧光笔观感已被接受,v1 像素有冻结测试锁,存量文档与混合版本协作要求 v1 一个像素都不能动;同时 ADR-020 刚把五笔差异收敛到 BrushRenderProfile 单一真源,不能被第二条渲染链稀释成两套口径。

### 决策

- `customData.flowMuse.brushRenderVersion` 持久化双版本(classicV1/naturalMediaV2),缺失即 classicV1;仅铅笔/毛笔创建时默认写 v2(`defaultRenderVersionForNewStroke`),显式降级必须移除标记(`customDataWithFreedrawRender`)。
- **ADR-020 仍管 classic**:BrushRenderProfile 继续作为两种版本共用真源——classic 管线照旧消费它,v2 的密度/透明度/可见下限等常数(brushV2*/pencilV2* 族)同样收在 profile,不另立宽度表。
- `strokeRendererFamilyFor` 是 core 层**纯枚举**(不 import 渲染);唯一像素 dispatch 在 rendering 层单点 `element_renderer.dart`:`pressures.isEmpty ? classicV1 : strokeRendererFamilyFor(customData)`——无压力点的笔迹(含存量 v2 元数据防御分支)永远走 v1。
- v2 几何与种子的单一真源是 `NaturalMediaStrokeSampler`(fnv1a32/mul32/mix32 种子栈,源码禁 hashCode/Random);Canvas 渲染器、SVG 导出、本地/远端湿墨、命中 bounds 四链消费同一 plan,渲染器只做 plan→Path(v2 不申请 shader,鸿蒙无 FragmentProgram 的限制不波及 v2)。
- 分块一致性(远端湿墨 64 点冻结块)用"边归属"而非段间协商:边 i 连接点 i−1→i 归较后段,桥接边归较后段,入界 join 补 from 边半宽,每边终点补边界顶点;v2 段携带 4 个 leading 点(桥接边 3 边滤波窗 + join from 切线窗)。LiveInkStyle 增 renderVersion(缺失=1 旧客户端兼容;非铅笔/毛笔强制回退 1)。
- 性能门禁实测触发 T4-C 条件缓存 `NaturalMediaPathCache`:LRU 2048,缓存恒等矩阵 ui.Picture;键含 id/version/versionNonce/renderVersion/isComplete/strokeWidth/strokeColor/opacity/geometryVersion(paint 烘进的输入必须入键);湿墨调用全部绕过——远端 owned 分段由参数自动绕过,本地湿墨整笔帧(isComplete=false,几何逐帧追加)由缓存条件显式排除,否则第二帧命中首帧 Picture 会冻结活动笔迹。1000 元素静态 v2/v1 由 4.14 收敛到 ≤3.0 门禁(实测 2.3~2.8,余量为颗粒栅格化本征成本)。

### 理由

- 双版本而非改写 v1:v1 像素冻结(N1 摘要锁)是存量兼容的硬约束,重写等于无条件回归;版本字段让新笔迹渐进获得新质感、旧笔迹永不变样。
- family 纯枚举放 core、dispatch 放 rendering:core 不得依赖 dart:ui 渲染器;渲染链选择是像素语义,单点 dispatch 防止分叉在 SVG/湿墨/bounds 各处开花(SVG 与湿墨各自有同语义分支,但都读同一 family 枚举)。
- 分块用无状态边归属而非协商:乱序到达、块合并重放、与整笔渲染逐值一致,由 63/64/65 边界 key 并集测试与 90% mask 像素门双锁。
- 缓存 Picture 而非 Path:Path 重放仍需逐子路径录制,Picture 一次录制直接 drawPicture;miss 与命中重放同一 Picture 对象,逐字节一致由测试锁(曾因 miss 分支只录不绘丢毫丝/基底双绘被 N13 远端对照抓到,已改为"录制→存→立即重放"单一路径)。

### 遗留约束

- 新增笔形走 v2 必须同时落六处:BrushRenderProfile 常数、sampler 分支、Canvas 渲染器、SVG `_render*V2`、elementVisualBounds 分支、LiveInkStyle renderVersion 白名单;缺一处即三处口径漂移。
- 改几何/种子/曲线常数必须 bump `NaturalMediaPathCache.geometryVersion`,跑 natural_media 全套(687 测试,含 v1-lock)与验收矩阵;v1 任何像素变化都是回归。
- `strokeSeedOf(strokeId)` 是笔迹视觉身份:live strokeId 必须等于最终 ElementId(`ToolOverlay.creationStrokeId` 通路),预览/提交/远端三链路不得各自造 id,否则同笔三帧颗粒不一致。
- 缓存只对整笔静态渲染(isComplete=true)生效:调用方传 ownedEdgeStart、让渡起收所有权或元素未完成即自动绕过;不得手工构造缓存键,键字段变更须同步 keyFor 与注释里的"烘进 Picture"清单。

---

做出重要技术决策(选型、架构变更、约束确立)时,追加一条:

```markdown
## ADR-NNN:<决策标题>

- **状态**:已采纳 / 已废弃 / 已取代(被 ADR-XXX 取代)
- **日期**:YYYY-MM-DD
- **关联**:<提交/文件/issue>

### 背景
<为什么需要决策?遇到了什么问题?>

### 决策
<决定怎么做?>

### 理由
<为什么这么选?考虑过哪些替代方案?>

### 遗留约束
<这个决策给后续开发带来的硬性要求>
```
