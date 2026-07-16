# forbidden_zones.md — H10 分布式协同白板禁飞区

> 本文件对应项目选题 H10「分布式协同白板」的三项 AI 禁飞区。禁飞区代码不得以未经理解的 AI 输出直接交付；责任人须能逐行讲解实现、边界条件和测试证据。

## 验收规则

1. AI 可以用于检索资料、解释已有实现和提出测试思路；提交前必须由责任人理解、改写并验证。
2. 禁飞区改动必须在 PR/MR 或代码审查记录中标明责任人、审查人和测试命令。
3. 无法讲清的禁飞区代码，不以「AI 生成」作为验收通过依据；应先重做或补足人工复核。

## 1. 协同绘制的冲突合并策略

| 项目       | 可核验位置                                                                                                                                                            |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 核心实现   | `FlowMuse-App/lib/features/whiteboard/collaboration/services/scene_reconciler.dart`、`change_accumulator.dart`                                                        |
| 集成入口   | `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`                                                                       |
| 关键语义   | 使用元素 `version`、`versionNonce` 与删除墓碑合并增量，过滤不可同步元素                                                                                               |
| 自动化证据 | `test/features/whiteboard/collaboration/services/change_accumulator_test.dart`、`change_accumulator_integration_test.dart`、`collaboration_repository_sync_test.dart` |
| 人工验收   | 说明同一元素并发更新、更新后删除、相同版本不同 nonce 三种情况的胜出规则                                                                                               |

## 2. AI 排版结果的校验与修正

| 项目               | 可核验位置                                                                             |
| ------------------ | -------------------------------------------------------------------------------------- |
| 请求与结果处理     | `FlowMuse-App/lib/features/whiteboard/ink_recognition/ink_recognition_repository.dart` |
| 场景落地与样式修正 | `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`     |
| 交互入口           | `desktop_toolbar.dart`、`compact_toolbar.dart`、`markdraw_file_handler.dart`           |
| 关键语义           | 排版失败不修改场景；成功结果落为普通白板元素，继续走撤销、保存、导出和协作链路         |
| 人工验收           | 说明识别失败、空结果、跨行文本和用户撤销后的行为，并演示 Markdown/LaTeX 导出           |

## 3. 跨端同步的冲突解决

| 项目                   | 可核验位置                                                                                                          |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------- |
| 实时与远端场景合并     | `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`                     |
| 快照乐观锁与 reconcile | `FlowMuse-App/lib/features/whiteboard/collaboration/services/encrypted_scene_store.dart`                            |
| UI 应用远端场景        | `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`                                                   |
| 关键语义               | 快照以 `baseSceneVersion/baseSceneHash` 乐观锁保存；409 后拉取、reconcile 并重试；协作内容全程 AES-GCM 密文传输     |
| 自动化证据             | `test/features/whiteboard/collaboration/encrypted_scene_store_test.dart`、`collaboration_repository_sync_test.dart` |
| 人工验收               | 两端离线后分别编辑再恢复网络，说明合并结果、失败重试与服务端无法读取白板明文的边界                                  |
