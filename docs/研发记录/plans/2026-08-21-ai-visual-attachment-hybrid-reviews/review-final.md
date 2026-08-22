# 最终全分支审查

- 审查对象：分支 `feature/ai-visual-attachment`，范围 `f1dc359..fae0b6e`（8 commits：C1=153ff87 + C1fix=04a974d、C2=c8715b1、C3=489789b + C3fix=a10425b、C4=137aedc + C4fix=30a4d10、C5docs=fae0b6e）
- 审查方式：不逐任务重验，以终态源码（HEAD==fae0b6e，工作树 clean）做端到端走读：C1 引擎 API ↔ C3 捕获消费 ↔ C4 面板驱动的全链路、C2 校验闸门覆盖面、九条不变量在最终代码上的逐条实证；交叉核对 7 份任务审查/复审报告与遗留 Minor 清单。
- 独立复跑证据（本审查亲自执行）：`flutter test` **+429 全绿**；`flutter analyze` **37 issues 与基线持平**；`git diff --check f1dc359..HEAD` **干净**。

## 结论：通过可合并

最终代码 Critical 0 / Important 0 / Minor 2（新增，均为留档或文档级跟进项，见集成面发现）。各任务审查环的开放发现全部 ADDRESSED，遗留 Minor 全部裁决完毕（无一构成合并前必修）。

## 不变量端到端核查（九条 ✅）

| # | 不变量 | 结论 | 端到端证据（终态源码） |
|---|---|---|---|
| 1 | PNG 纯净性全路径 | ✅ | 到达请求体的字节唯一通道是 `repository.run(attachments: _attachments)`（lib 内 `\.run(` 仅 ai_agent_dialog.dart:455 一处生产调用点；testConnection 走空默认值），run() :79 无条件过 `requireValidAiVisualAttachments`（mime→空→魔数→4MiB→结构化 chunk 扫描，ai_visual_attachment.dart:34-58），闸门覆盖选区渲染、PDF 页 Scene.files、手工构造三条到达路径——即使 normalizeAttachmentPng 对合规输入原样返回未扫 chunk（visual_attachment_capture.dart:25-28），发送闸门仍兜底拒绝。附件构造点全库仅 capture 模块两处（:125/:185）。测试锁定齐备：模型层畸形/IEND 尾挂用例 + capture 层 PDF chunk 扫描用例（visual_attachment_capture_test.dart:205-210 手写解析断三禁） |
| 2 | 预热三件套 + 在途去重 | ✅ | prewarmRegionImages（markdraw_controller.dart:5714-5759）：markDecoding 相交子集占位 → pauseDecodedCallback 计数暂停 → finally resume + releaseDecodingPlaceholders + 单次 notifyListeners；C1-fix 计数器方案消除并发互覆（image_cache.dart:127-143），全库唯一 pause/resume 调用方即此一处。四点状态机终态复核：markDecoding 跳过 _cache/_failed 且不覆盖在途（:74-80）、decodeAndWait 三分支（:56-66）、getImage 占位/在途返 null 不重启（:43）、_decode 失败先 _failed 再正常 complete（:161-167）；loadScene 路径与区域路径无保存/恢复式混踩 |
| 3 | peek-only 解析 | ✅ | exportRegionPng 经 `_peekResolvedImages()`（:5672→:5699-5708）仅 `_imageCache.peek`；`resolveImages()` 在导出路径零调用（grep 实证仅 ：1925 定义与 ：5544/:5601 存量封面/分享路径） |
| 4 | 维度护栏 | ✅ | normalizeAttachmentPng :21 `width*height > maxPixelCount`（默认 4096×4096）先于任何像素解码；`_pngDimensions` 用 ImageDescriptor.encoded 只读头（:51-64）；PDF 路径 IHDR 篡改用例锁定该分支先于重缩放触发 |
| 5 | 资源纪律 + 归一化单点 | ✅ | 终态逐一核验：_pngDimensions finally 双 dispose、_rescalePng finally frame.image+codec 双 dispose（:84-87）、exportRegionPng finally image+picture 双 dispose（:5690-5693）、image_cache disposed 早退释放产物（:151-155）。归一化单点实质成立：ai_assistant 树内 `instantiateImageCodec` 仅 visual_attachment_capture.dart:74 一处。⚠️ 口径附注见发现 F-M1 |
| 6 | 错误映射 | ✅ | aiVisualAttachmentError（ai_visual_attachment.dart:103-114）：hasAttachments 且 {400,413,415,422} 专用文案，其余 null → run() :125-132 落 'AI 服务暂时不可用（HTTP N）'；401/403/404/500 实证不误报视觉文案 |
| 7 | 日志脱敏 | ✅ | 全部新增日志仅两处 debugPrint（repository:105-108/:121-124）：attachments 数量/bodyKChars/status/elapsedMs，无 token/正文/图片字节；KChars UTF-16 口径有注记 |
| 8 | 0 附件回归 | ✅ | BASE 内联请求体与新 buildAiAgentRequestBody 结构比对一致（model/messages/tools/tool_choice/temperature 插入序、system=纯 _systemPrompt、userText 逐 token 同构——本审查对 git show f1dc359 基线逐字段核对）；ai_agent_request_test.dart:199 jsonEncode 串等值断言独立锁定插入序 |
| 9 | 已知边界如实披露 | ✅ | >50 自我逐出（execution.md 设计说明保留"报错但重开笔记无法兑现"）；预热 await 窗口快照穿透（接受口径，capture 注释 ：118-120 如实说明 _failed 粘性与重试不可达）；zoom≤98 推导保留于 execution.md |

