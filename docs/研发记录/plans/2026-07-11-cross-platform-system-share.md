# 跨端系统分享第一阶段实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立统一分享接口；鸿蒙端分享 PNG、`.markdraw`、`.excalidraw`、协作邀请链接，并作为两种可编辑文件的“用其他应用打开”目标。

**Architecture:** `features/whiteboard/share/` 仅处理 `SharePayload → ShareService → ShareResult` 和外部文件入站。它复用 `MarkdrawController` 导出/解析、`LibraryIndexNotifier` 创建笔记和 `WhiteboardSceneRepository` 保存场景；鸿蒙能力收敛在 MethodChannel 与 ArkTS，Web 使用下载/复制降级。

**Tech Stack:** Flutter、Riverpod、go_router、MethodChannel、HarmonyOS Share Kit/Core File Kit、现有 Markdraw/Excalidraw codec。

## Global Constraints

- 共享 Dart 代码禁止 `Platform.is*`，只使用条件导入。
- 不得记录或分享 `ownerKey`、token、roomKey、明文场景、外部文件 URI/内容；邀请链接须经用户确认。
- 外部打开仅限 `.markdraw`、`.excalidraw`，最大 20 MiB，队列最多 3 项，只能创建新笔记副本。
- 临时分享文件保留 24 小时；系统分享面板打开期间不得删除。
- 不实现隔空传送、自动导入、分享回执或实时场景迁移。
- 改动 OHOS Channel / `ohos/` 后必须运行 `rtk flutter build hap`，不进行真机安装或调试。

---

### Task 1: 分享领域模型与服务契约

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/share/models/share_payload.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/share/models/share_result.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/share_service.dart`
- Create: `FlowMuse-App/test/features/whiteboard/share/models/share_payload_test.dart`

**Interfaces:**

```dart
enum ShareContentType { png, markdraw, excalidraw, hyperlink }
enum ShareResult { completed, dismissed, unavailable, failed }

sealed class SharePayload {
  const SharePayload({required this.title, required this.contentType});
  final String title;
  final ShareContentType contentType;
}

abstract interface class ShareService {
  Future<ShareResult> share(SharePayload payload);
}
```

- [ ] 写失败测试：空文本、空文件名或非绝对文件路径抛出 `ArgumentError`；邀请链接只构造成 `ShareTextPayload`。
- [ ] 运行 `cd FlowMuse-App && rtk flutter test test/features/whiteboard/share/models/share_payload_test.dart`，确认失败。
- [ ] 实现 `ShareTextPayload`、`ShareFilePayload` 和上述结果类型；provider 通过条件导入创建服务，不持有 `BuildContext`。
- [ ] 运行 `rtk flutter test test/features/whiteboard/share && rtk flutter analyze lib/features/whiteboard/share`，确认通过。
- [ ] 提交：`git commit -m "feat:定义跨端系统分享领域契约"`。

### Task 2: 导出分享临时文件

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/share_artifact_store.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/share_artifact_store_io.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/share_artifact_store_web.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/share_export_coordinator.dart`
- Create: `FlowMuse-App/test/features/whiteboard/share/services/share_export_coordinator_test.dart`

**Interfaces:**

```dart
Future<ShareFilePayload> preparePng(MarkdrawController controller);
Future<ShareFilePayload> prepareDocument(
  MarkdrawController controller,
  DocumentFormat format,
);
Future<void> cleanupExpired({required DateTime now});
```

- [ ] 写失败测试：PNG 用 `selectedOnly: false`；`.markdraw`/`.excalidraw` 后缀和内容类型正确；仅清理超过 24 小时的文件。
- [ ] 运行相关测试，确认 coordinator/store 尚不存在。
- [ ] 实现：PNG 调用既有 `exportPng(selectedOnly: false)`；文档调用既有 `serializeScene(format: ...)`；非 Web 写入应用临时目录的 `flowmuse-share/`，Web 创建下载载荷。标题清理非法文件名字符，禁止从内容推断名称。
- [ ] 每次导出前和启动时执行 `cleanupExpired`；不得在 `share()` 返回前删除刚生成文件。
- [ ] 运行 `rtk flutter test test/features/whiteboard/share` 与 `rtk flutter test test/features/whiteboard/editor_core/markdraw_file_handler_pdf_test.dart`，确认通过。
- [ ] 提交：`git commit -m "feat:生成并清理系统分享文件"`。

