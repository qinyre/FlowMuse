# FlowMuse 融入 HarmonyOS 特性调研

> 调研日期：2026-07-11  
> 适用分支：`markdraw-harmonyos-probe`  
> 调研范围：`harmonyos-guides/` 本地官方文档、华为开发者联盟公开文档，以及 FlowMuse 当前 Flutter / ArkTS / 协作架构。  
> 目标：找出能增强鸿蒙端体验、且不牺牲跨端一致性和端到端加密边界的能力；本文不等同于实施计划。

## 1. 结论摘要

推荐的优先顺序如下：

| 优先级 | 能力 | 面向用户的价值 | 结论 |
| --- | --- | --- | --- |
| P0 | Share Kit 系统分享 | 将 PNG、SVG、`.excalidraw` / `.markdraw` 文件，或协作邀请链接交给任意目标应用/设备 | **最值得先做**；现有导出器和 `FileSaveChannel` 可复用，新增鸿蒙分享适配层即可。 |
| P1 | Pen Kit 全局取色 | 用手写笔/手指在屏幕任意位置取色，直接设置当前笔或图形颜色 | **值得做**；是独立、低耦合的编辑器增强，但必须做设备能力检测与失败降级。 |
| P1（技术验证） | Pen Kit 报点预测 | 缩短笔尖与湿墨尾部的视觉间隙 | **先做可行性 Spike，不能直接承诺接入**；预测需要拿到 ArkTS 原始 `TouchEvent`，而目前 Flutter 画布并没有向 ArkTS 暴露这一路事件。 |
| P2 | Form Kit 桌面卡片 | 从桌面快速打开最近笔记、继续上次编辑，或进入协作房间 | **适合做轻量入口**；卡片必须用 ArkTS 单独开发，不能复用 Flutter UI，也不能把白板编辑器塞进卡片。 |
| P2（产品验证） | Intents Kit 本地搜索 | 从小艺搜索发现本地笔记标题并打开对应笔记 | **仅在“本地笔记可被系统索引”得到用户授权后考虑**；不应把白板内容、协作密钥或加密快照暴露给系统。 |

不建议现在接入的能力：

- **Pen Kit 手写套件作为主画布**：会与 Markdraw 的元素模型、撤销历史、Excalidraw 序列化和协同同步形成双引擎，改造收益不确定。
- **一笔成形直接替换自由笔画**：官方输出是 `ShapeInfo/Path2D`，而当前需要的是可编辑、可序列化的 Markdraw 元素；自动替换也会改变用户手写语义。若做，只能作为用户显式开启的实验模式。
- **ArkData 分布式数据同步 / 分布式文件系统作为协同通道**：当前协作已经是服务端中转的 AES-GCM 加密协议。再引入设备间数据同步会产生两套真相源，并可能绕过“服务端只见密文”的安全设计。

## 2. 当前项目基线与判断约束

FlowMuse 已具备以下基础：

1. 编辑器有自由笔、形状、文本、撤销/重做和 Excalidraw 兼容序列化；已有 PNG / SVG 导出器。
2. 鸿蒙已有 `FilePickerChannel`、`FileSaveChannel`、`PdfImportChannel` 与 `HttpChannel`，统一在 `EntryAbility.ets` 注册。
3. 协作使用 `roomId + roomKey` 邀请信息，场景和消息使用 AES-GCM；`ownerKey` 仅用于房主结束房间并存于安全存储。
4. 鸿蒙手写笔目前走 Flutter `PointerEvent`，且仅在自由画笔下由 `HarmonyStylusStrokeSmoother` 处理；它仍是固定 EMA，不是原生 Pen Kit 画布。

因此，所有候选项必须遵守：

- 鸿蒙原生能力通过 service / Platform Channel 收敛；共享 Dart 业务层不写 `Platform.is*` 分支。
- 协作邀请中的 `roomKey` 是加入房间的能力凭证；系统分享前必须由用户显式确认。任何分享、日志、卡片或意图索引都不得包含 `ownerKey`、登录 token、明文场景和加密快照。
- 鸿蒙增强可以降级，但不能改变 Android、iOS、桌面和 Web 的既有输入、序列化、协作协议或导出结果。

## 3. 推荐能力一：Share Kit 系统分享（P0）

### 官方能力与适配价值

系统分享允许宿主应用构造文本、文件或备忘录等内容，拉起系统分享面板，由用户选择目标应用或设备。手机以模态面板展示，2in1 以 Popup 展示；官方要求按内容选择精确的 UTD 类型。

这与 FlowMuse 的现有能力高度匹配：编辑器已有导出器，鸿蒙已有文件保存 Channel，但尚未形成“导出后立即交给系统”的闭环。

