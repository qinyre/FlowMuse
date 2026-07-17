# 跨端系统分享第一版设计

> 日期：2026-07-11  
> 状态：已完成设计，待评审  
> 范围：系统分享；不包含隔空传送。

## 1. 目标与非目标

### 目标

为 FlowMuse 提供统一的“分享”业务入口，第一版支持：

1. 分享当前白板的 PNG 图片；
2. 分享当前白板的 `.markdraw` 可编辑文件；
3. 分享当前白板的 `.excalidraw` 可编辑文件；
4. 分享现有协作房间邀请链接。
5. 在鸿蒙端作为“用其他应用打开”的目标，接收 `.markdraw` 与 `.excalidraw` 文件并创建新笔记副本。

共享 Flutter 业务层只处理分享内容与结果，不感知平台。鸿蒙使用 Share Kit 系统分享面板；Android、iOS、macOS、Windows 与 Web 使用 `share_plus` 调起各端系统分享能力，Web 不支持时才降级为下载或复制。

### 非目标

- 不接入隔空传送、一抓一放或碰一碰。
- 不传送实时协作场景，不做接收端自动导入。
- 不在第一版中用外部文件静默覆盖正在编辑的白板，也不支持从其他应用接收 PNG、SVG、PDF 或素材库文件。
- 不追踪接收方是否打开、保存、导入或加入房间；“完成”仅表示已成功发起系统分享。
- 不分享 `ownerKey`、账户 token、明文加密快照、房间管理接口信息。

## 2. 用户体验

### 2.1 入口

白板工具栏提供“分享”菜单，包含：

- 分享图片（PNG）；
- 分享可编辑副本（`.markdraw`）；
- 分享 Excalidraw 副本（`.excalidraw`）。

协作面板提供“分享邀请链接”。首次执行前必须给出明确告知：持有该链接的人可以加入当前协作房间；只有用户确认后才调起系统分享。

### 2.2 成功与降级

系统分享面板调起成功即视为本次分享已发起。用户取消时静默返回，不显示错误；当前白板、选区、历史栈、协作连接均不改变。

若目标平台或浏览器没有可用系统分享能力：

| 内容 | 降级行为 |
| --- | --- |
| PNG / `.markdraw` / `.excalidraw` | 文件保留为已导出状态，并提示用户从文件中发送。 |
| 邀请链接 | 提供复制链接入口。 |

导出或原生调用失败时使用不含敏感信息的 SnackBar 提示，编辑器状态保持不变。

### 2.3 从其他应用打开可编辑文件

鸿蒙端在文件管理器或其他应用中被选择为 `.markdraw`、`.excalidraw` 文件的打开目标后，先进入导入确认页，而不是直接覆盖当前画布。确认页展示文件名、格式和“将创建为新笔记副本”的说明；用户只能选择：

- 创建新笔记并打开（默认、唯一的导入动作）；
- 取消。

导入成功后，FlowMuse 创建新的本地笔记并载入场景，原笔记、当前选区、历史栈与协作会话均不受影响。`.markdraw` 只承诺可由 FlowMuse 继续编辑；`.excalidraw` 对其他应用的可打开性取决于对方是否支持 Excalidraw 导入，FlowMuse 不为第三方应用做兼容性承诺。

## 3. 架构

```text
白板工具栏 / 协作面板
        ↓
ShareViewModel
        ↓
ShareService
        ↓
SharePayload（文本或临时文件）
        ↓
条件导入的各端适配实现
  ├─ 鸿蒙：MethodChannel → ArkTS Share Kit
  ├─ Android / iOS / macOS / Windows：系统分享面板
  └─ Web：Web Share API；不可用时下载/复制
```

### 3.1 组件边界

