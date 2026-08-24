# R3 资源安全回归审查（第一轮）

审查对象：`docs/研发记录/plans/2026-08-21-ai-visual-attachment-hybrid.md`（下称"方案"）
对照基线：`docs/研发记录/plans/2026-08-21-ai-visual-attachment-execution.md`（下称 execution.md）+ 合并后 A 线代码（`436ba77`）

## 结论：可行但需修订

核心防线（解码风暴三件套、PNG 纯净性、日志脱敏、0 附件字节回归、错误映射合并、60MiB 量化与鸿蒙通道风险继承）方向正确且大体可实现；但存在 5 项 Important 级缺口：预热三件套对"decodeAndWait 与在途解码并发"不闭合（方案声明的双解码防线未兑现，且修复需触及任务范围外的 image_cache.dart）、新旧两套归一化实现并存、PNG 纯净性不变量在 PDF 页路径不可验证、测试合并存在多处必挂/自相矛盾点未盘点、自动捕获在途期间快捷指令/发送语义未定义。无 Critical 级（用户可感知事故型）缺口。

## 发现清单

### [Important] 1. 预热三件套防不住 decodeAndWait 与"已在途解码"的并发——§3.2 声称的"同 fileId 双解码泄漏"防线未闭合，修复落在任务范围外

- 证据：
  - `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/image_cache.dart:40-43`——`decodeAndWait` 只检查 `_cache.containsKey || _failed.contains`，**不检查 `_decoding`**；
  - `image_cache.dart:30-33`——`getImage` 才是受 `markDecoding` 占位保护的入口；`image_cache.dart:83`——`_cache[fileId] = image` 直接覆盖，旧 `ui.Image` 不 dispose；
  - `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart:2943`——`loadScene` fire-and-forget 调 `_prewarmImageCache()`，`:2950-2963` 其循环同样逐个 `decodeAndWait`；
  - `markdraw_controller.dart:5594`（exportCoverThumbnail）与 `editor_canvas.dart:411`（每次重绘）经 `resolveImages()`→`getImage` 启动的异步 `_decode` 在面板打开前即可在途；
  - 方案 §3.2 / execution.md T3 注释自述威胁模型"decodeAndWait 不检查 _decoding……双重 _decode 泄漏旧 ui.Image"。
- 问题：`markDecoding(相交子集)` 只能阻止 `getImage` **新启动**解码，无法阻止 `prewarmRegionImages` 的 `decodeAndWait` 与一个**已在途**的 `_decode` 对同一 fileId 并发。两条可达路径：
  1. 打开笔记后大图/PDF 场景 `_prewarmImageCache`（串行循环可持续数秒）仍在跑时，用户打开 AI 面板触发自动捕获（§1.2.1），`prewarmRegionImages` 与 loadScene 循环对相交 fileId 并发 `decodeAndWait`；
  2. 画布重绘（editor_canvas.dart:411 / exportCoverThumbnail:5594）刚对某 fileId 启动 `_decode`（大图解码几十至几百 ms），用户立刻选中并打开面板/按快捷指令，prewarm 对同一 fileId 再解一次。
  两次 `_decode` 后完成者覆盖 `_cache` 条目，先完成者的全尺寸 `ui.Image` 依赖引擎 finalizer 延迟回收（Dart GC 感知不到 native 内存压力），并使 `_lruOrder` 出现重复条目。这正是方案 §3.2 声称已防住的泄漏，且修复必须改 `image_cache.dart`（如在缓存内维护 `Map<String, Future<void>>` 在途表，让 `getImage`/`decodeAndWait`/`markDecoding` 共享同一 Future）——而 T3 任务边界只允许向 markdraw_controller.dart 增方法，execution.md §0 修订 4 明确"预热逻辑放入控制器公开方法"，没有任何任务覆盖 image_cache.dart 的改动。
- 建议：为 T3 增补一条子任务——`ImageElementCache` 内部去重在途解码（in-flight Future 共享），`decodeAndWait` 命中在途 Future 时 await 而非重解；同步在 §3.3 增一个"prewarm 与 loadScene 预热并发不产生双重解码"的用例（两条循环交错启动）。若判断该并发在实际交互中不可达或可接受 finalizer 兜底，则必须把 §3.2 不变量措辞收窄为"防 getImage 触发的新增解码风暴"，如实反映防线边界。

### [Important] 2. `buildAiVisualAttachment`（T1' 改造保留）与 `normalizeAttachmentPng`（T4' 新建）双归一化实现并存，防线参数分叉

