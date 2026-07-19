# FlowMuse 鸿蒙 AI 学习闭环双人并行实施计划

## Context

FlowMuse 已具备自研 Markdraw 白板、鸿蒙手写笔压感、原生 PDF 渲染、原生语音识别、AI 手写识别、智能排版、AI 笔记助手、思维导图、端到端加密协作和桌面服务卡片。当前问题不是缺少单点能力，而是这些能力分散在不同入口，AI 助手又主要读取 `TextElement`，无法直接理解用户最常使用的手写笔迹、PDF 页面和图片，因此尚未形成适合鸿蒙人工智能大赛展示的完整智能工作流。

本计划将项目收敛为一条可演示的鸿蒙 AI 学习闭环：

```text
鸿蒙导入 PDF / 手写批注
        ↓
框选文字、笔迹、图片或当前页
        ↓
AI 理解用户明确选择的内容
        ↓
生成摘要、知识点、思维导图和自测题
        ↓
作为普通白板元素原子落地
        ↓
语音继续修改 / 服务卡片继续复习
```

实施由两人并行完成：A 线负责 AI 核心与白板落地，B 线负责鸿蒙体验、服务卡片、服务端测试和比赛交付。两条线通过预先冻结的数据契约协作，尽量避免同时修改同一文件。

## 目标

1. AI 助手能够理解用户明确选择的文本、手写区域、图片或 PDF 页面。
2. 新增结构化的“一键复习包”，生成摘要、知识点、自测题和思维导图。
3. AI 结果继续落为普通 Excalidraw 兼容元素，复用撤销、保存、导出和协作链路。
4. 鸿蒙语音识别可以作为 AI 指令输入，而不只用于创建文本元素。
5. 鸿蒙服务卡片可以从“继续创作”延伸到“继续复习”。
6. 完成鸿蒙应用身份、隐私日志、AI 配置、真机验收和比赛演示材料的打磨。
7. 两条开发线工作量接近、文件所有权清晰、可独立验证和提交。

## 明确不做

- 不重写 Markdraw 编辑器内核。
- 不修改 Excalidraw 场景基本格式、协作消息格式或冲突合并算法。
- 不让模型生成坐标、元素 ID、binding、version 或完整 Excalidraw JSON。
- 不在本轮引入端侧大模型、向量数据库、跨笔记知识图谱或长期记忆。
- 不开放任意白板写操作，所有 AI action 继续使用白名单和严格参数校验。
- 不把笔记正文、图片、API Key、token、ownerKey、roomKey 或模型请求写入日志。
- 不为单一实现新增无必要的抽象层、状态管理框架或第三方依赖。

## 开工前置条件

当前 `feature/github-actions-quality` 已包含 GitHub Actions 质量门禁以及 Flutter 版本修正。正式开始本计划前：

- [ ] 将 `feature/github-actions-quality` 合入 `main`。
- [ ] 确认 `main` 工作区干净且 GitHub Actions 通过。
- [ ] 两人均从同一个最新 `main` 创建功能分支。
- [ ] 确认正式鸿蒙 Bundle ID、vendor 和签名证书主体。
- [ ] 准备比赛使用的固定 PDF、固定手写内容和可用 AI 测试账号。

建议分支：

```text
feature/ai-multimodal-study-pack
feature/harmony-ai-experience
```

## 共享契约冻结

两人开始并行编码前，共同完成以下契约评审。契约一旦冻结，除非双方确认，不在分支中单方面改名或改变语义。

### 1. 多模态附件

新增纯 Dart 数据对象 `AiVisualAttachment`，建议字段：

| 字段 | 含义 |
|---|---|
| `mimeType` | 仅允许受支持的图片 MIME |
| `bytes` | 压缩后的图片字节，不持久化 |
| `sourceLabel` | 当前选区、当前 PDF 页、选中图片等用户可见来源 |
| `width` / `height` | 压缩后的图片尺寸 |

信任边界：

