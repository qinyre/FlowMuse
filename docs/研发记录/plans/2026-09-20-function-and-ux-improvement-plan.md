# FlowMuse 功能与应用体验优化计划

日期：2026-09-20。代码基线：`main @ bb367c7`。状态：B–D 开始实施，分支 `feature/smart-layout-v3-ux`；E/F 暂不实施。

本计划只处理功能和应用体验，不安排参赛材料、视频、上架或提交工作。基于当前代码与已有问题记录提出方向；没有在本轮重新进行实机体验，下面明确区分已确认缺陷与待验证问题。

## 1. 要做成什么样

把现有能力连成一条顺手的使用流程：**打开笔记 → 整理内容 → 看清前后差异 → 修正结构 → 应用后继续编辑。**

现阶段不再追求功能数量。优先改进智能排版、PDF 批注、AI 助手的使用体验，并补少量帮助用户开始使用、回看来源的功能。

范围边界：

- 手写笔点击与工具栏输入问题由队友负责，本计划不接手其排查、修复或相关分支集成，也不将其作为其他工作包的前置依赖。
- V1 识别和排版保持原样；排版相关改动只进入 V3。
- 复用现有编辑器、候选生成与评分、纠错重跑、资料库、截图与页面导航，不另建工作流、渲染器或 AI 平台。
- 保留内容守恒、应用前校验、取消、过期结果拦截、单次撤销和协作兼容。这些是防丢内容的功能要求，不新增政策或审批流程。
- 不把降低识别质量、关闭错误检查、延长超时算作性能优化。
- 本计划不重新定义旧 R9 是否通过，也不把少量功能回归样例冒充完整识别评测。

## 2. 为什么选这些方向

| 当前依据 | 结论 | 对应工作包 |
| --- | --- | --- |
| [候选卡片](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/views/smart_layout_candidate_view.dart:62)只有 64×48 的预览，直接展示 candidateId、排名、分数与指标名 | 用户难以判断排版是否合适，界面仍偏调试用途 | C |
| [审阅面板](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/views/smart_layout_session_view.dart:352)的合并按钮传空 subjectIds；[接线](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart:982)拒绝，ViewModel 静默返回 | 已确认的无效操作，不是单纯文案问题 | C |
| [候选适用性](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/composition/layout_composition_planner.dart:86)已有短纯文字页限制，但存在图/图注时不走该稀疏限制 | 不能重复开发“短页单栏”；应验证短文字加小图、列表归组和推荐结果 | B |
| [识别链](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart:550)按批串行；已有阶段计时、缓存与超时重试修复 | 仍有性能检查空间，但缺少本轮真实耗时数据，不能直接认定并发就是答案 | D |
| [资料库空状态](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/library/widgets/library_content.dart:860)主要引导创建空白笔记；已有纸张模板不是内容示例 | 缺的是让新用户直接尝试真实流程的示例，不是再增加纸张背景 | E |
| [视觉附件](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart)有来源标签，但没有结构化页/区域定位字段 | “回到原文”有实际价值，但需要补真实定位数据，不能只解析标签 | F |

已具备的摘要、待办、导图、语音指令、页面导航、只读/简洁模式和 PNG/SVG 导出，不列为从零新增。用户此前展示的标题加三项列表截图作为历史问题场景，不据此断言最新 V3 仍有同一根因。

## 3. 工作包与推荐顺序

工程量为熟悉项目的开发者有效人日粗估，包含相关测试，不是模型运行时长保证；设备等待与第三方模型波动另计。

原工作包 A（手写笔点击/工具栏输入）已移出，由队友独立负责。保留 B–F 原编号，避免与此前讨论混淆。

| 包 | 优先级 | 用户能感受到的结果 | 预估工程量 |
| --- | --- | --- | --- |
| B：V3 默认排版质量 | 必做，核心 | 短列表不乱分栏，标题、正文、图文关系合理 | 2–3 人日；复杂识别问题另估 |
| C：看得清、能纠正的排版审阅 | 必做 | 大图比较原稿与结果，修改标题/正文角色或保留原件 | 2–3 人日 |
| D：等待、失败恢复与实测提速 | 必做 | 知道正在处理什么，能取消、能重新开始，减少有证据的无效耗时 | 1–2 人日 |
| E：两份可编辑场景示例 | 推荐，独立插入 | 第一次打开就知道能拿它做什么 | 0.5–1 人日 |
| F：AI 结果回看来源 | 可选新增 | 看解释或摘要时能返回提问时的页面/选区 | 1–2 人日 |

最低完成集合是 B–D，串行粗估 5–8 人日，不能把它理解为剩余周期内全部必然完成。E 可独立开展；F 不阻塞核心功能交付。先做 B 的基线复现，然后推进 B/C，D 的测量可同步进行，无需等待队友的手写笔任务。

