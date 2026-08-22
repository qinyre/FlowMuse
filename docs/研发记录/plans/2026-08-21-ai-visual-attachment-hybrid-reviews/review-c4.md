# 审查报告 C4/T6'（diff a10425b..137aedc，单 commit `feat:AI面板支持添加与管理视觉附件`）

审查人：spec 合规 + 代码质量双裁决子代理。日期：2026-08-22。
权威依据：融合方案书 v5（§1.1/§1.2/§1.4/§1.5/§1.6、§2 面板行、§4 T6' 行、§4.1-1/5）> execution.md（T6 骨架 596-745 + §3.5 用例表 827-840）> 任务简报。本任务由控制器亲自实现（实现级子代理派发被基础设施阻断），故本报告以独立源码走读为主、不以实现者报告为证据来源。

**结论：Spec ❌（16/17 项——功能项全部通过，唯"§3.5 用例表全部落地"未达标），Needs fixes。Critical 0 / Important 1 / Minor 5。**

除 diff 自身外，本审查独立完成的核验：
- **提交边界**：a10425b..137aedc 恰 1 commit；HEAD==137aedc 且工作树 clean（`git status` 空、`git diff 137aedc` 空）。
- **测试未重跑**（按指令采信控制器全量数据：flutter test 419 全绿、analyze 37 与基线持平），改为逐用例走查测试与实现的对应关系与锁定力（见"测试锁定性"节）。
- **残留引用全树 grep**：`attachments` 在 whiteboard_page.dart 零命中；全库 `attachments:` 仅余 dialog:456 的 `repository.run(attachments: _attachments)` 单点；`showAiAgentDialog(` 调用仅测试 :608 一处且无 attachments 实参；`AiAgentContextSnapshot(` 构造零残留（快照均为字面 record 且字段已同步为 5 域）。
- **whiteboard_page 接线复读**（:600-714）：hasSelection 透传保留（:634/:702）、两捕获回调绑定 `_markdrawController`、快照 record 恰为 typedef 5 域、`ai_visual_attachment.dart` import 连带删除、注释同步更新。
- **模型同一性前提实证**：`AiVisualAttachment` 无 `operator ==` 重写（ai_visual_attachment.dart 全文 grep 为空）⇒ `List.indexOf` 即引用判同，与 `_removeAttachment` 的 `identical()` 语义一致，活动槽"引用判同一"在语言层成立。

## Spec 合规清单