## 集成面发现

### 端到端链路核验（无缝隙）

开面板被动捕获 → 缩略条 → 发送 → 仓库校验 → 请求体，全链在终态走读闭合：

1. **接线**：whiteboard_page:628-644 传两捕获回调（绑 `_markdrawController`）+ 初始快照 5 域 record（含 hasSelection，OverlayEntry 丢弃缺陷已修）；快照不再承载附件（:695-703 注释明示）。
2. **面板驱动**：initState 仅在有捕获回调时 postFrame 触发 passive 捕获（dialog:170-181）；`_AiCaptureScene` 三场景分流是 §1.2 表的单一定义点（:336-379），passive-null 静默 / refresh-null 移槽 / manual-null 内联提示 / 失败按场景分级（refresh 移槽+_error 追加后果原文），全部与方案书 §1.2 表逐行吻合。
3. **活动槽不变量**：槽登记仅 passive(:343-346)/replace(:391-394,:402-405) 两处，手动分支永不写槽；移除 identical 清槽（:524-527）、清对话双清（:515-517）；替换计数中性不受满额限制（indexOf 原位替换）；满额槽空提示内联不驱逐。四条变更路径对"slot≠null ⇒ 引用在列表中"的维护闭合（C4 初审 M-4 重写后含卫语句与原子提交）。
4. **时序**：`_generate` 在组请求前 await `_pendingCapture` 且异常吸收（:438-443），注册序保证捕获 setState 先行（测试①②真锁定）；await 后 generation/cancelToken 复查位与既有模式同位。发送窗口内 `_loading=true` 使添加/移除全禁用，附件集合稳定。
5. **闸门覆盖**：lib 内 `AiAgentRepository.run` 生产调用点唯一（dialog:455）；`AiVisualAttachment` 构造点唯一（capture 模块）；校验单点 `requireValidAiVisualAttachments` 在 run() 入口处无条件执行——不存在绕过校验的到达路径。
6. **引擎 API ↔ 消费签名**：prewarmRegionImages(Rect)→Future<int>（失败计数消费正确）、exportRegionPng(Rect)→Future<Uint8List?>（null→'截图生成失败'）、pageForVisibleRect(Rect)→CanvasPage?（nearest 回退陷阱经 visible.overlaps(page.bounds) 自行判定规避，测试 #7 以远置页+pageId 匹配构造反证锁定）、ExportBounds.compute 经 barrel export.dart 导出（依赖方向 editor_core ← ai_assistant 保持，barrel 本分支零改动）。