### B. V3 默认排版质量

**做什么**

1. 先用现有平板 fixture 与问题页跑出基线，按“源内容 → 识别正文 → 语义结构 → 候选 → 推荐结果”定位第一次变坏的位置。默认选中的结果必须单独验收，不能靠另一个候选好看就过关。
2. 围绕六类内容建立 8–12 个轻量回归场景：标题加短列表、短文字加小图、长段落、图与图注、原生文字混手写、公式/复杂图形需保留。优先真实笔记；程序构造样例和历史截图重建必须明确标识，不冒充实机原始数据。
3. 保持短列表阅读顺序和条目归属；依据真实内容量、图片尺寸及图文关系检查多栏适用性，不让一个小图就自动证明需要侧栏。只修复复现成立的缺口，保留已经有效的短页规则。
4. 检查标题/正文字号、行距、段距、内容宽度与留白。短页允许下半页空白，不以填满页面为目标；长页保证可读宽度；图片与图注不要被拆散。参数变更沿用现有 token/profile 版本与测试机制，不重建主题系统。
5. 将“不能乱序、不能丢失、不能重复、不能遮挡”作为先行约束，评分只在可用结果中比较。仅当回归样例证明评分偏好错误时调整对应指标，不整体重写评分器或添加一批拍脑袋权重。

**完成标准**：历史标题列表问题有自动回归；六类场景逐页对比默认结果，记录内容完整性、阅读顺序、层级、图文关系和明显留白问题。所有样例无新增丢失、重复、遮挡；修复目标有可见改善。识别仍不可靠的区域原样保留并提示，不能用模型自报置信度或总分替代效果结论。

**控制工程量**：先修排名最前的 2–3 类复现缺陷。不重建 OCR/V4、不训练模型、不全面重做公式/表格。若基线显示根因在识别而不是排版，只对现有 V3 分区、资产、结构恢复做有样例支撑的局部修复；超出此范围的根因单独报出，不能隐去或用 UI 美化冒充解决。

**落点**：[语义适配](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/recognition/semantic_adapter.dart)、[候选适用性](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/composition/layout_composition_planner.dart)、[块装配](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/composition/layout_block_assembler.dart)、[评分](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/validation/layout_scorer.dart)。这些是排查入口，不要求全部改动。

### C. 看得清、能纠正的排版审阅

**做什么**

1. 主要区域展示当前候选大图，支持放大查看；原稿/结果可一键切换，宽屏可并排，窄屏用切换。两边使用同一捕获版本和一致的页面坐标范围，不能用持续变化的当前画布假装原稿。
2. 候选使用“单栏阅读、双栏阅读、图文侧栏、保守重排”等真实结构名称；默认展示少量有明显差异的代表，其他候选可展开。只有一个可用候选就显示一个，不凑数，不改变底层正确性校验。
3. 内部编号、三位小数评分、逐笔 source 账本移到详情。主界面使用“已整理/原样保留”与可理解的保留原因；计数必须标清是内容块还是源元素，不能把数百笔画叫数百段内容。
4. 提供可选择的内容块列表，最小纠错只支持“作为标题/作为正文”和“保留原件”。通过现有语义 patch 与 rerun 接线生成新候选；blockId、sourceIds 来自当前语义与源映射，不能从文字或列表序号猜测。
5. 本包移除当前无效的“合并所选区域”入口，保留底层区域纠错能力；不临时制造空 ID 调用。合并、拆分、拖拽阅读序、关系图编辑暂不做。拒绝纠错时显示可理解原因，不再静默吞掉。

**完成标准**：平板横屏与窄窗口能看清文字、访问应用/取消按钮；换候选不写 Scene、不重新请求识别；角色纠错后预览确实变化；保留原件后源内容仍在。纠错过期、切页、关面板后旧结果不能覆盖新状态。应用一次可一次撤销恢复原状。

**明确限度**：第一版不支持在预览中逐字改 OCR 正文；识别错误可保留原件，应用后的可编辑文本走现有编辑能力。不得宣传为“完整识别纠错编辑器”。放大预览不能只把低清位图拉伸：先核查现有真实渲染图分辨率，不足时仅为选中的候选补按需渲染，限制资源并在失效/关闭时释放。

**落点**：[面板](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/views/smart_layout_session_panel.dart)、[审阅视图](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/views/smart_layout_session_view.dart)、[ViewModel](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart)、[真实接线](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart)、[语义纠错](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/correction/semantic_correction.dart)。UI 优先用现有主题、间距与组件。

### D. 等待、失败恢复与实测提速

**做什么**