- 证据：
  - 方案 §2 模型行：T1' "保留 `validated` 工厂外壳，注入上述修正；……`buildAiVisualAttachment` 失败改抛错或返回结构化结果，不再静默 null"；§2 捕获模块行：T4' 新建 `normalizeAttachmentPng(byteLimit, maxPixelCount)`；
  - 现状 `FlowMuse-App/lib/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart:62-97`：`buildAiVisualAttachment` 自带一套归一化（2048 上限、无 maxPixelCount 维度护栏、无 PNG 魔数校验、`ImmutableBuffer`/异常路径资源泄漏）；
  - 其唯一调用点是 `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart:692`，而 T5' 将把 whiteboard_page 改为传捕获回调（经 T4' 捕获模块→normalizeAttachmentPng）。
- 问题：T5' 改线后 `buildAiVisualAttachment` 变成零调用方的活代码，与 `normalizeAttachmentPng` 形成两套语义不同的归一化（最长边 2048 vs 1568、有无解压炸弹护栏、有无魔数校验、构造签名 5 参 vs 3 参——A 线 `validated` 还要求 width/height 字段，B 线构造器无此字段）。后续任何维护者误走旧路径即绕过全部新防线（含 maxPixelCount 解压炸弹护栏），违反 AGENTS.md §3"复用优先/绝不重复造轮子"，也是典型"防线分叉后静默劣化"源。
- 建议：T1' 明确写死处置——删除 `buildAiVisualAttachment`（连同 `validated` 的 width/height 字段取舍一并定稿），或将其改为对 `normalizeAttachmentPng` 的薄委托；并在 T7 门禁加"模型文件内不得存在第二套归一化循环"的检查项（grep `instantiateCodec`/`instantiateImageCodec` 只允许出现在捕获模块）。

### [Important] 3. PNG 纯净性不变量（§3.1）只对选区渲染路径可验证，PDF 页/手工构造字节路径无 chunk 防线

- 证据：
  - 方案 §3.1："附件字节禁止携带 tEXt/iTXt/zTXt……测试 chunk 反验锁定"；§3.3-#4（execution.md）的 chunk 反验**只测 `exportRegionPng` 的输出**（引擎生成的干净 PNG）；
  - execution.md T4：`normalizeAttachmentPng` "已合规的输入原样返回（不重编码）"；PDF 页路径直接取 `Scene.files` 字节（T4 `captureCurrentPdfPageAttachment`），仅有 mime 白名单 + T1 魔数校验；
  - execution.md §7 第一轮 S1 自述威胁模型："Scene.files 可经手工构造的 .markdraw/Excalidraw 文件载入任意 mimeType+bytes 组合"；
  - execution.md §7 已驳回建议表：驳回"PDF 页附件每次发送前强制重编码"，理由是"生产路径字节来自导入时系统 PDF 渲染的新鲜位图"——该理由只覆盖生产路径，未覆盖 S1 自己指出的手工构造路径。
- 问题：一个带合法 PNG 魔数、mime='image/png'、但内嵌 tEXt/iTXt chunk（最大可至 4MiB 文本）的手工构造 .markdraw 文件，经 PDF 页入口（或任何未来复用 Scene.files 的入口）可原样通过全部校验直达用户配置的 LLM 端点。危害有限（主要是共享笔记场景下的元数据外发/提示注入面），但 §3.1 作为"全部附件字节"的不变量与实现不符，防线声明强于实际。
- 建议（二选一，写入 T1'）：a) 在 `requireValidAiVisualAttachments`（或 PDF 页捕获入口）加一次 PNG chunk 类型线性扫描（4MiB 内纯 Dart 扫描开销微秒级），发现 tEXt/iTXt/zTXt 即拒，配一个用例锁 PDF 路径；b) 把 §3.1 不变量收窄为"选区渲染路径产出零文本 chunk；PDF 页路径字节来自导入渲染器（手工构造文件为已接受的残余风险）"，并把共享笔记分发场景列入 §6 风险表。

### [Important] 4. 测试合并的三类必挂/自相矛盾点未被盘点——§6"测试合并冲突"风险行的具体清单缺失