- 最多 3 张附件。
- 单张建议不超过 4 MiB。
- 限制最长边，避免把原始超大 PDF 页面直接发送给模型。
- 只读取用户明确选择的区域；不得默认上传整块白板或整份 PDF。
- 附件只存在于当前请求内，不进入 SQLite、协作协议或导出文件。

### 2. 一键复习包

新增受限 action `generate_study_pack`，建议结构：

```json
{
  "titleSuggestion": "可选标题",
  "summary": "摘要",
  "keyPoints": ["知识点"],
  "questions": [
    {"question": "问题", "answer": "答案"}
  ],
  "mindmapRoot": {
    "text": "主题",
    "children": []
  }
}
```

客户端限制：

- 标题沿用现有 100 字符限制。
- 摘要和答案分别设置明确长度上限。
- 知识点最多 10 条。
- 自测题建议 3～5 道，最多 10 道。
- 思维导图继续限制最多 4 层、50 个节点、单节点最多 100 字符。
- 拒绝未知字段、空问题、空摘要、超量数组和非法嵌套。
- 同一响应最多一个复习包 action。
- 模型只返回内容结构，客户端负责布局、ID、样式和绑定。

### 3. 服务卡片复习状态

服务卡片只同步最小元数据：

| 字段 | 含义 |
|---|---|
| `noteId` | 最近白板 ID |
| `title` | 最近白板标题 |
| `updatedAt` | 最近更新时间 |
| `hasStudyPack` | 是否已生成复习包 |
| `questionCount` | 自测题数量 |

不把摘要、问题正文、答案或白板场景写入鸿蒙 Preferences。

## 分工总览

| 负责人 | 主线 | 主要产物 | 预计工作量 |
|---|---|---|---|
| A | AI 核心与白板落地 | 多模态上下文、复习包 action、确定性布局、AI 面板与 Flutter 测试 | 8～12 人日 |
| B | 鸿蒙体验与工程交付 | 应用身份、日志脱敏、AI 能力中心、智能卡片、语音 AI、Go 测试与真机材料 | 8～12 人日 |

## A 线：AI 核心与白板落地

### 文件所有权

A 线负责：

- `FlowMuse-App/lib/features/whiteboard/ai_assistant/**`
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- 与 AI action、上下文和白板落地直接相关的 Flutter 测试

B 线在 A 线合并前不修改上述文件。若必须接入公共回调，由 A 提供最小接口。

### A1. 多模态上下文模型

- [ ] 新增 `AiVisualAttachment` 及严格校验。
- [ ] 扩展 Agent 请求参数，支持文本和视觉附件同时存在。
- [ ] 保持现有文本选区优先、整篇文本回退逻辑。
- [ ] 当选区包含笔迹、图片或 PDF 页面时生成视觉上下文。
- [ ] 在 AI 面板显示实际上下文范围和附件数量。
- [ ] 请求前向用户说明视觉内容将发送到其配置的模型服务。

验收：

- 纯文本笔记行为不变。
- 纯手写选区不再退化为“暂无文字”。
- 未选择视觉元素时不生成或上传图片。
- 附件超限时在客户端拒绝并显示可理解提示。

### A2. 复用现有渲染生成视觉附件

- [ ] 搜索并复用现有元素 bounds、PNG/SVG 导出和图片缓存能力。
- [ ] 支持渲染选中的自由笔迹、图片和 PDF 背景及其上层批注。
- [ ] 保持元素比例、文字清晰度和公式可识别性。
- [ ] 对超大区域进行缩放或分块，禁止直接发送未压缩大图。
- [ ] 渲染过程不得修改 Scene、History 或当前选区。
- [ ] 取消请求后释放临时字节引用。

验收：

- PDF 背景和批注能够出现在同一附件中。
- 手写公式截图边界正确，不裁掉笔迹。
- 渲染失败不修改场景，也不产生撤销记录。

### A3. OpenAI 兼容多模态请求