| # | 要求（来源） | 结果 | 证据 |
|---|---|---|---|
| 1 | 被动捕获 null 静默不动作；失败走附件条内联提示不进 `_error`（§1.2 表行 1） | ✅ | dialog:335-339（null 分支零状态变更）、:364-367（`_attachmentNotice = message`）；⚠️ 该两分支无测试（见 I-1） |
| 2 | 快捷指令刷新 null → 移除活动槽、按纯文本执行（§1.2 表行 2） | ✅ | dialog:346-348 `setState(_removeActiveSelectionSlot)`；测试 :481 锁定 |
| 3 | 刷新 StateError → 移除槽 + `_error` 展示且追加后果说明原文（§1.6 第四轮裁决） | ✅ | dialog:368-376，文案与 §1.6 逐字一致（'本次发送将以文字上下文为主…可重试或修改指令'）；测试 :447 锁定移槽+文案+纯文本发送三件事 |
| 4 | 手动 chip：null 内联提示'当前选区没有可截图的视觉内容'；失败进 `_error`；产物不登记槽（§1.2 表行 3 / §4.1-5） | ✅ | dialog:352-358；文案逐字一致。⚠️ 三分支均无直接测试（I-1）；"不登记槽"由代码路径保证并经③⑫间接佐证 |
| 5 | 活动选区槽引用判同一；手动附件任何刷新分支不动（§1.2） | ✅ | 槽登记仅 passive(:343)/replace(:390,:400) 两处，手动分支永不写槽；`indexOf` 因模型无 `==` 重写即同一语义；测试③（null 移槽手动 PDF 保留）、⑫（满额提示不驱逐手动件）锁定 |
| 6 | 替换计数中性不受满额限制（第三轮 R1-N1） | ✅ | dialog:386-395（indexOf 原位替换，条长不变）；测试⑬ :553 在满额态下替换成功且计数仍 3 |
| 7 | 槽空且满 3 张 → 内联提示'附件已满，移除一张以附带当前选区'，不驱逐（§1.2） | ✅ | dialog:396-398，走 `_attachmentNotice`（内联引导样式，合规）；文案逐字一致；测试⑫ :514 断言提示 + PDF 1/3 页仍在 + 计数仍 3 |
| 8 | 用户移除槽附件 / 清除对话时槽引用同步清空（§1.2） | ✅ | `_removeAttachment` identical 判断清槽（:520-521）；`_clearConversation` 清 `_attachments`+槽+notice（:511-513）。⚠️ 两路径无测试（§3.5#5/#8 缺失，I-1） |
| 9 | 门控：`_capturing` 加入添加 chips/移除按钮/清除对话/快捷指令禁用（§1.1） | ✅ | chips :799-803/:817-822、缩略条移除钮 :917、清除对话 :663、快捷指令 :718 四处齐备；`_removeAttachment` 方法体兜底 :518 |
| 10 | 发送不禁用；`_generate` 构请求前 await `_pendingCapture` 且异常吸收，以当前 `_attachments` 继续（§1.2.5） | ✅ | 发送/追问按钮不含 `_capturing`（:1128-1143）；await+catch 吸收（:434-438）；`attachments: _attachments`（:456）；测试①②锁定 |
| 11 | await 时点保证捕获 setState 先于 `_generate` 恢复 | ✅ | 注册序即执行序：`_runCaptureTask` 先 `await capture()`（:332）→ `_captureAndApply` 次之（:310）→ `_generate` 最后（:437），恢复序保证结果 setState 先行；测试①②具备反证力（若未等待，①断言的 sourceLabel 将是旧图、②receivedAttachments 将非空） |
| 12 | 推迟删除三项：快照 attachments 字段（typedef/dialog/whiteboard_page）、showAiAgentDialog.attachments 参数（保留 hasSelection）、AiAgentPanel.attachments 参数——全树无残留 | ✅ | typedef :16-22 已删域；showAiAgentDialog :41-52 仅存 hasSelection；Panel :79-108 参数已删；grep 实证零残留（见头部核验）；阶段态改读 `_attachments`（:982） |
| 13 | 隐私文案 v2 含'会随打开面板或点击视觉指令自动加入或更新'+ 0 附件折叠句（§1.5） | ✅ | dialog:949-958 与 §1.5 原文逐串一致；折叠句 '本次提问仅发送文字上下文'（:950）；测试 :348 断言两子串 |
| 14 | 区块仅在存在捕获回调时渲染，旧调用方零回归（§2/execution §3.5#1） | ✅ | 整块门于 `_hasAttachmentSources`（:788）；旧调用方（无回调）连 chips/缩略条/隐私文案整体跳过，既有 '发送时读取画布…' 提示保留在外（:964-969）。⚠️ "不渲染"无显式断言（§3.5#1 缺失，I-1） |
| 15 | 缩略条规格：44px/cacheWidth:88/来源标签/KiB(sizeLabel)/移除按钮/捕获中占位项（§1.1/T6 骨架） | ✅ | :833-928：44×44+cacheWidth:88（:881-887）、sourceLabel/sizeLabel 双行（:895-910）、移除钮（:913-921）、'截取中…' 占位（:844-874，itemCount 含 `_capturing?1:0`） |
| 16 | `_errorMessage` 补 TimeoutException 分支（execution T6-5） | ✅ | :594，dart:async 已导入（:1），置于 FormatException 之后通用之前，与骨架一致 |
| 17 | 测试面：存量 2 用例行为改写 + §3.5 全部 + 新增 4 场景 | ❌ | 存量 2 改写 ✅（:348 缩略条+隐私文案+随请求发送；:394 阶段态）；新增 4 场景 ✅（①:414 ②:447 ③:481 ④拆⑫:514/⑬:553 两例，覆盖优于单例）；**§3.5 未全落地**——#1/#3/#5/#6/#8 缺失，#2/#4/#7 仅部分覆盖（详见 I-1） |

