# FlowMuse AI 笔记 Agent P0-P1 优化计划

## Context

现有 AI 笔记助手已经支持用户自备 OpenAI 兼容接口、读取当前标题与文本元素、生成 `rename_note` / `insert_text` 动作，并在预览确认后写回笔记。

当前主要问题是：

- 长 AI/语音文本会形成超长单行文本框，遮挡画布内容。
- 单个文本元素超过 5000 字或整篇笔记超过 30000 字时直接拒绝，较大笔记无法使用。
- 常见任务需要重复输入提示词。
- 模型返回多个动作时只能全部应用，用户不能排除不需要的重命名或插入。

本轮只执行 P0、P1；P2、P3 不进入实现。

## P0：可靠落地与大笔记可用

### 目标

1. AI 与语音生成的长文本根据当前视口或当前分页宽度自动换行。
2. 插入位置优先选择当前可见区域中的空闲位置。
3. 多段 AI 文本仍作为一次场景变更写入，保持一次撤销。
4. 大笔记不再直接拒绝：按文本元素顺序安全截取最多 30000 个 Unicode 字符，单段最多 5000 字，并明确提示上下文已截断。

### 实现

- 复用 `MarkdrawController.insertPlainText(s)`，增加可选的自适应布局参数；普通粘贴保持原行为。
- 分页模式使用当前页内边距区域，非分页模式使用当前可见视口。
- 用现有元素包围盒做轻量空闲区扫描，不引入布局引擎或新依赖。
- 在 AI 模型层增加纯 Dart 上下文裁剪函数，白板页面只负责收集文本元素。

### 验证

- 长语音文本会换行。
- 长 AI 文本不越出当前页横向边界。
- 已占用左侧区域时优先放到右侧空闲位置。
- 超长上下文被切分并限制在 30000 字以内。

## P1：降低操作成本并保留用户控制

### 目标

1. 提供“总结笔记”“提取待办”“生成大纲”三个快捷指令。
2. 预览阶段允许逐个勾选模型动作。
3. 至少选择一个动作才能确认应用。
4. 只把勾选后的动作传给现有原子应用流程；工具白名单和参数长度校验保持不变。

### 实现

- 在现有 AI 对话框中增加快捷 `ActionChip`，仅填充输入框。
- 生成结果后默认全选，以 `CheckboxListTile` 控制动作集合。
- 确认时构造只含已选动作的 `AiAgentResponse`，不修改网络协议和 Repository。

### 验证

- 点击快捷指令会更新输入框。
- 取消重命名后确认，只执行插入文本。
- 全部取消时确认按钮禁用。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/ai_assistant/models/ai_agent_models.dart`
- `FlowMuse-App/lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart`
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`
- `FlowMuse-App/test/features/whiteboard/`

## 明确不做

- P2：多轮会话、流式输出、选区级上下文、图片/PDF OCR。
- P3：开放更多写操作、服务端 Agent 编排、长期记忆、向量检索。
- 不改数据库、Excalidraw 场景格式、协作协议和 FlowMuse 服务端。

## 实施清单

- [x] P0 自适应文本框布局
- [x] P0 大笔记上下文安全裁剪
- [x] P0 单元测试
- [x] P1 快捷指令
- [x] P1 动作级勾选与应用
- [x] P1 Widget 测试
- [x] 静态检查与相关测试
