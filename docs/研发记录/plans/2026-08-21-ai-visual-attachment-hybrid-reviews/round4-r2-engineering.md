# R2 工程可行性审查（第四轮复核·聚焦验证）

审查对象：`docs/研发记录/plans/2026-08-21-ai-visual-attachment-hybrid.md` **v4**
审查基线：第三轮报告 `round3-r2-engineering.md`（X-1：C3 触 dialog 测试断裂）+ 工作区代码（本轮新增验证：test/ 下无任何引用 `WhiteboardPage`/`_currentAiAgentContext`/`_toggleAiAgent` 的测试；`ai_agent_dialog.dart` 中 `AiAgentPanel` 现状无 `onCaptureSelection`/`onCaptureCurrentPdfPage` 参数）
审查人：对抗审查子代理 R2（工程可行性与代码对齐镜头）
日期：2026-08-21

## 结论：可行但需修订

第三轮 X-1 **ADDRESSED**（v4 采纳"删除面推迟 C4"方案，四处一体同步）。但修复表述过强引入一项新 Important（Y-1）：T5' 的"whiteboard_page 回调传递"与"T5' 不触 dialog 文件"**字面矛盾**——回调的接收方 `AiAgentPanel` 定义在 `ai_agent_dialog.dart`，其回调参数按 execution T6/v4 §2 面板行属 T6'(C4) 添加；严格按字面执行 C3 无法编译。该矛盾解法单向且局部（见下），不构成返工级风险，但实施前必须澄清措辞。

未解决：Critical 0 / Important 1（Y-1，v4 新引入）/ Minor 0。

## 裁决表（第三轮发现 → v4 处置）

| 第三轮发现 | v4 证据 | 裁决 |
|---|---|---|
| **X-1** T5'(C3) 删除面触及 dialog 测试（`_openDialog:432` 编译断 + :338/:386 运行时红），改写全在 C4 | §2 whiteboard_page 行（:101）：`快照 attachments 字段此时恒空保留——字段删除与 dialog 侧改动一并推迟到 T6'/C4（第三轮 R2-X1 裁决：…若 C3 删参数/字段则 C3 编译断裂）`；§4 T5' 行（:125）：`不触 dialog 文件与其测试（快照字段恒空保留、showAiAgentDialog 参数不动，删改推迟 T6'/C4）`；§4 T6' 行（:126）：吸收 `删除快照 attachments 字段（三处）与 showAiAgentDialog 的 attachments 参数`，dialog 测试改写含 `_openDialog:432` 传参改捕获回调注入；§2 面板行（:100）：快照字段删除标注"自 T5' 推迟而来"；提交切分（:129）：`C3 = T4'+T5'（不触 dialog 文件与其测试…）；C4 = T6'（dialog 全面改写 + 吸收自 T5' 推迟的字段/参数删除）`。**C3 可绿验证**（除 Y-1）：dialog 测试经 `_openDialog`→`showAiAgentDialog`→`AiAgentPanel.attachments` 注入，不经 whiteboard_page——C3 后该路径完全未动，:338/:386 行为断言照常通过；模型测试 3 个行为用例随 `buildAiVisualAttachment` 删除同步迁 §3.4（T5' 行已注明）；whiteboard_page 无测试文件（本轮 grep 验证） | **ADDRESSED**（但修复引入 Y-1） |

## 发现清单

### [Important] Y-1 T5' "传捕获回调" 与 "不触 dialog 文件" 字面不可兼得
- 证据：§4 T5' 行（:125）：`接线调整：whiteboard_page 回调传递 + …；不触 dialog 文件与其测试`；§2 whiteboard_page 行（:101）：`改为传捕获回调（onCaptureSelection/onCaptureCurrentPdfPage）`；`ai_agent_dialog.dart:66-98`：`AiAgentPanel` 定义于此文件，现状**无**这两个参数（本轮 grep 验证）；execution.md T6 规格含 `AiAgentPanel 新增可选参数与字段`（即参数添加时点为 C4）；提交切分（:129）`C3 … 不触 dialog 文件`。
- 问题：回调传递的接收方是 `ai_agent_dialog.dart` 里的 `AiAgentPanel` 构造参数。C3 传参的前提是参数已存在，而参数添加按规格在 C4——严格遵循"不触 dialog 文件"字面，T5' 的"回调传递"无法编译，实施者必然撞墙后自行决策。实质上 v4 的真实约束应是"**不触 dialog 测试**"（可绿）；"不触 dialog 文件"是过强表述：给 `AiAgentPanel` 加两个**无读取的可选回调参数**（字段声明、默认 null）确实触碰 dialog 文件，但零行为变化、零测试影响（`_openDialog` 不传新参数，dialog 测试路径与断言完全不变——本轮已验证测试注入不经 whiteboard_page）。
- 建议（二选一，均为措辞/边界级）：(1) T5' 行改为"不触 dialog **测试**——AiAgentPanel 仅新增两个无读取的可选回调参数（行为零变化），快照字段与 showAiAgentDialog 参数删改仍推迟 C4"；(2) 将"回调传递"整体挪至 C4 与参数添加同提交，T5' 收窄为"删内联捕获 + 删 buildAiVisualAttachment + 初始 hasSelection 传入"（`hasSelection` 参数 AiAgentPanel 已有（ai_agent_dialog.dart:75/:89），后者确可不触 dialog 文件）。

## C1→C5 时序推演结论（v4 任务面）

- **C1** 可绿（第三轮已验证；v4 新增 T3 用例 ②（LRU 逐出后 getImage 重解码）自含、可测）。
- **C2** 可绿（第三轮已验证构造点清单完备；v4 未改 C2 面）。
- **C3** 按字面存在 Y-1 编译矛盾；按意图执行（方案 (1) 或 (2)）则**可绿**且无其他断裂：dialog/repository 测试在 C3 零触碰且行为不变（测试注入路径不经 whiteboard_page，本轮代码验证）；模型测试迁移已列；whiteboard_page 无测试。
- **C4** 可绿（T6' 全面改写 dialog 文件与测试 + 吸收推迟项 + §3.5 增 4 用例，改动面集中自洽）。
- **C5** 可绿（文档 + grep 门禁）。

## v4 其他新增内容的对抗检查记录（无问题项）

1. **满额×槽占用三分支**（§1.2.2：槽占用→替换计数中性不受满额限制 / 槽空未满→加入 / 槽空已满→提示不驱逐）：逻辑完备，消除 v3 歧义（"不刷新"会让过期槽图随指令发送）；§3.5 用例 ④ 对应拆分正确。
2. **markDecoding 前置条件复述**（§2 T3 ①："无"= 无表条目且不在 `_cache`/`_failed`）：与 image_cache.dart:49 现状吻合；所防缺陷（对已缓存 id 插占位→LRU 逐出后永久空白）技术推理成立。
3. **IEND 后残余字节一律拒绝**（§4.1-3）：两条生产路径（Flutter `toByteData(png)`、系统渲染位图）输出均无 IEND 尾部，严格化无误伤；基准 1×1 PNG 结构兼容。
4. **视口判定不依赖 `pageForVisibleRect` 判 null**（T4' 行）：代码属实（:4571-4594 nearest 回退使有页时几乎不返回 null）；`visible.overlaps(page.bounds)` 自行判定可行。
5. **`_clearConversation` 清槽引用**（§1.2 活动槽段）：防悬挂引用，正确。
6. **引导性提示内联样式 + 限额文案收口两处**（§1.2 新段）：UI 规格可实现。
7. **§7 项数重算**（R3-F4）：与本轮所见分报告口径一致。
