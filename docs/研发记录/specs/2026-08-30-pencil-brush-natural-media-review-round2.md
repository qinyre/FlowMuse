# 铅笔与毛笔自然介质重构计划第二轮对抗审查报告

> 日期：2026-08-30
> 审查对象：[2026-08-30-pencil-brush-natural-media-redesign.md](../plans/2026-08-30-pencil-brush-natural-media-redesign.md)（v1）
> 代码基线：`main@3eb2b97`（分支 `plan/pencil-brush-natural-media-redesign`，计划文档为未跟踪文件）
> 审查方式：三条只读子线并行（R1 渲染几何与测试有效性 / R2 数据协作兼容 / R3 性能与任务执行性）+ 主审独立核验、去重与裁决；不信任上一轮审查与计划文本的任何结论，全部回到代码
> 实跑证据：`brush_visual_matrix_test` 2/2、`pencil_grain_path_test` 2/2、`freedraw_pressure`+`remote_wet_ink_store`+`live_ink_chunk`+`collaboration_message` 30 例、`brush_integration_test`+`remote_wet_ink_store_test` +20、`editor_core/rendering` 目录 90 例全绿、`dart analyze --format=machine` 基线 41 条 info；另有一组独立 dart2js 编译实证（见 F-1）
> 上一轮审查：[2026-08-30-pencil-brush-natural-media-review.md](2026-08-30-pencil-brush-natural-media-review.md)

## 1. 总体判级

**可行但需修订。**

计划的架构路线（版本化双 renderer、共享采样器、edge 所有权、旧数据 v1 不迁移）与代码现实高度吻合，绝大多数事实主张经代码实证成立。但存在 **1 个 Critical**：计划 §3.3 字面规定的确定性哈希算术（"每步 `& 0xffffffff`"）在默认 Flutter Web 编译器 dart2js 上**必然**与 VM 产生不同结果（本机编译实证），而 §7 门禁命令中没有任何一条会在 Web 上执行哈希向量断言——即按计划字面实施，"跨端同一确定性几何"这一核心目标会静默失败且自动化验收不可见。该缺陷有已验证的最小修复（安全乘法写法 + Web 平台测试门禁），因此不推翻整体路线，但必须在 T2 实施前修订计划文字。

另有 5 项 Important（方向滞后与分块 context 的确定性矛盾、静态层缓存缺位、renderVersion 管道改动点遗漏、layeredWetInk 默认值未裁决、N 矩阵指标缺算式），全部是文字级修订即可关闭的计划缺口，不动摇架构。

## 2. 统计

| 级别 | 数量 |
| --- | ---: |
| Critical | **1**（F-1） |
| Important | **5**（F-2 ～ F-6） |
| Minor | **11**（F-7 ～ F-17） |
| Note | **6**（F-18 ～ F-23） |

## 3. 核心代码事实核验表

主审合并三线与独立核验后的裁决。行内"线"为出处（主=主审独立核验，R1/R2/R3=子线）。