## 专项走查结论（审查方法指定五项）

1. **`_runCaptureTask` 各场景 catch 分支**：正确。passive→仅 notice；refresh→同一 setState 内先移槽再置带后果文案的 `_error`（原子更新，无中间态可见窗口）；manual→仅 `_error`。finally 以 mounted 保护置 `_capturing=false`；`await capture()` 后及 catch 入口均有 `!mounted` 早退，面板关闭后完成不触 setState。notice 于每次捕获启动时清空（:329），无跨场景残留。
2. **`_replaceActiveSelectionSlot` 越界**：不可达。不变量"slot≠null ⇒ 同一引用在 `_attachments` 中"由四条变更路径闭合维护（登记即入列 :341-344、替换原位换入 :390-392、移除同步清槽 :409-412、清对话双清 :511-512；`_removeAttachment` identical 清槽 :520-521），手动添加不触槽。但代码本身无 `index<0` 卫语句（对比 `_removeActiveSelectionSlot` 有），且 `_activeSelectionSlot = attachment` 在 setState 外先行赋值（:390）——若未来不变量被破坏会先留下脏槽引用再抛 RangeError。→ M-4。
3. **initState addPostFrameCallback**：保护充分。调度侧 `if (mounted)`（:172）覆盖"当帧即关"窗口；捕获完成侧 `!mounted return`（:333/:361）+ finally mounted（:380）覆盖捕获中途关闭；`_pendingCapture` 残留于已 dispose 的 State 上无副作用。
4. **`_generate` pending await 后竞态**：未引入。generation/cancelToken 复查位于 pending-await 与 contextProvider-await 两者之后、任何状态写入之前（:443-445），与 BASE 既有"contextProvider await 后复查"模式同位；pending-await 窗口内取消按钮可用，`_cancelGeneration` 使 generation++/token cancel ⇒ 恢复后走 return，迟到响应既有防线照常生效。唯一代价是取消后仍多调一次 contextProvider（无害，与既有行为同类）。
5. **快捷指令误触发**：不存在。chips 集合本身按 `_context.hasSelection` 三元切换（:700-714）：false 时显示总结/待办/大纲/思维导图/手写排版通用集，true 时显示的全是 §1.2.2 枚举的四个视觉指令；闭包内 `if (_context.hasSelection)` 再加一道保险（该保险同时使存量无回调用例 :372 点'解释这里'安全早退）。非视觉指令集在任何状态下都不会触发刷新。contextProvider 刷新 `_context` 后集合随之切换，口径自洽。

## 测试锁定性抽查

- **①在途时点（:414）**：Completer 挂起第 2 次捕获 → tap 快捷指令 → tap 发送 → 才 complete。若 `_generate` 未等待，repository 收到的将是旧图'开面板截图'；断言 sourceLabel=='刷新后截图' 构成真锁定。✅
- **②在途失败（:447）**：completeError(StateError) 后断言三件事——后果文案出现、旧槽图消失、receivedAttachments 为空。若未等待或未吸收异常，三者必有一失。✅
- **③null 移槽（:481）**：手动 PDF 页先入列，刷新返回 null 后断言开面板截图消失而 PDF 保留、隐私计数归 1。✅
- **④满额两分支（:514/:553）**：槽空分支断言内联提示 + 手动件不驱逐 + 计数不变；槽占用分支断言旧图被换新图、两张 PDF 不动、计数恒 3——恰为 R1-N1/N3 两裁决的行为锁。✅
- fake repository 以引用记录 `receivedAttachments.add(attachments)` 安全：State 对列表全程不可变重建（`[..._attachments]`），记录点快照不会被后续变异污染。