- [ ] 扩展 `AiAgentRepository.run()` 的消息构造。
- [ ] 文本上下文继续作为不可信 JSON 数据传递。
- [ ] 图片使用 OpenAI 兼容的多模态 content 结构。
- [ ] 保留 `NativeHttpClient`、鸿蒙原生 HTTP、取消令牌和超时机制。
- [ ] 模型不支持视觉输入时给出明确错误，而不是显示通用失败。
- [ ] 为 Repository 增加最小可测试的 HTTP 注入点，避免引入完整网络框架。

验收：

- 多模态请求 JSON 有自动化契约测试。
- API Key、图片字节和笔记正文不进入日志。
- 取消后的迟到响应不能覆盖面板或落地场景。

### A4. `generate_study_pack` 严格解析

- [ ] 扩展 `AiAgentTool` 和 action parser。
- [ ] 注册 `generate_study_pack` Function Calling 工具。
- [ ] 按共享契约校验标题、摘要、知识点、题目和思维导图。
- [ ] 拒绝未知字段、非法 JSON、超长内容和超量节点。
- [ ] 用户编辑预览后重新走同一校验器。
- [ ] 保持现有 `rename_note`、`insert_text`、`generate_mindmap` 行为兼容。

### A5. 复习包确定性白板落地

- [ ] 在 `MarkdrawController` 增加最小的复习包插入入口。
- [ ] 复用 `insertPlainTexts`、`MindmapLayout`、分页追加和 `CompoundResult`。
- [ ] 使用固定模板布局摘要、知识点、自测题和思维导图。
- [ ] 所有新元素和最终选区作为一次 Scene 变更提交。
- [ ] 分页空间不足时只追加实际需要的页面。
- [ ] AI 结果继续落为普通白板元素，参与保存、导出和协作同步。

验收：

- 一次撤销完整移除整个复习包。
- 导出 Excalidraw 后仍为兼容的普通元素。
- 协作端能够收到生成结果。
- 任一步失败都不留下半个复习包。

### A6. AI 面板体验

- [ ] 增加“一键生成复习包”快捷指令。
- [ ] 选区存在时提供“解释这里”“检查公式”“整理成导图”“生成自测题”。
- [ ] 显示准备选区、理解内容、生成结构、排版等阶段状态。
- [ ] 鸿蒙平板使用响应式侧栏，不固定在过小的最大尺寸。
- [ ] 保留预览、编辑、逐项选择、追问、取消和应用后继续对话。
- [ ] AI 写入继续要求用户确认，不自动修改笔记。

### A7. A 线测试

- [ ] 多模态附件数量、MIME、尺寸和总大小限制测试。
- [ ] 多模态 Chat Completions 请求契约测试。
- [ ] 合法与非法复习包结构测试。
- [ ] 思维导图深度、节点数和题目数量限制测试。
- [ ] 复习包一次落地、一次撤销测试。
- [ ] 分页空间不足时追加页面测试。
- [ ] 面板选区范围、预览编辑和取消测试。
- [ ] 现有 AI 助手、思维导图和语音文本插入测试保持通过。

## B 线：鸿蒙体验与工程交付

### 文件所有权

B 线负责：

- `FlowMuse-App/ohos/**`
- `FlowMuse-App/lib/features/whiteboard/service_widget/**`
- `FlowMuse-App/lib/features/whiteboard/speech_recognition/**`
- `FlowMuse-App/lib/features/settings/**`
- `FlowMuse-Server/internal/recognition/**`
- `.github/**`
- README、技术设计、验收材料和比赛演示材料

B 线第一阶段不修改 `whiteboard_page.dart` 和 `markdraw_controller.dart`。语音 AI 的最终公共接线在 A 线接口稳定后完成。

### B1. 鸿蒙应用身份和发布信息

- [ ] 将 `com.example.flowmuse` 替换为确认后的正式 Bundle ID。
- [ ] 更新 `vendor: example`、UTD 类型 ID 和外部文档通道类型。
- [ ] 替换 `module description`、`EntryAbility_desc` 等模板文案。
- [ ] 更新版本号、应用图标、启动页和服务卡片名称。
- [ ] 更新 `pubspec.yaml` 的模板 description。
- [ ] 检查签名配置、证书和本地 build profile 未被提交。