| # | 计划/调研关键主张 | 判定 | 代码证据（file:line） | 线 |
| --- | --- | --- | --- | --- |
| 1 | v1 铅笔/毛笔仅靠 perfect_freehand 参数差异，无介质机制 | VERIFIED | `brush_render_profile.dart:98-165`（纯参数表）；`freedraw_renderer.dart:94-123` 唯一 `getStroke` 路径 | 主/R1 |
| 2 | pencil.frag 只有标量 FBM alpha，无轨迹/压力/种子输入 | VERIFIED | `shaders/pencil.frag:135-145`（uniform 仅 uColor/uOpacity/uFreq） | R1 |
| 3 | 攻击补偿 1500ms/0.50 仅 pencil/brushPen，且烘焙进 points.pressure（渲染器不可恢复） | VERIFIED | `markdraw_controller.dart:152-153, 2220-2229`；`stroke_input_modeler.dart:263-268`；输出经 `markdraw_controller.dart:2257` `_encodeStrokePressure` 入元素 pressures | 主/R2 |
| 4 | `.markdraw` 写 pressure 数组但不写 encoding 标记、解析只恢复 brushType | VERIFIED | `sketch_line_serializer.dart:305-322`；`sketch_line_parser.dart:605`（`customDataWithBrushType(null, brushType)` 从 null 重建） | 主/R2 |
| 5 | customData 在 Excalidraw JSON / SQLite / 协作 / copy-duplicate / undo-redo 全链往返 | VERIFIED | `excalidraw_json_codec.dart:193, 495-501`；`whiteboard_scene_repository.dart:82-86`；`select_tool.dart:1805` + `element.dart:156`；`history_manager.dart:17-49`（整 Scene 快照） | R2/主 |
| 6 | customData 新键不参与 LWW/版本仲裁 | VERIFIED | `scene_reconciler.dart:100-117`（仅 version/versionNonce） | 主/R2 |
| 7 | 外部 sanitizer 只剥 collaborationOwner、保留其余 flowMuse 键 | VERIFIED | `external_export_sanitizer.dart:9-43`；`collaboration_element_owner.dart:74-91` | 主/R2 |
| 8 | `LiveInkStyle.fromJson` 忽略未知键；不加 renderVersion 不 bump protocolVersion=2 双向兼容 | VERIFIED | `live_ink_chunk.dart:61-84`（只读四键）；`:139-141` 严格 `!= 2` 即 throw；服务端 envelope 版本（`hub.go:23,202`）与 payload 内 protocolVersion 是两套机制 | 主/R2 |
| 9 | RemoteWetInkSegment "只有 startIndex、points 和无 index 的 context" | VERIFIED（索引可推导，真实缺口在渲染语义） | `remote_wet_ink_store.dart:33-48`；context 索引 = startIndex±1（`:608-618`），段内恒连续（`:591-594`）；现状 painter 把 context 点**画进折线**（`remote_wet_ink_painter.dart:463-467`）——v2 需改为"只算导数不拥有绘制权" | 主/R1/R2 |
| 10 | live strokeId 与最终 ElementId 现状已同源 | VERIFIED | `freedraw_tool.dart:87` 与 `:235`（`_liveElementId ??=` 复用）；发送端 `whiteboard_page.dart:2035`；远端临时元素同 id（`remote_wet_ink_painter.dart:472`） | 主/R2 |
| 11 | 远端冻结 Picture 未变不重录；focus dim 只改合成 alpha | VERIFIED | `remote_wet_ink_painter.dart:346-397`（block revision 命中即跳过）；`:226-239`（逐 stroke saveLayer alpha） | 主/R3 |
| 12 | 静态画布无任何元素级缓存、整帧全量重绘 | VERIFIED | `static_canvas_painter.dart:164-246, 783-804`；`rough_path_cache.dart:3-11` 仅缓存 rough Drawable（不含 freedraw） | 主/R3 |
| 13 | layeredWetInk 默认 false；生产默认活笔走 buildPreviewElement 预览元素 | VERIFIED | `writing_feature_flags.dart:7-10`；`editor_canvas.dart:335-346`；`live_ink_flags.dart:9-18`（FLOWMUSE_LIVE_INK_V2 亦默认 false）；预览元素已带 customData（08-29 修复在位，`markdraw_controller.dart:~3126`） | 主/R3 |
| 14 | 四条渲染链（静态/本地湿墨/远端湿墨/SVG）已收敛到 profile+buildOutline 单真源 | VERIFIED | `element_renderer.dart:155-171`；`local_wet_ink_painter.dart:56-78`；`remote_wet_ink_painter.dart:471-498`；`svg_element_renderer.dart:347-428` | 主/R1 |
| 15 | SVG 可脱离 Canvas 消费同一几何（"同一 plan 写 path"可实现） | VERIFIED | 现状先例：`svg_element_renderer.dart:373-382, 432-459` 消费 `List<Offset>` outline、纯字符串构建 `d` | 主/R1 |
| 16 | StrokeInputSample 无 tilt/orientation | VERIFIED | `stroke_input_sample.dart:16-35` | 主/R2 |
| 17 | v2 压力分流点存在且中途切笔/undo 场景闭合 | VERIFIED | modeler 逐笔于 pointer-down 构造（`markdraw_controller.dart:2223`），笔形取落笔冻结值（`:2220`、`_freezeStrokeBrush`）；undo/redo 走 Scene 快照不重放 modeler | R2 |
| 18 | ActiveFreedrawView.pressures 与提交元素 pressures 同值同源 | VERIFIED | 同源 `_previewPressures`（`freedraw_tool.dart:43,91,259`） | R2 |
| 19 | 现有视觉门禁识别不了介质质量（v1 能通过） | VERIFIED | `brush_visual_matrix_test.dart:104-160` 仅两两着墨并集差异 >5%；本轮实跑 2/2 通过 | 主/R1 |
| 20 | drawPath/saveLayer/耗时/内存门禁有现成机械载体 | VERIFIED | `canvas_spy.dart:13-39`；`brush_integration_test.dart:313-348`（16k/1k 比值+防 0µs 假绿）；`remote_wet_ink_painter.dart:17-63`（retained bytes 估算） | 主/R3 |
| 21 | §3.3 FNV-1a "每步 & 0xffffffff" 跨运行时一致 | **REFUTED** | 见 F-1：主审独立 dart2js 编译实证，同一输入 VM `5514c2ad` vs JS `7fee3458` | 主/R2 |
| 22 | T2 验收"Web/VM 哈希向量一致"可被 §7 门禁执行 | **REFUTED** | §7 仅 `flutter test`（VM）与 `flutter build web`（编译不跑断言）；全计划无 chrome/web 平台测试命令 | R2/主 |
| 23 | "静态重绘不得重新生成可缓存的 seed 表"有实现载体 | **REFUTED（无载体）** | T2-T9 无任务为静态元素建 plan/seed 缓存（见 F-2） | R3/主 |
| 24 | 4096 粒子复合 Path 的成本被 `drawPath<=4` 掩盖（上轮 I-7 担忧） | REFUTED（作为缺陷不成立） | v1 16k 点笔每帧构建 ~2N 轮廓顶点 + N 段二次贝塞尔（`freedraw_renderer.dart:145-158`）；v2 上限后 4096×(2-5 verb) 同量级；另有 N19/T12/字节预算三道门禁 | R1 |
| 25 | flutter_ohos 无 FragmentProgram（v2 不用 shader 论据之一） | UNVERIFIABLE（论据疑似过时，决策不依赖） | 仓内无直接证据；有引擎差异实证（`pencil_shader.dart:120-124`）；v2 不依赖 shader，论据成立与否不影响路线 | R3 |

## 4. 发现列表

### F-1 | Critical | §3.3 确定性哈希规范在 dart2js 上必然漂移，且 §7 门禁对 Web 断言为空洞

- **问题**：计划 §3.3 规定 `fnv1a32`/`mix32` "以 `& 0xffffffff` 约束每步"。Dart VM 的 int 是 64 位、乘法模 2^64 精确；默认 Flutter Web 编译器 dart2js 的 int 是 JS double（53 位尾数），`h * 16777619`（h<2^32，积达 2^56）**先丢低位精度再做掩码**，`& 0xffffffff` 无法恢复。且 dart2js 的 `&` 走 ToInt32，bit31 置位时结果为负（VM 为正），符号差异进一步放大分歧。这不是概率问题——FNV 基值 0x811c9dc5 × 素数 ≈ 2^55 已超 2^53。
- **证据（主审独立实证，/tmp 临时目录，未触碰仓库）**：
  - 按计划字面写法 `h = (h * 16777619) & 0xffffffff`，同一程序 `dart run`（VM）与 `dart compile js` + node（dart2js）结果：`"flowmuse-natural-media-v2|abc"` → VM `5514c2ad` vs JS `7fee3458`；`[0xFF×4]` → `e3160fb1` vs `b096448` 等，**四组输入全部漂移**。
  - 修复写法（16 位拆分乘法 + 每步 `.toUnsigned(32)`）VM 与 JS 五组输入（含 bit31 置位、200 字节随机）**逐值一致**，且与 VM 朴素语义相同（`5514c2ad`…）。
  - 仓库已有跨端安全哈希先例：`scene_reconciler.dart:180-186` djb2（`<<5`+加法+`.toUnsigned(32)`，中间值 <2^41 双精度精确）。
  - 官方语义依据：Dart 官方数字表示文档（web 整数 >2^53 丢精度、位运算按 32 位）；Flutter Web 默认仍为 dart2js（wasm 为 opt-in）。
