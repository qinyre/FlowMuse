# 审查报告 C3/T4'+T5'（diff c8715b1..489789b，单 commit `feat:选区截图与PDF页视觉附件捕获`）

审查人：spec 合规 + 代码质量双裁决子代理。日期：2026-08-21。
权威依据：融合方案书 v5（§1.2 契约、§1.6 失败文案集合、§2 捕获模块/接线行、§3 不变量 4/5、§4 T4'/T5'、§4.1-4/7）> execution.md（T4/T5 骨架 408-594 + §3.4 用例表 810-826）> 实现者报告。

**结论：Spec ❌（21/22 项，缺 §1.6 PDF 路径"图片过大"专用文案 1 项），Needs fixes。Critical 0 / Important 1 / Minor 0（另 4 项信息级记录 + 实现者自报 2 偏差均裁决接受）。**

除报告自述证据外，本审查独立完成的核验：
- **全量重跑**：`flutter test` 413 passed / 0 failed（00:31）；新文件单独重跑 14/14 全绿。
- **analyze 零新增实证**：37 issues 逐文件清点，涉 issue 的 15 个文件与本次 6 个触改文件**零交集**（触改文件零 issue），未触碰文件的 issue 不可能由本 diff 引入——比报告的"stash 对比 37"更强的证明。
- **pageForVisibleRect 源码走读**（markdraw_controller.dart:4561-4600）：nearest 回退实证（有页永不返回 null），其 doc 注释本身即警告 "callers … must not rely on a null return"；对测试 #7 场景（页 y=5000、视口 (0,0,800,600)、pdfBackground 元素 pageId 与页同 id）推演：若沿用骨架的 `page == null` 判定，会经 nearest 拿到页、pageId 匹配成功、**错误附上视口外的页图走通**——新实现的 `!visible.overlaps(page.bounds)` 判定正确拦截，该陷阱已被用例锁定（R3-F3 落实）。
- **守卫迁移等价性**：BASE c8715b1 的 `_currentAiAgentContext`（:652-653 先 `!isDeleted` 过滤，:681-684 再 `is! TextElement`）与新守卫 `selectedElements.any((e) => !e.isDeleted && e is! TextElement)` 逐语义比对**等价**；`selectedElements` getter（:616-621）为 selectedIds→getElementById 同步映射，`selectedIds.isEmpty` 短路与 any() 双读在同一同步窗口无竞态。
- **防御分支确不可达**：ExportBounds._collectElements（export_bounds.dart:44-53）实证过滤 `isDeleted`，守卫保证 ≥1 活选区元素 ⇒ compute 必非 null；报告"理论不可达"表述属实。
- **C1 API 签名核对**：`exportRegionPng(Rect,{maxLongestSide})→Future<Uint8List?>`、`prewarmRegionImages(Rect)→Future<int>`（失败计数，消费正确：>0 → '图片解码失败，请重新打开笔记后重试'）、`pageForVisibleRect(Rect)→CanvasPage?`、`ExportBounds.compute(Scene,{selectedIds,padding})→Bounds?`（left/top/size.width/size.height 取法与 Bounds 形状一致）。
- **依赖类型实证**：`isPdfBackground`/`pageId` 系 `FlowMuseElementData` 扩展（canvas_layout.dart:248-257）；`pdfBackgroundCustomData` 写 pageId+pdfBackground:true（:209-213）；`ImageFile{mimeType,bytes}` 存在；均经 barrel 导出。canvasSize 800×600 兜底与控制器现行实现一致（实际 :1842，注释写 :1843，行号漂移 1 行、事实一致）。
- **删除彻底性**：`buildAiVisualAttachment` 全树 grep 仅余注释与历史计划文档；'请先在画布选中要发送的内容' 生产代码零残留（仅测试注释引述修订理由）；whiteboard_page:2067 的 `exportPng` 系 `_fileHandler` 分享路径，与 AI 捕获无关。归一化单点预检：ai_assistant 树内 `instantiateCodec|instantiateImageCodec` 仅存在于 capture 文件（T7 门禁可过）。
- **边界核验**：diff 恰 6 文件，editor_core、pubspec.yaml、ai_agent_dialog_test.dart、showAiAgentDialog 参数零触碰；`Platform.is` 三触改文件 grep 为空；commit 树 c8715b1..489789b 恰 1 commit。
- **ai_agent_dialog.dart 改动面清点**：+9 行 = 2 构造参数 + 2 字段 + 契约 doc 注释；面板 State 全文 grep 无 onCapture* 读取（默认 null、零行为变更成立）。初始快照 `attachments: initialContext.attachments`（恒 const []，与 BASE OverlayEntry 丢弃时的默认值等价）+ `hasSelection: initialContext.hasSelection`（BASE :628-639 确实丢弃，此传参即 §0 缺陷修复，使 :513 快捷指令列表开面板即正确显示）。

## Spec 合规清单