### 回归面核验

- **0 附件路径**：jsonEncode 串等值双锁（deep-equals + 串等值），基线逐字段比对一致；折叠句 '本次提问仅发送文字上下文' 由 `_attachments.isEmpty` 三元驱动（dialog:952-953），测试 #8 以该句必然性间接锁清空行为。
- **旧调用方（showAiAgentDialog 无回调）**：整块附件区门于 `_hasAttachmentSources`（:793），chips/缩略条/隐私文案整体跳过；initState 不调度被动捕获；既有 '发送时读取画布…' 提示保留门外（:967）；测试 #1 四断言防门控回归（test:589-600）。快捷指令闭包内 hasSelection 保险使存量无回调用例安全早退。
- **editor_core 既有功能**：exportCoverThumbnail 相对基线零改动（diff 空）；loadScene/_prewarmImageCache 主逻辑零改动（仅 image_cache 内部状态机升级，既有 prewarm 测试 13 例绿）；分享路径 exportPng 未触碰；全量 429 绿覆盖协作/导出/封面等既有面。

### 新增发现（本审查）

1. **[Minor] F-M1：T7 归一化单点门禁未固化为可执行资产，且字面口径与库内存量解码点不符**
   - 证据：hybrid §3-5 门禁字面为"grep instantiateCodec|instantiateImageCodec 仅允许出现在该文件与既有 image_cache"；但终态 lib 内还有 markdraw_controller.dart:5935（图片导入期解码取尺寸）与 ：6199（PDF 导入期 putImage）两处真实调用——git show f1dc359 实证两者 BASE 即有（当时 ：5809/:6073），非本分支引入、亦非归一化实现；同时本分支未向 CI（.gitlab-ci.yml 仅 analyze+test）或脚本落地该门禁，仅作为审查过程步骤执行（progress.md 有通过记录）。
   - 影响：无现行缺陷（归一化单点实质成立）；但后来者若按字面跑门禁会对存量两处误报，且门禁无 durable 记录易失传。
   - 建议：跟进项——把口径写进计划文档勘误或 AGENTS.md："门禁范围为 ai_assistant 树内仅 visual_attachment_capture.dart；editor_core 两处为导入期解码、非归一化、BASE 存量豁免"。一行文档改动，不阻塞合并。
2. **[Minor] F-M2（信息级）：`kind` 字段当前无生产消费者**
   - 证据：`AiVisualAttachmentKind` 仅由 capture 构造赋值（:129/:189）并被测试断言；面板活动槽/替换逻辑实际采用引用同一（identical/indexOf，方案书 §1.2 明示"无需模型加 origin 字段"），未读取 kind。
   - 影响：无。系实现以引用同一达成方案目标后的自然简化，kind 作为来源元数据留存（调试/未来分流可用），符合规格形状。
   - 建议：留档即可，勿删（测试已锁定其语义，删除反致无谓 churn）。

### 方案符合度抽查（§1 产品规则 vs 最终行为）

三场景表逐行吻合（见链路核验 2）；活动槽四规则（刷新替换计数中性/null 或失败移除/手动件永不自动删/满额仅槽空提示）全部落实且有测试④⑫⑬锁定；44px+cacheWidth:88 缩略条、KiB 标签、移除钮、截取中占位、≤3 混合计数 chips 禁用均到位；隐私文案 v2 含自动加入/更新披露句与 0 附件折叠句逐字一致（dialog:951-961 vs §1.5）；PDF 双文案按场景 isPdfBackground 元素判定区分（capture:151-158）；`_errorMessage` 补 TimeoutException 分支（:598）。限额类文案收口两处（chip 守卫 '最多添加 3 张图片' 已按 M-1 修复改走内联；快捷指令槽空满额 '附件已满，移除一张以附带当前选区'）。C5 文档三件（README 能力句/execution.md 勘误/项目需求.md §4.12）与 T7 要求一致。