- **实际影响**：按现文实现，Web 端每个 strokeSeed 与 VM/Windows/HarmonyOS 不同 → 协作两端、Web 导出 SVG 与原生 PNG 的粒子/毫丝布局分叉，直接违反计划核心承诺（§0、§10.C"Web 通过不能替代"、T12"同一 fixture 无算法级形态分叉"）。更严重的是验收空洞：T2 验收写了"Web/VM 对固定哈希向量结果一致"，但 §7 门禁只有 `flutter test`（VM 自洽必绿）和 `flutter build web`（编译不执行断言），漂移将静默通过全部自动化门禁。
- **最小修订**（均已验证）：
  1. §3.3 把乘法规范改为 mod-2^32 安全写法，并要求每步以 `.toUnsigned(32)`（或 `>>> 0`）归一符号：如 `_mulmod32(a,b) = ((a&0xFFFF)*b + ((((a>>>16)&0xFFFF)*b & 0xFFFF)<<16)) & 0xFFFFFFFF`，或参照仓内 djb2 先例用"移位+加法+toUnsigned"形式；禁用裸 `& 0xffffffff` 作为唯一约束；
  2. §3.3 给出 `mix32` 的规范参考实现（目前只有名字，任何 32 位乘法同样受限）；
  3. §7 门禁增加 `flutter test --platform chrome <哈希向量测试文件>`（或等效 headless Web 执行）作为 T2 合并硬门禁；≥8 组测试向量保留。
- **是否阻断实施**：**是**——阻断 T2 开工（不阻断 T0/T1，见 §10）。
- 来源：R2-1（Critical 裁决）+ 主审独立编译实证（推翻上一轮 I-1 的 CLOSED 结论，见 §7）。

### F-2 | Important | §6.1"静态重绘不得重新生成可缓存的 seed 表"预设的缓存在任何任务卡中都不存在

- **问题**：静态画布今天零缓存、逐可见元素每帧全量重绘。v2 每元素成本 = sampler O(n) + ≤4096 粒子的 Path 构造 + ≤4 次 draw；v1 是 getStroke O(n) + 1-2 次 draw。主审裁决：量级为同阶、常数约 1～4×（R3 报告"差两个数量级"的估算偏高——长笔情形 v1 轮廓构建反而更重），但 T12 门禁余量只有"1000 元素 P95 退化 ≤20%"，铅笔/毛笔占比高时极可能击穿；而 §6.1 该条门禁预设"可缓存的 seed 表"存在，T2-T13 没有任何任务产出这个缓存（T4/T8 文件清单均无缓存载体），门禁一旦失败只能中途插任务返工。
- **证据**：`static_canvas_painter.dart:164-246, 783-804`（无 Picture/plan 缓存、无 RepaintBoundary）；`rough_path_cache.dart:3-11`（仅 rough Drawable）；计划 §6.1、§5 T4/T8 工作项无缓存项。
- **实际影响**：性能门禁失败风险无人负责；失败后排程返工（估 2-4 人日）。
- **最小修订**：T4（或 T8）增加一条工作项：为静态 freedraw 元素定义 plan/Path 缓存载体（element id/version → NaturalMediaStrokePlan 的失效缓存），并给"未变化不重建"门禁指定断言载体（缓存命中计数器）；或在 §11 明示"若 T12 不达标，补建静态缓存"为预定处置路径并调整估算。
- **是否阻断**：不阻断批准；应在 T4 开工前修订。
- 来源：R3-1（主审修正量级）。

### F-3 | Important | renderVersion 数据管道的具体改动点在 T6/T7 任务卡中不完整（四处）

- **问题**（四个具体缺口）：
  1. **生产默认本地湿墨是 buildPreviewElement 预览元素路径**（layeredWetInk 默认 false），T6 工作项未点名该路径——预览元素 customData 不带 renderVersion=2 就会在书写中显示 v1、提交后跳 v2，重演 2026-08-29 修掉的"变身"缺陷（且这次是算法级跳变）；
  2. **远端 `_drawSegment` 临时元素没有 customData**（brushType 直传、`pressureEncoded: true` 硬编码），renderVersion 需要新传递通道才能进 v2 分发；
  3. **`RemoteWetInkStore._sameStyle` 只比较 brushType/色/宽/opacity**，renderVersion 加入 LiveInkStyle 后若不纳入比较，同笔混版本 chunk 不会被 invalidChunk 拒绝；
  4. **`freedraw_tool.dart` 不在 T1/T6 文件清单**，而 `ActiveFreedrawView` 是 local view 携带 renderVersion 的字段载体。
- **证据**：`writing_feature_flags.dart:7-10`；`markdraw_controller.dart:~3096-3130`（buildPreviewElement freedraw 分支现写 `customDataWithFreedrawRender`）；`remote_wet_ink_painter.dart:471-498`；`remote_wet_ink_store.dart:377-382`；`freedraw_tool.dart:18-33, 87, 242`。
- **实际影响**：任一漏改都会造成 v1/v2 预览-提交跳变或混版本包静默接受；N13/N15 验收最终会暴露，但按计划清单执行者大概率漏改返工。
- **最小修订**：T6/T7 工作项显式增列上述四点（预览路径、远端临时元素版本通道、`_sameStyle`、ActiveFreedrawView 字段），T6 主要文件补 `freedraw_tool.dart`。
- **是否阻断**：否；实施前修订。
- 来源：R2-2 + R3-3 + R3-4 + 主审（buildPreviewElement 路径）。

### F-4 | Important | T6/T12 的验收口径建立在非默认开关路径上，layeredWetInk/liveInkV2 默认 false 未裁决

- **问题**：T6 验收"本地笔画无新增页面 setState/scene 重建"只对分层湿墨 painter（flag off）有意义；生产默认路径是每次 pointer move `notifyListeners()` → StaticCanvasPainter 全量重绘（既有行为，非本计划回归）。T12"Web+Windows 双端协作同时书写"需要 `FLOWMUSE_LAYERED_WET_INK` 与 `FLOWMUSE_LIVE_INK_V2`（及服务端 protocol≥2）同时开启，计划全文未提及这两个 flag。若不裁决，T6 可能只修了 flag-off 的小众路径、验收在默认配置下不可测。
- **证据**：`writing_feature_flags.dart:7-10`；`live_ink_flags.dart:9-18`；`editor_canvas.dart:335-346`；`markdraw_controller.dart:2383-2386, 2461`；`whiteboard_page.dart:169`（默认构造，全仓无 dart-define 覆盖）。
- **最小修订**：§3/T6 增加一条裁决：v2 验收按哪条路径执行（建议：默认 preview 路径必须满足 WYSIWYG 断言 N12；分层路径维持既有门禁），T12 协作场景写明需开启的 dart-define。
- **是否阻断**：否；实施前修订。
- 来源：R3-2 + 主审。

### F-5 | Important | N1~N22 多项指标缺算式定义，阈值先行固定，存在作弊面与恒真面