| # | 要求（来源） | 结果 | 证据 |
|---|---|---|---|
| 1 | null 守卫：选区过滤 !isDeleted 后含非文本元素否则**返回 null 不抛错**（§1.2/§4.1-4） | ✅ | capture:24-27；与 BASE visualSelected 语义等价（见核验）；空选区与纯文本选区两断言（测试 #5） |
| 2 | StateError=真失败；消息即用户文案（§1.2） | ✅ | prewarm 计数>0 / exportPng null / 归一化三处均抛；旧"请先选中"文案零残留 |
| 3 | ExportBounds.compute null 防御分支返回 null | ✅ | capture:29；_collectElements 过滤 isDeleted 实证该分支不可达，报告如实披露 |
| 4 | 构造附件带 kind（selection/pdfPage）+ 标签 '选区截图'/'PDF 第 N 页'（§2） | ✅ | capture:50-55/:120-125；测试 #9/#11 断言 kind 与标签 |
| 5 | PDF 双文案：场景无 !isDeleted&&isPdfBackground 元素→'当前笔记没有 PDF 页面'；有但视口不在页内→'当前视图不在 PDF 页面内，请先滚动到 PDF 页'（§1.6/§4.1-7） | ✅ | capture:62-69；场景扫描带 !isDeleted（已删背景不计入"场景含 PDF"，语义较字面更正确）；测试 #6/#7 锁两分支 |
| 6 | 视口判定用 visible.overlaps(page.bounds)，**不得**依赖 pageForVisibleRect 返回 null（R3-F3） | ✅ | capture:63；nearest 回退源码实证 + 测试 #7 陷阱场景（页 y=5000、pageId 匹配，旧判定会错误走通附错页图） |
| 7 | normalizeAttachmentPng 档位 1568/1280/1024/768、首值=常量 | ✅ | capture:18-23；与骨架逐字一致 |
| 8 | 已合规原样返回（不重编码） | ✅ | capture:13-16 返回原对象；测试 #1 `identical(input, output)` 真锁定 |
| 9 | byteLimit/maxPixelCount 注入参数，默认全局常量/4096×4096（不变量 4） | ✅ | capture:8-11；测试 #3/#4/#14 经注入断言 |
| 10 | maxPixelCount 于首解前拦截（只读头不解码像素） | ✅ | _pngDimensions 用 ImageDescriptor.encoded（仅解析头部）；护栏先于 _rescalePng 的全尺寸解码 |
| 11 | 资源 try/finally（不变量 5） | ✅ | _pngDimensions 骨架原样；_rescalePng 补 try/finally（见偏差②裁决：骨架原版违反 §3.5-5，此修复为权威要求） |
| 12 | AiAgentPanel 增两个可选回调 `Future<AiVisualAttachment?> Function()?` 默认 null 零行为变更（R2-Y1） | ✅ | dialog +9 行清点；State 零读取；契约 doc 注释含 null/StateError 语义 |
| 13 | showAiAgentDialog、dialog UI 逻辑、dialog 测试一概不动 | ✅ | 签名原样；diff 无 ai_agent_dialog_test.dart；全量 413 含 dialog 14 例全绿 |
| 14 | T5' 接线：两回调绑定 _markdrawController | ✅ | whiteboard_page:634-637，与 execution T5 骨架写法一致；顶部 import 增补 |
| 15 | 初始快照完整传入面板（含 hasSelection，修复 OverlayEntry 丢弃） | ✅ | :632-633；BASE :628-639 丢弃实证；attachments 恒空传入与旧默认值等价（零回归） |
| 16 | _currentAiAgentContext 内联捕获移除；快照 attachments 恒空 const [] 保留（字段删除属 C4）；'，含视觉内容' 死分支等价移除 | ✅ | exportPng+buildAiVisualAttachment+debugPrint 块整体删除；分支条件永假故等价；typedef 字段原样 |
| 17 | buildAiVisualAttachment 删除且全树无引用、dart:ui 导入连带删 | ✅ | grep 仅注释/计划文档；模型文件零 dart:ui |
| 18 | 3 个归一化行为用例迁入捕获测试 | ✅ | 小图→#1（identical 加强）；超大长边→#2（1568×784，输入换 §3.4-#2 规范值 2000×1000，行为类同）；非法字节→#12 语义按新契约改抛 '图片处理失败，请重试'（§1.6 反转静默降级所致，测试注明缘由）；ai_visual_attachment_test.dart 恰删 3 例+2 助手 |
| 19 | §3.4 表 12 用例全部落实（#5/#6 按修订）+ 新增 PDF chunk 扫描用例 | ✅ | 14 例映射齐（#1-#14 ↔ 表 #1-#12 + R3-F3 陷阱 + chunk 扫描）；chunk 扫描含手写结构化解析断 tEXt/iTXt/zTXt 缺席 + 模型层全量校验通过 |
| 20 | editor_core 零改动、无新依赖、无 Platform.is* | ✅ | diff 6 文件清点；pubspec 未触；grep 为空 |
| 21 | **§1.6 PDF 路径"图片过大"专用文案 '该 PDF 页面图片过大，无法作为附件发送'** | ❌ | 全库 grep 该串不存在（来源：round1 R1-M 建议，v2 吸收入 §1.6 定稿文案集合）；captureCurrentPdfPageAttachment:118 直接透传 normalizeAttachmentPng 的 '图片过大，请缩小选区后重试'——"缩小选区"指引对 PDF chip 不可执行。继承自 execution T4 骨架（骨架与 §1.6 冲突未 reconciled；简报权威序规定 hybrid 优先）。可达性：标准导入 targetPageWidth=1600（pdf_page_renderer.dart:15，A4 约 1600×2263=3.6M px）通常不触发，但超长页（宽 1600×高 >~10486px 即破 4096×4096 像素护栏）或手工构造 .markdraw 大图可触发——后者正是本计划明确防御面（mime 白名单/chunk 扫描同源威胁模型） |
| 22 | 单 commit、全量测试全绿、analyze 零新增 | ✅ | 独立重跑 413/0 + 37 issues 全在未触文件（见核验）；commit 树恰 1 commit，信息符合仓库惯例 |