### Task 3: 白板和协作邀请入口

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/share/widgets/share_menu.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`（只增加 `onShare` 回调）
- Create: `FlowMuse-App/test/features/whiteboard/share/widgets/share_menu_test.dart`

- [ ] 写失败 Widget 测试：取消邀请确认时 `ShareService` 未被调用；选 PNG 时请求完整画布；`dismissed` 不显示失败 SnackBar。
- [ ] 运行 `rtk flutter test test/features/whiteboard/share/widgets/share_menu_test.dart`，确认失败。
- [ ] 保留现有 `onExportPng`/`onExportSvg` 保存行为；新增“分享”菜单，提供 PNG、`.markdraw`、`.excalidraw` 与邀请链接。
- [ ] 链接优先使用 `WhiteboardViewState.roomLink`，否则用 `roomValue`；确认文本固定为“持有该链接的人可以加入当前协作房间”。不得把链接写入 SnackBar、日志或异常。
- [ ] `unavailable` 对文件提示已导出、对链接给复制动作；`failed` 只显示通用失败文案。
- [ ] 运行分享 Widget 与 `whiteboard_canvas_widget_test.dart` 回归，确认通过；提交 `feat:添加白板和协作系统分享入口`。

### Task 4: 鸿蒙 Share Kit 发送实现

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/share_service_ohos.dart`
- Create: `FlowMuse-App/ohos/entry/src/main/ets/channels/SystemShareChannel.ets`
- Modify: `FlowMuse-App/ohos/entry/src/main/ets/entryability/EntryAbility.ets`
- Create: `FlowMuse-App/test/features/whiteboard/share/services/share_service_ohos_test.dart`

**Channel:** `flow_muse/system_share`, method `share`, parameters `kind`, `title`, `text` or `filePath`, `fileName`.

- [ ] 写失败 MethodChannel 测试：PNG 使用 `kind: png` 和文件参数；`MissingPluginException` 映射 `unavailable`；`PlatformException` 映射 `failed`。
- [ ] 运行测试确认失败。
- [ ] ArkTS 使用 Share Kit 的 `SharedData`：PNG 使用图片 UTD、两种场景使用精确文件 UTD、链接使用 `HYPERLINK`；只回传 `completed` 或 `dismissed`，不回传目标应用、URI 或载荷。
- [ ] 在 `EntryAbility` 按现有 FilePicker/FileSave/Http Channel 方式注册。Dart 捕获两类 Flutter 异常，不输出敏感数据。
- [ ] 运行 `rtk flutter test test/features/whiteboard/share/services/share_service_ohos_test.dart && rtk flutter analyze lib/features/whiteboard/share && rtk flutter build hap`，确认全部通过。
- [ ] 提交：`git commit -m "feat:接入鸿蒙系统分享面板"`。

### Task 5: 鸿蒙外部文件接收队列

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/share/models/external_document_request.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/external_document_ingress.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/external_document_channel_ohos.dart`
- Create: `FlowMuse-App/ohos/entry/src/main/ets/channels/ExternalDocumentChannel.ets`
- Modify: `FlowMuse-App/ohos/entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `FlowMuse-App/ohos/entry/src/main/module.json5`
- Create: `FlowMuse-App/test/features/whiteboard/share/services/external_document_ingress_test.dart`

**Interfaces:**

```dart
class ExternalDocumentRequest {
  const ExternalDocumentRequest({required this.fileName, required this.bytes});
  final String fileName;
  final Uint8List bytes;
}

bool enqueue(ExternalDocumentRequest request); // 最大三项，超过 20 MiB 返回 false
Future<ExternalDocumentRequest?> takeNext();
```

- [ ] 写失败测试：冷启动前 FIFO 缓存三项；第四项被拒绝且前三项保留；20 MiB 以上被拒绝。
- [ ] 运行 ingress 测试确认失败。
- [ ] `module.json5` 仅注册 `.markdraw`、`.excalidraw` 打开 Skill，绝不注册 `.json` 或宽泛 MIME。`EntryAbility.onCreate` 与 `onNewWant` 都交给外部文件 Channel。
- [ ] ArkTS 只读取系统授予 URI，在本端先检查 20 MiB，再将文件名和 `Uint8Array` 通过 `flow_muse/external_document` 传到 Dart；不保存 URI，不写内容日志。
- [ ] Dart 入站服务 FIFO 缓冲最多三项，等待 Flutter 路由就绪；应用退出即丢弃。
- [ ] 运行 `rtk flutter test test/features/whiteboard/share/services/external_document_ingress_test.dart && rtk flutter analyze lib/features/whiteboard/share && rtk flutter build hap`，确认通过；提交 `feat:接收鸿蒙外部绘图文件请求`。