- **问题**：以下口径在计划中无算式：ink coverage 的着墨像素判定阈值；N2"**相同宽度下**重压 coverage ≥+35%"与 N3"宽度可增 35%"的口径互斥如何固定宽度；N3"有效宽度"的测量剖面位置；N6"中段"；T6/T7/N12/N13"前 90% 像素差"按什么排序（像素无自然序，应为弧长前 90% 区域，未写）；N5"边缘不规则度"算式与"无固定周期峰"的检测方法（自相关/FFT 峰显著性均未提）；N16"趋势同向"未定义；N18 行文字未携带上轮 I-8 要求的"按渲染阶段分别计数"（静态整笔 / owned segment 录制 / 稳定帧回放），机械照 N18 字面实现会写出必失败的断言（稳定帧 = 每块一次 drawPicture + 有限 tail draws）。T0 产出 `natural_media_image_metrics.dart`，但计划未要求"指标定义随基线一起冻结"，测试编写者可自选最宽松口径。
- **证据**：计划 §T4/§T6/§T7 验收、N2/N3/N5/N6/N12/N13/N16/N18 行文；现成可扩展基础：`brush_path_metrics.dart:66,106`（widthAtArc）；N5 若定义得当可顺带拦截 v1 降级颗粒的规则 `size/3` 弧长间距（`freedraw_renderer.dart:369-372`）。
- **实际影响**：N2 可被"宽度增长带来的 coverage 增长"作弊通过（恰是计划想排除的）；N5/N12 无法落笔；N18 会误导实现。
- **最小修订**：T0 验收追加一条："每个进入 N 矩阵的指标必须给出算式、fixture 与采样口径，并随基线一起冻结"；N18 行补"静态整笔与录制期分别计数，稳定帧只断言 tail 有限与无重录"。
- **是否阻断**：不阻断 T0 启动；阻断 T11 的 N 矩阵可写性。
- 来源：R1-2 + R3-8。

### F-6 | Important | §3.7 方向滞后与 §3.4 分块有限 context 存在未闭合的确定性矛盾；N11 multiset 不证明几何等价

- **问题**：毛笔"对 tangent 做有限低通形成短距离方向滞后"是跨边历史状态滤波；分块渲染时每段只携带有限前文（现状仅 1 个 leading 点，计划也只写"前后相邻点"）。若滞后窗口超过 context 深度，冻结块/tail 无法复现整笔的滤波后方向。更关键：N11 的"primitive key multiset 相等"只证明 seed 相同——key 由 (edgeStartIndex, ordinal, channel) 派生，不编码滤波输入，两份 key 完全相同的渲染仍可算出不同包络。计划把 multiset 测试当作分块等价性的证明，但它对此失明；唯一兜底像素差口径又未定义（F-5）。
- **证据**：计划 §3.4/§3.7/N11；`remote_wet_ink_store.dart:604-618`（context 仅 1 点）；`live_ink_chunk.dart:3-8`。
- **实际影响**：块边界包络方向跳变/接缝——恰是计划最想消灭的 64 点周期缺陷——可能在全部自动化门禁绿的情况下存在。
- **最小修订**：§3.4 补硬约束"segment context 深度 ≥ 方向滞后窗口覆盖的边数"（或规定滞后滤波为固定 stencil 的因果形式，仅依赖有限 context）；T7 增加结构性断言：分块与整笔在边界处的包络顶点/滤波切线逐值相等（不依赖 key multiset）。
- **是否阻断**：不阻断计划批准；T7 动工前必须闭合。
- 来源：R1-1（主审认可）。

### Minor（11 项）

| ID | 问题 | 证据 | 最小修订 |
| --- | --- | --- | --- |
| F-7 | 既有测试 `wet_ink_preview_fidelity_test.dart:309-329` 断言毛笔/铅笔起笔抬到 0.5 水位，与 v2 默认行为直接冲突，且该文件不在 T3 清单；它同时是"v1 回退保留攻击补偿"的唯一行为锁 | 主审实读该测试 | T3 文件清单补列，并注明该用例改写为锁定 renderVersion=1 路径而非删除 |
| F-8 | "只允许整数 1、2"若用 `is int` 校验，VM（`1.0 is int`→false）与 dart2js（→true）行为不同；现有 `pressureEncodingFromCustomData` 用 num 相等 `== 1` 恰好规避 | `brush_type.dart:132` | §3.1/§3.9 明确校验语义为 num 相等或 toUnsigned 前置转换，禁用裸 `is int` |
| F-9 | §3.6 末条自认"单笔内部压力非单调"风险，但 N 矩阵无压力坡道沿弧长的密度/亮度单调断言；`pressureRamp` fixture 现成可用 | `brush_stroke_fixtures.dart:65-72` | 新增（或并入 N2）：坡道 fixture 沿弧长滑窗平均亮度非降 |
| F-10 | §3.3 plan 输出未列 primitive 记录（kind/channel/几何参数）与 channel 枚举、join 等非采样 primitive 的 key 规则；粒子几何若埋进 renderer 私有 Path 构建，T9/N11 将被迫走第二采样真源 | 计划 §3.3/§3.8/N11；先例 `svg_element_renderer.dart:373-382` | §3.3 输出表补"primitive 记录，供 Canvas/SVG/测试三端消费"；§3.4 给 channel 枚举与 join key 规则 |
| F-11 | renderer family 分发落位未写明：profile 在 `core/elements` 且自我约束不持运行时对象，若 family 直接持 renderer 引用将造成 core→rendering 反向依赖；ADR-021 与 ADR-020"禁止按 brushType 特判"的相容性只有标题级内容 | `brush_render_profile.dart:26-27`；`.agent/decisions.md` ADR-020 遗留约束 | §3.2 补"family 为 core 层纯枚举，唯一 dispatch switch 位于 rendering 层单一入口；profile 不 import rendering"；ADR-021 写明枚举分发不算 brushType 特判的例外依据 |
| F-12 | 毛笔受限 miter 阈值与铅笔 scatter 外扩常数未定义，而 T8 的解析保守上界依赖它们（miter 外扩 = halfWidth/sin(θ/2) 无界，限制后上界 = miterLimit×halfWidth） | `element_visual_bounds.dart:10-23` 现仅 v1 公式 | §3.7 写入 miterLimit 与 scatter 半径常数语义（数值可 T0 校准），§T8 要求与 bounds 上界同源入 profile |
| F-13 | 弱断言：N4 三次覆盖亮度单调（sourceOver 同色叠加合成 alpha=1-(1-a)^n 数学必然单调，v1 今天就能过）；N8"形态不同"近恒真；N16"同向"未定义 | 计划 N4/N8/N16；合成数学 | N4 降级为辅助证据；N8 改具体断言（如无降压 fixture 距尾 2×size 宽度 ≥ 中段 70%）；N16 改"轻/重/提按的平均亮度或宽度排序一致" |
| F-14 | 4096 上限下长笔（16k 点、弧长数万 px）粒子间距被均匀放大一个数量级，压力→密度表达退化为 alpha/桶选择，无自动门禁也无登记 | `remote_wet_ink_store.dart:163`；`freedraw_renderer.dart:369-372` 同型数学 | T11 加"上限触发时长笔仍满足 N2 密度差"或在实施记录登记降级预期 |
| F-15 | §4"T4/T5 可并行"与两任务共改 `element_renderer.dart`（同一分发 switch）和 `element_visual_bounds.dart` 冲突 | 计划 §5 T4/T5 文件清单 | 注明分发点合并顺序或由单人串行合入 |
| F-16 | T12"相对 main 退化 ≤15%/≤20%"未定义对照基线获取程序（同机同日？），未引用仓内已有 `integration_test/whiteboard_writing_perf_test.dart` + `test_driver/`（支持 dart-define 场景注入） | `integration_test/`、`test_driver/` 目录 | T12 补"基线获取程序"一段或指定复用 writing_perf 驱动 |
| F-17 | §3.8"parser 对未知 render 值产生 warning"需要新增机制——当前 PropertyBag 对未知属性 token 完全静默（仅未知行首关键字告警）；T1 也未给 serializer 输出示例行（何时写 `pressure-encoded`/`render=v2`） | `sketch_line_parser.dart:78-87`（告警仅行首关键字）；`:787-794, 818-821`（namedString/hasFlag 可承载新语法） | T1 补示例行与告警机制说明；ParseWarning 管道已存在，改动量小 |

