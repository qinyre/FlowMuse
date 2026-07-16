# FlowMuse AI 笔记 Agent 第一版实施计划

## Context

FlowMuse 已具备语音转文字、手写识别、智能排版、标准文本元素、笔记标题更新和 OpenAI 兼容模型配置，但这些能力尚未组合成用户可见的 Agent 工作流。

第一版目标是在不改变数据库、Excalidraw 格式和协作协议的前提下，让用户用自然语言要求 AI 总结当前笔记，并在确认预览后修改标题、向白板插入文本。

## 范围

- 输入仅包含当前笔记标题和未删除的 `TextElement.text`。
- 模型只能返回 `rename_note`、`insert_text` 两类动作。
- 最多 5 个动作；标题 1～100 字符；插入文本 1～5000 字符。
- 所有动作由服务端规范化，客户端再次严格校验。
- 用户确认后串行执行：先更新标题，再把全部文本作为一次白板变更提交。
- 第一版一次性返回，不做流式输出。
- 忽略原始笔迹、图片和 PDF；没有文本时提示先识别或使用语音输入。
- 临时协作房间不开放入口；普通笔记中的结果仍沿用现有保存和协作同步链路。

## 实现方案

1. 复用 `OpenAICompatibleSmartLayouter` 持有的模型配置和 HTTP 客户端，增加 Function Calling 请求与标准 `tool_calls` 解析。
2. 在现有 recognition HTTP API 注册 `POST /api/ai/agent`，通过账户身份解析器拒绝未登录请求。
3. Flutter 新增 AI Agent 模型、Repository 和对话框，网络继续使用 `NativeHttpClient`，API Key 只存在服务端。
4. 工具栏增加 AI 入口；对话框负责输入、等待、动作预览和确认。
5. `MarkdrawController` 增加批量纯文本插入，所有插入共享一个 `CompoundResult` 和一条撤销记录。

## 关键文件

- `FlowMuse-Server/internal/recognition/ai_agent.go`
- `FlowMuse-Server/internal/recognition/api.go`
- `FlowMuse-App/lib/features/whiteboard/ai_assistant/`
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`

## 验证

- Go 假服务验证发送 `tools` 并解析标准 OpenAI `tool_calls`。
- 有 `FLOWMUSE_AI_*` 环境变量时，可运行真实模型兼容性测试。
- Dart 单测覆盖未知工具、空参数、超长参数和合法响应。
- Controller 测试覆盖多文本一次插入、一次撤销。
- `go test ./...`、`go vet ./...`、`flutter analyze`、`flutter test`。

## 实施步骤

- [x] 服务端请求/响应模型与校验
- [x] Function Calling 调用与兼容性测试入口
- [x] 鉴权 HTTP 端点
- [x] Flutter Repository 与严格解析
- [x] AI 输入/预览对话框
- [x] 工具栏入口与动作执行
- [x] 批量文本单次提交
- [x] 文档同步与全量验证

> 真实模型兼容性测试由 `FLOWMUSE_AI_INTEGRATION=1` 显式启用，运行环境还需提供有效的 `FLOWMUSE_AI_*` 配置；无密钥时只执行标准 OpenAI `tool_calls` 契约测试，不把真实调用标记为已验证。
