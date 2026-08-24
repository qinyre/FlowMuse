# R3 资源安全回归审查（第五轮·最终确认）

审查对象：`docs/研发记录/plans/2026-08-21-ai-visual-attachment-hybrid.md` **v5**
对照基线：第四轮报告 `.superpowers/sdd/hybrid-review/round4-r3-resource-safety.md`（0C/0I，余 M1 Minor）

## 结论：可行

## 一、第四轮 M1 裁决

| # | 发现 | 裁决 | v5 证据 |
|---|---|---|---|
| M1 [M] | 快捷指令捕获失败路径活动槽未清，与 §1.6"以文字上下文为主"文案口径差 | **ADDRESSED** | §1.2 表（:45）快捷指令行 StateError 列："移除活动槽附件（过期意图产物，与 null 分支同处理），`_error` 展示 + 追加后果说明（……刷新失败时驻留会让'以文字上下文为主'文案失实）"——采纳第四轮建议方案 a（失败时清槽，与 null 分支对称）；T6' 用例②（:126）同步："在途捕获失败→**活动槽被移除**、发送仍以纯文本完成且 `_error` 展示追加后果文案" |

时序复核：清槽发生在快捷指令 handler 的 catch（`await capture()` 的第一个续体），`_generate` 对同一 `_pendingCapture` 的 await 续体注册在后——微task 注册序保证 `_attachments` 先更新再被 `_generate` 读取，与 §1.2.5（:58）"发送以当前 `_attachments` 继续"一致，用例②可按此实现。三场景表其余两行（开面板失败无槽可清、手动 chip 产物不登记槽）与新规则无冲突。

## 二、v5 其余改动核查（无新矛盾）

1. **C3 触碰面收窄（R2-Y1 吸收，:101/:125/:129 三处一致）**：对 ai_agent_dialog.dart "仅限为 `AiAgentPanel` 增两个可选回调参数（默认 null、零行为变更），不触 UI 逻辑与任何 dialog 测试"——修复了 v4 "传回调"与"不触 dialog 文件"的字面矛盾；纯增量参数无调用方破坏、C3 可绿、C4 再接线，提交链 C2→C3→C4 编译连贯性维持（C2 已完成存量构造点签名适配，快照 `attachments` 字段与 `showAiAgentDialog` 参数在 C3 恒空/不动、C4 删除，:100/:101/:125 表述互洽）。
2. **§7 第四轮记录（:182-183）**：R3 结论"可行（0C/0I，余同一 Minor）"与第四轮报告事实一致；header :4 "第四轮 1I/2M"（R2-Y1 1I + R1/R3 各 1M）计数正确。
3. 未改动段落（§2 四点状态机、§3 不变量、§4.1 八条、§6 风险表、T1'-T4'/T7 行）与 v4 逐字一致，第四轮全部通过性核查继续有效。

## 三、新发现

无。四轮 R3 视角累计发现（第一轮 5I/5M、第二轮 3I/4M+2 项 PARTIALLY、第三轮 1I/3M、第四轮 1M）全部闭合，关键防线（image_cache 在途去重状态机含 markDecoding 前置条件、结构化 chunk 扫描含 IEND 残余拒绝、归一化单点 + grep 门禁、0 附件 jsonEncode 字节回归、日志脱敏、错误映射合并、`_pendingCapture` 异常吸收、失败路径清槽）在 v5 文本上自洽、可实现且有测试锁定。

**最终判定：可行（未解决 Critical 0 / Important 0 / Minor 0）。**