1. 复用现有计时，比较本地准备/渲染、请求传输与服务端处理、模型识别/复核、结构恢复、本地候选生成。能够分开的阶段才分别报告；无法独立测得上传耗时就不要用总请求时间冒充上传时间。
2. 等待界面显示真实阶段与已等待时间；已知分母时可显示已处理区域数，不显示伪造百分比或未经测量的预计剩余时间。阶段推进后更新，取消与关闭始终可用。
3. 区分服务不可用、处理超时、部分原件被保留、无可用候选、画布已变化。保留有效错误信息，给出“重试/缩小范围/重新分析”等确实支持的操作；重试建立新操作，旧响应不能串入。
4. 根据测量只选一个主要可优化瓶颈：重复渲染/编码、冗余大图、重复请求或本地候选计算。先复用已有缓存与本地结构判断；当前已有重试修复不重做。不得未验证上下文依赖和账本并发就把串行批次改成 `Future.wait`。

**完成标准**：断网、超时、取消、切页、晚到响应都有可运行的回归；原稿不受影响。选三页固定样例，在同设备、模型、配置、网络条件下前后各跑 5 次，记录中位数和最慢值，并区分缓存状态。只有实测改善且 B 的质量回归通过，才能称“提速”。若主要瓶颈在模型服务且本期无法消除，如实交付耗时结论与等待体验，不承诺“几秒完成”。

**不做**：新流式协议、任务队列、后台跨会话任务、全套可观测平台、自动多模型路由；也不默认更换模型或进一步拉长现有 180s/130s 操作/请求超时。

**落点**：[pipeline](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart)、[repository](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/smart_layout/recognition/recognition_repository.dart)、C 的状态展示；仅在数据证明需要时调整 [服务端 V3](D:/Program/HarmonyOS/2024-se-17/FlowMuse-Server/internal/layoutrecognitionv3)。

### E. 两份可编辑场景示例

**做什么**：在空资料库及新建入口提供“试用示例”，第一版只做“课堂笔记整理”“图文学习笔记”两份。内容是真实可编辑的白板元素，少量提示写清操作位置；打开示例不调用模型。已有摘要/导图能力可以从示例继续使用，不新增一套 AI 流程。

复用创建笔记、Scene 保存和现有编解码，每次创建独立副本；保留空白新建入口。不新建模板市场、下载服务或教学弹窗系统，不把示例中预制的整理结果当实时 AI 结果。

**完成标准**：从入口两步内进入可编辑示例；离线可打开与书写；保存重开有效；重复创建互不影响。写入中途失败不留下标为成功的空壳，不覆盖用户笔记。AI 未配置或不可用时显示实际原因，本地内容仍可继续编辑。

**落点**：[资料库 UI](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/library/widgets/library_content.dart)、[现有创建 API](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/library/repositories/library_repository.dart)、[Scene 保存 API](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/repositories/whiteboard_scene_repository.dart)。不新增数据库表。

### F. AI 结果回看来源（可选）

**做什么**：仅在当前 AI 会话内，为附带选区截图/PDF 页的回答展示“查看本次提问来源”。多附件逐个列出，点击回到对应页面或区域；它表示回答的输入来源，不表示模型逐句给出了证据。

在捕获时保存真实的 note/page 标识、场景矩形及必要元素标识，给现有附件补兼容的可选来源信息，由宿主复用页面/视口定位能力。不能从“PDF 第 N 页”字符串反推永久身份。需处理助手面板遮挡：临时收起以查看，再返回时保留会话；不重新设计助手入口。

**完成标准**：选区与 PDF 两条路径能定位；页面/元素被删除或上下文失效时说明无法定位，不跳错页；定位不修改笔记、不重新请求模型。旧附件仍可使用。第一版不承诺重开应用后的永久链接、跨笔记全库索引、逐句引用或 RAG。

**落点**：[捕获函数](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/ai_assistant/repositories/visual_attachment_capture.dart)、[附件模型](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart)、[助手面板](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart)、[白板宿主](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart)。不变更识别或协作协议。

## 4. 其他方向为什么暂不排进去

| 方向 | 当前取舍 |
| --- | --- |
| 一键复习卡 | 后备小功能：可复用现有摘要与 insert_text，先把现有输出可用性做稳，暂不建题库、复习调度或新协议 |
| 讲解/演示模式 | 已有简洁模式、只读模式和页面导航；先验证能否直接满足，暂不再建模式系统 |
| 全文搜索 | 当前主要搜标题/副标题；正文检索涉及保存、导入与协作更新的索引一致性，不当作一两处 UI 改动加入 |
| 多页 PDF 导出 | 当前 PNG/SVG 导出不等于 PDF 导出；分页、字体、原生保存需要单独工作量，本轮不默认加入 |
| AI 正文逐字纠错、区域合并拆分 | 比角色切换更复杂，涉及正文事实/替换映射与区域选取；不是给现有按钮加弹窗就完成，另行设计 |
| 新 OCR、新协作协议、全面 UI 重做 | 风险与回归面过大，本轮不做 |

