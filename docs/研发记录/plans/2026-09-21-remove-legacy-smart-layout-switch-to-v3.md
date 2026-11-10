# 移除旧版智能排版并切换 V3 入口

## Context

白板智能排版存在新旧两套并行实现：旧版（v2 模板卡片制，editor_core 内）与 V3（`features/whiteboard/smart_layout/` 全链路，灰度门禁 + 右下角悬浮球入口）。用户决定旧版彻底下线：工具栏最右侧原智能排版按钮改为触发 V3，旧实现全部删除。

## 需求

1. 点击工具栏最右侧原"智能排版"按钮 → 打开 V3 会话面板（原 `_openSmartLayoutV3Panel`）。
2. 移除右下角 V3 悬浮球入口（入口合并到工具栏按钮）。
3. AI 助手 `AiAgentTool.smartLayout` 动作改接 V3 面板。
4. 删除旧版全部实现：客户端旧流程 + 服务端 5 条旧端点。
5. 与其他功能（含 V3）共享的代码必须保留：
   - `smart_layout_document.dart`（Scene.smartLayout、tool_result、V3 patch/document 依赖）
   - `smart_layout_exporter.dart` + 菜单导出项（导出 scene.smartLayout 文档，V3 也产出该文档）
   - `/api/ink/recognize`（手写识别）与 InkBounds 等共享类型
   - V3 全目录

## 实现方案

### 客户端删除（lib/）

- 删除 `editor_core/src/core/smart_layout/` 中：content、ink_clusterer、move_builder、plan、template_engine、vision_matcher、barrel（保留 document、exporter；barrel 收缩为这两个或直接删 barrel 改直接引用）。
- 删除 `views/smart_layout_dialogs.dart`、`views/smart_layout_template_sheet.dart`。
- 删除 `rendering/interactive/smart_layout_ghost_painter.dart`。
- `markdraw_controller.dart`：摘除旧流程全部方法（prepare/buildPlan/applyPlan/draft 态/vision 识别/transcribe/ghost/文本物化等，约 3360-5160 行大段），保留 `exportSmartLayout`/`canExportSmartLayout`。
- `editor_canvas.dart`：摘 ghost overlay。
- `whiteboard_page.dart`：摘旧流程状态与方法（`_startSmartLayoutFlow`/`_runSmartLayoutPage`/bar action/progress/ghost 刷新），按钮改 `_openSmartLayoutV3Panel`，删 FAB，AI agent 动作改接 V3。
- `ink_recognition_repository.dart`：删 `visionSmartLayout`/`transcribeCrop` 及独占模型。
- `markdraw_editor.dart`：确认 `onVisionSmartLayout` 等旧回调随流程摘除；`onSmartLayoutPressed` 保留（新语义=V3）。

### 服务端删除（FlowMuse-Server/）

- 删 `internal/recognition/smart_layout.go`、`vision_layout.go` 及对应 `_test.go`。
- `api.go`：删 5 条旧路由 + 5 个 handler + 旧校验函数 + layouter/visionLayouter 字段与注入；保留 recognize 与 v3。
- `types.go`：删 SmartLayout*/Vision/Transcribe 类型，保留 InkBounds 与 recognize 类型。
- `cmd/flowmuse-collab-server/main.go`：摘 smartLayouter 构造与注入。
- 确认 `internal/layoutrecognitionv3` 包与 v3 文件无依赖牵连。

### 测试