| 组件 | 职责 | 不负责 |
| --- | --- | --- |
| `SharePayload` | 表达不可变文本或临时文件载荷，含显示名称与内容类型。 | 不判断平台、不包含密钥。 |
| `ShareService` | 接收载荷并返回 `completed`、`dismissed`、`unavailable` 或 `failed`。 | 不导出白板、不修改 UI。 |
| `ShareViewModel` | 选择导出格式、管理加载状态、处理确认弹窗、映射提示与安排清理。 | 不直接调用 ArkTS API。 |
| 平台实现 | 拉起本端系统分享能力，处理文件 URI/内容类型。 | 不理解白板、房间和协作协议。 |
| 鸿蒙 Share Channel | 将 Dart 载荷转换成 Share Kit `SharedData` 并调用系统分享。 | 不保存密钥、不处理场景序列化。 |
| ExternalDocumentIngress | 接收鸿蒙外部文件启动请求，读取受授权文件内容并将其排队交给 Flutter。 | 不直接替换当前控制器场景、不把原始 URI 写入日志。 |
| ImportedDocumentCoordinator | 校验、解析外部文件，并在用户确认后创建新笔记副本。 | 不修改原笔记、不建立协作房间。 |

共享代码禁止用 `Platform.is*` 分支；平台选择必须通过条件导入或抽象实现收敛。

### 3.2 载荷规则

| 载荷 | 来源 | 可包含 | 禁止包含 |
| --- | --- | --- | --- |
| `ShareImage` | 既有 PNG exporter | 当前画布导出的临时 PNG、名称、图片类型 | 协作密钥、调试信息。 |
| `ShareDocument` | 既有 Markdraw / Excalidraw 序列化与文件导出 | 临时场景文件、名称、精确文件类型 | token、ownerKey、明文协作快照。 |
| `ShareText` | `CollaborationRoom.shareLink()` | 用户已确认分享的邀请链接、标题和说明 | ownerKey、服务端管理信息。 |

`roomKey` 是既有邀请链接的一部分，属于“持链接可加入”的能力凭证；不得自动、静默发送，也不得写入日志、卡片或系统索引。

## 4. 鸿蒙实现设计

鸿蒙适配位于 `FlowMuse-App/ohos/entry/src/main/ets/channels/`，由 `EntryAbility.configureFlutterEngine()` 注册。Dart 侧实现置于独立的 service / channel 文件，并通过条件导入提供统一接口。

ArkTS 将根据载荷选择精确的 Share Kit `SharedData` 类型：图片使用图片类型，`.markdraw` / `.excalidraw` 使用对应文件类型，链接使用超链接类型。Channel 必须捕获平台异常并返回可序列化的结果码；Dart 侧同样捕获 `PlatformException` 与 `MissingPluginException`，映射到 `unavailable` 或 `failed`。

文件必须位于系统分享可读取的临时位置。实现阶段须在目标鸿蒙版本验证 URI 授权、系统面板对三个文件类型的识别，以及取消分享后的文件可清理性。

## 5. 其他端实现设计

Android、iOS、macOS、Windows 与 Web 通过 `share_plus` 13.2.0 实现，且只在非 OHOS 的条件导入文件中引用该包；当前 Flutter 3.41.10 满足该版本 Flutter 3.38.1+ 的要求。Android 使用 Sharesheet，iOS 使用 `UIActivityViewController`，其余支持端使用对应的平台分享 UI；鸿蒙继续使用 Share Kit，不让该插件进入 OHOS 的实现链路。

| 平台 | 邀请链接 | PNG、`.markdraw`、`.excalidraw` | 降级 |
| --- | --- | --- | --- |
| Android / iOS / macOS / Windows | 系统分享面板 | 系统文件分享 | `unavailable` 时复制链接或保留导出文件。 |
| Web | Web Share API | 支持文件分享的浏览器走 Web Share API | 下载文件；链接复制。 |
| Linux | 不纳入本期原生文件分享验收 | 不保证文件分享 | 保留导出文件；链接复制。 |

`share_plus` 的结果仅说明本端分享调用状态，不能作为接收方打开、保存、导入或加入房间的证据。非鸿蒙端与鸿蒙端都只分享任务生成的临时副本，不能暴露应用数据库路径或场景存储路径。