### 建议的最小产品形态

| 用户动作 | 分享内容 | 安全边界 |
| --- | --- | --- |
| 分享图片 | 当前画布 PNG | 导出的静态图，不含协作凭证。 |
| 分享矢量稿 | SVG / `.excalidraw` / `.markdraw` 文件 | 先写入应用可分享的临时文件；完成或取消后按系统规范清理。 |
| 邀请协作 | 既有 `CollaborationRoom.shareLink()` 文本 | 分享前明确提示“持有该链接可加入房间”；绝不附加 `ownerKey`。 |

### 实现边界与验收

- Dart 侧新增抽象 `ShareService`，鸿蒙实现通过 `MethodChannel` 调用 ArkTS `ShareController`；其他端保持原有导出/复制链接路径，后续再分别接各平台分享实现。
- ArkTS 侧应使用精确的文件或链接类型，而不是一律按纯文本传递。
- 验收：PNG、SVG、场景文件和邀请链接分别能拉起面板；取消分享不影响编辑器；分享链接能加入房间；日志中不出现密钥；所有既有导出测试仍通过。

## 4. 推荐能力二：Pen Kit 全局取色（P1）

### 官方能力与适配价值

`imageFeaturePicker.pickForResult(displayX, displayY)` 可启动系统全局取色器，并返回所选位置的颜色和色域信息。官方约束为：需要设备支持手写笔；Tablet、PC/2in1 支持，Phone 从 5.1.1(19) 起增加支持。

它适合白板工具栏中的“吸管”按钮：用户从 PDF 背景、图片或屏幕中的其他内容取色后，立即应用到当前笔形或当前选中图形。它不涉及场景格式、协作协议或网络。

### 落地规则

1. 仅在用户主动点按“取色”后调用，传递触发位置的屏幕坐标。
2. ArkTS Channel 只返回安全的纯数据（例如 ARGB / 色域）；取消、设备不支持或 API 异常返回 `null`，Flutter 保持原颜色。
3. 色值进入现有笔形独立状态或选中元素样式，不保存系统截图，也不把取色过程写入协作消息。
4. 非鸿蒙端继续显示已有颜色选择器，不伪造“全局取色”能力。

## 5. 推荐能力三：Pen Kit 报点预测（P1，先验证）

### 官方能力与预期收益

`PointPredictor.getPredictionPoint(TouchEvent)` 根据当前 ArkTS 触摸事件返回预测点。官方将其定位为改善自定义手写画布的跟手性。

这只能改善**进行中的湿墨尾部延迟**，不能替代当前的轮廓曲线渲染、速度自适应滤波或压力建模；预测点不能进入最终 `FreedrawElement`、撤销历史、序列化或协同消息。

### 当前架构的关键阻碍

当前绘制发生在 Flutter surface，手写输入已经以 `PointerEvent` 到 Dart。官方 API 需要 ArkTS `TouchEvent`，而现有 `EntryAbility` 和 Platform Channel 并没有接收 Flutter 画布的逐帧原始 TouchEvent。因此，不能仅在 Dart 每个 `move` 时调用一个方法就正确使用 `PointPredictor`。

### 必须先完成的 Spike

1. 验证 Flutter OHOS 嵌入层是否可在不干扰 Flutter 事件分发的情况下取得同一原始触摸事件；若不能，应停止，不引入透明 ArkTS 覆盖层抢事件。
2. 验证坐标系、缩放、页面滚动和设备像素比转换后的预测点是否与 Flutter canvas 对齐。
3. 建立湿墨临时尾部：真实点到达时替换预测点；抬笔时丢弃预测尾部。
4. 对同一段回放数据测量端到端延迟、笔尖偏差和帧耗时；只有明显优于不预测路径才进入正式实现。

## 6. 推荐能力四：Form Kit 桌面卡片（P2）

### 合适的卡片范围

ArkTS 卡片支持静态、动态和互动三种形态；但卡片运行在独立渲染环境，且官方明确不支持跨平台 UI、native 语言或任意 API。因此它应是鸿蒙入口，不是 Flutter 页面镜像。

建议从静态或低频动态卡片开始：

- 最近编辑的一到两条笔记：标题、更新时间、缩略图；点击打开应用内对应笔记。
- “继续上次编辑”单动作。
- 可选的“进入协作房间”入口：仅显示房间名称/状态，点击后回到应用完成鉴权和解密；不在卡片保存或显示 roomKey。

不建议：在卡片中绘制可编辑白板、实时渲染协作光标、持续高频刷新，或把本地 SQLite 明文全量复制给卡片。

### 接入前提