## 发现清单

### Important

- **I-1｜§3.5 验收用例未全部落地**（简报明确要求"§3.5 用例表全部"；execution.md §3.5 未被 hybrid §4.1 废止的行仍为验收清单，§4.1-5 仅修订 #2 文案与 #4/#5 相关期望值）。缺失/缺口逐行：
  - #1 不传回调时附件区不渲染——无显式断言（现靠既有无回调用例隐式不崩，回归防护为零）；
  - #2 手动'选区截图'chip 点击路径与 '0 KiB' sizeLabel 断言缺失（现仅被动路径 :348 与手动 PDF chip :481 侧面覆盖）；
  - #3 达上限后 chip onPressed==null——未测；
  - #4 捕获失败三分支仅 refresh 场景有测试；passive 失败→内联提示、manual null→内联引导、manual StateError→`_error` 容器三条 §1.2 表分支零覆盖；
  - #5 移除附件（含移除槽附件后槽引用清空的同步性）——未测；
  - #6 loading 期间添加/移除禁用——未测；
  - #7 追问保留附件——首发送半边已覆盖（:369 等），追问后再发仍带附件未断言；
  - #8 清除对话清空附件——未测。
  影响：已交付的门控/清空/移除同步等用户可见行为处于无回归防护状态。建议：补齐上述用例（多数可复用现有 `_openDialog`+fake repo 范式，预计 6-8 例）；或由控制器明示豁免范围并记录。

### Minor

- **M-1**：手动 chip 满额守卫 `'最多添加 N 张图片'` 走 `_error` 容器（dialog:304），与 hybrid §1.2 "非失败的引导性提示（**满额提示**、手动 chip null 提示）统一走附件条内联引导样式"的字面相悖。该路径实际不可达（chips 满额即禁用，守卫仅为纵深防御），可达路径（快捷指令槽空满额）已正确走内联。建议一行改 `_attachmentNotice` 以合字面。
- **M-2**：并发捕获处置为静默丢弃（`_captureAndApply` :301 直接 return），简报表述为"await 旧 future 完成后再启动（串行）"。因所有 UI 入口在 `_capturing` 期间禁用且被动捕获仅在 initState 触发一次，并发在 UI 层不可达，两种语义观测等价，且与 execution T6 骨架的 guard-return 一致。记录差异，不要求改动。
- **M-3**：格式粘连 dialog:376 `});        case _AiCaptureScene.manual:` ——dart format 未跑/被绕过的痕迹（analyze 不查 format 故 37 条不受影响）。建议对该文件跑一次 dart format。
- **M-4**：`_replaceActiveSelectionSlot`（:386-395）无 `index<0` 卫语句且在 setState 外先行赋值槽引用（对比 `_removeActiveSelectionSlot` :410-411 的防御写法）。当前不变量下安全，属对称性/健壮性改进。
- **M-5**：passive-null 分支 `setState(() {})`（:338）空重建冗余——finally 的 `_capturing=false` 必然触发重建，可直接 return。纯样式。

### Cannot verify from diff

- flutter test 419 全绿、analyze 37 条与基线持平：采信控制器运行结果（按审查指令未重跑）；作为补偿已对 13 个附件相关用例做逐一对实现路径的对应关系核验（见上两节），未发现"测试绿但未锁行为"的伪覆盖（I-1 所列为"缺"，非"假"）。

## 总评

功能实现质量高：`_AiCaptureScene` 枚举把三场景分流收敛为单一定义点，槽机制四条变更路径对不变量的维护闭合，门控四处齐备，推迟删除三项干净（全树零残留），隐私文案与两处限额文案逐字合稿，在途时序经注册序自然获得保证并被两个 Completer 用例真实锁定。五项专项走查均未发现真实缺陷。唯一实质缺口是测试面：相对简报要求的"§3.5 全部"，约 6 行验收用例缺失、3 行部分覆盖（I-1）。修复建议以补测为主（M-1/M-3 可顺手一并处理），无需触碰生产逻辑。
