# FlowMuse AI 笔记 Agent 交互与上下文优化计划

## Context

当前 AI 笔记助手已支持自备 OpenAI 兼容接口、受限 Function Calling、动作预览勾选和自适应文本落地，但一次生成后无法继续追问，生成内容不可编辑，长请求不能取消；同时上下文仍以全笔记纯文本为主，未利用当前选区、页面和元素位置，超高文本在分页画布上也可能越过页面边界。常用指令只有固定三项，无法保存个人模板。

本轮只扩展客户端，不改变 FlowMuse 服务端、数据库 schema、Excalidraw 场景格式和协作协议。

## 需求（前七项）

1. 支持基于上一轮候选动作继续追问，例如“再精简一点”“改成待办列表”。
2. 预览阶段允许直接编辑重命名标题和插入文本，应用前继续执行现有长度与工具白名单校验。
3. 生成中可取消请求；取消后迟到响应不得覆盖界面。
4. 有选中文本元素时只把选区作为上下文；无文本选区时回退到当前笔记文本。
5. 上下文携带文本元素的页面序号和坐标，并按页面、纵坐标、横坐标排序。
6. 自适应插入的超高文本拆成多个文本框；分页空间不足时自动追加空白页，仍保持一次撤销。
7. 支持保存、复用和删除自定义常用指令，使用现有 `LocalSettingsRepository` 跨端持久化。

## 实现方案

### 1. 追问与可编辑预览

- `AiAgentRepository.run()` 增加可选 `previousResponse`，把上一轮已经通过客户端校验的候选动作作为 JSON 数据附在新请求中；每次只携带上一轮，避免无限增长的会话历史。
- 对话框在首次生成后清空指令框并显示追问提示；后续生成用当前候选动作作为修改基线，返回的新动作整体替换旧预览。
- 动作预览改为文本输入框。确认应用时重新通过 `AiAgentAction.fromJson()` 构造动作，未知工具、空内容、超长内容仍拒绝。

### 2. 请求取消

- 为 `NativeHttpClient.post()` 增加可选取消令牌：非鸿蒙平台关闭当前 `http.Client`；鸿蒙通道传递 requestId，并调用 `HttpRequest.destroy()`。
- 对话框使用生成序号丢弃取消后的迟到响应，取消只影响当前请求，不关闭对话框。

### 3. 选区与空间上下文

- `AiNoteText` 增加可选 `pageIndex`、`x`、`y`，序列化为模型可读 JSON，不进入白板场景。
- 白板页面优先读取当前选中的未删除 `TextElement`；没有文本选区时读取全笔记文本。
- 元素按 `pageIndex → y → x` 排序；分页归属优先读取现有 `pageId`，无法识别时按元素中心所在页面推断。
- 对话框明确显示“当前选区”或“整篇笔记”，避免用户误解分析范围。

### 4. 超高文本分页落地

- 复用 `TextRenderer.measure()`，按当前页面可用宽高将长文本切成可容纳的文本段，优先在换行或空白处分段。
- 分页模式依次使用当前页及后续页；空间不足时只追加所需数量的空白页，并为文本写入现有 `pageId` customData。
- 新页面元素、文本元素和最终选区放入同一个 `CompoundResult`，历史栈只 push 一次。
- 非分页模式拆分后向下排列，不创建页面。

### 5. 自定义常用指令

- 新增轻量 `AiPromptStore`，用 `local_settings` 的 `flowmuse.ai.custom_prompts.v1` 保存 JSON 字符串列表。
- 最多保存 10 条，每条复用 1000 字指令上限；去重后最近保存的排在前面。
- 对话框提供“保存当前指令”和自定义 `InputChip`，点击复用、删除按钮移除。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/ai_assistant/models/ai_agent_models.dart`
- `FlowMuse-App/lib/features/whiteboard/ai_assistant/repositories/ai_agent_repository.dart`
- `FlowMuse-App/lib/features/whiteboard/ai_assistant/repositories/ai_prompt_store.dart`
- `FlowMuse-App/lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart`
- `FlowMuse-App/lib/features/whiteboard/ink_recognition/native_http_client.dart`
- `FlowMuse-App/ohos/entry/src/main/ets/channels/HttpChannel.ets`
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/test/features/whiteboard/ai_assistant/`
- `FlowMuse-App/test/features/whiteboard/editor_core/`

## 验证方案

- Widget 测试：首次生成后输入“再精简一点”，验证 repository 收到上一轮候选动作；编辑动作后只应用编辑且合法的内容；取消后迟到响应不显示。
- Store 单元测试：保存、去重、最多 10 条、删除和损坏 JSON 降级为空列表。
- Model/Repository 单元测试：空间字段序列化、追问请求包含上一轮动作且仍经过白名单校验。
- 编辑器测试：超高文本拆为多个元素；分页空间不足时追加页面；一次 undo 恢复插入前场景。
- 静态检查：`flutter analyze --no-pub` 不新增 error。
- 相关测试：AI assistant 与 text insertion 测试全部通过；再运行全量 `flutter test --no-pub`，若基线失败需单独说明。
- 鸿蒙原生改动：运行 `flutter build hap`；若本机环境阻塞，明确记录未完成的真机构建验证。

## 实施步骤

- [x] 扩展 AI 模型、追问请求与取消令牌
- [x] 实现动作编辑、追问和取消交互
- [x] 实现选区优先与页面/坐标上下文
- [x] 实现超高文本拆分和分页追加
- [x] 实现自定义常用指令持久化与交互
- [x] 补齐单元测试、Widget 测试和编辑器测试
- [x] 更新需求与前端架构文档
- [x] 完成静态检查、相关测试与跨端自检

## 验证结果

- AI、常用指令与文本插入相关测试：20 项全部通过。
- 全量测试：184 项通过；`hand_drawing_menu_test.dart` 的 2 项既有菜单定位测试仍失败，与本次 AI 改动无关。
- `flutter analyze --no-pub`：无新增 error，仍有仓库既有的 38 项 warning/info。
- `flutter build hap --debug`：通过，鸿蒙 HTTP 请求取消代码已完成编译验证。
- `git diff --check`：通过。

## 明确不做

- 不做服务端会话、向量检索、OCR、跨笔记检索或长期记忆。
- 不保存模型完整聊天记录；追问只携带上一轮已校验动作。
- 不开放新的白板写工具，仍只有 `rename_note` 与 `insert_text`。
- 不修改协作协议、数据库 schema 或 Excalidraw 字段。
