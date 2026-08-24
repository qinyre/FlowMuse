# AI 助手生成功能优化（意图感知 + 键盘修复）执行计划

> 分支：`feature/ai-generate-smart-confirm`（基于 `origin/main` e3d12bb 新建）
> 议题：#7 优化AI助手的生成功能
> 目标：对用户指令做智能意图理解——"向笔记内生成内容"型指令先确认再写入；"仅回复"型指令不确认。并对已知典型案例（无内容可生成时把说明文案误包成 `insert_text` 动作）及其同类问题兜底。附带修复 AI 助手对话框点击输入框不弹键盘的问题。

## 0. 事实基线（撰写当日核实）

| 主题 | 事实 | 位置 |
|---|---|---|
| 意图判定现状 | 完全由模型承担（`tool_choice: auto`），系统提示仅"只在用户要求修改当前笔记或白板时才用工具" | `ai_agent_repository.dart:11-23` |
| 面板确认现状 | 动作列表（`rename_note`/`insert_text`/`generate_mindmap`/`smart_layout`）→"确认后将执行：" + CheckboxTile + 可编辑 + "确认应用"；无动作 → 仅显示回复、无确认 UI | `ai_agent_dialog.dart:512-533,1067-1188` |
| 写入落地 | `whiteboard_page.dart:785-842 _applyAiAgentResponse`（rename/insert/mindmap/smartLayout），唯一写入路径，不改 | `whiteboard_page.dart:785-842` |
| 典型案例根因 | 指令"生成待办"但笔记无可生成内容 → 模型回复"当前并没有可生成代办的内容" **却仍返回 insert_text 动作**（把说明当作内容）→ 面板弹确认，用户被迫确认写一句废话进笔记 | 由提示词"生成型→产动作"逼出，属模型判断错误 |
| 工具语义 | `insert_text` 描述为"Insert a summary, action items, outline, or other requested text"——无"无内容则不调用"约束 | `ai_agent_repository.dart:209-224` |
| 键盘 bug 参考修复 | 创建笔记页命名框：`onTapAlwaysCalled: true` + `onTap` 内 `FocusScope.requestFocus`（未聚焦时）/ unfocus+50ms 延迟重新聚焦（已聚焦时），commit `02546f3 修复命名框输入法调用问题` | `create_note_page.dart:579-591` |
| AI 面板输入框现状 | 指令框 `TextField`（`ai_agent_dialog.dart:779-813`）与动作编辑框（`1113-1139`）均**无 FocusNode/onTapAlwaysCalled/onTap**；滚动区 `SingleChildScrollView` 无 `keyboardDismissBehavior`（`718`）；面板是 OverlayEntry 浮层（非 Dialog，无 barrier） | `ai_agent_dialog.dart:718,779,1113`；`whiteboard_page.dart:600-664` |
| 现有测试 | `ai_agent_request_test.dart` 有请求体基线（含 system prompt 逐字段）；`ai_agent_dialog_test.dart` 36 例含"空笔记纯对话无确认 UI"；**无任何焦点/键盘测试** | `test/features/whiteboard/ai_assistant/` |
| 复用 | `AiAgentResponse`/`AiAgentAction` 纯模型（`ai_agent_models.dart`）便于加净化函数；请求体构建为纯函数（`buildAiAgentRequestBody`）可快照 | `ai_agent_models.dart:20-136`；`ai_agent_repository.dart:142-187` |

## 1. 需求

1. **意图理解**：内容生成型指令（总结/待办/大纲/思维导图/整理/续写/手写排版等）由 AI **产出内容并准备写入**，面板展示"确认后将写入"（沿用现有勾选确认）→ 用户确认才真正写进笔记；问答/解释/点评型指令**只显示回复，无任何确认/应用 UI**。
2. **无内容防呆（典型及同类）**：当笔记没有可生成对应内容时（如"生成待办"但笔记无待办事项），回复只用 message 体现（"当前没有可生成待办的内容"），**不得**携带写动作、不弹确认。
3. **同类泛化**：任何动作（insert/rename/mindmap）出现"内容不成立"情形（空值、与回复重复的说明、无效重命名、空导图）都不得进入确认清单。
4. **键盘修复**：AI 面板指令输入框与动作编辑框点击后必须弹出软键盘（复刻 02546f3 方案）；滚动区拖动可收起键盘。

## 2. 实现方案

### 2.1 提示词与工具语义（模型判断层，主修复）

