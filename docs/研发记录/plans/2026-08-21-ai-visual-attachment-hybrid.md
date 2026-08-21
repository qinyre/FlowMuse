# FlowMuse AI 视觉上下文——融合方案书（A 线交互 × B 线底座）

> 分支：`feature/ai-visual-attachment`（已合并 A 线实现，合并提交 `436ba77`）
> 上游文档：
> - B 线总体方案：`docs/研发记录/plans/2026-08-21-ai-visual-attachment.md`
> - B 线详细执行计划：`docs/研发记录/plans/2026-08-21-ai-visual-attachment-execution.md`（经三轮子代理对抗审查至无反驳，其 §7 审查记录中的全部工程结论为本方案直接继承）
> - A 线计划：`docs/研发记录/plans/2026-08-21-ai-multimodal-a-line-phase1.md` / `phase2.md`（队友实现，已在库）

## 0. 背景与决策

两条并行线独立实现了"AI 理解画布视觉内容"：

| | A 线（队友，已合入） | B 线（原计划，未实施代码） |
|---|---|---|
| 交互 | 隐式：打开面板时选区含非文本元素即自动截图附带；选区快捷指令（解释这里/检查公式/整理文字/整理成导图） | 显式：用户点按钮添加附件、缩略图确认、可移除 |
| 捕获 | `exportPng(embedMarkdraw: false)`（PngExporter 路径） | `exportRegionPng`（新建区域渲染引擎，未实施） |
| 底座 | 无预热、无 resolvedImages、无错误映射细分、无日志 | 完整工程方案（渲染引擎/预热防护/校验护栏/日志脱敏） |

评审结论（详见两份文档的审查记录）：**A 线交互方向胜出**——选中即意图，快捷指令让能力可发现，演示路径最短；**B 线底座必需**——A 线当前存在功能阻断（PngExporter 不传 `resolvedImages`，选区含图片/PDF 背景元素时截图缺图，而其系统提示词却向模型承诺 "images, or PDF pages"）及资源泄漏、静默降级等缺陷。

**本方案决策**：以 A 线代码为基座，按 B 线已审查定稿的工程方案补齐缺口；产品规则取融合态（§1）。B 线 execution 计划作为验收清单继续有效，任务编号在本文以 T*' 标注差异。

## 1. 产品设计（最终交互形态）

### 1.1 附件条——单一事实源

AI 面板新增常驻附件条（沿用 B 线 T6 设计，替换 A 线的一行文字提示）：

- 已捕获附件显示为横向缩略图条：44px 预览（`cacheWidth: 88`）+ 来源标签 + KiB 大小 + 移除按钮；
- 上限 ≤3 张（任一来源混合计数），达上限后添加入口禁用并提示；
- **发送前始终可见**——把"知情"从流程步骤变成常驻状态，这是隐式路线获得隐私正当性的关键改造；
- `_loading || _applying || _capturing` 期间添加/移除禁用。

### 1.2 自动捕获规则（保留 A 线零摩擦，加控制阀）

1. 打开面板时，选区过滤 `!isDeleted` 后含非文本元素 → 自动捕获 1 张选区截图加入附件条（A 线行为保留）。
2. **移除即粘性**：用户手动移除自动加入的附件后，本次面板会话内不再自动重新加入（避免"删不掉"的体验）；关闭面板重开视为新会话。
3. 快捷指令强制补充：点击视觉类快捷指令（解释这里/检查公式/整理文字/整理成导图）时，若附件条为空且当前选区含视觉元素 → 即时捕获加入（捕获发生在用户按下表达视觉意图的按钮之后，构成知情同意时刻）。
4. 纯文本泛问不带图的条件由 1.2.2 保证（用户可一次性移除后自由提问）。

### 1.3 PDF 页入口（新增，来自 B 线）

附件条增加「PDF 页」chip：显式添加当前页原始位图（`pageForVisibleRect` 判页 → `Scene.files` 取 `isPdfBackground` 元素字节）。无选区也能用，覆盖"问整页 PDF 内容"场景。来源标签「PDF 第 N 页」。

### 1.4 追问语义