## 5. 怎么执行，避免流程又变重

1. **只维护本文的五个包（B–F），不生成新 manifest、审批 Gate 或逐项回执。** 每包一个简短完成记录：改了什么、测试结果、待实测项、已知问题。
2. 每包允许拆成少量内聚提交，不规定“一条检查一个提交”。默认由执行者运行测试并自检；不强制每包调用子代理。若使用独立审查，集中看 B/C 的内容守恒、纠错代次与应用撤销，再对整体验收补一次即可。
3. E 可以独立推进。B/C 共享真实接线；D 的 UI 部分与 C 共享视图，先约定最小状态字段再串行集成。F 涉及白板宿主，等 C 稳定后接入。不要让多个执行者同时改同一个大文件。
4. 每包可以独立停下、提交和验收。缺设备/真实页面/服务数据时，只把对应效果验证标为待验证，继续无依赖的开发；不得伪造设备结果，也不让一个实测项阻塞全部工作。
5. 在独立功能分支实施，保留其他执行者的未提交成果。2026-09-20 已授权实施 B–D；按可验证的小阶段及时提交，不等三个包全部完成才提交。

## 6. 验证只保留必要内容

**开发中**：只跑受影响测试目录；对已确认缺陷补最小可复现测试，复用现有测试设施。B 的实际平板场景从 [既有回归](D:/Program/HarmonyOS/2024-se-17/FlowMuse-App/test/features/whiteboard/smart_layout/recognition/tablet_scene_repro_test.dart)扩展，不能把 fake transport 回放叫在线实测。

```powershell
Set-Location 'D:\Program\HarmonyOS\2024-se-17\FlowMuse-App'
# B/C/D：按变更选择该目录，或其中更窄的现有子目录。
& 'D:\Program\HarmonyOS-Flutter\bin\flutter.bat' test test/features/whiteboard/smart_layout
# E / F：分别选择，不要求每个提交全部重复运行。
& 'D:\Program\HarmonyOS-Flutter\bin\flutter.bat' test test/features/library
& 'D:\Program\HarmonyOS-Flutter\bin\flutter.bat' test test/features/whiteboard/ai_assistant
```

**提交前**按仓库要求执行静态检查和全量测试；每条命令退出码均应为 0。有失败应定位，不能仅凭最后一条命令成功宣称全过。

```powershell
Set-Location 'D:\Program\HarmonyOS\2024-se-17\FlowMuse-App'
& 'D:\Program\HarmonyOS-Flutter\bin\flutter.bat' analyze
& 'D:\Program\HarmonyOS-Flutter\bin\flutter.bat' test
# 仅在修改服务端时追加：
Set-Location 'D:\Program\HarmonyOS\2024-se-17\FlowMuse-Server'
& 'D:\Program\go\bin\go.exe' test ./...
& 'D:\Program\go\bin\go.exe' vet ./...
```

涉及原生适配/Platform Channel 时追加 `flutter build hap`；构建通过不代表渲染和网络已经通过实机验证。UI 保留必要的前后截图。不要另写一堆临时 Python 验证脚本。

**最终实机只围绕使用流程集中走一轮**：

- 整理短笔记与图文页：推荐结果可读、放大对照、改角色/保留原件、应用、撤销、保存重开。
- 异常恢复：断网、长等待时取消、换页、重新开始、旧结果晚到。
- 现有能力回归：PDF 页背景未被误处理、协作中排版应用/撤销未丢元素、鼠标与键盘操作可用。
- 若做 E/F：示例副本互不影响，来源定位正确，失效来源有提示。

收口看的是“默认结果是否更好、操作是否顺手、原稿是否安全”，不是新增了多少按钮或自动测试累计多少条。

## 7. 实施记录

### B（2026-09-20）

- 两个先红后绿的复现：小图无条件放行多栏；明确归属第二张图的图注被错误绑定到第一张图。
- 修复图文内容量判定（文字按可读栏宽实测，图片按源显示尺寸计量）、小图只缩不放（preflight 与放置同口径）、明确图注归属优先。未改 OCR、评分权重或冻结 token 值。
- 新增 `default_layout_quality_test.dart` 八页构造场景，逐页验证排名第一的实际产物：正文无丢失/重复/乱序、短列表单栏与层级、长文可读宽度、上下图注、小图尺寸、混合文本、公式/图形原样保留；已有真实平板 fixture 补强默认候选非空、正文存在与资源释放断言。
- 验证：`flutter analyze --no-pub` 零问题；全量 `flutter test --no-pub` 1678 项通过（退出码均为 0）。上述场景是离线回放/构造样例，不是在线 OCR 或实机效果评测；平板视觉对照、真实识别质量仍待集中实测。
