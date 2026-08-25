# FlowMuse Issue #8 协作元素归属聚焦——v4 执行计划

> Issue：[优化协作时元素归属显示](https://github.com/qinyre/FlowMuse/issues/8)
>
> 实施分支：`feat/issue-8-collaboration-ownership-focus`
>
> 代码基线：`origin/main@c40a847`（2026-08-25 拉取后创建分支）
>
> 文档状态：**第三轮聚焦复审修订版；R1/R3 已判“可行”，R2 唯一 Important 已修复，必要实现注记已补齐；按要求暂不启动第四轮复核；本提交只修订计划，不实现功能**
>
> 首版目标：在不改变共享 Scene、全局 z 序和协作 LWW 语义的前提下，显示元素创建者，并允许按创建者或“历史内容”聚焦；其他普通元素变淡但不消失。

---

## 0. 结论先行

本功能可行，但“每个人独占图层”只能实现为**作者逻辑分组视图**，不能实现为物理图层。

最终方案保持一个共享 `Scene` 和一条全局 fractional-index z 序，在普通元素的 `customData.flowMuse.collaborationOwner` 中记录不可变创建者。用户聚焦某位创建者时，画布仍按原顺序单遍绘制，只把不属于目标的普通元素按连续区段以 `0.22` 透明度合成。系统底图、正在编辑的本地反馈、协作光标和选择框始终全亮。

首版需要一项**客户端加法兼容的 payload 扩展**：现有端到端加密 presence 消息增加可选 `creatorKey`，用于让游客在 Socket 重连后仍能正确关联头像、元素和湿墨。除此以外，不增加消息类型，不修改 Socket.IO 事件，不修改服务端，不修改数据库，不引入 CRDT，不引入物理图层。

### 0.1 成功后的用户体验

1. 协作中新建的元素能显示“由谁创建”。
2. 点击顶部协作者头像，可聚焦该创建者；再次点击或点击退出按钮恢复全量视图。
3. 选中单个元素后，属性面板提供“查看张三的内容”；无创建者的旧元素显示“查看历史内容”。
4. 聚焦时，目标创建者元素保持全亮，其他普通元素变淡但仍保留空间上下文。
5. PDF 底稿、分页纸张、网格、协作光标、选择框、正在输入的文字和本地活动笔迹不变淡。
6. 聚焦仅是本机视图，不改变文档、不写历史、不保存、不广播，也不限制编辑。

### 0.2 首版明确不做

- 不创建每人一份 Scene、元素桶或 CustomPainter。
- 不改变元素 z 序，不把目标元素重绘到最上层。
- 不提供隐藏/solo、图层排序、图层拖拽。
- 不把归属用作权限、锁定或安全鉴权。
- 不支持归属转移、最后编辑者、编辑历史。
- 不由服务端签名或校验创建者。
- 不给历史元素自动猜测或回填作者。
- 不让游客跨房间、跨 App 重启，或在同一房间完整退出后再次加入时保持同一身份。完整退出再加入会形成新的逻辑创建者组；旧内容仍可从元素入口聚焦，新头像只聚焦新会话内容。
- 不自动 `zoomToFit`，不自动跟随协作者视口。
- 不在外部导出文件中携带创建者信息。

首版接受以下非阻断显示限制，不为它们增加新身份机制：空态只表示“暂无已提交内容”，可与尚未提交的活动湿墨短暂同屏；同名并发游客不增加会话编号；同一离线创建者若不同元素保存了不同历史名字，属性入口可随所选元素显示各自快照。若实际用户测试证明造成高频误解，再单独设计消歧交互。

---

## 1. 本版对前序方案的修订记录

| # | 前序描述 | 最终裁决 | 代码依据与原因 |
|---|---|---|---|
| R1 | 将非目标元素画一遍，再把目标元素整体重绘到最上层 | **否决；改为原 z 序单遍、连续变淡区段** | `static_canvas_painter.dart` 当前按 `scene.orderedElements` 顺序绘制；两遍绘制会让原本被覆盖的目标元素浮到上层，并拆散 Frame、箭头/绑定文字等跨元素关系 |
| R2 | 已有 owner 永远以本地值为准 | **否决；LWW 胜者优先，胜者缺失时才从败者回填** | 本地粘滞在双方非空但不同的病态场景会永久分裂；`SceneReconciler` 必须继续确定性收敛 |
| R3 | 登录用户键为 `hash(roomId|userId)` | **否决；登录用户键跨房间稳定，不含 roomId** | 本地笔记可从房间 A 保存后再发起房间 B；房间盐会让同一用户自己的旧元素与新头像无法匹配 |
| R4 | `.markdraw` 往返可按原 Element UUID 恢复 | **证伪；改为 split-pane 会话内 alias sidecar** | `SceneDocumentConverter` 为元素生成 `rect1` 等 alias；文本写 `id=alias`，解析后 alias 成为新元素 ID，原 UUID 不保留 |
| R5 | presence 明文携带 userId | **证伪；应用 presence 经 `_send()` AES-GCM 加密** | `collaboration_repository.dart::_send` 先 JSON 编码再加密；服务端可见的是房间成员元数据，不是消息正文 |
| R6 | 协作协议完全零改动 | **修正为服务端零改动、现有加密 payload 可选字段扩展** | 游客没有稳定 userId，socketId 重连会变化；若不广播稳定 `creatorKey`，游客头像和湿墨无法与重连前元素关联 |
| R7 | 外部导出在通用 Excalidraw codec 内剥离 | **否决；只在外部出口净化** | 通用 codec 同时服务本地持久化和协作，内部链路必须保留归属 |
| R8 | `.markdraw` 只要有 `id=` 就等价于元素身份稳定 | **收紧；仅在当前分屏会话 sidecar 中稳定** | 外部文件没有可信 sidecar；用户删除、修改或重复 alias 时必须按新元素或受控失败处理 |
| R9 | 只在本端 start/join 或 reconnect 时补发 creatorKey | **补充新成员触发：现有成员发现新 socket 后补发自身 presence** | 否则先在线且静止的 A 不会向后加入的 B 发送任何 presence，B 永远无法按 A 聚焦 |
| R10 | analyze 基线按 severity/code/file/line/message 比较 | **改用 `dart analyze --format=machine`，去掉位置字段并按 multiset 比较** | 本任务必改文件中的存量诊断会发生行号平移；含 line 必然假红，set 又会吞掉同键重复诊断 |
| R11 | tracked/untracked 格式门禁直接合并两个可能为空的 PowerShell 变量 | **在过滤器首项增加 `$_ -and` 空值守卫** | `@($null; $value)` 会保留 null；直接调用 `$_.EndsWith(...)` 会报错并可能使门禁被跳过 |

---

## 2. 当前代码事实基线

以下事实均按 `c40a847` 核验，实施前若 main 再变化，应重新核对调用点，不应死守本文行号。

| 主题 | 当前事实 | 主要文件 |
|---|---|---|
| 元素扩展字段 | `Element` 已有 `Map<String, Object?>? customData`，`copyWith` 默认保留 | `editor_core/src/core/elements/element.dart` |
| JSON 往返 | Excalidraw codec 写出并解析 `customData` | `editor_core/src/core/serialization/excalidraw_json_codec.dart` |
| 既有 FlowMuse 键 | `brushType`、`pageId`、`pdfBackground`、思维导图 `role`、智能排版字段已使用 `customData.flowMuse` | `brush_type.dart`、`canvas_layout.dart`、`mindmap_utils.dart`、`smart_layout_plan.dart` |
| 全局顺序 | Scene 按 fractional index 形成单一有序元素列表 | `editor_core/src/core/scene/scene.dart` |
| 静态渲染 | `StaticCanvasPainter` cull 后按 `scene.orderedElements` 单遍绘制；Frame clip、箭头标签清洞在元素循环内 | `editor_core/src/rendering/static_canvas_painter.dart` |
| saveLayer 先例 | `pendingElements` 预览使用外层 `saveLayer`；这只证明 API 路径可用，不证明大场景性能 | 同上 |
| 数学文字 | 静态层 `skipMathText: true`，最终数学文字在 Widget overlay 单独绘制 | `editor_canvas.dart` |
| 湿墨 | 本地和远端湿墨是独立绘制层；远端快照含 `senderSocketId` | `local_wet_ink_painter.dart`、`remote_wet_ink_painter.dart`、`remote_wet_ink_store.dart` |
| 协作者头像 | 顶部已有 `CollaborationParticipantBadge` 与 `_ParticipantAvatarStack` | `editor_core/src/ui/markdraw_editor.dart` |
| presence | `CollaboratorPresence` 有 socketId、userId、username、avatarUrl、isGuest，但无 creatorKey | `collaboration/models/collaborator_presence.dart` |
| 游客身份 | `CollaborationIdentity.guest` 的 userId 为 null；Socket 查询只携带 guestName/avatar | `account/models/collaboration_identity.dart`、`socket_io_realtime_transport.dart` |
| presence 加密 | mouse/idle/visible-bounds 均调用 repository `_send()`，正文经 AES-GCM | `collaboration_repository.dart` |
| LWW | `SceneReconciler` 以 version 高者胜，同 version 时 versionNonce 小者胜 | `collaboration/services/scene_reconciler.dart` |
| 批处理比较 | `ChangeAccumulator._shouldReplace` 必须与 reconciler 的 version/nonce 规则一致 | `collaboration/services/change_accumulator.dart`、ADR-013 |
| 本地变更入口 | 大多数新元素经 `MarkdrawController.applyResult` 的 `AddElementResult`/`CompoundResult`；仍存在少量直接 `_editorState.applyResult` 路径 | `editor_core/src/ui/markdraw_controller.dart` |
| 内部持久化 | 白板本地存储和协作适配使用 Excalidraw JSON，能保留 customData | `whiteboard_page.dart`、`whiteboard_collaboration_adapter.dart` |
| `.markdraw` | converter 为每个顶层元素生成 alias，serializer 输出 `id=alias`；customData 不写入文本 | `scene_document_converter.dart`、`sketch_line_serializer.dart` |
| 分屏编辑 | canvas→text 后 debounce parse，再 `applyScene/replaceScene` 整场替换 | `markdraw_split_pane.dart` |
| 外部出口 | 文件保存、分享、PNG/SVG 嵌入、Excalidraw/JSON、素材库存在多条调用链 | `markdraw_file_handler.dart`、`share_export_coordinator.dart`、`png_metadata.dart`、`svg_exporter.dart` |
| 双端测试 | 已有 `MemoryRealtimeRoomHub` / `MemoryRealtimeTransport`，无需拉起真实服务端 | `collaboration_repository_sync_test.dart` 等 |
| 依赖 | `crypto` 和 `uuid` 已存在 | `FlowMuse-App/pubspec.yaml` |

---

## 3. 产品语义与不可破坏的不变量

### 3.1 “归属”的唯一定义

归属 = **创建该元素实例的操作者**。

- 移动、缩放、旋转、改色、改字、重新绑定、删除，不转移归属。
- 复制、粘贴、从素材库实例化、导入为新元素、AI 生成、手写识别生成、智能排版确认生成，均产生新实例，归执行操作者。
- `TextElement.containerId != null` 的绑定文字是容器/箭头的派生视觉部分，始终继承父元素 owner；给他人形状补标签属于编辑原元素，不建立第二个可聚焦归属。
- 撤销/重做恢复原元素及其原归属。
- 删除 tombstone 保留原归属。
- 旧普通元素无归属，归入“历史内容”；不根据最后编辑者猜测。
- Canvas Page、PDF Background、网格、页面阴影等是系统底层，不参与创建者分组。

### 3.2 聚焦语义

聚焦目标只有三种：

```text
none                    不聚焦，所有内容按当前行为绘制
creator(<creatorKey>)   聚焦某位创建者
history                 聚焦所有无创建者的普通历史元素
```

系统底层在三种状态下都全亮。聚焦不改变命中测试、选择、编辑、保存、撤销和协作消息。

### 3.3 必须保持的技术不变量

1. Scene 仍是唯一文档 SSOT。
2. 元素仍按原 fractional index 顺序各绘制一次。
3. focus state 不进入 Scene、History、SQLite、导出或 Socket 消息。
4. 归属字段不参与权限判断。
5. LWW 的 version/versionNonce 比较规则不变。
6. 所有 `customData` 合并必须保留非归属字段。
7. 默认无聚焦路径不新增 `saveLayer`。
8. 服务端仍只处理既有密文和房间成员元数据，不解析创建者。
9. 共享 Dart 代码不增加平台分支，鸿蒙走同一逻辑。

---

## 4. 数据模型与身份规则

### 4.1 元素元数据

使用现有扩展位，不给每个 Element 子类增加正式字段：

```json
{
  "customData": {
    "flowMuse": {
      "collaborationOwner": {
        "version": 1,
        "creatorKey": "user:4f...",
        "displayName": "张三",
        "isGuest": false
      }
    }
  }
}
```

字段语义：

| 字段 | 规则 |
|---|---|
| `version` | 首版固定 1；未知高版本读取时只把合法公共字段用于显示，不崩溃 |
| `creatorKey` | 客户端稳定、伪匿名的逻辑分组键；不是账号 ID，不是权限凭据 |
| `displayName` | 创建时快照；创建者离线时作为回退显示 |
| `isGuest` | 创建时身份快照 |

不保存 `avatarUrl`：头像 URL 可能变化且会放大文档；在线时由 Presence 覆盖，离线时用名字首字或默认访客头像。

### 4.2 登录用户 creatorKey

```text
creatorKey = "user:" + sha256("flowmuse-creator-v1|" + userId)
```

- 不包含 roomId，保证房间 A → 本地笔记 → 房间 B 后同一用户仍能匹配自己的元素。
- 固定前缀用于域隔离，避免与现有房主 `ownerKeyHash` 混淆。
- 哈希只是避免在元素中直接写 userId，不构成匿名化或身份认证。
- 不新增依赖，使用已有 `crypto`。

### 4.3 游客 creatorKey

```text
creatorKey = "guest:" + roomId + ":" + sessionUuid
```

- `sessionUuid` 在首次加入该房间时生成。
- Socket.IO 自动重连期间复用。
- 完整退出/结束房间后清除；App 重启后改变可接受。
- 同一游客完整退出后再次加入同一房间时生成新键；这是新的逻辑创建者组，不与旧键合并。旧内容仍可从元素入口聚焦，新头像只代表新会话。
- 不使用 socketId，不使用可能重名的 guestName。
- 在 `WhiteboardPage` 协作会话内存态持有即可，不写 `LocalSettingsRepository`。

### 4.4 Presence 的最小兼容扩展

现有 `MOUSE_LOCATION`、`IDLE_STATUS`、`USER_VISIBLE_SCENE_BOUNDS` 的端到端加密 payload 增加可选：

```json
{"creatorKey": "guest:room:uuid"}
```

规则：

1. 新客户端发送三类 presence 时都带同一 creatorKey。
2. 首次 `start/join` 完成点直接复用现有 `IDLE_STATUS` 主动发送一次当前 presence；重连仅在 `reconnecting → joined` 转换时补发。不能依赖 broadcast 状态流重放，也不能等待用户先移动鼠标。
3. `WhiteboardPage` 在既有 `roomUsers` 订阅中比较前后 socket 集合；每批检测到至少一个新 socket 加入时，本端再补发一次自身 `IDLE_STATUS`。该补发调用 `_broadcastIdleState(..., force: true)`（或等价的现有底层发送入口），`force` 只绕过 `_lastIdleState == state` 的去重短路，普通 idle 更新仍保持原去重行为。无法可靠取得自身 socketId 时无需排除自己，允许一次幂等冗余补发；只响应新增 socket，不响应离开、改名或普通 presence，批内只发一次，避免风暴和回环。这样后加入的 B 即使面对全程静止的 A，也能收到 A 的 creatorKey。
4. 接收端把它写入 `CollaboratorPresence.creatorKey`。
5. 登录用户在字段缺失时可由 presence.userId 本地推导，用于兼容旧客户端。
6. 游客字段缺失时不得按 username 猜测；头像暂不可按作者聚焦，远端湿墨 fail-open 全亮。
7. 未知字段由旧客户端忽略；不增加消息类型和 Socket 事件。
8. creatorKey 随现有消息正文加密，不新增服务端明文字段。
9. 该字段仍可被客户端伪造，只服务于视觉显示。

此处是首版唯一的协作 payload schema 扩展，也是 Claude 审查必须重点确认的兼容项。

### 4.5 读取与深合并规则

新增集中式 helper，禁止各调用点手写多层 Map。依赖边界如下：

- `editor_core` 新增的 owner 值对象、customData codec、系统元素判定和外部 sanitizer 不读取账号、不计算用户身份，也不新增对 collaboration/account 的 import。
- `collaboration` 内只放 userId/guest session → creatorKey 的身份派生，并调用 editor_core 的纯数据 helper。
- 基线已有 `editor_canvas.dart`、`markdraw_editor.dart`、`remote_wet_ink_painter.dart` 对 `remote_wet_ink_store.dart` 的三处反向 import；本任务不顺带重构它们。T6 穿透现有 UI 层的参数只能是 `String?`、`bool`、只读 `Map<String, String>`、元素 ID 集合/修订号等纯数据，不能再传入 collaboration 业务模型。

纯数据 helper 提供：

- `readCreator(Element)`：校验层级和类型，非法值返回 null。
- `withCreator(Element, CollaborationCreator)`：深合并 `customData` 和 `flowMuse`，只覆盖 `collaborationOwner`。
- `withoutCreator(Element)`：只删除 `collaborationOwner`；若 `flowMuse` 仍有其他键必须保留。
- raw JSON 版本用于 reconciler：同样只触碰目标嵌套键。

所有 helper 和 reconciler 修复必须 copy-on-write：未改元素可复用，发生 owner 改动时至少新建元素 Map、`customData`、`flowMuse` 和 `collaborationOwner` 路径；不得原地修改输入列表或嵌套 Map。系统元素判定直接复用既有 `isCanvasPage` / `isPdfBackground` getter，不复制第二套键位判断。

必须通过测试锁定 `brushType`、`pageId`、`pdfBackground`、mindmap `role`、智能排版字段和顶层识别字段不丢失，并断言 reconcile 前后的 local/remote 输入对象内容不变。

---

## 5. 元素生命周期与合并规则

### 5.1 编辑器核心的依赖边界

`editor_core` 不直接 import collaboration 业务模型。由宿主给 `MarkdrawController` 注入一个可空的通用本地结果预处理回调：

```dart
ToolResult Function(ToolResult result, Scene currentScene)?
    onPrepareLocalResult;
```

执行顺序固定为：

```text
ToolResult
  → viewport constraint
  → default style
  → onPrepareLocalResult（仅本地用户变更）
  → clipboard side effect
  → EditorState.applyResult
  → history / scene changed / collaboration broadcast
```

远端 `applyRemoteScene/applyRemoteElements`、undo/redo、reset，以及未来新增的非 `userEdit` 来源不走“新建者盖章”。分屏整场替换走第 9 节 sidecar 规则。

实施时必须把 `MarkdrawController` 内直接调用 `_editorState.applyResult` 的本地创建/更新路径收口到同一内部 helper；不得只覆盖公开 `applyResult` 后假定所有路径都已盖章。

### 5.2 本地 ToolResult 归属变换

递归处理 `CompoundResult`：

| Result | 处理 |
|---|---|
| `AddElementResult` 普通独立元素 | 无论传入是否自带 owner，覆盖为当前操作者；防止粘贴/导入冒用旧归属 |
| `AddElementResult` 绑定文字 | 从同一 CompoundResult 新父元素或当前 Scene 父元素继承 owner；父元素无 owner 则绑定文字也无 owner |
| `AddElementResult` 系统元素 | 删除/不写 owner；Canvas Page、PDF Background 保持系统身份 |
| `UpdateElementResult` 已有 owner | 强制保留 Scene 中旧 owner，忽略更新对象中的缺失或变化 |
| `UpdateElementResult` 旧元素无 owner | 继续无 owner；编辑历史内容不转移归属 |
| `RemoveElementResult` | Scene soft-delete 自然保留 customData |
| clipboard/file/selection/viewport | 不处理 |
| `SwitchToolResult` / `SetSmartLayoutResult` | 不含元素变更，不处理 |

复合创建（容器+绑定文字、箭头+标签、思维导图节点/文字/边、流程图、AI/识别/智能排版产物）中的独立新元素获得当前 creator，绑定文字通过父元素继承同一值。递归 CompoundResult 处理必须能看到同批次先新增的父元素，不能只查变更前 Scene。

### 5.3 协作 reconciler 的确定性修复

保持现有 `_shouldKeepLocal` 完全不变。先按现有规则选出 winner/loser，再做归属修复：

| winner owner | loser owner | 输出 |
|---|---|---|
| 有 | 无 | winner 原样 |
| 无 | 有 | 把 loser owner 深合并回 winner |
| 无 | 无 | 无 owner |
| 相同 | 相同 | winner 原样 |
| 不同且都非空 | 不同且都非空 | 保留 LWW winner；只增加脱敏冲突计数 |

理由：

- “winner 缺失时回填”能修复某条重建/旧客户端链路剥离 customData 的情况。
- “双方冲突时 winner 生效”保证交换 local/remote 参数后结果仍收敛。
- 不改比较函数，因此无需修改 `ChangeAccumulator._shouldReplace`；若实施中确实改了比较逻辑，必须遵守 ADR-013 同步更新两处。

完成全部元素 winner 选择后，再做一次确定性父子规范化：对 `containerId` 非空的绑定文字，以**结果集中父元素**的 owner 覆盖自身 owner；父元素无 owner 或不存在时清除绑定文字 owner。该后处理不改 version/versionNonce，所有客户端面对同一结果集会得到相同输出。

winner 回填和父子规范化均必须构造新的输出元素 Map；不得在 winner、local/remote 输入或其嵌套 `customData` 引用上原地写入。测试除验证输出外，还要保存输入深拷贝并断言 reconcile 后输入完全不变。

日志只允许：

```text
ownerConflictCount=1 ownerBackfillCount=1
```

禁止记录 creatorKey、displayName、userId、元素正文。

### 5.4 兼容旧客户端

- 旧客户端创建的元素无 owner，新客户端显示为历史内容。
- 旧客户端编辑新元素若保留 customData，owner 正常；若剥离，reconciler 从 loser 回填。
- 旧客户端忽略 presence.creatorKey，不影响既有协作。
- 新客户端面对旧游客 presence 时不猜作者，功能降级但协作不失败。

---

## 6. 聚焦状态与交互设计

### 6.1 状态归属

聚焦状态由 `WhiteboardPage` 持有为纯本地内存态，例如：

```dart
sealed class CollaborationFocusTarget {
  const CollaborationFocusTarget();
}
final class CreatorFocus extends CollaborationFocusTarget {
  const CreatorFocus(
    this.creatorKey, {
    required this.labelSnapshot,
    required this.isGuest,
  });
  final String creatorKey;
  final String labelSnapshot;
  final bool isGuest;
}
final class HistoricalFocus extends CollaborationFocusTarget {
  const HistoricalFocus();
}
```

`labelSnapshot` 只是离线回退值：只要存在同 `creatorKey` 的在线 Presence，focus pill 和属性入口都显示显示层代表项的当前名字，并持续把 `labelSnapshot` 更新为该最后已知在线名；离线后回退到这个最新快照，不倒退到进入聚焦时的旧名。重连交叠期的名字和头像也必须取 §6.2 选出的同一个代表 socket，禁止从另一个 Presence 任意取值。不需要 Riverpod 全局 provider，不需要数据库，不需要 feature flag。房间退出/结束时清空；普通 Socket 重连时保留。

所有“是否聚焦同一创建者”、头像再次点击退出和 focus 对象更新都按 `creatorKey` 值比较，禁止依赖 `CreatorFocus` 对象 identity。

### 6.2 顶部头像

扩展现有 `CollaborationParticipantBadge`：

- 增加可空 `creatorKey`。
- 增加 `focused` 状态和点击回调。
- 当前用户和远端登录用户都有 creatorKey。
- 旧游客 creatorKey 缺失时头像仍显示，但禁用“按作者聚焦”，tooltip 使用中性文案“暂不可按归属聚焦”，不承诺稍后一定同步成功。
- `_ParticipantAvatarStack` 继续最多直接显示 5 个头像，但 `+N` 必须可点击并打开完整参与者列表；列表中的每个可识别参与者都可聚焦，缺少 creatorKey 的参与者显示同一禁用态。
- 非空 creatorKey 的去重只发生在头像/完整列表显示层，不删除 `collaborators` map，也不丢弃任何 socketId→creatorKey 映射。重连交叠时代表项按 `active > idle > away` 选择，状态相同以 socketId 做确定性排序；名字和头像复用同一代表项。当前用户的 badge 作为其 creatorKey 的本端代表，与自己同 creatorKey 的其他设备不再另显示 badge，但其 socket 映射仍保留；第三方也只显示该 creatorKey 的一个代表项。creatorKey 缺失的旧游客仅按 socket 显示，不能合并或猜测。
- 点击未聚焦头像 → 聚焦；点击已聚焦头像 → 退出；点击另一头像 → 切换。
- 离线创建者不进入在线头像堆叠，但可从其元素入口聚焦。

### 6.3 元素入口

首版不新造右键菜单系统，复用现有桌面/紧凑属性面板：

- 仅单选普通元素时显示。
- 有 owner：`由 张三 创建` + `查看张三的内容`。
- 无 owner：`历史内容` + `查看历史内容`。
- 系统元素不显示入口。
- 在线同 creatorKey 时使用 §6.2 代表项的名字/头像；离线用持续刷新的最后已知快照。

为避免 editor_core 依赖 collaboration，向 `PropertyPanel` / compact panel 传一个可空的通用 action resolver；由宿主根据选中元素返回 label 和 callback。不要在属性面板解析 `customData.flowMuse.collaborationOwner`。

最小接口使用 Dart record 即可，不新增 action 类层级：

```dart
({String attributionLabel, String actionLabel, VoidCallback onPressed})?
    Function(Element element)? attributionActionResolver;
```

### 6.4 聚焦状态提示

顶部协作区域显示可退出状态 pill：

```text
正在聚焦：张三    [退出]
正在聚焦：历史内容 [退出]
```

规则：

- 创建者离线后保持聚焦，直到用户手动退出。
- 空态按整个 Scene 的已提交元素判断：目标组没有任何未删除普通元素时保持聚焦和退出入口，creator focus 显示“该创建者暂无已提交内容”，history focus 显示“暂无已提交的历史内容”；目标组新增/恢复任一元素后立即消失。仅内容在视口外不显示空态；目标活动湿墨尚未提交时可与该提示短暂同屏，文案不声称“无人正在书写”。
- 房间退出/结束清空。
- 进入 `zenMode` 或 `viewMode` 时立即清空 focus，避免协作 chrome 被隐藏后失去退出入口；若此前确有 focus，复用现有轻提示机制显示一次“已退出协作者聚焦”。退出这些模式不会自动恢复旧 focus。
- 不自动缩放或移动视口。
- 聚焦时仍可命中和编辑变淡元素。
- 被选中、拖动或正在编辑的普通元素本体临时恢复全亮，操作结束后重新按当前 focus 分类；这只是本地反馈，不改变归属或交互权限。
- 框选拖动过程不算“元素拖动”：框选矩形本身始终全亮，框内元素在松手成为选中集后才加入本地高亮。
- 离线游客旧会话从元素入口聚焦时，属性入口和 pill 都在快照名后加“（历史会话）”；同一 creatorKey 的 Presence 重新在线时立即去掉后缀。完整退出后用新 creatorKey 重进不算重连，旧组继续保留后缀；不显示 creatorKey，也不尝试按同名合并。

---

## 7. 静态画布渲染方案

### 7.1 分类函数

静态 painter 直接复用 editor_core 内的 owner 纯数据 helper，并接收可比较的视图标量和本地高亮元素集合/修订号：

```dart
String? focusedCreatorKey;
bool focusHistoricalContent = false;
Set<ElementId> locallyHighlightedElementIds = const {};
int localHighlightRevision = 0;
```

前两者分别表达 creator focus 和 history focus；都为空/false 即无 focus。本地高亮集合含当前已选中、正在移动或正在编辑的元素；若编辑的是绑定文字，还必须加入其父容器/箭头 ID。集合以 `Set.unmodifiable` 新快照传入，宿主仅在集合内容变化时递增 `localHighlightRevision`；painter 只比较 revision，禁止对 Set 使用 `identical` 或 `==`。这些状态不进入文档。editor_core 只理解元素扩展数据，不读取账号、Presence 或房间业务。

分类顺序必须是：

1. 无 focus → `1.0`。
2. Canvas Page / PDF Background / 其他系统底层 → `1.0`。
3. 当前选中、拖动或正在编辑的静态元素 → `1.0`。
4. creator focus 且 owner 相同 → `1.0`。
5. history focus 且无 owner → `1.0`。
6. 其余普通元素 → `0.22`。

### 7.2 单遍连续区段算法

禁止“非目标一遍 + 目标第二遍”。按当前 `visible` 顺序遍历：

```text
dim=false
for element in visible:
  alpha = classify(element, focusedCreatorKey, focusHistoricalContent)
  if alpha<1 and dim=false: open dim saveLayer; dim=true
  if alpha=1 and dim=true: restore dim saveLayer; dim=false
  draw element using existing frame clip / arrow label flow
after loop: if dim=true restore
```

约束：

- 每个元素最多调用一次 `ElementRenderer.render`。
- 现有 parent Frame 的 `save/clip/restore` 必须保持在区段层内部。
- 现有箭头+绑定文字的嵌套 `saveLayer` 必须保持不变。
- `previewElement`、`pendingElements` 在主循环之后继续全亮绘制。
- Grid、分页背景、PDF、page shadow 在分组层外全亮。
- `StaticCanvasPainter.shouldRepaint` 和 `RemoteWetInkPainter.shouldRepaint` 都纳入两个 focus 标量。仅当旧/新任一状态存在 focus 时，静态层才比较 `localHighlightRevision`，远端湿墨层才比较 socketId→creatorKey 映射的 `presenceCreatorRevision`；两端都无 focus 时，这两个 revision 单独变化不触发重绘，因为分类恒为 1.0。映射 revision 只在内容变化时递增，保证 focus 中的 late presence/reconnect 无需等待下一笔也会重新分类。

### 7.3 为什么不做“两遍重绘”

假设全局顺序是 `A(张三) → B(李四) → C(张三)`。聚焦张三后若先画 B 再把 A/C 画上层，A 会越过 B，改变遮挡关系。单遍区段保持 A→B→C，符合“变淡但不消失”，也避免拆开 Frame、箭头端点和绑定文字。

### 7.4 性能事实与门禁

连续区段数取决于全亮/变淡交替次数。最坏的作者交替场景仍可能达到 O(N) 个 saveLayer，不能只用平均场景证明性能。

首版门禁采用结构化指标，不虚构毫秒 SLO：

| 场景 | 必测指标 |
|---|---|
| 无 focus，1000/5000 元素 | 新增 saveLayer = 0；元素 render 次数不增加 |
| 全部非目标且无本地高亮 | dim saveLayer = 1 |
| 全部目标 | dim saveLayer = 0 |
| 交替目标/非目标 | saveLayer 数 = 连续 dim 段数；元素最多画一次 |
| creator focus + 跨 owner 多选/拖动，1000/5000 元素 | saveLayer 数 = 纳入本地高亮后的连续 dim 段数；高亮变化不增加元素 render 次数 |
| PDF + 批注 | PDF/页面全亮，批注按 owner 分类 |

“元素 render 次数不增加”通过 test-only Canvas spy/wrapper 分开统计几何 `draw*` 与 `saveLayer`：同一 Scene 的 focus/no-focus 几何 draw-call 数必须相等；dim `saveLayer` 不参与等量比较，单独断言为“连续 dim 段数 + 基线已有嵌套层数”。不为此加入生产环境埋点。该指标是结构代理，真机性能仍以 Profile/GPU 数据为准。

保留但首版不同时实现的 fallback：如果鸿蒙真机 Profile/GPU 数据证明 saveLayer 方案不可接受，再改为 renderer alpha multiplier。fallback 会让重叠元素出现叠加变暗，是已知视觉取舍，必须另开决策，不在本任务同时维护两套渲染路径。

---

## 8. 湿墨、文字与其他 Overlay

### 8.1 明确行为表

| 层/状态 | 聚焦目标内 | 聚焦目标外 | 映射失败 |
|---|---:|---:|---:|
| 已提交普通元素 | 1.0 | 0.22 | 按历史内容 |
| 本地活动湿墨 | 1.0 | **仍为 1.0** | 1.0 |
| 远端活动湿墨 | 1.0 | 0.22 | **fail-open 1.0** |
| 本地创建预览/AI/流程图/思维导图预览 | 1.0 | 1.0 | 1.0 |
| 正在编辑的 Text Overlay | 1.0 | 1.0 | 1.0 |
| 最终 Math Overlay | 1.0 | 0.22 | 按元素 owner |
| Frame label 编辑 Overlay | 1.0 | 1.0 | 1.0 |
| Selection/handles/link icons | 1.0 | 1.0 | 1.0 |
| 远端光标/用户名/选区 | 1.0 | 1.0 | 1.0 |
| Grid/Page/PDF/shadow | 1.0 | 1.0 | 1.0 |

本地活动笔迹必须全亮，否则用户聚焦别人时会在 22% 的反馈中书写，直接破坏跟手感。笔迹提交为 Element 后再按当前用户 owner 分类，因此聚焦他人时允许在提交瞬间从 1.0 跳到 0.22；首版不加动画，避免拖慢连续书写反馈。

被选中、拖动或正在编辑的已提交元素本体与其 selection/handles 一并临时全亮；操作结束后恢复 owner 分类。远端湿墨在映射缺失时全亮、同作者已提交元素可能已变淡，允许出现约 5–15 秒的暂态不一致，作为 fail-open 的已知取舍。

### 8.2 远端湿墨映射

`RemoteWetInkStrokeSnapshot.senderSocketId` → `CollaboratorPresence.creatorKey` → focus 分类。

- socketId 只用于查当前 Presence，不写入元素。
- 游客重连后通过新 presence 中相同 creatorKey 恢复关联。
- 未收到 creatorKey、presence 已离线或乱序时全亮；不得缓存错误 owner。
- 远端 cache 中的冻结 Picture 不能被永久预乘某个 focus alpha，否则切换 focus 后需重录全部几何。优先在绘制每个 stroke cache 时包一层临时 alpha，不改几何缓存。
- 首版允许逐 stroke 临时乘 alpha；每层必须使用实际渲染笔迹包围盒，余量按应用 `brush.sizeScale` 和压力变粗后的最大有效线宽，再加抗锯齿安全边界计算，禁止只按名义 `strokeWidth/2` 或使用 `saveLayer(null, ...)` 形成全屏层。用粗笔、最大压力和边缘像素测试兜底裁边风险。远端 store 上限 64 strokes，先不增加连续段合并。只有真机 Profile 证明这里成为瓶颈时再优化。

### 8.3 数学文字

`_MathTextOverlay` 复用现有颜色路径，将 focus alpha 乘入 `element.opacity` 后通过 `withValues(alpha: ...)` 绘制，不额外包 `Opacity` Widget/saveLayer；但元素 ID 在本地高亮集合中时跳过 focus alpha、保持全亮。正在文本编辑的公式由编辑 overlay 保持全亮。测试必须覆盖普通数学公式、被选中数学公式和错误回退文本。

---

## 9. `.markdraw` 分屏、复制与素材库边界

### 9.1 分屏 sidecar

`.markdraw` 文本不承载 owner，这是外部格式兼容边界。仅在当前 `MarkdrawSplitPane` 生命周期内维护：

```text
alias -> CollaborationCreator
```

canvas→text：

1. 使用与 `serializeScene` 相同的 `MarkdrawDocument` 构建结果。
2. 从 `doc.aliases` 获得 alias→原 ElementId。
3. 从当前 Scene 读取 owner，生成 sidecar。
4. sidecar 不写入文本、不写数据库、不进剪贴板。

text→canvas：

1. 先检测重复 `id=alias`；重复时显示可读 parse error，保留上次成功画布，不随机继承。
2. parser 输出元素 ID 为 alias；alias 命中 sidecar则恢复原 owner。
3. alias 新增、删除后重加但已不在 sidecar、或用户改名 → 视为当前操作者创建的新元素。
4. 保留 alias 但改变元素类型 → 保留 owner，因为用户是在编辑同一逻辑行。
5. 绑定文字没有独立可用行/alias时，从容器或箭头继承 owner。
6. 系统元素仍清除 owner。
7. 应用成功后不立即丢 sidecar；后续 canvas 侧真实变化触发重新序列化时再重建。

不得写“按原 UUID 恢复”；验收只按 alias sidecar。

### 9.2 Clipboard

- `.markdraw` 剪贴板不携带 owner。
- 粘贴产生新的 `AddElementResult`，统一盖当前 creator。
- 即使未来剪贴板带 customData，本地 Add 规则也必须覆盖为当前 creator。

### 9.3 素材库

- 从当前场景添加进素材库时，外部库产物必须剥离 owner。
- 从 `.markdrawlib` / `.excalidrawlib` 实例化到协作 Scene 时，实例归当前操作者。
- 素材模板本身不保留协作身份。

---

## 10. 内部持久化、外部导出与隐私

### 10.1 保留 owner 的内部链路

- 当前内存 Scene。
- 本地 SQLite/溢出 scene 文件中的 Excalidraw JSON。
- 协作 SCENE_INIT / SCENE_UPDATE 密文。
- 加密远端快照。
- 临时房间“保存到本地”的 Excalidraw JSON。

不得在通用 `ExcalidrawJsonCodec.serialize` 中默认剥离。

### 10.2 必须剥离 owner 的外部产物

- `.markdraw`。
- `.markdrawlib` / `.excalidrawlib`。
- 外部 `.excalidraw` / `.json`。
- PNG tEXt 内嵌 Markdraw 数据。
- SVG HTML comment 内嵌 Markdraw 数据。
- 系统分享中的 PNG、Markdraw、Excalidraw 文件。
- 外部文档协调器重新输出的文件。

剥离只删除：

```text
customData.flowMuse.collaborationOwner
```

其他 `customData` 和 `flowMuse` 键必须保留。

### 10.3 单一外部出口机制

新增纯函数 `sanitizeSceneForExternalExport(Scene)`，返回不可变拷贝。控制器提供显式外部 API，例如：

```text
serializeScene(...)                  内部，保留 owner
serializeSceneForExternalExport(...) 外部，先 sanitize
exportPng/exportSvg                  外部，内部统一 sanitize
exportLibraryContent                 外部，统一 sanitize library items
```

`MarkdrawFileHandler` 和 `ShareExportCoordinator` 只能调用外部 API；`WhiteboardCollaborationAdapter` 和本地自动保存只能调用内部 API。

实施验收增加调用点门禁：检索 `ExcalidrawJsonCodec.serialize`、`serializeScene`、`PngExporter.export`、`SvgExporter.export`、`LibraryCodec.serialize`、`ExcalidrawLibCodec.serialize`，并审计 `DocumentService.save/convert`，逐一登记“内部保留/外部剥离”。`exportSmartLayout` 只输出 md/tex、没有 Scene 数据，登记为无需净化。不能只测 helper 而不测最终产物。

### 10.4 外部导入

外部文件中的 `collaborationOwner` 不可信：

- 打开为普通本地笔记时先剥离，元素成为历史/无归属。
- 作为新元素插入协作 Scene 时由 Add 规则归当前操作者。
- 内部本地笔记恢复和协作快照不是“外部导入”，不得剥离。

---

## 11. 详细任务拆解

### T1｜创建者模型、键生成与深合并 helper

**目标**：建立唯一的数据读写入口，不触碰 UI/渲染。

**主要文件**：

- 新建 `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart`
- 新建 `FlowMuse-App/lib/features/whiteboard/collaboration/services/collaboration_creator_identity.dart`
- 新建 `FlowMuse-App/test/features/whiteboard/editor_core/collaboration_element_owner_test.dart`
- 新建 `FlowMuse-App/test/features/whiteboard/collaboration/collaboration_creator_identity_test.dart`

**工作项**：

1. 在 editor_core 定义 version、creatorKey、displayName、isGuest 的不可变值对象。
2. 在 collaboration service 实现登录用户 SHA-256 key 和游客 session key。
3. 在 editor_core 实现 Element/raw JSON 读取、深合并、删除、系统元素判定。
4. 在 editor_core 实现外部 Scene sanitizer，供 controller/exporter 使用。
5. 对 malformed/unknown version 做安全降级。
6. 用 import 边界测试证明本任务新增的 owner/codec/sanitizer 文件不 import collaboration/account；基线已有三处 remote-wet-ink 反向依赖作为明确例外，不要求本任务清理。

**完成判据**：

- 同一 userId 跨 room 得到相同 key；不同 userId 不同。
- guest 同 room/session 稳定，换 session 改变。
- 写/删 owner 不丢任何其他 customData。
- 页面/PDF helper 正确识别。
- 无新依赖。

### T2｜协作会话身份与加密 Presence 兼容扩展

**目标**：让在线头像、远端湿墨与 creatorKey 稳定关联，覆盖游客重连和“先在线者静止、后加入者仍能获取身份”的方向。

**主要文件**：

- `FlowMuse-App/lib/features/account/models/collaboration_identity.dart`（如需只读派生信息，不把 guest key 持久化到账户）
- `collaboration/models/collaboration_message.dart`
- `collaboration/models/collaborator_presence.dart`
- `collaboration/repositories/collaboration_repository.dart`
- `whiteboard/views/whiteboard_page.dart`
- 现有 message/repository/transport tests

**工作项**：

1. WhiteboardPage 创建/复用/清理当前房间 guest session UUID。
2. 三类 presence factory、broadcast API、接收解析增加可选 creatorKey。
3. 首次 start/join 完成点直接发送一次 `IDLE_STATUS`；普通重连在 `reconnecting → joined` 时补发，不能只订阅不会重放的 connectionStatus broadcast stream。
4. 在既有 roomUsers 订阅中检测新增 socket；每批新增事件用 `force: true` 绕过 idle 状态去重并补发一次自身 `IDLE_STATUS`，忽略离开/资料变化，且不由 presence 消息反向触发。自身 socketId 不可得时容忍一次冗余补发。
5. 登录用户对旧 presence 做 userId hash fallback；游客不按名字猜。
6. 验证 `_send()` 加密路径不变，服务端代码 diff 为零。

**完成判据**：

- 同一游客 Socket 重连前后 creatorKey 相同、socketId 不同。
- leave/end 后新会话 key 改变。
- 不移动指针的新游客在连接后也能让其他新客户端拿到 creatorKey。
- A 先在线且全程静止、B 后加入时，即使 `_lastIdleState` 已等于当前状态，A 仍因 roomUsers 新 socket 事件强制补发一次，B 能拿到 A 的 creatorKey；单批多人加入只补发一次，自身 socketId 缺失也不会阻断。
- 老 payload 无字段可解析。
- 新 payload 加密后传输，明文不出现在 transport payload/日志。
- `FlowMuse-Server/` 无修改。

### T3｜本地创建/更新归属与 LWW 保真

**目标**：统一所有本地元素生命周期，并保证协作收敛。

**主要文件**：

- `editor_core/src/ui/markdraw_controller.dart`
- `collaboration/services/scene_reconciler.dart`
- `whiteboard/views/whiteboard_page.dart`
- 必要时 `collaboration/services/collaboration_debug_log.dart`
- 新建/扩展 creator lifecycle 与 reconciler tests

**工作项**：

1. 增加通用 `onPrepareLocalResult` 回调并放在确定顺序中。
2. 在 WhiteboardPage 根据当前协作身份配置 controller 本地结果预处理；该接线与回调 API 同属本任务，保证提交 2 不前引提交 3 的 API。
3. 审计并收口 controller 内直接 `_editorState.applyResult` 的本地创建/更新。
4. Add 普通元素覆盖当前 creator；Update 保留旧 owner；系统元素排除。
5. 绑定文字按父元素继承，并覆盖“父子同批 Add”和“给既有父元素补标签”两条路径。
6. 覆盖 compound、AI、识别、智能排版、思维导图、流程图、图片、PDF、分页。
7. reconciler 在 winner 选定后执行缺失回填与冲突计数，所有修复 copy-on-write。
8. reconciler 结果集按父元素确定性规范化绑定文字 owner。
9. 不修改 LWW 比较；若不可避免，成对更新 ChangeAccumulator 并补 ADR-013 测试。

**完成判据**：

- 创建、编辑他人元素、复制、导入、删除、undo/redo 全符合第 5 节表格。
- 交换 local/remote 参数，非空冲突最终 creator 相同。
- winner 缺失 owner 时成功回填且其他 customData 不丢。
- reconcile 前后的 local/remote 输入列表及嵌套 Map 完全不变。
- 日志无 creatorKey/displayName/userId。

### T4｜`.markdraw` sidecar、外部导入导出收口

**目标**：分屏编辑不意外丢归属，外部文件不泄漏归属。

**主要文件**：

- `editor_core/src/core/io/scene_document_converter.dart`
- `editor_core/src/ui/markdraw_controller.dart`
- `editor_core/src/ui/markdraw_split_pane.dart`
- `editor_core/src/ui/markdraw_file_handler.dart`
- `editor_core/src/rendering/export/png_metadata.dart`
- `editor_core/src/rendering/export/png_exporter.dart`
- `editor_core/src/rendering/export/svg_exporter.dart`
- `editor_core/src/core/serialization/library_codec.dart`
- `whiteboard/share/services/share_export_coordinator.dart`
- `whiteboard/share/services/imported_document_coordinator.dart`

**工作项**：

1. 暴露一次构建文档即可同时拿到序列化文本与 aliases 的最小接口，避免重复生成 alias。
2. 在 split pane 维护 alias→creator sidecar。
3. 实现 duplicate alias 受控失败、alias 新旧规则、bound text 继承。
4. 增加内部/外部序列化 API，迁移所有调用点。
5. PNG/SVG/Library/Share 最终产物统一净化。
6. 外部导入先剥离不可信 owner。

**完成判据**：

- 分屏保留 alias 时 owner 保留；改 alias/新建行归当前用户；重复 alias 不改画布。
- 原 UUID 改变不影响 sidecar 验收。
- 内部 SQLite/协作 JSON 有 owner。
- 六类外部最终产物均无 `collaborationOwner`，其他 flowMuse 键仍在。

### T5｜本地聚焦状态、头像与元素入口

**目标**：完成用户可操作的逻辑图层视图，不影响 Scene。

**主要文件**：

- `whiteboard/views/whiteboard_page.dart`
- `editor_core/src/ui/markdraw_editor.dart`
- `editor_core/src/ui/property_panel.dart`
- `editor_core/src/ui/compact_property_panel.dart`
- `editor_core/src/ui/property_panel_content.dart`

**工作项**：

1. 建立 none/creator/history 本地 focus target。
2. participant badge 增加 creatorKey、focused、点击行为。
3. 让 `+N` 可点击并提供完整参与者列表；旧游客使用“暂不可按归属聚焦”禁用态。
4. 重连交叠按 creatorKey 只在显示层确定性去重，保留全部 socket 映射。
5. 同 creatorKey 的名字/头像绑定同一代表项；当前用户代表同账号其他设备，不重复显示 badge。
6. 属性面板显示创建者/历史入口。
7. 顶部显示可退出 focus pill；Scene 级目标为空时显示 creator/history 对应空态；游客旧组标“历史会话”。
8. 在线 Presence 名字优先并持续刷新离线快照。
9. leave/end、进入 zenMode/viewMode 时清除，Socket reconnect 保留；模式清除时复用现有轻提示。

**完成判据**：

- 头像聚焦/再次点击退出/切换目标正确。
- 历史内容可单独聚焦。
- 离线 creator 仍可从元素进入并保持。
- 第 6+ 位参与者可从完整列表聚焦；完整退出再加入的游客形成新组，旧组仍可从元素进入。
- 在线名字在头像、pill、属性入口一致；缺字段不会显示永久等待承诺。
- 同账号多设备在每端都只显示一个逻辑组；游客同名重进时旧组 pill 可区分。
- zen/viewMode 不存在隐藏且无法退出的 focus。
- focus 变化不触发 SceneChanged、History 或 repository send。
- 桌面与紧凑属性面板均可用。

### T6｜静态画布、数学 Overlay 与远端湿墨

**目标**：在保持 z 序和书写反馈的前提下完成视觉聚焦。

**主要文件**：

- `editor_core/src/ui/editor_canvas.dart`
- `editor_core/src/ui/markdraw_editor.dart`
- `editor_core/src/rendering/static_canvas_painter.dart`
- `editor_core/src/rendering/remote_wet_ink_painter.dart`
- `whiteboard/views/whiteboard_page.dart`
- 必要的 painter/overlay tests

**工作项**：

1. 从 WhiteboardPage 经 MarkdrawEditor/EditorCanvas 传入 `focusedCreatorKey` / `focusHistoricalContent`、不可变本地高亮元素 ID 快照和 revision 等纯数据；绑定文字编辑时加入父元素。
2. 实现原顺序连续 dim segment。
3. Math Overlay 在现有颜色 alpha 上乘 focus alpha，不增加 Opacity Widget；本地高亮的数学元素保持全亮。
4. RemoteWetInkPainter 接收只读 socketId→creatorKey 快照、映射 revision 和 focus 标量，以包含 sizeScale/压力最大线宽余量的笔迹包围盒临时合成，不污染几何 cache。
5. 本地活动预览、被选中/拖动/编辑的元素本体、编辑 overlay、selection、remote cursor 全亮。
6. 更新静态与远端湿墨 painter 的 `shouldRepaint`：focus 中比较 revision 标量，禁止对 Set/Map 使用 identity/`==`；两端均无 focus 时忽略仅由 highlight/mapping revision 引起的重绘。
7. 用测试 Canvas spy/wrapper 分开统计几何 draw 与 saveLayer，验证 focus 不增加元素绘制次数。

**完成判据**：

- 像素/z 序测试证明目标元素不会浮到遮挡者上方。
- PDF/页面/网格全亮。
- 本地书写反馈全亮。
- 远端湿墨目标内/外/未知三种行为正确。
- Frame、箭头标签、绑定文字及其父元素、数学公式不破坏；框选和选中态符合第 6–8 节定义。

### T7｜双客户端、压力、回归与文档收尾

**目标**：以自动化证据关闭功能和兼容风险。

**主要文件**：

- `collaboration_repository_sync_test.dart` 或同目录新集成测试
- painter/performance tests
- `.agent/decisions.md`（若 payload 扩展被视为需要 ADR）
- `docs/项目说明/项目需求.md`

**工作项**：

1. 复用 `MemoryRealtimeRoomHub` 做 A/B 双端测试。
2. 覆盖 A 创建→B 收到→B 编辑→creator 不变→快照刷新。
3. 覆盖登录用户 room A→local→room B 同 creator。
4. 覆盖游客 reconnect 同 creator、新 session 不同 creator。
5. 证明 focus 切换无线消息。
6. 1000/5000 元素结构化压力测试，覆盖无高亮、作者交替和 focus×跨 owner 多选/拖动；远端湿墨检查局部 bounds。
7. 更新需求/ADR/Issue 验收说明。

**完成判据**：第 12 节所有门禁通过，且无服务端、数据库、平台原生代码改动。

---

## 12. 自动化验收矩阵

### 12.1 模型与生命周期

- [ ] owner codec 合法/缺失/畸形/未知版本安全读取。
- [ ] customData 和 flowMuse 深合并保留全部既有键。
- [ ] 登录 creatorKey 跨房间稳定。
- [ ] guest reconnect 稳定、leave 后变化。
- [ ] guest 完整退出再加入同房间形成新组，旧组仍可从元素入口聚焦。
- [ ] 普通 Add 归当前 creator。
- [ ] 绑定文字在新父元素和既有父元素两种路径下都继承父 owner。
- [ ] 系统 Add 无 owner。
- [ ] Update 他人元素不转移。
- [ ] Update 历史元素仍为历史。
- [ ] copy/paste/import/library/AI/识别/智能排版归操作者。
- [ ] tombstone、undo、redo 保留。

### 12.2 合并与协作

- [ ] LWW winner 有 owner 时保持。
- [ ] winner 缺失、loser 有时回填。
- [ ] 双方非空冲突按 winner 收敛。
- [ ] local/remote 参数交换结果一致。
- [ ] reconciler 输出中的绑定文字与结果集父元素 owner 一致。
- [ ] reconciler 回填/规范化 copy-on-write，输入 local/remote 列表和嵌套 Map 未被修改。
- [ ] protected element 暂态结束后仍可收敛。
- [ ] snapshot refresh 复用同一修复规则。
- [ ] presence 新旧 payload 双向兼容。
- [ ] 新字段仍在 AES-GCM 正文内。
- [ ] 首次 start/join 完成即主动发送 creatorKey；reconnecting→joined 再补发，静止用户无需移动指针。
- [ ] A 先在线且静止、B 后加入时，A 检测新 socket 后强制绕过 idle 去重补发自身 presence，B 能拿到 A 的 creatorKey；自身 socketId 不可得、单批加入和回环边界正确。
- [ ] A/B 双端创建、编辑、删除、重连正确。

### 12.3 UI 与本地状态

- [ ] 当前用户/远端用户头像可聚焦。
- [ ] `+N` 可打开完整参与者列表，第 6+ 位参与者可聚焦。
- [ ] 缺 creatorKey 显示“暂不可按归属聚焦”，不显示永久等待承诺。
- [ ] 重复 creatorKey 只在显示层确定性去重，全部 socket→creatorKey 映射仍保留。
- [ ] 代表项同时决定 badge、在线名字和头像；重连交叠异名时不混用 Presence。
- [ ] 同账号多设备在本端只显示一个 creatorKey 组，其他设备 socket 映射仍保留。
- [ ] 重复点击退出，点击另一头像切换。
- [ ] 同一聚焦目标按 creatorKey 值判断，不依赖 CreatorFocus 对象 identity。
- [ ] 单元素显示 owner；无 owner 显示历史。
- [ ] 离线 owner 仍可聚焦。
- [ ] 在线 Presence 名字在头像、pill、属性入口一致并刷新最后已知快照，离线后名字不倒退。
- [ ] Scene 中目标组无未删普通元素时显示对应 creator/history 空态；目标恢复后消失，内容仅在视口外不误报。
- [ ] 游客同名重进后，旧组属性入口和 pill 都有“历史会话”标识且不泄漏 creatorKey；同 key 重连上线后后缀消失。
- [ ] leave/end 清除，Socket reconnect 不清除。
- [ ] 进入 zenMode/viewMode 清除 focus、给出一次轻提示，退出后不自动恢复。
- [ ] focus 不进 Scene、不进 History、不广播。
- [ ] focus 不改变 hit test 和编辑。

### 12.4 渲染与 Overlay

- [ ] 无 focus 与当前像素输出等价，新增 saveLayer=0。
- [ ] 无 focus 时仅 highlight/presence-map revision 变化不触发 painter 重绘。
- [ ] 全 dim 且无本地高亮时仅一个外层 dim segment。
- [ ] 每个普通元素最多 render 一次。
- [ ] test-only Canvas spy/wrapper 证明 focus/no-focus 几何 draw-call 数相同；saveLayer 按连续 dim 段单独断言。
- [ ] 交错 z 序不改变。
- [ ] Frame child clip 正确。
- [ ] 箭头清洞和绑定标签正确。
- [ ] PDF/Page/Grid/shadow 全亮。
- [ ] 本地 wet ink/preview/editing overlay 全亮。
- [ ] 被选中、拖动或编辑的元素本体全亮，操作结束后恢复分类。
- [ ] 框选过程只有框选矩形全亮，松手后选中元素才进入高亮；编辑绑定文字时父元素一并全亮。
- [ ] 本地湿墨提交到非目标 owner 时允许 1.0→0.22 瞬时跳变且不加动画。
- [ ] finalized Math 按 owner 变淡，被选中/编辑时全亮。
- [ ] remote wet ink 目标外变淡、未知全亮。
- [ ] focus/highlight revision 触发 StaticCanvasPainter 重绘；focus/socket-owner-map revision 触发 RemoteWetInkPainter 重绘。
- [ ] 远端湿墨 alpha saveLayer 使用含 sizeScale、最大压力线宽和抗锯齿余量的 stroke bounds；粗笔/最大压力边缘像素不裁切且不创建全屏层。
- [ ] 1000/5000 元素的 focus×跨 owner 高亮场景仍满足“一元素最多绘制一次”和段数断言。
- [ ] selection/link icon/remote cursor 全亮。

### 12.5 格式与隐私

- [ ] format 门禁在 tracked-only、untracked-only、两者并存和两者皆空四种输入下均不报空值错误，且不会漏掉存在的 Dart 文件。
- [ ] analyze machine 路径完成反转义和 `/` 归一化；exit 2 由 multiset 比较接管。
- [ ] 内部 Excalidraw 本地存储保留 owner。
- [ ] 协作元素和快照保留 owner。
- [ ] split pane alias sidecar 正确。
- [ ] duplicate alias 阻止应用。
- [ ] 外部 `.markdraw` 无 owner。
- [ ] 外部 `.excalidraw/.json` 无 owner。
- [ ] `.markdrawlib/.excalidrawlib` 无 owner。
- [ ] PNG tEXt 最终产物无 owner。
- [ ] SVG embedded comment 最终产物无 owner。
- [ ] ShareExportCoordinator 三类产物无 owner。
- [ ] 剥离后 brush/page/pdf/mindmap/smart-layout 数据仍在。
- [ ] 日志不含 creatorKey/displayName/userId。

---

## 13. 验证命令与提交门禁

基线 `origin/main@c40a847` 的全量 `dart format --set-exit-if-changed lib test` 会报告 96 个既有文件不符合格式，`dart analyze --format=machine` 为 42 issues（0 error / 17 warning / 25 info，诊断存在时 exit 2）。本任务不得为清理基线混入 96 文件无关 diff；格式门禁只约束本分支触碰的 Dart 文件，analyze 门禁采用“相对基线无新增 error/warning/info”。

在仓库根目录先执行改动文件格式门禁：

```powershell
$trackedDart = git diff --name-only --diff-filter=ACMRTUXB origin/main -- FlowMuse-App/lib FlowMuse-App/test
$untrackedDart = git ls-files --others --exclude-standard -- FlowMuse-App/lib FlowMuse-App/test
$changedDart = @($trackedDart; $untrackedDart) |
  Where-Object { $_ -and $_.EndsWith('.dart') -and (Test-Path -LiteralPath $_) } |
  Sort-Object -Unique |
  ForEach-Object { (Resolve-Path -LiteralPath $_).Path }
if ($changedDart.Count -gt 0) {
  dart format --output=none --set-exit-if-changed $changedDart
}
```

再在 `FlowMuse-App/` 执行；具体新增测试文件名可按最终实现调整，但范围不得缩减：

```powershell
dart analyze --format=machine
flutter test test/features/whiteboard/collaboration
flutter test test/features/whiteboard/editor_core
flutter test test/features/whiteboard/views
```

仓库根目录执行：

```powershell
git diff --check
git status --short
git diff -- FlowMuse-Server
git diff -- FlowMuse-App/ohos FlowMuse-App/android FlowMuse-App/ios FlowMuse-App/macos FlowMuse-App/windows FlowMuse-App/web
```

预期：

- `FlowMuse-Server` 无功能 diff。
- 所有平台原生目录无 diff。
- `pubspec.yaml` 无新依赖。
- 无数据库 schema migration。
- 无 `GeneratedPluginRegistrant.ets`。
- 无 creatorKey/displayName 出现在 debug log 快照。
- 使用实测可用的 `dart analyze --format=machine` 保存基线与本分支诊断；先按 machine 格式反转义 file 字段，再归一化为相对 `FlowMuse-App/` 且统一使用 `/` 分隔符的路径，以 `severity + code + file + message` 为键做 **multiset 计数差**。line/column/length 只供人工定位，不进入门禁键，避免存量诊断行号平移造成假红。本分支相对上述 42-issue 基线不得新增任何 error、warning 或 info，也不能只比较总数或普通 set，以免吞掉同键重复项；诊断导致的 exit 2 由比较脚本接管，不能把“非零”本身误判为新增问题。

鸿蒙真机不作为代码审查前的自动化阻断，但合并前至少做一次 Profile/GPU 手工验证：普通协作场景、PDF 批注、1000 元素混合作者、focus×跨 owner 多选/拖动、连续书写、快速切换头像。记录设备、系统版本、Flutter 构建模式、可见元素数、dim segment 数、远端湿墨 saveLayer 数及其 bounds/覆盖面积和明显掉帧现象；没有基线前不承诺虚构的毫秒指标。

---

## 14. 风险、降级与回滚

| 风险 | 触发 | 预防/降级 |
|---|---|---|
| 最坏交替作者导致 saveLayer 多 | segmentCount 接近 visibleCount | 压力测试+真机 Profile；必要时后续改 renderer alpha fallback |
| 远端湿墨逐 stroke saveLayer 最坏 64 层 | 多 sender 满笔迹且画面跨度大 | 使用 stroke bounds 而非全屏层并做真机 Profile；证明确为瓶颈后再做连续段合并 |
| 新元素路径漏盖章 | 某功能直接改 EditorState | 收口本地 apply helper + AddElementResult 审计 + 功能矩阵测试 |
| 自定义数据被覆盖 | 浅合并 flowMuse | 集中 helper + 保留键测试 |
| LWW 不收敛 | 双方 owner 不同仍本地粘滞 | 严格使用 winner，只有缺失才回填 |
| 游客重连身份断裂 | 使用 socketId/姓名 | session UUID + 加密 presence.creatorKey |
| 老游客无法聚焦 | 旧客户端不发 creatorKey | 禁止猜测；头像入口降级，湿墨 fail-open |
| 游客完整退出再加入身份分组 | session UUID 按会话清理 | 明确视为新逻辑组；旧组从元素入口访问，不做账号化追踪 |
| 聚焦退出入口丢失 | zen/viewMode 隐藏协作 chrome | 进入对应模式立即清除 focus |
| reconciler 污染输入 | 嵌套 customData 引用共享 | copy-on-write + 输入不变断言 |
| 分屏丢 owner | 依赖原 UUID | alias sidecar；duplicate alias 阻断 |
| 外部导出泄漏 | 调用点绕过 sanitizer | 明确外部 API + grep 调用点门禁 + 最终产物测试 |
| 聚焦影响输入反馈 | 活动 overlay 跟随 dim | 本地 wet ink/text/preview 强制全亮 |
| 归属被误当权限 | 客户端 metadata 可伪造 | API/文档明确 display-only，不接锁定判断 |

不加运行时 feature flag：focus 默认为 null，未点击时天然不改变当前行为；数据字段向后兼容，回滚 UI/渲染后元素 customData 仍可被旧代码透明保留。若上线后只需紧急关闭视觉聚焦，可移除/禁用入口而不迁移数据。

---

## 15. 建议提交序列

每个提交应可独立编译测试，避免把模型、渲染、UI 和隐私收口压在一个大提交：

1. `feat: 增加协作元素创建者元数据与稳定身份键`
2. `feat: 在加密协作状态中同步创建者键`
3. `fix: 保证元素创建者在本地编辑与LWW合并中稳定`
4. `fix: 保留分屏归属并净化外部导出元数据`
5. `feat: 增加协作者与历史内容聚焦交互`
6. `feat: 按原层级顺序渲染协作归属聚焦效果`
7. `test: 补齐协作归属兼容性能与隐私验收`
8. `docs: 更新协作元素归属设计与验收记录`

任何提交若修改服务端、数据库 schema、平台原生代码或引入 CRDT，应立即暂停并重新审查范围。

---

## 16. Claude 严格审查清单

请审查者不要只评价产品概念，必须对照当前代码逐项回答 PASS / BLOCK / NEEDS-EVIDENCE：

1. `onPrepareLocalResult` 是否能覆盖所有本地 Add/Update，是否存在绕过路径？
2. 系统元素判定是否完整，PDF 底稿是否始终全亮？
3. 登录 creatorKey 去 roomId 后，跨房间语义是否成立且无新的身份碰撞？
4. 游客若不扩展 presence.creatorKey 是否确实无法跨 reconnect 关联；当前可选字段方案是否与旧客户端兼容，且“静止 A 先在线、B 后加入”是否通过 roomUsers 新 socket 触发并绕过 idle 去重完成强制补发？
5. presence.creatorKey 是否仍在 AES-GCM 正文内，服务端是否确实无需改动？
6. reconciler 的 winner/backfill 规则是否对 local/remote 交换保持收敛？
7. 是否有任何代码把 creator 当权限、锁定或可信身份？
8. 单遍 dim segment 是否严格保持全局 z 序、Frame clip、箭头标签清洞和绑定文字？
9. worst-case alternating owner 是否有足够压力证据，fallback 是否没有被过早双实现？
10. 本地湿墨、文本编辑、预览、数学 Overlay、远端湿墨的行为是否全部有定义和测试；focus 中 revision 是否立即重绘、无 focus 时是否避免无意义重绘、压力粗笔 bounds 是否不裁切？
11. `.markdraw` sidecar 是否真按 alias 而非原 UUID；duplicate alias 是否受控？
12. 内部保存与外部导出是否使用不同入口，是否还有绕过 sanitizer 的调用点？
13. PNG/SVG embedded data、Library、Share 的测试是否验证最终字节/字符串，而不是只测 helper？
14. customData 深合并是否保住 brush/page/pdf/mindmap/smart-layout/recognition 数据？
15. focus 是否完全本地，不触发 SceneChanged、History、持久化或网络？
16. 第 6+ 位参与者、旧客户端禁用态、zen/viewMode、游客完整重进、同账号多设备、空态和被选中 dim 元素是否都有可执行行为？
17. reconciler 是否 copy-on-write，且测试证明输入列表/嵌套 Map 不变？
18. format 是否覆盖 tracked+untracked 并防御任一侧 `$null`；analyze 是否正确反转义路径、使用无位置字段的 machine multiset 基线，且未借机制造大范围无关 diff？
19. 是否能删除任何不必要的抽象、依赖、feature flag、服务端或平台代码，同时不降低验收覆盖？

### 审查阻断标准

出现以下任一项不得进入实现/合并：

- 仍依赖 socketId 或用户名作为永久归属键。
- 仍按本地 sticky owner 处理双方非空冲突。
- 仍用两遍绘制把目标作者抬到最上层。
- 仍宣称 `.markdraw` 保留原 Element UUID。
- 在通用 codec 中无条件剥离 owner，导致内部保存丢失。
- 外部 Excalidraw/PNG/SVG/Library/Share 任一产物可能带 owner。
- focus 进入文档、历史或网络。
- 归属参与权限判断。
- 未覆盖本地活动笔迹全亮与远端映射失败 fail-open。
- 为此功能修改服务端或引入 CRDT/物理图层而无新的 ADR 和范围批准。

---

## 17. Definition of Done

只有同时满足以下条件才可关闭 Issue #8：

1. 数据、身份、生命周期、合并、渲染、Overlay、UI、格式和隐私测试全部通过。
2. 新旧客户端缺失字段场景不崩溃，LWW 可收敛。
3. 原 z 序和系统底图语义有像素/结构化证据。
4. 内部持久化保留 owner，所有外部最终产物剥离 owner。
5. 聚焦状态经测试证明不写 Scene/History/网络。
6. 服务端、数据库、原生平台目录和依赖清单无不必要改动。
7. 鸿蒙真机完成至少一轮 Profile/GPU 手工验证并记录结果。
8. 首轮与二轮审查发现均已落实；任何后续审查在进入实现前提出的 Critical/Important 必须全部关闭，NEEDS-EVIDENCE 必须补齐证据。


---

## 18. 实现落地记录（2026-08-26）

### 18.1 分支与提交序列

实施分支 `feat/issue-8-collaboration-ownership-focus`（基线 `origin/main@c40a847`），按实现细则计划 T1-T16 逐任务提交：

| 任务 | 提交 | 内容 |
|---|---|---|
| T1 | 4257377 | 创建者值对象、customData codec 与外部 sanitizer |
| T2 | 8a1372e | 登录/游客 creatorKey 稳定身份键派生 |
| T3 | 1ecb9d4 | 三类加密 presence 消息可选携带 creatorKey |
| T4 | e16862e | 游客会话 UUID 生命周期、三路强制补发、socket→creatorKey 映射 |
| T5 | 6a06202 | 本地创建/更新统一盖章（onPrepareLocalResult）并收口 14 处直连点 |
| T6 | 115e1de | LWW 合并后归属回填、冲突计数与父子规范化 |
| T7 | 3bb04c1 | 外部导出双入口收口与不可信导入剥离 |
| T8 | afd4bc2 | .markdraw 分屏 alias sidecar 与重复标识阻断 |
| T9 | 2c82248 | 聚焦状态机、顶部 pill 与生命周期清理 |
| T10 | 92f4a1d | 属性面板创建者/历史内容入口 |
| T11 | 35b98c6 | 参与者头像聚焦、显示层去重与 +N 完整列表 |
| T12 | 53e0291 | 静态画布单遍连续 dim 段渲染 |
| T13 | 334ee4c | 聚焦参数穿透、本地高亮集合与数学 Overlay |
| T14 | a68c1ab | 远端湿墨按创建者分类临时 alpha 合成 |
| T15 | 33df287 | 双端集成与 1000/5000 结构化压力验收 |
| T16 | （本提交）| 门禁执行、ADR-018 与文档收尾 |

对应 v4 §15 的 8 提交序列映射见实现细则计划附录 B。

### 18.2 门禁结果摘要

- **格式门禁**：本分支触碰的 43 个 Dart 文件 `dart format --set-exit-if-changed` 全部通过（0 变更）。
- **analyze 门禁**：`dart analyze --format=machine` 按 severity|code|file|message multiset 差比较，基线（c40a847 worktree 实测）42 issues = 分支 42 issues，零新增 error/warning/info。
- **测试门禁**：`test/features/whiteboard/collaboration` 93 通过；`test/features/whiteboard/editor_core` 277 通过；`test/features/whiteboard/views` 27 通过。
- **范围门禁**：`git diff --check` 干净；FlowMuse-Server、ohos/android/ios/macos/windows/web 平台目录、pubspec.yaml 零改动；无数据库 schema 变更；无 GeneratedPluginRegistrant.ets。
- **隐私断言**：全库无 CollaborationDebugLog.write 调用携带 creatorKey/displayName/userId；owner_repair 日志脱敏测试锁定只输出 `ownerConflictCount=N ownerBackfillCount=N`。
- **外部导出**：六类外部最终产物（.markdraw/.excalidraw/.json/PNG tEXt/SVG comment/分享与库文件）经测试断言无 collaborationOwner；内部 SQLite/协作密文保留（serializeScene 内部路径源码门禁锁定）。

### 18.3 真机人工验收待办（合并前完成）

当前环境无鸿蒙真机，以下 Profile/GPU 手工验证项按 v4 §13 最后一段执行后回填：普通协作场景、PDF 批注、1000 元素混合作者、focus×跨 owner 多选/拖动、连续书写、快速切换头像；记录设备型号、系统版本、Flutter 构建模式、可见元素数、dim segment 数、远端湿墨 saveLayer 数及其 bounds 覆盖面积与明显掉帧现象。真机数据不达标时按 v4 §7.4 另开 renderer alpha multiplier fallback 决策。

### 18.4 实现裁决登记

1. **非协作状态不盖章**：`activeRoom == null`（本地笔记）时 `_currentCreator()` 返回 null，新建登录用户元素无归属（进入协作后归"历史内容"）。这是 R3（登录键跨房间稳定）字面语义的推论空白而非矛盾——R3 保证"房间 A 已盖章元素在房间 B 仍匹配"，本地阶段新建元素从未盖章。见实现细则 Task 4 Step 4.3。
2. **远端湿墨 bounds 余量**：采用 `kMaxBrushSizeScale = 4.2`（highlighter 为当前笔型 sizeScale 上界）常量推导 margin = strokeWidth × 4.2 × 0.5 × 1.3 + 2px；若未来新增更粗笔型（sizeScale > 4.2）必须同步上调该常量，否则聚焦层可能裁切边缘像素。见实现细则 Task 14。