验收：

- HAP 包信息不包含 `example` 或模板描述。
- `.markdraw` 和 `.excalidraw` 文件关联仍可打开。
- Bundle ID 与比赛签名证书一致。

### B2. 隐私日志清理

- [ ] 删除服务卡片中的完整 snapshot、标题、noteId 和 Preferences 内容日志。
- [ ] 删除或脱敏原生 HTTP 的完整 URL 和请求信息日志。
- [ ] 将必要日志限制为状态、数量、长度、错误码或哈希前缀。
- [ ] 清理无恢复逻辑、无日志说明的空 catch。
- [ ] 确保 Release 构建不输出诊断日志。
- [ ] 扫描 API Key、token、ownerKey、roomKey 和笔记正文泄漏。

### B3. AI 能力中心与演示配置

- [ ] 将“Beta AI”配置区整理为统一的 AI 能力中心。
- [ ] 分别显示 AI 笔记助手、智能排版和鸿蒙语音的配置状态。
- [ ] 增加一键健康检查和具体错误分类。
- [ ] 支持通过构建参数提供 Base URL 和模型名。
- [ ] API Key 继续存安全存储或由现场安全注入，禁止提交到仓库。
- [ ] 给出模型不支持视觉输入或 Function Calling 时的明确提示。
- [ ] 准备比赛演示前的配置检查清单。

验收：

- 演示者能够在进入白板前确认所有 AI 能力是否可用。
- 用户不需要理解客户端 AI 和服务端智能排版的内部配置差异。

### B4. 服务卡片智能化

- [ ] 增加 `reviewLastWhiteboard` 启动动作。
- [ ] 卡片支持“立即创建”“继续创作”“继续复习”三种状态。
- [ ] 按共享契约同步 `hasStudyPack` 和 `questionCount`。
- [ ] 卡片 Preferences 不保存摘要、问题或答案正文。
- [ ] 完成冷启动、后台恢复和 `onNewWant` 路由。
- [ ] 笔记删除或状态损坏时安全回退资料库。
- [ ] 补齐 Store、Channel、Coordinator 测试。

### B5. 语音 AI 指令

该任务在 A 线 AI 面板接口稳定后实施。

- [ ] 区分“语音输入文字”和“语音询问 AI”两种模式。
- [ ] AI 模式下最终识别结果作为 Agent 指令，不直接创建文本元素。
- [ ] 支持总结当前页、生成导图、生成复习包和检查公式等常用指令。
- [ ] 中间结果继续只显示本地浮层。
- [ ] 取消、页面退出和应用退后台立即释放麦克风。
- [ ] 服务卡片可启动语音速记或语音 AI 入口。

验收：

- AI 语音指令不会被误插入白板。
- 取消识别不发起 AI 请求。
- 权限拒绝、引擎忙和平台不可用不影响白板继续使用。

### B6. 服务端识别测试补齐

为 `FlowMuse-Server/internal/recognition/` 新增测试，至少覆盖：

- [ ] API 只接受 POST。
- [ ] 请求体大小和非法 JSON。
- [ ] MyScript 或 AI 未配置时的错误状态。
- [ ] OpenAI 响应 content 解析。
- [ ] Markdown 代码围栏中的 JSON 清理。
- [ ] 公式和文本类型归一化。
- [ ] 非法 block ID 和非法页面决策过滤。
- [ ] article / in_place 决策回退。
- [ ] 上游超时、取消和非 2xx 错误。
- [ ] 错误响应和日志不泄露密钥或输入正文。

### B7. GitHub 与鸿蒙构建门禁

