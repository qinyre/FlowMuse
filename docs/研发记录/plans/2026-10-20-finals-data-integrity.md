# 决赛前协作与保存正确性修复

## Context

起点：`main` / `214d921`；分支：`fix/finals-collaboration-data-integrity`。
用户要求先解决审查中的 1–5，并保持小步提交。现有未追踪的软著准备文档不属于本任务。

## 需求与范围

1. 协作期间撤销、重做保留远端新增、修改和删除，包括落笔期间收到的更新。
2. 本地与 WebDAV 备份包含独立场景文件的实际内容；缺失引用不得静默覆盖现有资料。
3. 快照正在保存时退出协作可完成，上传成功和失败都能释放等待，保持原有错误通道上报。
4. 强制全量同步能够补回已标为发送、但对端没有收到的元素。
5. 本地自动保存失败保留待保存状态、可重试，保存状态正确显示。

## 实现方案与关键文件

- 保留 `HistoryManager` 的 Scene 快照栈，记录远端胜出元素，撤销/重做时按现有 version/nonce 规则合入；本地撤销后的版本规范化不记为远端编辑。
- `LocalBackupRepository` 导出时展开 `SceneContentStore` 引用，使用既有 JSON v2 字段；导入先验证场景完整性，沿用 SQLite 事务回滚。
- `CollaborationRepository` 排空当前保存后再失效会话；强制同步独立于普通增量去重，保持 AES-GCM 与 SCENE_INIT/UPDATE 兼容。
- `WhiteboardPage` 保留失败草稿并串行保存，接通保存中/失败/重试状态，退出等待保存结果。
- 测试落在对应的 editor_core、settings、collaboration、views 测试目录；不修改鸿蒙原生或 vendor 代码，不新增依赖，不改变数据库 schema。

## 验证与提交

每项独立提交代码、对应测试及必要行为说明；提交前运行该项回归。最终运行全量 `flutter test`、`flutter analyze`，并检查 `git diff --check`。
协作协议不新增字段或事件；强制同步沿用现有消息类型，并运行 Go 测试与 vet 核对服务端兼容性。
真机触控、物理笔延迟、现场弱网和生产服务不在本机自动化证据范围内。

## 审查记录

实现与自动化验证：Codex。责任人、人工审查人：由项目负责人指定，未冒充完成人工复核。
本任务触及 `.agent/forbidden_zones.md` 所述跨端同步区域；人工验收需检查两端撤销、离线编辑恢复及保存失败后的退出行为。

## 结果

实施时按提交追加测试命令、结果和边界。

### 1. 协作撤销

- 保留快照栈，远端胜出元素在撤销/重做时懒合并；本地版本规范化明确不记录成远端操作。
- 移除已修复用例的 skip，修正工作流中“撤销应同时清空远端笔迹”的旧断言，并检查远端笔迹不被广播删除。
- `flutter test --no-pub test/features/whiteboard/editor_core/collaboration_undo_test.dart test/features/whiteboard/editor_core/ui/markdraw_controller_test.dart test/features/whiteboard/views/whiteboard_writing_workflow_test.dart test/features/whiteboard/smart_layout/recognition/apply_undo_reopen_test.dart`：25 项通过。
- 追加重做广播校验：先更新本地历史基线，再触发版本规范化回调，保证重做版本严格高于删除版本，避免同版本随机 nonce 导致重做被远端丢弃；该真实页面协作测试通过。

### 2. 完整备份

- 本地/WebDAV 共用的 JSON v2 导出展开实际正文；恢复在清库前验证引用，大场景采用独立暂存文件，不覆盖现有正文文件。
- `flutter test --no-pub test/features/settings test/features/whiteboard/whiteboard_scene_repository_test.dart`：8 项通过。覆盖新设备恢复、缺失文件拒绝、事务失败保留原库与文件、旧 v2 本机引用兼容。
- 修改文件的 `flutter analyze --no-pub ...` 无问题；备份 v2、数据库 schema 和 WebDAV 上传协议不变。

### 3. 保存中退出协作

- 删除提前使会话失效的操作；由既有 reset 在快照等待结束后统一递增会话代次，保存任务的 finally 可以正常清理标记。
- `flutter test --no-pub test/features/whiteboard/collaboration/collaboration_snapshot_retry_test.dart test/features/whiteboard/collaboration/collaboration_join_cancel_test.dart`：5 项通过，覆盖上传成功/失败退出及现有退避、旧房隔离。