### Task 6: 解析外部文件并新建笔记副本

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/imported_document_coordinator.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/share/widgets/import_external_document_dialog.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Modify: `FlowMuse-App/lib/app/app_router.dart`
- Create: `FlowMuse-App/test/features/whiteboard/share/services/imported_document_coordinator_test.dart`
- Create: `FlowMuse-App/test/features/whiteboard/share/widgets/import_external_document_dialog_test.dart`

**Interfaces:**

```dart
Future<ImportedDocumentPreview> preview(ExternalDocumentRequest request);
Future<String> importAsNewNote(ImportedDocumentPreview preview);
```

- [ ] 写失败测试：`.markdraw` 导入调用 `LibraryIndexNotifier.createNote()` 和 `WhiteboardSceneRepository.saveScene()`；普通 JSON 不创建笔记；确认 UI 仅有“创建新笔记并打开”和“取消”。
- [ ] 运行测试确认失败。
- [ ] 校验扩展名、大小、UTF-8，调用现有 `DocumentService`/`DocumentParser`/`ExcalidrawJsonCodec` 得到解析结果与 warning。预览只显示文件名、格式、大小和 warning。
- [ ] 确认后创建 note，把解析内容序列化成 Excalidraw 并保存，生成封面后导航 `AppRoutes.whiteboardPath(noteId: noteId)`。解析失败、取消或 warning 不接受时不得创建 note。
- [ ] 在 `WhiteboardPage` 消费 ingress；协作编辑中收到文件仍显示确认，确认后创建新本地笔记，不停止或覆写协作场景。
- [ ] 运行 `rtk flutter test test/features/whiteboard/share test/features/whiteboard/whiteboard_canvas_widget_test.dart test/features/whiteboard/collaboration/collaboration_room_test.dart`，确认通过；提交 `feat:将外部绘图文件导入为本地笔记副本`。

### Task 7: Android、iOS、macOS、Windows、Web 原生分享与文档同步

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/share_service_web.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/share/services/share_service_native.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/share/services/share_service.dart`
- Modify: `FlowMuse-App/pubspec.yaml`
- Create: `FlowMuse-App/test/features/whiteboard/share/services/share_service_web_test.dart`
- Modify: `docs/项目说明/项目需求.md`
- Modify: `.agent/architecture.md`
- Modify: `.agent/conventions.md`

- [ ] 写失败测试：`ShareFilePayload` 被映射为 `XFile(path, mimeType, name)`；`ShareTextPayload` 被映射为 `ShareParams(text: ..., title: ...)`；Web 无 Web Share API 时复制链接或下载文件。
- [ ] 运行 Web 服务测试确认失败。
- [ ] 在 `pubspec.yaml` 添加 `share_plus: ^13.2.0`，运行 `rtk flutter pub get`。创建非 OHOS 条件导入实现：用 `SharePlus.instance.share(ShareParams(...))` 发送文本或 `XFile` 文件，并将插件状态映射为领域 `ShareResult`。该版本要求 Flutter 3.38.1+，当前 Flutter 3.41.10 满足要求。
- [ ] Web 优先使用同一实现；若 Web Share API 不可用，文件下载、链接复制。Linux 文件分享不可用时保持相同降级。OHOS 必须继续选择 `share_service_ohos.dart`，绝不导入 `share_plus` 实现。
- [ ] 文档记录“鸿蒙 Share Kit + 非 OHOS share_plus”的条件导入边界、外部文件打开安全规则和各端验收矩阵。
- [ ] 运行 `cd FlowMuse-App && rtk flutter analyze && rtk flutter test && rtk flutter build hap`，确认通过；运行 `rtk git diff --check`。
- [ ] 提交：`git commit -m "docs:记录跨端系统分享与鸿蒙文件打开约束"`。

## 执行后验收

1. 鸿蒙四类发送内容均能拉起系统面板；取消不改变白板或协作状态。
2. 文件管理器及其他应用可将 `.markdraw` / `.excalidraw` 交给 FlowMuse；冷/热启动均显示“创建新笔记副本”确认。
3. 损坏文件、普通 JSON、超 20 MiB 文件、队列溢出和协作中收到外部文件均不崩溃、不替换当前场景。
4. 日志、测试输出和截图均不包含 token、ownerKey、roomKey、文件内容或外部 URI。