附件驻留面板状态、跨追问复用（B 线语义，替换 A 线的每次发送重捕获）——消除"中途取消选区导致追问时 AI 失明"的多轮不一致。「清除对话」同时清空附件。发送时随请求重发，隐私文案如实披露。

### 1.5 隐私文案（继承 B 线三轮审查定稿文本）

> 选区截图包含选区矩形内的全部可见内容（可能含未选中的相邻内容）；PDF 页附件为导入时的整页原始位图（不含白板批注）。仅发送你添加的 N 张图片，不会自动上传附件之外的画布图像内容（文字上下文仍按既有规则随请求发送）；追问时附件将随每次请求重新发送，直到移除或清除对话。发送前请确认。

### 1.6 失败处理（反转 A 线的静默降级）

捕获/归一化失败不再静默返回 null：业务失败抛 `StateError`（消息即用户文案），面板写入既有 `_error` 展示、不打断纯文本路径。文案继承 B 线定稿："请先在画布选中要发送的内容"、"图片解码失败，请重新打开笔记后重试"、"图片过大，请缩小选区后重试"、"当前笔记没有 PDF 页面"、"当前页面不是 PDF 页"、"图片处理失败，请重试"。

## 2. 架构与代码归属

| 模块 | 来源 | 处置 |
|---|---|---|
| `ai_agent_repository.dart`：attachments 参数、vision parts、`_post` 注入 typedef | A 线 | **保留**。增量：错误映射提为纯函数 `aiVisualAttachmentError`（{400,413,415,422}，404 落通用）；补 `[AiAgent]` 日志（attachments 数量/bodyKChars/status/elapsedMs，KChars 为 UTF-16 码元口径） |
| `ai_visual_attachment.dart` 模型 | A 线 | **改造**（T1'）：修双资源泄漏（`ImmutableBuffer`、`frame.image` 未 dispose）；加 `maxPixelCount`（默认 4096×4096）维度护栏于首解之前；最长边上限 2048→1568（待产品确认，见 §5）；增加 PNG 8 字节魔数校验（PDF 页路径的字节来自 Scene.files，需防手工构造文件）；`buildAiVisualAttachment` 失败改抛错或返回结构化结果，不再静默 null |
| editor_core 渲染引擎 `exportRegionPng` + `prewarmRegionImages` + `pageForVisibleRect` 公开 | B 线 T3 | **新建**（A 线最大缺口）。完整执行 execution.md T3，含：resolvedImages 传入（修缺图）、skipMathText:true、contentBounds、isDarkBackground 同源、分页裁剪、markDecoding(相交子集)+onImageDecoded 暂停+单次刷新预热防护、peek-only 解析、try/finally 资源释放 |
| `visual_attachment_capture.dart` 捕获模块 | B 线 T4 | **新建**。选区路径改用新引擎（替换 whiteboard_page 直调 exportPng）；PDF 页路径新增；`normalizeAttachmentPng(byteLimit, maxPixelCount)` 归一化 |
| 面板：阶段态（preparing/generating）、异步 contextProvider、选区快捷指令、平板宽面板 | A 线 | **保留**。增量：插入附件条 UI 与隐私文案（T6'）；`_generate` 改从附件条状态取值；新增 `_addAttachment`/`_removeAttachment` 与粘性移除标记 |
| `whiteboard_page.dart` 接线 | A 线 | **调整**：改为传捕获回调（`onCaptureSelection`/`onCaptureCurrentPdfPage`），捕获时机由面板驱动（1.2 规则），不再在 `_currentAiAgentContext` 内联捕获 |

依赖方向不变：ai_assistant → editor_core（barrel 导入），editor_core 不 import ai_assistant，无 `Platform.is*`，无新通道/依赖。

## 3. 技术不变量（全部继承自 B 线三轮审查结论）

