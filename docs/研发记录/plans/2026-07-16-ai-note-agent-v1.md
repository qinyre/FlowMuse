# FlowMuse AI 笔记 Agent 第一版实施计划

## Context

FlowMuse 已具备语音转文字、手写识别、智能排版、标准文本元素、笔记标题更新和 OpenAI 兼容模型配置，但这些能力尚未组合成用户可见的 Agent 工作流。

第一版目标是在不改变数据库、Excalidraw 格式和协作协议的前提下，让用户用自然语言要求 AI 总结当前笔记，并在确认预览后修改标题、向白板插入文本。

## 范围

- 输入仅包含当前笔记标题和未删除的 `TextElement.text`。
- 模型只能返回 `rename_note`、`insert_text` 两类动作。
- 最多 5 个动作；标题 1～100 字符；插入文本 1～5000 字符。
- 模型返回标准 OpenAI `tool_calls`，客户端负责解析和严格校验。
- 用户确认后串行执行：先更新标题，再把全部文本作为一次白板变更提交。
- 第一版一次性返回，不做流式输出。
- 忽略原始笔迹、图片和 PDF；没有文本时提示先识别或使用语音输入。
- 临时协作房间不开放入口；普通笔记中的结果仍沿用现有保存和协作同步链路。

## 实现方案

1. 在 FlowMuse 实验室保存用户填写的 OpenAI 兼容 Base URL、API Key 和模型名称，其中 API Key 使用本机安全存储。
2. Flutter Repository 通过 `NativeHttpClient` 直接请求 `chat/completions`，发送两个受限工具并解析标准 `tool_calls`。
3. 不新增 FlowMuse 服务端接口，不依赖服务端模型配置或登录状态。
4. 工具栏增加 AI 入口；对话框负责输入、等待、动作预览和确认。
5. `MarkdrawController` 增加批量纯文本插入，所有插入共享一个 `CompoundResult` 和一条撤销记录。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/ai_assistant/`
- `FlowMuse-App/lib/features/settings/views/settings_page.dart`
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`

## 验证

- Dart 单测覆盖标准 OpenAI `tool_calls`、未知工具、超长参数和 URL 补全。
- Controller 测试覆盖多文本一次插入、一次撤销。
- `go test ./...`、`go vet ./...`、`flutter analyze`、`flutter test`。

## 实施步骤

- [x] BYOK 配置与安全存储
- [x] OpenAI 兼容 Function Calling 直连
- [x] Flutter Repository 与严格解析
- [x] AI 输入/预览对话框
- [x] 工具栏入口与动作执行
- [x] 批量文本单次提交
- [x] 文档同步与全量验证

> 自动化测试验证标准 OpenAI `tool_calls` 契约；具体模型是否完整兼容，需用户保存对应 Base URL、API Key 和模型名称后实际调用确认。