- 证据与问题（三组）：
  1. **B 线用例表内部矛盾**：execution.md §3.1 用例 5 输入 `Uint8List(maxAiVisualAttachmentBytes + 1)`（全零字节）期望 `'单张图片需小于 4 MiB'`，但同文件 T1 骨架的校验顺序是 mime→空→**魔数**→大小，全零字节会先命中魔数检查抛 `'仅支持 PNG 图片附件'`——按规格实现必挂。用例 1 的"3 张合法"也需要真 PNG 魔数字节才能通过，规格未注明。
  2. **A 线既有测试与魔数校验冲突**：`FlowMuse-App/test/features/whiteboard/ai_assistant/ai_agent_repository_test.dart:70/103/127`、`ai_agent_dialog_test.dart:342/391` 均以 `[1,2,3,4]`/`[1]` 等非 PNG 字节构造"合法"附件；`ai_visual_attachment_test.dart:22-34` 以 `bytesOf(1024)`（全零）当"合法 PNG"。魔数校验无论落在 `validated` 工厂还是 `requireValidAiVisualAttachments`，这批用例全红。方案 T1' 只写"测试合并双方用例（A 线 8 例 + B 线 10 例去重）"，未提这三个文件的改写。
  3. **A 线 dialog 测试锚定旧交互**：`ai_agent_dialog_test.dart:354-355` 断言旧隐私文案（`'1 张选区截图'`/`'模型服务'`，对应 `ai_agent_dialog.dart:591-593` 现文案，T6' 将替换为 B 线文案，两断言必红）；`:386-411` 经 `showAiAgentDialog` 的 `attachments` 参数走"每次发送由 contextProvider 重捕获"旧流（`ai_agent_dialog.dart:279` `attachments: context.attachments`），T6' 改面板驻留后此注入通道废弃或语义变更；另 `ai_visual_attachment_test.dart:101-108` 断言缩放上限为 `maxAiVisualEdgeLength`（2048），§5 若定稿 1568 则需同步改。
- 建议：T2'/T6' 各增一行"存量测试改写清单"，逐文件列出上述断言的处置（改字节为基准 PNG / 改文案期望 / 改注入路径为捕获回调 / 改 2048→1568）；修正 B 线 §3.1 用例 5 的输入构造（PNG 签名前缀 + 超长填充）或调整校验顺序并同步说明。这是防"假绿"（实现者为迁就红测试而弱化校验顺序/魔数）的必要前置。

### [Important] 5. 自动捕获在途期间，快捷指令"强制补充"与发送的语义未定义——`_capturing` 门控会静默吞掉 §1.2.3 的承诺

- 证据：方案 §1.2.3"点击视觉类快捷指令时，若附件条为空且当前选区含视觉元素→即时捕获加入（强制补充）"；§1.1/T6' 沿用 execution.md T6 的 `_addAttachment` 门控 `if (_loading || _applying || _capturing) return;`（静默返回）；§1.2.1 自动捕获发生在"打开面板时"，大图场景预热+导出耗时数百毫秒。
- 问题：面板刚打开、自动捕获仍在途（`_capturing=true`、附件条显示 0 张）时：a) 用户点视觉快捷指令→强制补充走 `_addAttachment` 被门控静默跳过，违背"强制补充"；b) 用户直接发送→0 附件纯文本发出，与用户刚表达/期望的视觉意图不符（多轮不一致问题以新形态回归）；c) 隐私计数文案在捕获完成前后从 0 翻到 1，瞬时不准确。方案未定义 `_generate` 是否应等待在途捕获、快捷指令是否应排队或提示。
- 建议：T6' 明确规则，例如：`_generate` 开头 `if (_capturing) await _pendingCapture`（或发送按钮并入 `_capturing` 禁用集）；快捷指令补充在 `_capturing` 时改为等待而非跳过；并补一个"捕获在途时点快捷指令→发送带 1 张附件"的 dialog 用例。

### [Minor] 6. T2' 未重申附件校验顺序，与 A 线现状顺序不一致

- 证据：execution.md T2 定稿唯一顺序"instruction→title→附件→会话压缩→texts→config（勿再调整）"；A 线现状 `ai_agent_repository.dart:56-75` 附件校验在会话压缩与 texts 循环**之后**。方案 T2' 只写"错误映射纯函数+日志"，未声明是否执行重排。
- 问题：不重排则与 execution.md 验收清单冲突；重排则改变"texts 非法 + 附件超限"同错时的异常消息（无用户可见危害）。
- 建议：T2' 补一句"校验顺序按 execution.md T2 定稿执行"。

### [Minor] 7. 控制器 `_disposed` 后在途 `_decode` 仍向已 dispose 的缓存写入（存量缺陷，新增捕获路径略增触发面）

- 证据：`markdraw_controller.dart:715-720`（dispose 先置 `_disposed` 再 `_imageCache.dispose()`）；`image_cache.dart:77-95` `_decode` 完成时无 disposed 检查，`:83` 写入已清空的 `_cache`。AI 面板捕获（T4'）延长了控制器销毁与解码并发共存的窗口（用户在捕获/预热中关闭笔记页）。
- 问题：控制器销毁后完成解码产生的 `ui.Image` 无人释放（同样依赖 finalizer）。
- 建议：可延后；若修，`ImageElementCache` 加 `_disposed` 标志并在 `_decode` 完成段早退即可（与发现 1 同文件，宜一并处理）。

### [Minor] 8. 隐私文案"仅发送你添加的 N 张图片"与 §1.2.1 自动捕获存在措辞张力