## 遗留 Minor triage

| # | 遗留项（来源） | 裁决 | 依据 |
|---|---|---|---|
| 1 | image_cache `_decode` catch 段缺 disposed 守卫（对称性）（C1初审 M2） | **留档** | catch 段迟到失败仅回填已清空的 `_failed` 并调 `_notifyDecoded`；controller 注册闭包自带 `!_disposed` 守卫（markdraw_controller.dart:104-108），cache 已弃用无人再读——零功能后果。修复收益低于再次触碰 image_cache 的回归面；随下次触碰该文件顺带 |
| 2 | 测试⑩ identical 断言完成序漏检窗口（C1初审 M3） | **留档（已接受口径）** | 行为断言口径系方案书 §4 T3 行 R2-N3/R3-N4 裁决定稿，第 12 例（计数器互覆）已提供更强锁定；收紧收益有限，不再行动 |
| 3 | `_decode` 未 dispose codec（C1初审 M4，存量） | **建议尽快跟进** | image_cache.dart:147-148 取 frame 后 codec 未释放，每次解码泄漏一个 Codec 句柄直至 GC——真实资源泄漏且解码高频发生；BASE 已有非本分支引入故不阻塞合并，但属一行低风险修复（frame 取得后 `codec.dispose()`），建议单独小 commit 或随下一次 image_cache 触碰顺带闭合 |
| 4 | normalizeAttachmentPng 文案变更会使 PDF oversize 映射静默退化（C3fix 复审附注） | **留档** | 哨兵串匹配（capture:180）的两个 throw 点同文件同消息串（:22/:46），漂移风险低；退化后果仅为 PDF 场景显示选区版文案（指引欠准，非数据错误）。下次触碰该文件时改哨兵错误类型或 oversizeMessage 参数更稳 |
| 5 | C4 M-2：并发捕获 guard-return 与简报"await 串行"表述差异 | **留档** | UI 层并发不可达（所有捕获入口在 `_capturing` 期间禁用、被动捕获每会话一次），guard-return 与串行观测等价，与 execution T6 骨架一致；无需改动 |
| 6 | C4 复审 OBS-1/OBS-2（测试锁定强度观察） | **留档备查** | OBS-1（notice↔error 通道互换测试仍绿）：生产通道归属已经两轮源码复读确认无误，强化配方（断言祖先容器 decoration）已记录；OBS-2（移除后槽同步弱锁定）：系脏槽健壮化的固有代价，同步逻辑经代码走查证实，满额态变体配方已记录。未来重构面板状态机时按配方补强 |

## 总评

八个提交构成完整自洽的实现链：C1 提供的渲染引擎 API 与 C3 消费签名精确咬合，C3 捕获模块的 null/StateError 契约被 C4 三场景分流完整兑现，C2 校验闸门以"仓库层唯一入口 + 构造点唯一来源"的结构性方式覆盖全部到达路径，C4-fix 补齐八子项验收用例后测试面对全部用户可见行为形成回归防护。五轮方案审查裁定的关键规则（活动槽、计数中性替换、满额不驱逐、过期意图产物随失败移除、在途 await 异常吸收）在终态代码中全部可追溯且多数有专项测试锁定。验证声明全部独立复核属实：flutter test 429 全绿、analyze 37 与基线持平、git diff --check 干净、归一化单点 grep 过（含存量豁免口径澄清）。无合并前必修项。

**结论：通过可合并｜Critical 0 / Important 0（新增发现 Minor 2：F-M1 建议跟进文档口径、F-M2 信息级留档；遗留 6 项 triage 见上表，其中 1 项建议尽快跟进为存量一行修）**