- 删 `test/features/whiteboard/editor_core/smart_layout_*_test.dart`（旧模块测试）。
- `ink_recognition_repository_test.dart`：删 vision/transcribe 用例。
- 检查 ai_assistant、creator_stamping 等测试的 SmartLayout 引用，保留共享语义、修编译。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`（入口重接 + 旧流程摘除）
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（旧流程手术，7439 行）
- `FlowMuse-Server/internal/recognition/api.go`、`types.go`

## 验证方案

1. `cd FlowMuse-App && flutter analyze` 无新增 error。
2. `flutter test` 全绿。
3. `cd FlowMuse-Server && go build ./... && go test ./... && go vet ./...`。
4. 手动走查：工具栏按钮 → V3 面板打开；导出入口仍可用；手写识别不受影响。

## 实施步骤

1. whiteboard_page 入口重接（按钮/FAB/AI 动作）。
2. 删客户端旧文件 → analyze 驱动修引用（controller/canvas/barrel/repository）。
3. 删旧测试、修保留测试。
4. 服务端删除 + 构建测试。
5. 全量验证 + 文档同步（接口设计.md 端点清单）。

## 实施结果（2026-09-21 完成）

- 客户端：旧流程全部摘除（模板引擎/聚类/移动构建/视觉匹配/幽灵画家/对话框/模板卡/草稿态/视觉管线方法与状态）；`SmartLayoutPlacement`/`SmartLayoutUtils` 抢救至 `smart_layout_placement.dart`（mindmap 重排与页面归属合并仍依赖）；`smart_layout_document.dart` 中无引用的旧 DTO（InkBlockRequest/RecognizedBlock/Vision*/Transcribe*）一并删除，仅保留 Document/Block 导出模型。
- 入口：工具栏最右侧按钮与 AI 助手 smartLayout 动作均直接打开 V3 会话面板；右下角 V3 悬浮入口已移除。
- 服务端：删 `smart_layout.go`/`vision_layout.go` 及测试、5 条旧路由/handler/校验、types.go 旧类型、`NewHTTPAPI` 可变 layouter 参数与 `WithVisionLayouter`；config 删 `AIBaseURL`/`AIAPIKey`/`AIModel`（`AITimeout` 保留作识别请求超时）；`.env.example` 与部署指南同步为 `FLOWMUSE_LAYOUT_V3_*`。
- 测试调整：删 v2 专属测试 13 个；`wiring_v3_entry_test` 删 R8 并发隔离与观测控制器；`v2_client_isolation_matrix_test` 退役"v2 原位保留"检查（保留公开面零 v2 符号/零 v2 import/端点纯净三项）；服务端删 `TestV2V3NoCrosstalk` 与路由隔离矩阵测试（前提失效），`jsonString` 辅助移入 `myscript_test.go`。
- 文档：接口设计.md 删 v2 小节并改写 v3 引言；前端架构.md 智能排版段落改写为 V3 链路。

验证：`flutter analyze` 零 issue；`flutter test` 全绿（1631 通过）；`go build/vet/test ./...` 全绿。

## 短正文使用本地结构（2026-11-10）

- Web 和 Android 发布源为 `a3dce6169eb66c314fe9b4096bc99685d6a883e7`，包含短正文排版快路径及此前的联网搜索会话修复。两端使用正式 API、分享地址、湿墨分层和实时墨迹 V2，构建标识为 `a3dce616`。
- 17:24（北京时间）发布 `web-smart-layout-fast-20261110-a3dce616`。Web Release 使用根路径、本地 Web 资源、启动字体优化及预压缩。主脚本 SHA-256 为 `eeb2bd82a81ba388c7ce3a23977b7541f613bb90fcc7d6a5b4359cd53ed607d9`，27 项公网检查通过，后端未重启。回退版本为 `web-auto-search-20261110-f73bacee`。Chrome 已进入编辑器，完整浏览器冒烟因创建笔记和自动选区阶段的脚本异常未通过。
- 17:26 覆盖安装 Android arm64 Release，安装包与平板 APK 的 SHA-256 均为 `c1c0a0c83688736b624416fc431da2e810682c4382110ed1b7391cdb0da7d770`。原安装记录保留，应用正常启动。
- 智能排版相关测试 755 项通过、4 项跳过，静态分析通过。回归验证短手写只发一次初读请求。未测真实手写的端到端耗时。
