# 复审报告 C4/T6' 修复环 1（diff 137aedc..30a4d10）

审查人：范围化复审子代理。日期：2026-08-22。
范围：仅裁决初审 review-c4.md 开放发现（I-1、M-1/M-3/M-4/M-5）的处置，并检查修复 diff 是否引入新破损；不展开全量重审。M-2 在初审已裁定"记录差异，不要求改动"，不在本轮范围。

**结论：全部开放发现 ADDRESSED（I-1 八子项 8/8 + M-1/M-3/M-4/M-5）。新破损：Critical 0 / Important 0 / Minor 0。I-1 关闭。**

独立完成的核验（不以控制器报告为证据来源的部分）：
- **提交边界**：137aedc..30a4d10 恰 1 commit（`test:补齐AI面板附件验收用例并统一引导提示通道`）；HEAD==30a4d10（git rev-parse 实证），工作树 clean（status 空）。改动面仅 dialog + test 两文件，与 stat 一致。
- **dart format 实测**：对两改动文件跑 `dart format --output=none --set-exit-if-changed` → "Formatted 2 files (0 changed)"，exit 0。
- **M-1 存量依赖 grep**：全 lib/test 搜 `最多添加` —— lib 仅 dialog:306（现走 `_attachmentNotice`）与 ai_visual_attachment.dart:38（模型 FormatException，另一路径）；test 唯一命中 ai_visual_attachment_test.dart:36（模型 FormatException 用例，与 dialog 守卫无关）。⇒ 无任何存量断言依赖旧 `_error` 通道。
- 测试结果仍按指令采信控制器数据（flutter test 429 全绿、analyze 37 与基线持平），补偿性做了新增用例与实现路径的一一对应走查（见"测试抽查"节）。

## 逐条裁决表

### I-1（§3.5 验收用例落地）——ADDRESSED，8/8

| 子项 | 裁决 | 用例证据（修复后实测行号） | 锁定力评估 |
|---|---|---|---|
| #1 不传回调不渲染 | ✅ | test:589-600 | 真锁定：断言 '选区截图'/'PDF 页' 两 chip findsNothing + 折叠隐私句 + 计数句 findsNothing。若门控（`_hasAttachmentSources`）回归为恒真，四断言必失。补上了初审指出的"回归防护为零"缺口 |
| #2 手动 chip + sizeLabel | ✅ | test:602-624 | 真锁定：tap '选区截图' 走手动捕获路径（第 2 次调用返回 '手动选区'），断言其入列 + `'0 KiB'` findsNWidgets(2)（两张 70B PNG 取整均为 0，同时锁被动件的 sizeLabel）+ 计数句 2 张 |
| #3 达上限禁用 | ✅ | test:626-659 | 真锁定且强于点击法：3 次 PDF 入列后直读两个 ActionChip 的 `.onPressed` 断言 isNull——属性级断言，比 tap-no-op 更不易假绿 |
| #4 失败三分支 | ✅* | passive 失败 test:661-672；manual null test:674-687；manual StateError test:689-709 | 三分支各有专属用例：#4a 断言消息出现且后果说明后缀（'本次发送将以文字上下文为主'）缺席（可与 refresh 径区分）；#4b/#4c 以不同 stub 序列分别锁定两 manual 分支的消息呈现。*通道归属（notice vs 错误容器）未直接断言，见 OBS-1 |
| #5 移除附件（含槽同步） | ✅* | test:711-737 | 锁定移除 UI 流：byTooltip 移除后缩略图消失；随后快捷指令重建成功证明列表可用性。*槽引用同步清空在本场景仅弱锁定，见 OBS-2 |
| #6 loading 禁用 | ✅ | test:739-771 | 真锁定：Completer 挂起发送、单 pump 进入 loading 态，直读添加 chip 与移除钮（byKey）的 `.onPressed` 均 isNull；complete 后 settle 收尾无计时器泄漏 |
| #7 追问保留附件重发 | ✅ | test:773-792 | 真锁定：首发后再追问，`receivedAttachments` hasLength(2) 且末次 hasLength(1)——若追问不带附件则第二断言必失 |
| #8 清除对话清空 | ✅ | test:794-812 | 真锁定：清除后 '开面板截图' findsNothing + 折叠句 '本次提问仅发送文字上下文' findsOneWidget——该句由 `_attachments.isEmpty` 三元驱动（dialog:952-953），附件未清则此断言必失 |

### Minor 各项

| 项 | 裁决 | 证据 |
|---|---|---|
| M-1 手动满额守卫改内联 | ✅ ADDRESSED | dialog:302-307：`_error` → `_attachmentNotice = '最多添加 $maxAiVisualAttachments 张图片'`，注释引 hybrid §1.2 并注明守卫系纵深防御。notice 渲染于附件区内联引导容器（outline 边框，dialog:932-948），与 errorContainer 样式分立，合 §1.2 字面。存量零依赖（头部 grep 实证），无破损 |
| M-3 dart format | ✅ ADDRESSED | 实测两文件 format clean（0 changed）；初审所指粘连行已修复（现 dialog:376-377 正常断行）。diff 中其余格式 hunk 均为空白级变更（详见新破损检查 4） |
| M-4 替换函数卫语句/原子性 | ✅ ADDRESSED | dialog:387-406 重写：`slot == null ? -1 : indexOf(slot)` 哨兵 → `if (index >= 0)` 卫语句；两处 `_activeSelectionSlot = attachment` 均移入 setState 与列表变更原子提交（:391-394、:402-405）；脏引用降级处置有注释明示（:397）。可达路径语义不变（见新破损检查 2） |
| M-5 passive-null 空 setState | ✅ ADDRESSED | dialog:337-341 改为裸 return + 注释说明理由。重建由 finally `if (mounted) setState(() => _capturing = false)`（:380-381）保证；捕获启动时 setState 已清 notice（:329-331），被删 setState 与 finally 之间确无状态差，属纯冗余重建。所有用例用 pumpAndSettle，无 pump 计数依赖 |