## 6. 临时文件生命周期

1. 用户发起文件分享时，先生成唯一临时文件，完成写入后才调用 `ShareService`。
2. 系统分享处于打开状态时不得删除文件。
3. 面板完成、取消或调用失败后，将文件标记为可清理；不依赖立即删除。
4. 每次应用启动及下一次分享前，清理创建时间超过 **24 小时**的应用分享临时文件。
5. 清理失败只记录脱敏状态，不影响白板编辑或后续分享。

第一版不承诺即时删除，因为目标应用可能在系统面板关闭后仍需要读取文件；统一保留 24 小时后再清理。

## 7. 鸿蒙外部文件打开

### 6.1 文件关联与启动生命周期

`module.json5` 当前只声明主页启动，未声明绘图文件的系统打开能力。第一版需为 `EntryAbility` 增加仅匹配 `.markdraw`、`.excalidraw` 的文件打开 Skill；具体 Want / 文件类型声明按照实施时目标 HarmonyOS API 版本的官方 schema 配置。不得用宽泛的 `application/json` 把所有 JSON 文件都注册给 FlowMuse。

鸿蒙 UIAbility 在冷启动时从 `onCreate(want, ...)` 接收启动参数；已运行实例再次被打开时从 `onNewWant(want, ...)` 接收新参数。因此 `EntryAbility` 必须将两条路径统一送入 `ExternalDocumentIngress`。若 Flutter engine 或 Dart 侧路由尚未就绪，请求进入最多 **3 项**的内存队列，待 Flutter 注册接收器后按顺序消费；队列只保存已验证的文件元数据和读取结果，应用退出即丢弃。队列满时拒绝新请求并保留当前编辑状态。

### 6.2 读取、验证与导入

1. ArkTS 只读取系统授予的外部文件 URI，不将 URI 视为可长期保存路径；读取模式复用现有 OHOS 文件选择 Channel 向 Dart 传递文件名与字节数组的边界。
2. Dart 同时校验扩展名、内容大小（最大 **20 MiB**）和 UTF-8 解码；不接受 `.json` 作为外部打开关联，避免误认普通 JSON 文件。
3. 使用现有 `DocumentService` 和 `MarkdrawController.loadFromContent()` 对 `.markdraw` / `.excalidraw` 解析。解析警告必须在确认页展示；解析失败、空内容或超出文件大小限制时终止导入并给出可理解提示。
4. 用户确认后，`ImportedDocumentCoordinator` 将解析出的场景写成新的本地笔记并导航至该笔记。第一版没有“替换当前白板”按钮。
5. 外部请求、URI、文件内容和解析后的白板不写入 debug 日志；仅允许记录脱敏格式、大小和成功/失败状态。

### 6.3 失败与边界

| 场景 | 行为 |
| --- | --- |
| 用户取消确认 | 丢弃待导入内容；不创建笔记。 |
| 同一文件多次打开 | 每次都是独立的新笔记副本；不依赖外部路径持续可用。 |
| 应用在编辑协作白板时收到文件 | 保持当前协作状态，展示导入确认；确认后导航至新笔记。 |
| 文件无法读取、格式不支持或解析失败 | 显示错误，当前笔记与协作连接不变。 |
| Excalidraw 包含不支持元素 | 按现有解析器的 warning 导入可支持部分；确认页须让用户知晓。 |

## 8. 分阶段交付

### 阶段一：基础分享闭环

- 建立 `SharePayload`、`ShareService`、结果类型与条件导入边界；
- 支持 PNG 与协作邀请链接；
- 鸿蒙接入 Share Kit；Web 提供下载/复制降级；
- 覆盖载荷、结果映射、确认门槛测试。

### 阶段二：可编辑场景文件

- 接入 `.markdraw` 与 `.excalidraw` 导出；
- 加入临时文件目录、清理标记与内容类型映射；
- 验证两种文件均能在鸿蒙分享面板中正确展示。

### 阶段三：其他端原生适配