1. **PNG 纯净性**：附件字节禁止携带 tEXt/iTXt/zTXt（禁 `embedMarkdrawData`）；测试 chunk 反验锁定。
2. **预热三件套**：`decodeAndWait` 循环前 `markDecoding(相交子集)` 占位 + 暂停 `onImageDecoded` 回调 + finally 恢复并单次 `notifyListeners()`——防 await 窗口内解码完成触发全场景并发解码风暴（>50 图场景峰值可达 90–350MiB）及同 fileId 双解码泄漏。
3. **peek-only 解析**：区域导出禁用 `resolveImages()`（副作用边界在 prewarm 的 await 窗口）。
4. **维度护栏**：归一化首解前拦截超大像素数（引擎对 PNG 无原生缩放解码，重缩放分支会全尺寸解码）。
5. **资源纪律**：ImmutableBuffer/ImageDescriptor/codec/frame.image/Picture/ui.Image 全部 dispose，异常路径 try/finally 兜底。
6. **错误映射**：仅带附件且 {400,413,415,422} 返回专用文案；401/403/404/500 落通用，防误导排查。
7. **日志脱敏**：只记数量/规模/状态码/耗时，无 token、无正文、无图片字节（AGENTS.md §9）。
8. **0 附件回归**：请求体与现状逐字节一致，测试锁定。
9. **已知边界如实披露**：相交图片 >50 时预热自我逐出、报错但重开笔记无法兑现（缓存容量语义）。

## 4. 任务分解（以 execution.md 为验收清单的差异标注）

| 任务 | 内容 | 相对 execution.md 的差异 |
|---|---|---|
| T1' | 改造 A 线模型文件 | 非"新建"；保留 `validated` 工厂外壳，注入上述修正；测试合并双方用例（A 线 8 例 + B 线 §3.1 10 例去重） |
| T2' | 仓库层增量 | 错误映射纯函数 + 日志；A 线 `_post` 注入保留；0 附件逐字节回归基线测试补齐（A 线仅有 content 类型断言） |
| T3 | 渲染引擎 | **原样执行** B 线 T3（含 §3.3 全部 9 个用例，图片用例经 applyResult 注入） |
| T4' | 捕获模块 | 选区路径逻辑同 B 线 T4；PDF 页路径新增；`byteLimit`/`maxPixelCount` 注入参数保留 |
| T5' | 接线调整 | whiteboard_page 从内联捕获改为回调传递 |
| T6' | 面板融合 | B 线 T6 附件条 + A 线壳保留项 + §1.2 自动捕获粘性规则 + 快捷指令钩子；`showAiAgentDialog` 新参数保持可选默认（旧调用方零回归） |
| T7 | 门禁与文档同步 | 项目需求.md 合并 A/B 两线描述为「AI 视觉上下文」一节 |

提交切分建议：C1 = T3（先修缺图，独立可交付）；C2 = T1'+T2'；C3 = T4'+T5'；C4 = T6'；C5 = T7。每个 commit 自含可绿测试。

## 5. 待产品确认项（不阻塞 C1-C3 开工）

1. 最长边 1568 vs 2048：1568 为 OpenAI 视觉经济档（低分辨率计费阈值 2048 内但 token 与 512² 短边换算更优）；建议 1568，若队友有实测清晰度理由可维持 2048。
2. 首次自动捕获是否需要一次性引导说明（"选区内容将随提问发送给模型"）——倾向不加，附件条常驻可见已充分。
3. PDF 页是否允许多页连选（当前设计单次一张、总量 ≤3 封顶）。

## 6. 风险与回滚

继承 B 线 execution.md §5 全部风险行（鸿蒙 STRING 通道大 payload 延后实测、60MiB 请求体峰值量化、zoom≤98、快照穿透窗口等），另增：

| 风险 | 缓解 |
|---|---|
| 自动捕获与用户意图错位（残留选区被误附） | 附件条常驻可见 + 粘性移除 + 快捷指令才强制补充；实机验收观察误附率 |
| A/B 测试用例合并冲突（双方都改 ai_assistant 测试） | 已在本次合并解决一轮；后续按任务归属分区维护（A 线用例不动，B 线新增独立文件为主） |
| 双计划文档并存造成实施歧义 | 本文为准；B 线文档降级为"验收清单 + 工程依据"，A 线 Phase 文档标记已被本方案取代 |

## 7. 审查记录

（待第一轮对抗审查——建议沿用三路子代理模式对本文与合并后代码复审）
