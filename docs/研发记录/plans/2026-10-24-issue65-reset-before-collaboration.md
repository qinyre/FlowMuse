# Issue #65：重置后创建协作房间

## 背景

用户补充复现流程：Web 的有限笔记先通过菜单“重置画布”，再创建协作房间，加入方显示无限画布，并且双方看不到正常协作。基于当前已部署的 F2 版本 `1980830`（分支文档头 `62d55e7`），单独在 `fix/issue65-reset-before-collaboration` 修复，不修改待合并的 PR #81。

## 已确认的代码缺口

`resetCanvas()` 用空 `Scene()` 替换全部元素，但保留 `_layout`。有限纸张仍按本机版式绘制，场景中同步版式所需的页面标记却被删除。房间初始化直接序列化该场景，加入端没有页面标记可恢复。

## 方案与边界

1. 先增加重置后版式往返和真实页面流程回归，验证原版失败；单独检查双向内容收发，不将版式不一致直接当成网络故障。
2. 在菜单与快捷键共用的 `resetCanvas()` 修复：清空内容时保留有限纸张标记，复用现有补齐标记方法。保留标记未知字段、版本、几何、模板与页序；无限画布仍清成空场景。
3. 保持现有重置回调、撤销/重做、文件清理和协作墓碑通路；覆盖重置后建房与协作中重置，检查删除不会复活、不删除远端新内容。
4. 不新增协议、房间/服务端状态、可靠墨迹通路或数据库迁移。不修改 LWW 或快照锁算法。

## 验证

- 空白/网格/古籍及全部模板：重置保留纸张数量、尺寸、模板、方向；Excalidraw 导出/导入与加入房间恢复一致。
- 旧标记扩展字段和版本保留；内容/图片文件清空；一次撤销可恢复，重做仍保留页面标记；无限画布保持无限。
- 实际菜单重置 → 确认创建房间 → 接收端加入 → 两端继续写入/删除/撤销的加密内存链路；另外覆盖加入后的续页、保存与重开。
- 相关测试、静态检查与完整 Flutter 回归。真实公网及安卓/Web 双端仍需实机复测，不以软件测试替代。

## 审查边界

本轮只在编辑器重置入口修复本机版式与可同步页面标记的一致性，不改协作冲突合并、归属、加密、外部导出净化或其他 H10 核心算法。人工责任人/审查人由项目组指定。

## 实施与验证回执

- 生产代码只修改共享 `MarkdrawController.resetCanvas()`：新空场景中保留当前有效页面元素，再复用 `_sceneWithLayoutPages()` 补齐页面。清除内容和附件，同时保留旧页面版本、未知扩展字段及几何，避免把内容重置变成换纸。
- 原版实际菜单 → 确认创建房间 → 加入流程已失败复现：期望 `CanvasLayoutType.paged`，实际 `unbounded`。修复后同一流程通过，还验证房主手写到加入端、加入端笔迹到房主、房主撤销/重做不覆盖加入端笔迹、房间内再次重置后仍可继续同步。
- 新增 17 项：`canvas_reset_test.dart` 13 项（11 模板、扩展字段/附件、无限画布），真实页面书写流程增加 3 种模板重置后入房用例及 1 项菜单/双向同步流程。
- `flutter test --no-pub --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true test/features/whiteboard/editor_core/canvas_reset_test.dart test/features/whiteboard/views/whiteboard_writing_workflow_test.dart test/features/whiteboard/editor_core/scene_dirty_elements_test.dart test/features/whiteboard/editor_core/collaboration_undo_test.dart test/features/whiteboard/smart_layout/snapshot/scene_revision_test.dart --reporter expanded`：60 项通过。
- `flutter test --no-pub --reporter expanded`：1964 项通过，5 项原有跳过；`flutter analyze --no-pub`：无问题；`git diff --check`：通过。
- 脱敏测试输出保留在忽略目录 `FlowMuse-App/build/issue65-reset-*.log`，不提交日志或真实笔记数据。
- 本轮未推送、未发布 Web/后端、未安装安卓包。安卓/Web 公网双端仍需部署后新建房间实机复测；旧房间中已经丢失的版式不会由本次改动自动恢复。