### Note（6 项）

| ID | 问题与建议 |
| --- |
| F-18 | §8 提交顺序列表缺 T12（编号 T11→T13 跳跃）。逻辑自洽（T12 不产生提交、摘要随 T13 文档入库）但属隐式闭环，建议加一行说明 |
| F-19 | 工作量下界偏乐观：`markdraw_controller.dart` 7088 行（T3/T6 触碰）、相关测试 94 文件约 16.7k 行；叠加 F-2 缓存返工（估 2-4 人日）。建议改为 17~24 人日或注明"不含静态缓存返工" |
| F-20 | "flutter_ohos 无 FragmentProgram"论据疑似过时（新版移植默认 impeller-vulkan）；仓内已有引擎差异实证（`pencil_shader.dart:120-124` uniform 按名绑定失败），建议改述为"shader 可用性跨端不可保证" |
| F-21 | T12 五人盲测无协议（呈现顺序随机化、对照组合、逐人记录格式）；SVG 预算提醒：线粒估算 ~100-250 KiB 安全，椭圆粒估算 ~400-600 KiB 贴近 512 KiB 上限（T9 已有按实测修订条款，实施时留意） |
| F-22 | `.markdraw` serializer 将点坐标取整（`sketch_line_serializer.dart:437-451`）——既有行为，N14 若做像素级往返比较需知此失真来自取整而非版本字段 |
| F-23 | v2 压力曲线叠加在 encodePressure 仿射之上：复合单调无冲突，但 sensitivity>1 时 k>1 钳制截去压力极值（pow 曲线无法恢复）；建议 T10 说明该复合语义，并禁止实现者"绕过"encodePressure 钳制（`LiveInkPoint.fromJson` 对 [0,1] 越界直接 throw，钳制是承重的） |

## 5. N1~N22 可执行性检查表

| 编号 | 判定 | 说明 |
| --- | --- | --- |
| N1 | 可执行 | 像素摘要逐字节比对有 A9 先例（`pencil_rendering_test.dart:71-95`）；CI 单平台不受 AA 微差影响 |
| N2 | **不可执行（现状）** | coverage 像素阈值未定义；"相同宽度"与 N3 口径互斥（F-5），存在宽度增长作弊面 |
| N3 | 部分可执行 | "有效宽度"剖面未定义；`brush_path_metrics.dart:66,106` widthAtArc 是现成可扩展基础（前提 F-10：v2 renderer 暴露包络几何） |
| N4 | 可执行但近恒真 | sourceOver 同色叠加数学必然单调，v1 即可通过（F-13）；只防"基底不透明"类错误 |
| N5 | **不可执行（现状）** | "无固定周期峰"无检测方法（F-5）；定义后反而能拦截 v1 降级颗粒的规则间距 |
| N6 | 部分可执行 | "中段"位置未定义（F-5）；比值本身可用宽度剖面度量 |
| N7 | 可执行 | `cornerPolyline` fixture 现成；"局部目标宽度"需一并定义 |
| N8 | 弱断言 | 压力输入不同几乎必然形态不同（F-13），建议具体化 |
| N9 | 可执行 | 现有 A19 同型（`brush_geometry_test.dart:194-233`） |
| N10 | 可执行 | SpyCanvas/摘要比对先例充分（`canvas_spy.dart:24-41`） |
| N11 | 部分可执行 | key 组成可从 §3.3 推出，但 channel/join key 规则未定义（F-10）；且 key 等价不证明几何等价（F-6） |
| N12 | **不可执行（现状）** | "前 90% 像素差"排序口径未定义（F-5）；primitive key 等价部分可执行 |
| N13 | 部分可执行 | 像素差部分同 N12；"无重复 primitive"部分依赖 F-10 的 key 定义 |
| N14 | 可执行 | 双往返先例在（`freedraw_svg_renderer_test.dart:213-233`）；注意 F-22 点取整既有失真 |
| N15 | 可执行 | 现有 collaboration 测试目录可承载；LiveInkStyle 兼容性已实证（核验表 #8） |
| N16 | 部分可执行 | path 数（应数真实 XML 节点，上轮 Minor-2）与字节量可执行；"趋势同向"弱（F-13） |
| N17 | 可执行（待 F-12 常数） | 消费链全走 `elementVisualBounds`（`scene.dart:133,162`、`export_bounds.dart:27`、`viewport_culling.dart:33`）；A20/A21 先例在册 |
| N18 | 需修订措辞 | SpyCanvas 可数 drawPath/saveLayer；但行文字未带"按渲染阶段分别计数"，字面实现必失败（F-5/R3-8） |
| N19 | 可执行 | 先例实跑通过（`brush_integration_test.dart:313-348`，含防 0µs 假绿） |
| N20 | 可执行 | `RemoteWetInkRenderCache.estimatedRetainedBytes` 等估算器现成（`remote_wet_ink_painter.dart:17-63`） |
| N21 | 可执行 | focus 测试文件已存在；dim 实现为纯 alpha saveLayer（核验表 #11） |
| N22 | 可执行 | 压力回放管线可驱动（R2 实证 modeler 逐笔构造、fixture 可回放）；OPD2404 慢爬序列在 issue #5/#21 记录中 |

## 6. T0~T13 依赖与提交闭环检查表