## 任务质量

- **正确性**：未发现任何逻辑错误。tier 循环跳过条件（`tier >= longest`）、双分支收敛测试、chunk 解析助手边界（`offset + 8 <= len`、IEND break、`12 + length` 步进含 CRC）均正确；PDF 判页链路与 §1.6/骨架双吻合；防御分支注释诚实标注不可达性。
- **测试真实断言**：`identical` 原样返回、真解码尺寸断言（1568×784）、R3-F3 陷阱场景构造（页远置 + pageId 故意匹配）、手写 chunk 扫描——无空转断言；测试头部注释解释 testWidgets fake-async 不可用的原因与 loadScene/setLayout 顺序约束，范式与 C1 一致。
- **风格**：中文 doc 注释标注契约出处（§1.2/§1.6/R3-F3/§3.5），资源释放与"为什么"注释超出最低要求；与仓库既有风格一致。

## 发现清单

1. **（Important）I-1：PDF 路径 oversize 文案缺失（清单 #21）**。修复建议（小而局部，属本模块职责、不宜推给 C4 面板）：`captureCurrentPdfPageAttachment` 包裹 `normalizeAttachmentPng` 调用，捕获 `StateError` 且 message=='图片过大，请缩小选区后重试' 时重抛 `StateError('该 PDF 页面图片过大，无法作为附件发送')`（或给 normalizeAttachmentPng 增可选 `oversizeMessage` 参数），选区路径文案不动；补 1 用例（`_pdfPageController(_solidPng(5000, 5000))`——纯色大维度 PNG 字节小但 25M 像素破护栏——期望 PDF 专用文案）。若团队裁决推迟，必须在 C4 任务简报显式列入，否则该文案无自然落点。
2. （偏差裁决：**接受**）§3.4-#9 用例改非文本元素构造：表内"TextElement 并选中→成功"与修订①守卫（纯文本选区必 null）不可兼得，权威序以 §1.2/§4.1-4 为准；成功路径（#11 RectangleElement）与 null 路径（#5 纯文本）双覆盖，语义保持。实现者自报并给出正确裁决依据。
3. （偏差裁决：**接受，且系必需**）_rescalePng 补 try/finally：hybrid §3.5（不变量 5）"异常路径 try/finally 兜底"为权威要求，骨架原版在 getNextFrame/toByteData 抛出路径泄漏 codec/frame——实现者修复的是骨架自身的权威违反，行为语义（失败降档返回 null）未变。
4. （信息，接受）零页 + PDF 背景退化场景落"请先滚动到 PDF 页"：严格按 §1.6 字面（"视口未落在页内"），仅手工 .markdraw 可构造，报告已如实披露供 C4 参考。
5. （信息）'截图生成失败，请重试' 不在 §1.6 文案集合内：execution T4 骨架自带（:527），T4' 指令为按骨架执行，非缺陷；T7 文档同步时可顺带把 §1.6 集合补全。
6. （信息）onCaptureSelection/onCaptureCurrentPdfPage "只接线不消费"：计划刻意（消费属 T6'/C4），报告已向 C4 提示；C4 同时须注意 C3 后中间态下附件暂不随请求发送（快照恒空、面板未消费回调），属提交链既定过渡态。
7. （信息）capture:42 注释"控制器 :1843"实际行号 1842，漂移 1 行，无实质影响。

## 裁决

- **Spec 合规：❌**（21/22 项过；1 项缺口 = §1.6 定稿文案集合中的 PDF 路径 oversize 专用文案未实现，其余含三项融合修订、R3-F3 判定、接线与边界全部落实）
- **代码质量：通过**（0 Critical / 1 Important（I-1）/ 0 Minor 需修复项；4 项信息级 + 2 项自报偏差均裁决接受）
- **结论：Needs fixes**——仅需 I-1 一处小修（约 6 行 + 1 用例）即可转 Approved；其余实现忠实、测试独立验证全绿、验证声明（413 全绿/analyze 零新增/单 commit）全部复核属实。