## 新破损检查（任务书四检查点）

1. **M-1 通道变化**：无存量断言依赖旧通道（grep 证据见头部）；该守卫路径本不可达（chips 满额即禁用），notice 渲染块位于附件区内部，满额态下条可见故提示可达。**无破损。**
2. **M-4 重写语义 vs 初审描述**：唯一调用方为 refresh 分支（dialog:352）。三条可达路径与初审记录的行为一一保持：活槽→indexOf 原位替换（唯一差异是槽赋值从 setState 外先行改为原子内联，即初审要求的修正本体）；无槽→满额提示或不限流追加（逐行等价）；脏槽→初审记载原为 RangeError 风险，现按槽空优雅降级并覆写槽引用（严格更优，且有注释）。既有用例 ④ 两例（test:514 区段满额提示 / :578-587 满额替换）覆盖前两径，与控制器全量绿自洽。**无破损。**
3. **ValueKey 加入**：dialog:918 为移除钮加 `key: const ValueKey('ai-attachment-remove')`。LocalKey 只需同父兄弟间唯一——各缩略 tile 的 IconButton 分属各自 Row/Container 父，多附件并存亦合法。存量 finder（byTooltip('移除图片')、byText、byType(Image)、widgetWithText(ActionChip,...)）均不感知 key，零影响；新 finder 仅用于 test:763，该时刻恰 1 个附件，满足 tester.widget 的单匹配约束。**无影响。**
4. **dart format 意外变更排查**：逐 hunk 复核——快捷指令 Wrap 条目重排缩进、ListView itemCount/separatorBuilder 折行、Theme.of 链式重排、隐私文案多行字符串缩进、loading 态文案三元链缩进、测试文件若干语句折叠与 EOF 空行删除——全部为空白/折行级；相邻字符串字面量拼接内容逐字未变（隐私文案新旧逐行比对一致），三元表达式结构未变。**无意外变更。**

## 新增用例 ↔ 实现路径对应抽查（10 例）

| 用例 | 对应实现路径 | 成立性 |
|---|---|---|
| :589 不传回调 | 整块门 `_hasAttachmentSources` | ✅ 四断言均在门内侧元素上 |
| :602 手动 chip | manual 有产物径 dialog:358 | ✅ 第 2 次调用区分被动/手动 |
| :626 达上限 | chips onPressed 三元禁用条件（含 length>=max） | ✅ 属性直读 |
| :661 passive 失败 | catch/passive :367 | ✅ stub 直接 throw |
| :674 manual null | manual-null :355 | ✅ 文案逐字断言 |
| :689 manual 失败 | catch/manual :378 | ✅ 第 2 次调用 error future |
| :711 移除+重建 | `_removeAttachment` identical 清槽 :521-528 + 追加径 :398-405 | ✅（同步性强锁定限度见 OBS-2） |
| :739 loading 禁用 | chips 三元 + 移除钮三元 + `_removeAttachment` 兜底 | ✅ Completer 真挂起 |
| :773 追问重发 | `_generate` follow-up 带 `attachments: _attachments` | ✅ 记录点计数 |
| :794 清除对话 | `_clearConversation` :504-518 三字段双清 | ✅ 经折叠句间接但必然地锁 `_attachments.isEmpty` |

对应关系全部成立，未见"测试绿但未触达目标路径"的伪覆盖；与控制器 429 全绿的数据自洽。

## 残留观察（不计新发现、不阻塞关闭、不要求再修环）

- **OBS-1（#4 通道归属弱锁定）**：三分支失败用例以消息文本存在性为主断言。由于 notice 容器（dialog:932-948）与错误容器渲染同一原始消息文本，若未来某场景在 notice↔`_error` 间互换通道，三例仍绿。跨场景判别部分存在（:661 例断言 refresh 专属后果后缀缺席）。此与既有用例的文本断言惯法一致（初审 ⑫ 满额提示例同为纯文本断言）；如需强化，可断言消息 Text 祖先 Container 的 decoration 通道。生产代码通道归属本身经本次源码复读确认无误（:306/:355/:367 notice；:373-375/:378 error）。
- **OBS-2（#5 槽同步弱锁定）**：M-4 将脏槽从 RangeError 改为按槽空降级后，在 test:711 的单附件场景中"移除槽件但未清槽引用"与正常路径收敛到同一终态（均成功追加），末段断言因此无法单独区分同步清空是否发生。这是使脏槽处理健壮化的固有代价而非缺陷；同步逻辑本身已经初审代码走查证实（初审 Spec#8 ✅，identical 判断 :524-525 本次复读仍在）。如需强锁定，可在满额态构造"移除槽件后快捷指令仍能加入"变体（脏槽情形会误报满额提示，从而可区分）。

## 结论

开放发现 I-1（八子项）、M-1、M-3、M-4、M-5 全部 ADDRESSED；四项新破损检查点（M-1 存量断言、M-4 语义一致性、ValueKey 影响、format 意外变更）均通过，未产生任何新的 Critical/Important/Minor 发现。两条锁定强度观察（OBS-1/OBS-2）留档备查，不构成再修环由。修复环 1 判定通过，C4/T6' 审查闭环。