- 证据：方案 §1.5 文案定稿于 B 线"显式添加"语境；§1.2.1 引入"打开面板自动捕获 1 张"（非用户主动添加，虽常驻可见且可移除）。
- 问题："你添加的"对自动加入项不准确，可能被质疑知情同意口径（§1.1 自己强调"把知情变成常驻状态"是隐式路线的正当性根基）。
- 建议：文案微调为"仅发送附件条中的 N 张图片"，或"随请求发送附件条中显示的 N 张图片"。

### [Minor] 9. execution.md 对 `exportCoverThumbnail` 资源防护的表述不准确（文档事实性）

- 证据：execution.md T3 设计说明"存量 `exportCoverThumbnail` 无此防护属历史瑕疵"；实际 `markdraw_controller.dart:5600-5607` 成功路径有 `image.dispose(); picture.dispose()`，缺的只是异常路径 try/finally。
- 问题：不影响实施；但 execution.md 是"验收清单+工程依据"，事实错误会误导后来者对存量风险等级的判断。
- 建议： opportunistically 修正一句（"异常路径无防护"）。

### [Minor] 10. T6' 未逐项列出 execution.md T6 第 5 点的三处既有方法修改

- 证据：execution.md T6 第 5 点：`_generate()` 取 `attachments: _attachments`、`_clearConversation()` 清空附件、`_errorMessage` 增加 `TimeoutException` 分支（现状 `ai_agent_dialog.dart:401-405` 确无该分支）。方案 §2 面板行只概括为"插入附件条 UI 与隐私文案（T6'）；`_generate` 改从附件条状态取值"，未提 `_errorMessage` 的 Timeout 分支与 `_clearConversation` 清附件。
- 问题：以 execution.md 为验收清单时这些会被继承执行，风险低；但 `AiAgentContextSnapshot` 的 `attachments` 字段（`ai_agent_dialog.dart:16-24` typedef）去留也未定，涉及 `showAiAgentDialog` 既有参数（`:37/:55`）的废弃路径，与发现 4.3 相关。
- 建议：T6' 补齐清单；`AiAgentContextSnapshot.attachments` 字段与 `showAiAgentDialog` 旧 `attachments` 参数明确定义为"移除"或"保留但标记 deprecated 不再读取"。

## 已核实无问题的审查点（供第一轮对账）

- **日志脱敏**：T2' 增量字段（attachments 数量/bodyKChars/status/elapsedMs）不含内容与字节，符合 AGENTS.md §9；KChars（UTF-16 码元）口径已注记，够用。附件 base64 无路径进入日志：`native_http_client.dart:100` 仅记 URL；HttpChannel.ets 全程不打 body；错误消息全为固定文案；A 线唯一的 `debugPrint('…降级纯文本: $error')`（whiteboard_page.dart:695）随 T5' 改线移除。
- **60MiB 量化自洽**：12MiB 原始字节 + 16MiB base64（Latin-1 单字节串）+ jsonEncode 输出与通道编码副本 ≈ 60MiB Dart 堆峰值，与 §6 行一致；仅补充一点——12MiB 原始附件因驻留语义（§1.4）存活整个面板会话而非仅网络往返，可在 §6 行注明。
- **鸿蒙通道**：`HttpChannel.ets:96-117` doPost 以 string extraData 透传、无显式大小上限，"STRING 通道大 payload 延后实测"被 §6 正确继承为风险而非已解决 ✓。
- **错误映射合并**：B 线 `aiVisualAttachmentError`（400/413/415/422 专用、404 落通用）与现状 `ai_agent_repository.dart:123-125` 的 400 专属分支可平滑替换；现有断言 `contains('视觉')`（ai_agent_repository_test.dart:141）对新文案仍绿；404 落通用与 B 线三轮结论一致，现状无 404 分支无冲突。
- **0 附件字节回归可实现**：Dart Map 按插入序迭代，`jsonEncode` 输出确定；A 线现状与 B 纯函数的键序（model/messages/tools/tool_choice/temperature；role→content；type→image_url→url）逐位一致，测试可用编码后字符串等值锁定（注意 deep-equals 不等于字节级，建议直接比较 `jsonEncode` 串）。
- **渲染引擎骨架可编译**：`StaticCanvasPainter` 具备 T3 骨架用到的全部命名参数（static_canvas_painter.dart:75-91，含 resolvedImages/isDarkBackground/contentBounds/renderPageShadows/skipMathText/gridSize/layout）；`_pageForVisibleRect`（:4554-4595）私有、内部唯一调用点 :4440，改名零风险；`selectedElements`（:616-622）不过滤 isDeleted，捕获侧自行过滤的要求已在 execution.md §1 事实表登记。