- [ ] 确认 GitHub Actions 使用项目实际 Flutter 版本。
- [ ] 确认 `flutter pub get` 能解析 vendor path 和 dependency overrides。
- [ ] 保持 Flutter analyze/test 和 Go test/vet 门禁。
- [ ] 增加 Git LFS 完整性检查，防止语音模型对象再次缺失。
- [ ] 评估使用自托管 OHOS runner 构建 HAP；没有可靠 runner 时保留人工 HAP release gate，不伪造 CI 通过。
- [ ] 在 README 和验收材料中记录标准 Flutter 与 `flutter_ohos` 的区别。

### B8. 真机验收和比赛材料

- [ ] 至少使用一台鸿蒙手机和一台鸿蒙平板验证。
- [ ] 验证手写笔压力、PDF、语音、AI 请求、服务卡片和文件导入导出。
- [ ] 记录冷启动、AI 首响应和复习包完成时间。
- [ ] 准备固定 PDF、固定手写内容和固定语音指令。
- [ ] 录制 AI 成功、网络失败降级和一次撤销三个演示视频。
- [ ] 更新 README、需求、前端架构、接口设计、隐私说明和验收材料。

## 并行实施顺序

### Phase 0：共同冻结契约

- [ ] 合并 GitHub Actions 分支。
- [ ] 冻结 `AiVisualAttachment`、`generate_study_pack` 和服务卡片复习状态。
- [ ] 确认正式 Bundle ID 和比赛演示环境。

### Phase 1：完全并行

A 线：

- [ ] A1 多模态上下文模型。
- [ ] A2 选区视觉附件生成。
- [ ] A3 多模态请求。
- [ ] A4 复习包严格解析。

B 线：

- [ ] B1 鸿蒙应用身份。
- [ ] B2 隐私日志清理。
- [ ] B3 AI 能力中心。
- [ ] B6 服务端识别测试。
- [ ] B7 GitHub 与构建门禁。

### Phase 2：功能落地

A 线：

- [ ] A5 复习包白板落地。
- [ ] A6 AI 面板体验。
- [ ] A7 Flutter 测试。

B 线：

- [ ] B4 服务卡片协议和三态 UI。
- [ ] B4 的数据同步先使用冻结接口，不修改 A 线文件。

### Phase 3：合并后接线

- [ ] 先合并 B 线中不依赖 A 的鸿蒙身份、日志、Go 测试和配置提交。
- [ ] 再合并 A 线的多模态和复习包提交。
- [ ] B 线 rebase 最新 `main`。
- [ ] 完成 B5 语音 AI 指令。
- [ ] 完成服务卡片与真实复习包状态的最终接线。
- [ ] 解决文档冲突并统一需求描述。

### Phase 4：联合验收

- [ ] 完整演示 PDF 导入、手写批注、选区 AI、复习包、语音修改和卡片继续复习。
- [ ] 完成 Flutter、Go、HAP 和真机验证。
- [ ] 记录失败项、环境、设备型号和降级范围。
- [ ] 生成比赛演示视频、截图和讲解稿。

## 提交与合并约定

- 每个提交只完成一个独立任务。
- 两条分支不得直接修改对方所有权文件。
- 共享契约变更必须先在计划或接口文档中更新，再由双方确认。
- A 线涉及 `whiteboard_page.dart` 和 Controller 的提交应保持小而可审查。
- B 线鸿蒙原生改动必须与对应 Dart Channel 和测试同提交或连续提交。
- 功能分支合并前必须同步最新 `main` 并解决冲突。
- 不直接在 `main` 上进行大改动。

建议提交粒度：

```text
feat:扩展AI多模态上下文
feat:新增AI一键复习包
feat:实现复习包白板原子落地
feat:完善鸿蒙AI能力中心
fix:清理鸿蒙服务卡片敏感日志
test:补齐服务端智能排版测试
feat:接入鸿蒙语音AI指令
feat:扩展鸿蒙复习服务卡片
```

## 验证方案

### Flutter 静态检查与测试

```powershell
cd FlowMuse-App
flutter pub get
flutter analyze
flutter test
```

优先运行相关测试：

```powershell
flutter test test/features/whiteboard/ai_assistant
flutter test test/features/whiteboard/editor_core
flutter test test/features/whiteboard/speech_recognition
flutter test test/features/whiteboard/service_widget
```