| 任务 | 依赖正确 | 文件清单完整 | 独立可提交 | 主要问题 |
| --- | --- | --- | --- | --- |
| T0 | 是（根节点） | 是（fixtures/指标/spike 均有先例） | 是 | "16k 无 O(n²)"判据有 measureStroke 先例可机械执行 |
| T1 | 是 | 基本完整 | 是 | freedraw_tool/controller 构造点未列（可由 codec 默认值覆盖，见 F-3d）；`.markdraw` 缺口为真 |
| T2 | 是 | 是（4 新文件+单测） | 是 | **F-1：哈希规范必须先修订**；源码禁项扫描有先例（`external_export_boundary_test.dart:121-141`） |
| T3 | 是 | 缺 `wet_ink_preview_fidelity_test.dart`（F-7） | 是 | 触碰 7088 行 controller，回归面大但测试齐 |
| T4 | 是（T2+T3） | 是（含 adapter） | 是 | F-2 缓存载体缺位；与 T5 共改分发文件（F-15） |
| T5 | 是（T2+T3） | 是 | 是 | 同 F-15；分阶段计数载体可行（RoughAdapter 装饰先例） |
| T6 | 是（T1/T3 经 T4/T5 传递成立） | 缺 `freedraw_tool.dart`（F-3d） | 是 | **F-4：默认 preview 路径未点名、flag 未裁决** |
| T7 | 是（T6） | 基本完整 | 是 | **F-3b/3c、F-6**：远端版本通道、`_sameStyle`、context 深度约束 |
| T8 | 是（T4+T5） | 是（scene/culling/export_bounds 调用方全枚举） | 是 | F-12 常数未定义；1000 元素 bounds 门禁有先例 |
| T9 | 是（T8） | 是 | 是 | SVG path 数应数真实 XML 节点（改造量小） |
| T10 | 是 | 是 | 是 | `toolbar_palette_buttons.dart:187` 已读 profile，改动面小 |
| T11 | 是（T6..T10） | 是 | 是 | **F-5：指标定义必须先于本任务冻结** |
| T12 | 是（T11） | —（无代码产物） | 无独立提交（设计如此） | F-16 基线程序未定义；HarmonyOS 不可得时列为用户验收+演示阻断项的处理自洽 |
| T13 | 是（T12） | 是 | 是 | F-18：T12 摘要隐式随本任务入库，建议显式说明 |

依赖图整体核验：无前向引用（T1 不依赖 T9，T1 自带往返验收；T6 引用的 plan 来自拓扑前序 T2）；T6→T7→T8→T9 串行链文件交集小、无环。§8 提交顺序列表本身完整对应一任务一提交，唯缺 T12 说明行（F-18）。

## 7. 对上一轮审查的复核

| 编号 | 本轮结论 | 依据 |
| --- | --- | --- |
| C-1 毛笔产品名歧义 | **ADDRESSED** | §2 目标表 + §1.2 非目标 + T0 确认门在计划文本中齐备；仍为执行前置条件（T0 未跑） |
| C-2 混合版本远端湿墨预览 | **ADDRESSED**（残留 F-3c） | 代码可行性实证：`LiveInkStyle.fromJson` 忽略未知键（`live_ink_chunk.dart:61-84`）、protocolVersion 双机制（payload vs envelope）不冲突；`_sameStyle` 未列入改动点 |
| C-3 纯 Path 收益未证明 | **ADDRESSED (BY GATE)** | T0 双原型 + 16k 探针 + 停止门设计在位；仍未执行，维持门禁属性 |
| I-1 稳定哈希跨端漂移 | **NOT ADDRESSED（推翻原 CLOSED）** | **推翻性证据**：上一轮修订"& 0xffffffff 每步 + ≥8 组向量"经主审 dart2js 编译实证不足以保证一致（VM `5514c2ad` vs JS `7fee3458`，四组输入全漂移），且 §7 无任何命令在 Web 上执行向量断言——见 F-1 |
| I-2 `.markdraw` 丢 pressureEncoding | **ADDRESSED** | 缺口实证属实（核验表 #4）；修复排 T1-4/T9/N14；补充事实：该解析路径当前零测试覆盖，N14 是全新门禁 |
| I-3 RemoteWetInkSegment 不足 | **ADDRESSED IN PLAN**（遗留 F-6） | 字段证据属实；精确化：context 索引可由 startIndex 推导、段内恒连续，模型扩展量小于原描述，真实缺口是"context 只参与导数"的渲染语义改造与 context 深度约束 |
| I-4 不能直接替换 v1 | **ADDRESSED** | "新建才写 v2/缺失=v1/不迁移"与现状 4 处 customData 构造点（均基为 null 的新笔迹）兼容；全链往返实证（核验表 #5） |
| I-5 压力地板不能直接删 | **ADDRESSED**（附 F-7） | T3 稳定器 + 双回放 fixture 在位；分流点实证可行（核验表 #3/#17）；既有水位断言测试改写需列入 T3 |
| I-6 与 ADR-020 冲突 | **PARTIALLY ADDRESSED** | §3.2 禁令与 family 映射在位，但 dispatch 落位/分层机制未写明、ADR-021 只有标题级内容（F-11） |
| I-7 draw 少≠构造便宜 | **ADDRESSED** | 四轴齐备（4096/1024 上限、N19 线性度、SVG 字节预算、plan 结构计数）；R1#16 反证还表明"掩盖成本"对 16k 笔不成立（v1 轮廓构建同量级） |
| I-8 ≤2 draw 不能套远端分块 | **PARTIALLY ADDRESSED** | T5 验收已按三阶段区分且机制可测；但 N18 行文字未携带分阶段口径（F-5/R3-8） |
| I-9 边界不得生成粒子 | **ADDRESSED**（附 F-12） | T8 "O(1)/O(points)、不得 O(particles)"明确、调用方全枚举；解析上界所需常数未定义归 F-12 |

上一轮遗漏（本轮新增的最重要内容）：① dart2js 哈希漂移与 Web 门禁空洞（F-1，上轮把该修订标为 CLOSED 反而制造了安全错觉）；② 静态层零缓存与 §6.1 门禁的矛盾（F-2）；③ renderVersion 管道四处改动点（F-3）；④ layeredWetInk 默认值与 T6/T12 口径（F-4）；⑤ 方向滞后 vs context 深度（F-6）；⑥ 既有水位断言测试冲突（F-7）。

## 8. 三分类清单

### 实施前必须修复（计划文字修订，合计约 1 人日内）

