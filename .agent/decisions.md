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
- **来源**:`docs/architecture_constraints.md`

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
- **来源**:`docs/probe-to-main-migration-audit.md`(2026-07-09)

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
- 备份格式版本(=2)与 DB schema 版本(=4)是两个独立常量,勿混淆。

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