- 在非 OHOS 条件导入实现中接入 `share_plus` 13.2.0，覆盖 Android、iOS、macOS、Windows、Web；
- 为 Web Share API 不可用和 Linux 文件分享不支持保留文件保存/链接复制降级；
- 验证新增依赖不影响 OHOS `flutter build hap`，且不改变分享入口、载荷结构或协作协议。

### 阶段四：鸿蒙“用其他应用打开”闭环

- 声明 `.markdraw`、`.excalidraw` 的精确文件打开关联；
- 将 `onCreate` / `onNewWant` 的文件请求桥接到 Flutter；
- 实现导入确认、新建本地笔记副本、解析 warning 和错误处理；
- 覆盖冷启动、热启动、取消、损坏文件、包含不支持 Excalidraw 元素、协作进行中收到外部文件等场景。

## 9. 错误处理与安全

| 场景 | 预期结果 |
| --- | --- |
| 用户取消面板 | `dismissed`；不报错、不改编辑器状态。 |
| 平台功能缺失 | `unavailable`；文件提示已导出，链接提供复制。 |
| 导出失败 | `failed`；SnackBar 提示，保持场景与历史栈。 |
| Channel 未注册或原生异常 | `failed` 或 `unavailable`；不崩溃。 |
| 页面销毁/进入后台 | UI 停止等待；临时文件按清理策略处理。 |
| 外部文件请求早于 Flutter 路由就绪 | 请求在 ArkTS 内存队列等待；就绪后一次消费。 |
| 外部文件格式错误或解析失败 | 不创建笔记、不替换当前白板。 |

不得在 `debugPrint`、异常、测试输出、缩略图、分享说明或 ArkTS 日志中写入 token、ownerKey、roomKey、明文场景或可还原密文。

## 10. 验收标准

### 自动化

- `SharePayload` 对 PNG、两个场景文件和邀请链接的类型映射正确；
- 分享结果正确映射为 UI 行为；
- 未确认时不得发起邀请链接分享；
- 取消或失败不修改编辑器场景、历史栈和协作状态；
- 现有导出与协作相关测试继续通过。

### 鸿蒙人工验收

1. PNG、`.markdraw`、`.excalidraw` 各自拉起 Share Kit 面板，并显示正确内容类型；
2. 邀请链接需先确认，系统分享后可进入既有加入流程；
3. 取消、目标应用不可用和 Channel 异常不导致崩溃；
4. 分享过程中继续编辑、切换笔记或返回，不损坏当前白板；
5. `flutter build hap` 成功，且日志不包含敏感数据。

### Android、iOS、macOS、Windows 与 Web 验收

1. 各支持端分别对 PNG、`.markdraw`、`.excalidraw`、邀请链接调起系统分享入口；
2. 用户取消不改变白板、历史栈或协作状态；
3. Web 无 Web Share API 时，文件下载、链接复制可用；
4. Linux 仅验证导出文件和链接复制降级；
5. 不显示目标应用标识，也不据此推断接收端结果。

### 鸿蒙外部打开人工验收

1. 从文件管理器和另一应用分别选择 `.markdraw`、`.excalidraw`，FlowMuse 出现在打开目标中；
2. 冷启动和应用已在前台时均出现导入确认，且默认说明为“新建副本”；
3. 确认后创建新笔记并正确显示；取消后不创建笔记；
4. 损坏文件、普通 `.json` 文件和超出大小限制的文件不可导入且不崩溃；
5. 当前正在编辑或协作中的白板收到文件时，原场景、撤销历史和协作连接保持不变。

## 11. 不变量

- Excalidraw 数据格式与协作 AES-GCM 加密边界不变。
- 当前导出、协作创建/加入、撤销/重做和非鸿蒙平台的编辑行为不变。
- 外部文件打开只创建新笔记副本，绝不静默替换当前笔记或协作场景。
- 隔空传送是后续独立设计：可复用 `SharePayload` 和 `ShareService`，但不属于本规格。