- **F-1（Critical）**：§3.3 哈希算术安全写法 + mix32 规范实现 + §7 增加 Web 平台哈希向量门禁。**阻断 T2**。
- F-2：静态缓存载体工作项或 T12 失败预案（T4 前落字）。
- F-3：T6/T7 四处 renderVersion 管道改动点 + 文件清单补遗。
- F-4：layeredWetInk/liveInkV2 裁决与 T6/T12 验收路径。
- F-5：指标定义随 T0 基线冻结的硬要求 + N18 分阶段措辞（T0 验收与 T11 前落字）。
- F-6：context 深度硬约束 + T7 边界几何等价断言（最迟 T7 动工前）。

### 可以实施时处理

F-7 ～ F-17（Minor：清单补遗、校验语义、新增断言、常数定义、并行冲突注记、盲测与基线程序）。

### 只能依赖真机/人工验证（自动化不可替代）

- HarmonyOS 真机 Profile 与手写手感（含 compound Path 在 impeller 的光栅成本）——计划已正确设为"比赛演示前阻断项，不得默认通过"；
- 五人无标签盲测（需先补 F-21 的三行协议）；
- T0 用户对 HB 铅笔/软头毛笔目标纸的确认（范围裁决，无法代理）；
- Web CanvasKit / Windows Skia 的实测书写帧率（T12 场景）。

## 9. 最终结论

1. **当前计划是否可以直接进入 T0**：可以。T0 的 fixture/指标/原型不依赖被推翻的 §3.3 哈希细节；唯一交集是 spike 的种子写法——建议 spike 直接采用 F-1 修订后的安全写法，避免原型结论建立在将来要改的算术上。若希望零返工，先完成 F-1 的文字修订（半小时级）再启动 T0 更稳妥。
2. **T0 通过后是否可以直接进入 T1**：可以。T1 是版本字段与序列化契约，与哈希规范无关；受 F-1 影响的是 T2——**T2 必须在 F-1 修订落地后开工**，受 F-2/F-3/F-4 影响的是 T4/T6/T7 开工前落字即可。
3. **必须阶段性独立复核的任务**：
   - **T2**：F-1 修复的验收（安全乘法实现 + Web 向量门禁实际执行）——Critical 的闭合点，必须独立代码审查，不能只看测试绿；
   - **T7**：分块连续性（F-3b/3c + F-6 闭合点），维持上一轮"单独代码审查 + 全部 63/64/65/127/128/129 边界"的要求；
   - **T4 后**（若采纳 F-2 缓存载体）：静态缓存的失效正确性（元素编辑后不得回放旧 plan）；
   - **T11**：N 矩阵指标定义冻结（F-5）与 N1 历史 fixture 真实性；
   - **T12**：人工/真机项，按计划登记，不得以 Web 通过推断。
4. 工作量：建议随 F-2 裁决同步调整为 17~24 人日（或注明不含缓存返工）；"单代理连续实施"的 M1/M2 里程碑切分与"低能力模型不得跨越 T2/T4/T5/T7"的约束维持不变。

---

### 附：本轮审查执行记录

- 主审：完整读取 9 份指定文档；独立核验 21 个代码文件（渲染/序列化/协作/输入链）；FNV-1a 漂移与修复的 dart2js 编译实证（VM/dart2js 双端对照，含 bit31 场景）；复跑 `brush_visual_matrix_test`（2/2）。
- R1：渲染几何/视觉/测试有效性，18 项主张核验 + N 矩阵判定 + 复跑 2 个测试文件。
- R2：数据/序列化/协作兼容，20 项主张核验 + 4 个测试文件 30 例实跑 + 上一轮 C-2/I-2/I-3/I-4 复核。
- R3：性能/缓存/跨端/任务执行性，21 项主张核验 + 2 个测试文件 +20 例与 rendering 目录 90 例实跑 + analyze 基线 + T0~T13 检查表 + I-7/I-8/I-9 复核。
- 主审对子线结论的修正：R3-1 的"Path 构造量差两个数量级"下调为"同阶、常数 1~4×"（R1#16 的反证成立，但 §6.1 门禁载体缺位的核心结论保留）；R2-1 的 Critical 予以维持并以更强证据（真实编译而非模拟）固化。

---

## 10. v2 修订复核附录（2026-08-30，主审）

> 复核对象：计划书 v2（`版本：v2（二轮对抗审查修订）`，918 → 1074 行）
> 复核方式：通读 v2 全文与 v1 逐节对照 + 对 §3.3 参考实现做 VM/dart2js 双端编译实证
> 复核结论：**v2 关闭全部阻断项（1 Critical + 5 Important）与全部影响实现正确性的 Minor；F-1 经代码级实证闭合。3 条编辑级残留，均不阻断。计划可进入 T0。**

### 10.1 F-1（Critical）闭合的代码级实证

从 v2 §3.3 逐字提取 `mul32`/`fnv1a32`/`fmix32`/`mix32` 参考实现，在仓库外以 `dart run`（VM）与 `dart compile js` + node（dart2js）双端运行同一程序，向量覆盖计划自要求的全部类型（空字符串、`abc`、bit31 置位、长 strokeId、最大合法 edge/ordinal/channel）另加直接乘法探针：

```text
输入长度  fnv1a32      mix32(max)   mix32(0,0,0)  mix32(0xFFFFFFFF,…)
0        811c9dc5     e263ff16     8b4eccd8      16ab336e     ← VM 与 node 输出逐行相同
3        1a47e90b     a525cdda     cc41ce57      16ab336e
35       a64248ad     e6510bb6     76c6f954      16ab336e
146      b491db93     85558b6b     4dfd8462      16ab336e
mul32(0xFFFFFFFF,0xFFFFFFFF)=1   mul32(0xFFFFFFFF,0x01000193)=fefffe6d   ← 两端一致
```

同时验证语义正确性：`fnv1a32("abc")=1a47e90b` 为规范 FNV-1a 32 值；`a64248ad` 与二轮审查中独立精确算术模拟一致；`mul32(0xFFFFFFFF,0xFFFFFFFF)=1` 符合模 2^32 数学。配套门禁齐备：§7 新增 `flutter test --platform chrome .../deterministic_stroke_seed_test.dart` 且明确"`flutter build web` 只能证明可编译"（:951）、T2 验收"VM 与 Chrome 实际执行同一固定向量逐值一致"（:487）、§4 阶段复核门 T2 条、§6.1"32 位乘法只走 mul32 语义"、风险台账与 §10.A 对应条目。**F-1 关闭，撤销对 T2 的阻断。**

### 10.2 逐项闭合核验

