# AI 多模态白板 A 线 Phase 2（A6/A7）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AI 面板具备选区感知的快捷指令、可理解的阶段状态与平板响应式布局；落地链路（A5）经既有测试验证零改动。

**Architecture:** 快照 record 增加 `hasSelection` 布尔字段驱动面板快捷指令切换；`_generate` 拆分 preparing/generating 两阶段文案；白板页 OverlayEntry 在宽屏放宽面板宽度。无新文件、无新依赖。

**Tech Stack:** Flutter/Dart、flutter_test widget 测试。

**Spec:** `docs/研发记录/plans/2026-07-20-smart-handwriting-whiteboard.md`（A6/A7 条目）

## Global Constraints

- 分支：`feature/ai-multimodal-whiteboard`；每任务一个独立提交，中文提交信息。
- 不改 Repository 协议与 action 白名单；不改编辑器内核。
- 纯文本/无选区路径的现有行为与文案保持不变（新增而非替换语义，除快捷指令组按需求切换）。
- 完成标准：`flutter analyze` 无新增 error、改动文件零告警；`flutter test` 全绿。

## A5 结论（勘察记录，无需任务）

落地链路 v1 已实现且被既有测试覆盖：多段文字一次场景变更+一次撤销（speech_text_insertion_test）、思维导图一次撤销（mindmap_ai_insertion_test）、超高文本自动加页且一次撤销（同文件）、自适应换行（同文件）、应用失败回滚重命名（whiteboard_page `_applyAiAgentResponse`）。Phase 2 仅在总计划勾选并注明验证方式。

---

### Task 1: 选区感知快捷指令

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`（快照填充）
- Test: `FlowMuse-App/test/features/whiteboard/ai_assistant/ai_agent_dialog_test.dart`

**Interfaces:**
- Produces: `AiAgentContextSnapshot` 增加 `bool hasSelection` 字段；`showAiAgentDialog` / `AiAgentPanel` 增加 `bool hasSelection = false` 参数。
- 行为：`hasSelection == true` 时快捷指令显示「解释这里 / 检查公式 / 整理文字 / 整理成导图」；否则维持现有五项。

- [ ] Step 1 失败测试：contextProvider 返回 `hasSelection: true` 的快照 → 面板出现「解释这里」，点击后指令框填入对应文案；无选区回归用例沿用现有「待办」chip 测试。
- [ ] Step 2 运行确认失败（编译错误：缺字段）。
- [ ] Step 3 实现：record/参数/初始化/白色页填充（`selectedTexts.isNotEmpty || visualSelected.isNotEmpty`）/chips 按 `_context.hasSelection` 切换。
- [ ] Step 4 `flutter test test/features/whiteboard/ai_assistant` 通过。
- [ ] Step 5 提交 `feat:AI面板支持选区快捷指令`。

### Task 2: 阶段状态与平板响应式宽度

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart:610`（panelWidth）
- Test: `FlowMuse-App/test/features/whiteboard/ai_assistant/ai_agent_dialog_test.dart`

**Interfaces:**
- Produces: 私有枚举 `_AiGenerateStage { preparing, generating }`；loading 文案规则：
  - preparing → 「正在准备上下文…」（覆盖截图渲染阶段）
  - generating 且带附件 → 「正在结合选区图像与笔记内容生成…」
  - 其余维持现有三条文案不变。
- 白板页：`size.width >= 900` 时面板宽 420，否则维持 `min(360, width-24)`。

- [ ] Step 1 失败测试：注入 Completer 版 fake repository + 带附件 contextProvider，发送后断言出现「正在结合选区图像」；complete 后正常渲染回复。
- [ ] Step 2 运行确认失败。
- [ ] Step 3 实现：`_generate` 中 await contextProvider 前置 setState(stage=preparing)，取得上下文后切 generating；build 中按上述规则取文案；panelWidth 调整。`# ponytail:` 真实分阶段需 Repository 进度回调，当前以客户端可知状态近似，后续需要时再引入。
- [ ] Step 4 `flutter test test/features/whiteboard/ai_assistant` 通过。
- [ ] Step 5 提交 `feat:完善AI面板阶段状态与平板布局`。

### Task 3: 全量验证与文档同步

- [ ] `cd FlowMuse-App && flutter analyze && flutter test` 全绿。
- [ ] 总计划勾选 A6/A7 与 Phase 2 清单，注明 A5 以既有测试验证。
- [ ] 提交 `docs:同步AI面板体验计划进度`。

## Self-Review 记录

- 规格覆盖：A6 四项 = 快捷指令(Task1)、阶段状态(Task2)、响应式侧栏(Task2)、预览/追问/确认保持既有（回归覆盖）；A7 = Task1/2 新增测试 + Task3 全量回归。
- 类型一致性：`hasSelection` 贯穿 record/参数/填充；无跨任务新签名。
