# FlowMuse AI 笔记助手会话上下文记忆实施计划

## Context

当前 AI 助手只把上一轮候选动作附加到下一次请求，能够处理“再精简一点”等单步追问，但连续两轮以上时会丢失更早的用户要求和 AI 回复。用户关闭面板后也没有明确的会话清理入口。

本次只扩展客户端当前面板会话，不修改服务端、数据库、OpenAI 兼容接口、白板场景格式或协作协议。

## 需求

1. 当前 AI 面板内保留最近 6 轮用户指令和 AI 回复。
2. 每次请求仍重新读取最新笔记或当前文本选区，历史记录不能代替最新画布上下文。
3. 会话历史设置独立字符预算，超限时从最早轮次开始移除。
4. 关闭 AI 面板、切换笔记或页面销毁后自动清除，不持久化到本地。
5. 面板提供“清除对话”按钮，清除后恢复首次对话状态。
6. 取消或失败的请求不得写入会话历史。

## 实现方案

### 1. 会话数据模型

- 在 `ai_agent_models.dart` 增加不可变的 `AiAgentConversationTurn`，只保存已校验的用户指令和 `AiAgentResponse`。
- 最大轮数为 6，独立上下文预算为 12000 个 Unicode 字符。
- 提供纯 Dart 裁剪函数：优先保留最新完整轮次，不拆断动作 JSON；单轮已超过预算时不传入该轮。

### 2. 请求组装

- `AiAgentRepository.run()` 接收 `conversation`，替代只传一份 `previousResponse` 的方式。
- 会话历史以 JSON 数据附加到当前用户消息，并明确标注为不可信数据，继续执行现有提示注入防护。
- 当前用户指令、当前笔记标题和最新文本上下文仍单独传入。

### 3. 面板状态与交互

- `AiAgentPanel` 在请求成功后追加一轮记录，失败和取消不追加。
- 下一次追问携带裁剪后的会话列表。
- 标题栏增加“清除对话”按钮；清除历史、当前回复和动作预览，但不关闭面板。
- 面板销毁即自然释放内存，不新增持久化 Store 或 Provider。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/ai_assistant/models/ai_agent_models.dart`
- `FlowMuse-App/lib/features/whiteboard/ai_assistant/repositories/ai_agent_repository.dart`
- `FlowMuse-App/lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart`
- `FlowMuse-App/test/features/whiteboard/ai_assistant/ai_agent_models_test.dart`
- `FlowMuse-App/test/features/whiteboard/ai_assistant/ai_agent_dialog_test.dart`

## 验证方案

1. 单元测试验证只保留最近 6 轮，并在字符预算内优先保留最新完整轮次。
2. Widget 测试连续发送三轮，确认第三轮能收到前两轮历史。
3. Widget 测试点击“清除对话”后历史和当前回复同时清空。
4. 回归 AI 动作预览、追问、取消、语音输入和智能排版相关测试。
5. 运行 AI 助手相关 `flutter test`、目标文件 `flutter analyze` 与 `git diff --check`。

## 实施步骤

- [x] 增加会话轮次模型和裁剪逻辑
- [x] 调整 Repository 请求参数与消息组装
- [x] 接入面板会话状态和清除交互
- [x] 更新 Fake Repository 与相关测试
- [x] 完成静态检查和回归测试

## 实施结果

- AI 助手相关定向测试通过，共 30 项。
- 完整 `flutter test` 通过，共 223 项。
- 完整 `flutter analyze` 未发现新增错误；输出为仓库既有的 38 条 warning/info。
- `git diff --check` 通过。

## 明确不做

- 不做跨面板、跨笔记、跨应用重启的长期记忆。
- 不把对话历史写入 SQLite、日志或服务端。
- 不引入向量数据库、摘要模型、检索增强或新的状态管理依赖。
- 不自动执行 AI 动作，仍保留现有预览和用户确认。