| 发现 | v2 落点 | 结论 |
| --- | --- | --- |
| F-1 哈希跨端漂移 + Web 门禁空洞 | §3.3 安全参考实现 + 禁令 + §7 Chrome 命令 + §4/§6.1/§9/§10.A 配套 | **ADDRESSED（实证闭合）** |
| F-2 静态缓存缺位 | 测量优先：T4 工作项 11 `planBuildCount` 探针 + T4-C 条件任务（缓存键含 id/version/versionNonce/renderVersion/profile 版本、失效测试、优先降密度）+ §6.1 改写为"记录构建次数，默认不预建" + §11 另加 2~4 人日 | **ADDRESSED**（采"先测后建"路线，优于预建缓存） |
| F-3 renderVersion 管道四处 | §3.10/T6-2（buildPreviewElement）、T7-2（`_drawSegment`）、§3.9/T7-3（`_sameStyle`）、T1/T6 文件清单含 freedraw_tool + T6-1（ActiveFreedrawView） | **ADDRESSED** |
| F-4 layeredWetInk 未裁决 | 新增 §3.10：默认路径必须支持 v2、layered 同 dispatcher、远端验收需双 flag + protocol≥2、flag 未开不得声称验证过远端；T6-10 双路径测试；T12 运行口径写明 dart-define | **ADDRESSED** |
| F-5 指标定义缺失 | T0 十项冻结指标（渲染底图/着墨阈值 16/255/共同中心带/法向剖面中位数/残差 RMS/lag2~32 自相关/弧长前缀定义/像素差公式/SVG 排序比较/分块结构比较）+ "T11 只能复用" + N2/N3/N4/N5/N6/N8/N11/N12/N13/N16/N18 全部重写并挂接 T0 公式 | **ADDRESSED** |
| F-6 方向滞后 vs context 深度 | §3.4：固定三 edge stencil、禁递归 IIR、context ≥2 leading + 可选 1 trailing、窗口与 context 同扩；三重等价证明要求（key multiset + 边界切线/包络顶点/paint bucket 逐值相等 1e-9 + 低 opacity 无接缝）；T2/T5/T7/N11 对应断言 | **ADDRESSED** |
| F-7 水位测试冲突 | T3 文件清单补列 + "不得删除，改为 renderVersion=1 锁定 v1 回退" | **ADDRESSED** |
| F-8 `is int` 分叉 | §3.1/§3.9 `num == 1/2` + T1-10 兼容测试（1、1.0、字符串、null、NaN/Infinity） | **ADDRESSED** |
| F-9 坡道单调无门禁 | T11 附加断言（滑窗 darkness/宽度不得逆压力方向大幅回落） | **ADDRESSED** |
| F-10 primitive 记录/channel 枚举 | §3.3 输出补 primitive 记录（kind/channel/key/几何参数/paint bucket）；§3.4 channel 编号写入测试 + join key 归属；T2-7；T9-1"不复制 sampler/seed/方向滤波" | **ADDRESSED** |
| F-11 分发落位 | §3.2：family 为 core 纯枚举、唯一 dispatch switch 在 rendering 层、profile 不 import rendering；T13 ADR-021 内容要求 | **ADDRESSED** |
| F-12 边界常数 | §3.6（pencilScatterRadiusScale/pencilParticleOverhang，初始 0.45 局部宽度）、§3.7（brushMiterLimit 初始 1.5）入 profile 与 bounds 共用；T8-3 | **ADDRESSED** |
| F-13 弱断言 | N4 降级为辅助并注明理由；N8 具体化（距尾 2×size ≥70%/≤45%）；N16 排序一致；N7 具体化为包络顶点距中心线 1.6×目标半宽 | **ADDRESSED** |
| F-14 长笔密度塌缩 | T11："上限触发的 16k 铅笔仍必须满足 N2" | **ADDRESSED** |
| F-15 T4/T5 并行冲突 | §4/§8：专用文件可并行，dispatch/profile/bounds 按 T4→T5 串行合入 | **ADDRESSED** |
| F-16 T12 基线程序 | T12 运行口径：复用 writing_perf 驱动、同机同日同构建同 fixture、main vs 分支、5 次 P95 中位数、禁历史 debug 日志 | **ADDRESSED** |
| F-17 parser warning/示例 | §3.8 规范示例行 + 写侧条件 + ParseWarning 管道复用 + T1-8 | **ADDRESSED** |
| F-18 §8 缺 T12 | :969"T12 不单独提交，验收摘要并入下一项" | **ADDRESSED** |
| F-19 工作量 | 17~24 人日 + T4-C 另加 2~4 | **ADDRESSED** |
| F-20 flutter_ohos 论据措辞 | 调研文档未改动（该措辞在 research §5.3，非计划书） | **NOT ADDRESSED（Note 级，不阻断；改不改由用户定）** |
| F-21 盲测协议 | T12 五条协议（固定种子随机化、匿名、具体问题、4/5 + 可读性中位数） | **ADDRESSED** |
| F-22 .markdraw 取整 | T9 验收：既有取整不纳入像素级版本验收，N14 只比语义与二次往返稳定性 | **ADDRESSED** |
| F-23 sensitivity 复合语义 | T10：滑块继续经烘焙与 [0,1] 钳制再进 v2 曲线，文案不得暗示恢复钳制极值 | **ADDRESSED** |

§4 新增的五个阶段复核门（T0 用户确认、T2 哈希复核、T4-C 条件触发时审缓存、T7 分块、T11 指标防放宽）与二轮报告 §9.3 的要求一一对应。

### 10.3 v2 新引入的残留（均编辑级，不阻断）

1. **Note**：§3.9（:322-323）出现重复短语"`fromJson` 缺失时取 1；缺失时回退 1"——编辑残留，删一处即可。
2. **Note**：T4 验收（:562）仍写"相同宽度下重压区域 ink coverage 至少比轻压高 35%"，沿用旧 coverage 口径，与 N2/T0 指标 #3 的"共同中心带 darkness、不使用总面积 coverage"不一致——应改为直接引用 T0 指标 #3，避免实现者按旧口径写 T4 测试、T11 时再返工。
3. **Note（实现注记，无需改计划）**：§3.4 三 edge stencil 在笔画起点的钳位规则未写（前文不足 2 条 edge 时窗口收缩）。确定性不受影响（整笔与分块在起点处同样缺前文），实现按"窗口内可用边数收缩"处理即可。

### 10.4 复核结论

- **v2 可直接进入 T0**；T0 通过后可进 T1；T2 的阻断已撤销（参考实现经双端实证，Chrome 门禁命令在 §7 落地）。
- 10.3 的三条残留可在任一后续文档提交中顺手关闭，不构成开工条件。
- 维持原要求：T2/T7/T11 阶段独立复核、T4-C 触发时审缓存失效、T12 真机与盲测人工项不假借自动化通过。