- 新增 ArkTS `FormExtensionAbility` 与卡片资源；它不能复用 Flutter widget。
- 定义从 Flutter 到鸿蒙卡片的最小脱敏快照：笔记 ID、标题、更新时间、可公开缩略图引用；卡片点击后再由 Flutter 加载真实场景。
- 评估卡片刷新频率与功耗。静态卡片频繁刷新会反复创建/销毁运行资源，官方不建议这样使用。

## 7. 推荐能力五：Intents Kit 本地搜索（P2，产品验证）

Intents Kit 可让应用向 HarmonyOS 分享意图实体，由小艺搜索建立本地索引；也可接收系统对应用能力的调用。官方限制为 Phone、Tablet、PC/2in1，HarmonyOS 5.0 及以上，且仅限中国大陆。

对 FlowMuse 最合理的初始用例是：用户在小艺搜索输入笔记标题后，得到“在 FlowMuse 中打开该笔记”的结果。建议只索引用户明确授权的**笔记标题、笔记本名称和本地 ID 映射**，并做到：

- 不索引白板元素文本、手写识别原文、PDF 内容、协作房间链接或任何密钥；
- 支持用户关闭索引，并在关闭时删除已共享实体；
- 搜索结果只负责拉起应用，不直接在系统层展示私密笔记内容；
- 因地区和系统版本限制，功能入口必须可用性检测并静默隐藏，不能影响普通搜索。

在未完成用户隐私文案、删除语义和系统版本覆盖验证前，不建议开发。

## 8. 受限实验：一笔成形

Pen Kit `InstantShapeGenerator` 接收触摸事件，在停顿后异步返回 `ShapeInfo.shapePath`；官方示例使用 280ms 暂停时间。它很适合草图规整，但与当前产品有两层冲突：

1. 现有自由笔和直线/菱形/圆形是不同工具语义，自动替换会让用户无法预测笔画何时变成形状。
2. `Path2D` 不是 Markdraw 的 rectangle / ellipse / line / arrow 元素，也不天然满足 Excalidraw 的可编辑序列化和跨端一致渲染。

若后续验证，应仅在“手绘图形规整”显式模式下工作：识别结果先显示可撤销预览，用户确认后再由 Dart 侧把**已支持的类型**转换成现有形状元素；不能识别或无法保真转换时保留原自由笔画。协同只同步最终确认的标准元素。

## 9. 建议实施顺序

```text
Share Kit 系统分享
  -> Pen Kit 全局取色
  -> 报点预测 Spike（通过才进入湿墨实现）
  -> Form Kit 最近笔记卡片
  -> 用户隐私与地域验证完成后，再评估 Intents Kit
```

每一项都应单独建分支、通过 `flutter analyze`、相关 Flutter 测试和 `flutter build hap`；涉及鸿蒙原生 Channel 的变更还需按能力边界做真机验收。预测与一笔成形尤其要录制“真实点 / 临时点 / 最终点”的对照，不可只凭主观观感上线。

## 10. 参考资料

### 本地官方文档

- `harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发/pen-point-prediction.md`
- `harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发/pen-image-feature-picker.md`
- `harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发/pen-instant-shape.md`
- `harmonyos-guides/应用服务/Share Kit（分享服务）/系统分享/system-share-overview.md`
- `harmonyos-guides/应用服务/Share Kit（分享服务）/share-access-precautions.md`
- `harmonyos-guides/应用框架/Form Kit（卡片开发服务）/ArkTS卡片开发（推荐）/arkts-form-overview.md`
- `harmonyos-guides/AI/Intents Kit（意图框架服务）/intents-introduction.md`

### 在线官方资料（2026-07-11 访问）

- [Pen Kit](https://developer.huawei.com/consumer/cn/sdk/pen-kit)
- [Share Kit](https://developer.huawei.com/consumer/cn/sdk/share-kit/)
- [Form Kit](https://developer.huawei.com/consumer/cn/sdk/form-kit/)
- [HarmonyOS 多设备开发最佳实践](https://developer.huawei.com/consumer/cn/best-practices/multidevice/)
- [HarmonyOS 文档中心](https://developer.huawei.com/consumer/cn/doc/)

## 11. 调研边界

- 本文依据公开文档和当前源码判断可行性；实际 API 版本、设备支持范围和上架要求应在实施时再次核对官方最新文档。
- 对 Pen Kit 报点预测的“可接入性”尚未验证 Flutter OHOS 事件桥接，因而结论是 Spike，不是承诺。
- 本文不建议把 HarmonyOS 特性做成只在鸿蒙可用的核心数据格式；所有核心笔记、协作和编辑能力仍必须保持跨端可读写。
