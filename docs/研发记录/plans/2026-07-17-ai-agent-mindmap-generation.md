# FlowMuse AI Agent 生成思维导图实施计划

## Context

当前 AI 笔记助手已能读取当前笔记或选中文本，并通过受限 Function Calling 生成重命名、插入文本操作。思维导图模块已经提供 `MindmapNode.fromJson()` 与 `MindmapLayout.treeToElements()`，但尚未接入 AI action 和画布控制器。

本次只扩展客户端公共 Dart 代码，不修改服务器、数据库、协作协议或平台原生工程。模型只生成内容树，坐标、元素 ID、绑定关系和样式继续由现有确定性布局算法产生。

## 需求

1. Agent 支持根据当前笔记或选中文本生成新的思维导图。
2. 模型返回根节点、子节点构成的内容树，不得直接生成白板元素或坐标。
3. 客户端在信任边界限制节点文本、树深和总节点数，拒绝未知字段和非法结构。
4. 对话框在应用前展示并允许编辑树形 JSON，确认后一次性插入画布。
5. 插入结果复用现有思维导图元素、保存、撤销、导出与协作链路。

## 实现方案

### 1. 扩展受限 action

- 新增 `generate_mindmap` 工具和 `AiAgentTool.generateMindmap`。
- 参数固定为 `{ "root": { "text": "...", "children": [...] } }`。
- 客户端限制最多 50 个节点、最多 4 层、单节点最多 100 个 Unicode 字符。
- 每层只允许 `text`、`children` 两个字段；根参数只允许 `root`。
- 同一响应最多包含一个思维导图 action，且不与 `insert_text` 混用，保证一次确认只有一次画布写入。

### 2. 预览与编辑

- 复用现有 action 编辑框，以格式化 JSON 展示思维导图内容树。
- 用户编辑后再次通过同一校验器解析；非法 JSON、超深或超量时禁用“确认应用”。
- 增加“生成思维导图”快捷指令与对应图标。

### 3. 画布落地

- `MarkdrawController` 新增公开插入方法，将已校验树传给 `MindmapLayout.treeToElements()`。
- 默认在当前视口内插入；所有新增元素和最终选区组成一个 `CompoundResult`，历史栈只压入一次。
- `WhiteboardPage` 将 AI action 转为 `MindmapNode` 后调用控制器；重命名失败回滚逻辑保持现状。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/ai_assistant/models/ai_agent_models.dart`
- `FlowMuse-App/lib/features/whiteboard/ai_assistant/repositories/ai_agent_repository.dart`
- `FlowMuse-App/lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart`
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/test/features/whiteboard/ai_assistant/ai_agent_models_test.dart`
- `FlowMuse-App/test/features/whiteboard/editor_core/`

## 验证方案

- 模型测试：合法树往返、未知字段、空文本、超长文本、超过 4 层、超过 50 节点、重复/混合 action 均被正确处理。
- 编辑器测试：生成树被转换成普通思维导图元素，一次 undo 可完整移除。
- Widget 测试：思维导图 action 可预览、编辑、勾选和应用。
- 回归：运行 AI assistant、思维导图相关测试及 `flutter analyze --no-pub`。
- 跨端：实现不引入 `dart:io` 或平台判断，Android、鸿蒙、Web 共用同一路径。

## 实施步骤

- [x] 扩展 action 模型及严格校验
- [x] 注册 OpenAI 兼容 Function Calling 工具
- [x] 补齐对话框预览和快捷入口
- [x] 接入控制器确定性布局与一次撤销
- [x] 补充测试和项目文档
- [x] 完成相关测试、静态检查与跨端自检

## 验证结果

- AI assistant 与思维导图相关测试：31 项全部通过。
- 全量测试：203 项通过；`hand_drawing_menu_test.dart` 的 2 项既有菜单定位测试仍失败，与本次改动无关。
- `flutter analyze --no-pub`：无新增 error，仍有仓库既有的 38 项 warning/info。
- `git diff --check`：通过。
- 跨端自检：只修改公共 Dart 代码，未引入 `dart:io`、平台判断、原生通道或新依赖。

## 明确不做

- 不让模型生成 Excalidraw 元素、坐标、binding 或 elementId。
- 不修改已有思维导图，不做局部增删节点 action。
- 不引入新的布局算法、第三方依赖、服务端接口或平台原生适配。