### Go 服务端

```powershell
cd FlowMuse-Server
go test ./...
go vet ./...
```

### 鸿蒙构建

涉及 `ohos/`、Platform Channel、插件注册或 vendor 时：

```powershell
cd FlowMuse-App
flutter build hap
```

HAP 构建通过不代表真机行为通过，必须记录实际设备验收结果。

### 手工验收主流程

1. 在鸿蒙平板导入固定 PDF。
2. 使用手写笔在 PDF 上完成一段批注和一道公式。
3. 框选当前页或手写区域，确认 AI 面板显示正确上下文范围。
4. 执行“一键生成复习包”。
5. 检查摘要、知识点、自测题和思维导图预览。
6. 确认应用，验证布局、分页、保存和协作同步。
7. 执行一次撤销，确认完整复习包同时消失。
8. 使用鸿蒙语音说“把这份复习包再精简一点”，确认作为 AI 指令处理。
9. 返回桌面，确认服务卡片显示“继续复习”和题目数量。
10. 点击卡片回到正确白板。

## 验收指标

| 指标 | 目标 |
|---|---|
| 固定演示流程首轮成功率 | 不低于 95% |
| AI 失败后的场景修改 | 0 |
| 复习包撤销次数 | 1 次完整撤销 |
| 未经选择上传视觉内容 | 0 |
| 日志中的正文或密钥 | 0 |
| 鸿蒙真机连续完整演示 | 10 次无崩溃 |
| Excalidraw 导出兼容 | 新增内容正常导出与恢复 |

性能目标需在固定设备和网络下记录，不以未测量的绝对数字作为完成条件。建议记录：

- 应用冷启动时间。
- 选区截图耗时。
- AI 首响应时间。
- 完整复习包生成时间。
- 复习包落地和撤销耗时。

## 风险与降级

### 1. 比赛网络不稳定

- 提前完成 AI 健康检查。
- 准备稳定热点和备用模型服务。
- 保留手写识别失败时的原始笔迹。
- AI 失败只提示，不修改场景。

### 2. 模型不支持多模态或 Function Calling

- 在能力中心明确显示不兼容原因。
- 视觉请求不可用时允许用户先运行手写识别，再使用文本 Agent。
- 不为兼容单一模型放松客户端结构校验。

### 3. 选区截图过大

- 限制数量、尺寸和总字节数。
- 使用现有渲染能力缩放，不上传原始 PDF 文件。
- 超限时提示用户缩小选区。

### 4. 两条分支产生公共文件冲突

- `whiteboard_page.dart` 和 Controller 始终由 A 线负责。
- B 线先定义事件和通道，最终接线在 A 合并后完成。
- 文档允许顺序合并，不同时重写同一章节。

### 5. 鸿蒙真机行为与构建结果不一致

- 原生代码每个阶段都执行 HAP 全量构建。
- 服务卡片、语音、文件选择和 PDF 必须真机验证。
- MR 中明确区分编译验证与真机验证。

## 完成定义

本计划只有在以下条件全部满足后才可标记完成：

- [ ] 多模态上下文只读取用户明确选择的内容。
- [ ] 一键复习包通过严格结构校验并可编辑预览。
- [ ] 复习包作为普通白板元素一次落地、一次撤销。
- [ ] 鸿蒙语音可以驱动 AI 指令。
- [ ] 服务卡片可以进入最近白板的复习状态。
- [ ] 鸿蒙应用身份和描述不含模板占位信息。
- [ ] 日志不泄露笔记正文、标识和密钥。
- [ ] 服务端 recognition 测试覆盖关键解析和失败路径。
- [ ] `flutter analyze`、`flutter test`、`go test ./...`、`go vet ./...` 通过。
- [ ] 涉及鸿蒙的改动完成 `flutter build hap`。
- [ ] 手机和平板真机主流程通过并有截图或录屏证据。
- [ ] 需求、架构、接口、隐私和验收材料已同步更新。