重写 `ai_agent_repository.dart` 的 `_systemPrompt`（原 11-23 行），新增两条硬约束并保持其余既有指令：

- **生成型 vs 问答型二分**：
  - 用户明确或从上下文可判定为"生成内容进笔记"（如 总结/待办/大纲/思维导图/整理文字/续写/生成 xxx）→ 必须产出具体内容，并用 `insert_text`（或 `generate_mindmap`/`smart_layout`/`rename_note`）返回**动作 draft**（应用前用户会确认）。
  - 问答/解释/点评/不要修改（如 这是什么/为什么/对吗/评价）→ **只写 `message`，禁止调用任何工具**。
- **无内容原则**：如果以生成内容为目标却无法从当前笔记/选区得到可生成的材料（内容为空、无待办事项、不适用）→ **只回复说明（如"当前没有可生成待办的内容"），禁止返回动作**；说明文案只能出现在 `message`，不得作为 `insert_text` 的值。不得"凑内容"。
- 保留原文中不需改动的部分（untrusted 声明、ordered、无 Markdown、mindmap 只出层级、禁合并工具、smart_layout 单独调用、视觉附件后缀）。

### 2.2 客户端动作净化（防呆层，纯函数可单测）

新增纯函数（放 `models/ai_agent_models.dart`，与 `AiAgentResponse` 同层）：

```dart
/// 丢弃"不成立"的写动作：空值、与回复 message 同文/被回复包含的说明性动作、
/// 无效重命名、空根导图。返回净化后的 actions（保序）。
List<AiAgentAction> sanitizeAiAgentActions({
  required String message,
  required List<AiAgentAction> actions,
})
```

规则（每条可单测）：
- **R1 空值**：`insert_text` 的 value trim 后为空 → 丢弃。
- **R2 回复回声**：`insert_text` 的 value（trim + 去尾部标点后）与 `message`（同归一化）相等或互为包含 → 证明该"内容"只是回复的说明/致歉，不是要写入的独立内容 → 丢弃。**这直接命中"当前并没有可生成代办的内容"案例**。
- **R3 无效重命名**：`rename_note` 的 title trim 为空或与响应上下文当前标题相同（调用方传入）→ 丢弃。
- **R4 无效导图**：`generate_mindmap` 根节点 text 为空 → 丢弃（响应解析已有白名单校验，此处补空值）。

净化时机：`_setResponse`（ai_agent_dialog.dart:512）对 `response.actions` 先净化再建控制器；净化后 `actions.isEmpty` → `< 0` 走"纯回复"分支（现有 setState 逻辑天然如此），面板不出现确认区块。

> 说明：原"指令含？即丢弃动作"的 Q3 规则**不采用**——"帮我总结一下好吗？"这类生成型疑问句会被误杀；防呆以 R1-R4 的"动作内容不成立"为准（与用户案例同类的问题族都在此归一）。

### 2.3 面板 UI 微调

- 确认区块标题由"确认后将执行："→"确认后写入当前笔记："（语义与需求对齐；文案精确匹配不对外，仅 UI 文案）。
- 动作全部被净化掉时，回复照常渲染 Markdown，无确认区块、无"确认应用"按钮（现状零动作即如此，无需新分支）。

### 2.4 键盘修复（复刻 02546f3）

- 指令输入框（ai_agent_dialog.dart:779 `TextField`）：加 `focusNode`（新 `_instructionFocusNode`，State 持有并 dispose）、`onTapAlwaysCalled: true`、`onTap` 全套"未聚焦→requestFocus；已聚焦→unfocus()+50ms 延迟重新聚焦"（逐字复刻 `create_note_page.dart:579-591` 舞步）。
- 动作编辑框（`1113-1139` 每个 `TextField`）：同样按 controller 逐一加 `FocusNode`（并入现有 `_actionControllers` 生命周期）与相同 onTap 舞步。
- `SingleChildScrollView`（`718`）加 `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`（拖动列表收起键盘，可选体验项）。
- 不改面板外的焦点逻辑；不动 `TextFieldTapRegion` 系（那是属性面板的"保持键盘"语义，不适用于聊天面板）。

## 3. 关键文件

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/features/whiteboard/ai_assistant/repositories/ai_agent_repository.dart` | 修改 | `_systemPrompt` 重写（生成/问答二分、无内容禁动作） |
| `lib/features/whiteboard/ai_assistant/models/ai_agent_models.dart` | 修改 | 新增 `sanitizeAiAgentActions` 纯函数（R1-R4） |
| `lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart` | 修改 | `_setResponse` 调用净化；确认区标题文案；两个输入框键盘舞步（FocusNode/onTapAlwaysCalled/onTap）；滚动区 keyboardDismissBehavior |
| `test/features/whiteboard/ai_assistant/ai_agent_request_test.dart` | 修改 | system prompt 基线更新（逐字段断言语义二分，非整串快照） |
| `test/features/whiteboard/ai_assistant/ai_agent_models_test.dart` | 修改 | `sanitizeAiAgentActions` 单测（R1-R4 各 ≥1 例 + 组合 + 空列表原样） |
| `test/features/whiteboard/ai_assistant/ai_agent_dialog_test.dart` | 修改 | ①"说明性动作被净化→无确认区"用例（伪造 response.actions == message 回声）；②点击指令框后 `FocusScope.hasFocus` 为 true（键盘舞步生效，widget 断言 focus 而非真键盘）；③零回归（36 例不动/少量更新） |
| `docs/项目说明/项目需求.md` | 修改 | 4.5.1 补"生成型确认写入 / 问答型不确认 / 无内容不写入"语义 |
| `docs/技术设计/接口设计.md` | 修改 | AI 助手节补工具使用与"无内容禁止动作"约定 |
| `docs/研发记录/plans/2026-08-24-ai-agent-smart-intent-confirm.md` | 新建（即本文件） | 本计划 |

不加依赖、不加数据库 schema、不改 Excalidraw/协作协议；`_applyAiAgentResponse` 与白板写入路径零改动。

## 4. 验证方案

1. `cd FlowMuse-App && flutter analyze`——不新增 error。
2. `flutter test test/features/whiteboard/ai_assistant`——全部通过（含既有 ~100 用例回归）。
3. `flutter test` 全量——无回归。
4. 手动回归（每条必测，用配置的 OpenAI 兼容服务）：
   - **主案例**：空白/无待办内容的笔记 → 发"生成待办" → 回复"没有可生成内容"且**无**确认区块 → 笔记不变。
   - 有内容的笔记 → "总结当前笔记" → 显示"确认后写入"+ 确认应用 → 点击后总结写入；不点 → 不写入。
   - 问答："这个公式对吗？" → 只有回复，无确认 UI。
   - 生成型疑问句："帮我总结一下好吗？" → 仍能产出总结 + 确认（验证 R2 未误杀）。
   - 动作编辑框/指令框点击 → 键盘弹出；拖动滚动区 → 键盘收起；连续点两次框仍可编辑（50ms 重聚焦舞步不闪烁）。
   - 导图/手写排版/重命名快捷指令逐一回归（应用、预览、失败回滚路径）。
5. 跨端自检：改动均在共享 Dart（无平台分支）；6 端行为一致；无 `Platform.is*` 引入；无需动 `ohos/`/`tool/vendor/`。

## 5. 实施步骤（TDD，每步含验证命令）

### T1：净化函数（先行红→绿）

1. `ai_agent_models_test.dart` 先写 `sanitizeAiAgentActions` 失败用例（R1-R4 + 组合 + 空输入返回空列表 + 保序），实现后再跑绿。
2. `flutter test test/features/whiteboard/ai_assistant/ai_agent_models_test.dart`。

### T2：提示词重构

3. 重写 `_systemPrompt`；同步更新 `ai_agent_request_test.dart` 中 system 基线断言（语义二分字段级断言）。
4. `flutter test test/features/whiteboard/ai_assistant/ai_agent_request_test.dart`。

### T3：面板接线 + 键盘修复

5. `_setResponse` 净化；确认区文案；两处 `TextField` FocusNode + onTap 舞步；滚动区 `keyboardDismissBehavior`。
6. `ai_agent_dialog_test.dart` 增补两用例（回声动作无确认区；点击指令框有焦点）并在旧用例回归下跑绿：
   `flutter test test/features/whiteboard/ai_assistant/ai_agent_dialog_test.dart`。

### T4：仓内回归 + 文档

7. `flutter analyze`；`flutter test` 全量。
8. 更新 `docs/项目说明/项目需求.md`、`docs/技术设计/接口设计.md`（见 §3）。
9. 手动按 §4 清单（需真机/桌面热重载回放）。

### 提交

- 一个功能提交，中文描述：`feat:AI助手按指令意图区分确认写入与纯回复并修复输入框键盘`。
- 不纳入无关工作区文件（本分支应保持干净；如遇 vendor 文件 M，先 stash 再提交）。
