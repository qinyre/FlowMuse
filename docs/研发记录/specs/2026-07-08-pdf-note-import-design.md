# PDF 笔记导入功能设计

- **日期**: 2026-07-08
- **状态**: 已确认（待实现）
- **相关文档**: `2026-07-08-cross-platform-pdf-import-research.md`（PDF 渲染跨平台方案，已实现）

## 1. 背景与动机

应用已有「PDF 渲染 + 插入白板」的完整底层链路（`PdfImporter` → `MarkdrawController.importPdfPages`，HarmonyOS 走原生 `PdfImportChannel` + 华为 PDF Kit），但该链路的**入口只在白板编辑器内部**，作用是把 PDF 每页渲染成图片塞进**当前已打开的笔记画布**。

它没有解决用户真正的需求：**让导入的 PDF 成为一个独立的笔记文件**，出现在资料库列表里，能被单独打开。

笔记数据模型早已为此预留了基础：
- `enum LibraryFilter { all, notes, pdf }` 的 `pdf` 值已存在。
- 资料库 UI（过滤芯片、`NoteCard` 的 PDF 封面、列表的 PDF 图标）已就绪。
- 但 `LibraryRepository.createNote()` 在所有实现中**硬编码 `kind: LibraryFilter.notes`**，从不产生 `pdf` 类型笔记。

本设计补齐这条缺失的链路：在资料库首页新增「导入 PDF」入口，导入后在资料库生成一条 `kind: pdf` 的笔记，并使该笔记的白板**被限制在 PDF 内容区域内**——用户只能在 PDF 渲染区浏览和编辑，无法滑动到 PDF 外的空白画布。

## 2. 目标与非目标

### 目标

1. 资料库首页新增「导入 PDF」入口，导入后生成 `kind: pdf` 的笔记。
2. 打开 PDF 笔记时，PDF 每页渲染成图片竖排堆叠并居中显示（复用现有渲染链路）。
3. PDF 笔记的白板画布**被限制在 PDF 内容区域内**：平移/缩放不超出该区域，新元素创建不越界。
4. PDF 笔记与普通笔记共享同一套持久化、保存、撤销机制。
5. 渲染失败时自动回滚（删除空笔记），不残留垃圾数据。

### 非目标（第一版不做）

- 元素拖动/移动的区域 clamp（第一版只做创建校验 + 平移/缩放 clamp）。
- 重复导入检测、PDF 文件大小/页数上限（复用现有 `PdfRenderOptions.maxPages`，不新增限制）。
- 专用 PDF 只读查看页（已确认走「白板 + 可批注」路线）。
- PDF 原始字节单独存储（仍以 base64 内嵌进 scene JSON）。
- 独立的二进制 blob 存储层（现有 base64 内嵌方式保留，不做性能优化重构）。

## 3. 用户流程

```
资料库首页
  → 点「导入 PDF」卡片
  → FilePicker 选 PDF 文件（仅 .pdf，withData: true）
  → 创建 kind=pdf 的 NoteItem，拿到 noteId
  → PDF bytes 存入 pendingPdfImportProvider
  → 跳转 whiteboardPath(noteId)
  → WhiteboardPage._openNote:
      a. ensureNote(noteId)
      b. 读 NoteItem.kind == pdf → 启用画布约束模式
      c. loadScene（此时为空场景）
      d. 消费 pendingPdfImportProvider 的 bytes，触发 PdfImporter.importPdf
      e. 每页 → ImageElement 竖排堆叠（复用 importPdfPages）
      f. 计算 PDF 页元素并集 bounds → 设为 contentBounds
      g. fitToBounds 让用户一进来就看到完整 PDF
  → 用户在受限画布内批注，onSceneChanged → 自动 saveScene
```

## 4. 架构总览

### 设计原则

- **不新建任何存储结构**，全部复用现有双层存储：
  - 笔记索引层：`flowmuse.library.index.v2`（`LibraryRepository`）
  - 白板内容层：`note.excalidraw.scene.<noteId>`（`WhiteboardSceneRepository`）
- **PDF 笔记与普通笔记的本质差异只有两点**：
  1. `NoteItem.kind == LibraryFilter.pdf`（已有枚举值，序列化已兼容）。
  2. 白板实例带 `contentBounds`（新增的可选配置）。
- 所有渲染、序列化、保存、撤销逻辑**原样复用**。

### 组件关系

```
资料库首页 (library_home_page)
   ├── ImportPdfCard（新增）
   │     → FilePicker → createNote(kind: pdf)
   │     → pendingPdfImportProvider 暂存 bytes
   │     → 跳转 whiteboardPath(noteId)
   │
   └── WhiteboardPage
         ├── _openNote
         │     ├── ensureNote
         │     ├── 读 kind == pdf → 约束模式
         │     ├── loadScene
         │     ├── 消费 pending bytes → PdfImporter.importPdf
         │     └── 设 contentBounds + fitToBounds
         │
         └── MarkdrawEditor(config: contentBounds)（新增字段）
               └── MarkdrawController
                     ├── ViewportState.clampToBounds（新增）
                     └── 元素创建区域校验（新增）
```

## 5. 详细设计

### 5.1 数据模型与存储变更

#### NoteItem / LibraryFilter（无改动）

- `LibraryFilter.pdf` 已存在。
- `NoteItem` 的 `_noteToJson` / `_noteFromJson` 用 `LibraryFilter.values.byName(kind)` 序列化，已兼容 `pdf`，**无需迁移**。
- `NoteItem.subtitle` 字段已存在，用于存 PDF 副标题（如「12 页 · filename.pdf」）。

#### LibraryRepository：`createNote` 加 `kind` 参数

当前 `createNote` 硬编码 `kind: LibraryFilter.notes`。改为：

```dart
Future<NoteItem> createNote({
  String? notebookId,
  List<String> tagIds = const [],
  LibraryFilter kind = LibraryFilter.notes,   // 新增，默认值保证向后兼容
  String? title,
  String? subtitle,
}) async { ... }
```

- 默认值 `LibraryFilter.notes`：普通笔记调用方**无需改动**，行为完全不变。
- PDF 笔记调用方传 `kind: pdf`。
- 两个实现（`SharedPreferencesLibraryRepository`、`InMemoryLibraryRepository`）同步改。
- `LibraryIndexNotifier` 同步加透传（透传 `kind` / `title` / `subtitle` 可选参数）。

#### 白板内容存储（零改动）

- PDF 笔记的白板内容仍存 `note.excalidraw.scene.<noteId>`。
- PDF 页 PNG 字节仍以 base64 内嵌进 scene JSON 的 `files` 字段（现有 `filesToJson` / `parseFilesJson`）。
- `WhiteboardSceneRepository`、`MarkdrawController.importPdfPages`、`Scene` / `ImageElement` / `ImageFile` **全部原样复用**。

### 5.2 画布边界约束机制（核心技术点）

#### 边界定义：锁定为初始 PDF 区域

PDF 导入完成后，所有 PDF 页 ImageElement 的**并集 bounds** 即为内容边界。关键决策：**边界锁定为初始 PDF 页并集，不随后续批注动态变化**。

- 导入 PDF 时，记录 PDF 页元素 id 集合（或导入完成后立即缓存 `sceneBounds()`）。
- 后续批注（用户新画的元素）**不计入边界**，边界保持不变。
- 这保证用户「只能在 PDF 渲染后的区域」活动，区域稳定可预期。

#### 配置入口：`MarkdrawEditorConfig.contentBounds`

`MarkdrawEditorConfig`（`lib/features/whiteboard/editor_core/src/ui/markdraw_editor_config.dart`）新增可选字段：

```dart
final Bounds? contentBounds;   // null = 无限画布（普通笔记，默认）；非 null = 受限画布（PDF 笔记）
```

- 普通笔记传 `null`，渲染层与控制器行为**完全不变**。
- PDF 笔记传入 PDF 页并集 bounds。
- `WhiteboardPage` 根据 `NoteItem.kind` 决定是否传入此值。

#### 平移 clamp：`ViewportState.clampToBounds`

在 `lib/features/whiteboard/editor_core/src/rendering/viewport_state.dart` 新增纯函数（不污染现有 `pan()`）：

```dart
ViewportState clampToBounds(Bounds sceneBounds, Size canvasSize) {
  // 保证 visibleRect(canvasSize) 不超出 sceneBounds
  // offset.dx clamp 到 [sceneBounds.left, sceneBounds.right - canvasSize.width / zoom]
  // offset.dy clamp 到 [sceneBounds.top, sceneBounds.bottom - canvasSize.height / zoom]
  // 允许少量 padding（如 16px）避免内容紧贴边缘
}
```

**注入点**：统一在 controller 的视口变更后调用 `clampViewport`。覆盖三处平移入口：
- `HandTool`（`editor/tools/hand_tool.dart:30`）
- `onScaleUpdate`（`ui/markdraw_controller.dart:1261`）
- `panViewport`（`ui/markdraw_controller.dart:1726`）

以及缩放后（`zoomAt` 后视口可能飘出边界，同样过 `clampViewport` 修正 offset）。

`contentBounds` 为 `null` 时，`clampViewport` 直接返回原 viewport（no-op），保证普通笔记零影响。

#### 缩放 clamp

- zoom 值已有 min/max clamp（复用 `_config.minZoom` / `maxZoom`），不新增。
- 缩放后视口可能飘出边界 → 同样过 `clampViewport` 修正 offset。
- 第一版**不设**「PDF 宽度铺满视口」的最小 zoom 下限，保持简单（后续可加）。

#### 元素创建区域校验

防止用户在 PDF 区域外新建元素。在工具落点处（`MarkdrawController.onPointerDown` 及各创建工具的 `applyResult` 前）加判断：

- 落点（场景坐标）是否在 `contentBounds.containsPoint` 内。
- 不在则忽略本次创建（不产生元素，不进 undo 历史）。
- 仅作用于**创建**；**第一版不对元素移动/拖动做 clamp**（已在「非目标」中声明）。

### 5.3 UI 入口与导航

#### 资料库首页入口

`lib/features/library/views/library_home_page.dart` 新增「导入 PDF」入口，与现有 `CreateNoteCard`（`lib/features/library/widgets/create_note_card.dart`）并列。

- 新增 `ImportPdfCard` widget（图标 `Icons.picture_as_pdf`，文案「导入 PDF」）。
- 点击触发导入编排（见下）。
- 位置：资料库首页的「新建」区域，紧邻 `CreateNoteCard`。

#### 导入编排

新增编排逻辑（位置：`LibraryHomeViewModel` 新增方法，或独立的 `PdfNoteImportService`）。参考现有 `_openExternalSceneAsLocalNote`（`whiteboard_page.dart:463-483`）的 createNote + saveScene + 跳转模式：

```
1. 选择 PDF 文件（多端分发，复用现有 MarkdrawFileHandler 的平台分支）：
   - OHOS：走原生 channel pickFilesViaOhosChannel（FilePickerChannel.ets）
   - 其它平台：FilePicker.pickFiles(type: custom, allowedExtensions: ['pdf'], withData: true)
   → 用户取消 → 静默返回，不创建笔记
2. 拿到 bytes + name
3. viewModel.createNote(kind: pdf, title: 去扩展名的文件名, subtitle: filename)
   → 拿到 noteId（此时 scene 为空；页数 N 此刻未知，渲染后回填）
4. PDF bytes 存入 pendingPdfImportProvider（Riverpod）
5. 跳转 whiteboardPath(noteId)
```

#### PDF bytes 的传递：Riverpod provider

新增 `pendingPdfImportProvider`（Riverpod `StateProvider<PdfImportPayload?>` 或类似），payload 含 `bytes` + `name`。

- `WhiteboardPage._openNote` 检测到 `pendingPdfImportProvider` 有值 → 消费它 → 渲染完成后清除（`provider.state = null`）。
- 优势：不污染路由参数，能承载大文件，消费即清除避免残留。

#### WhiteboardPage 消费 pending 导入

`_openNote`（`whiteboard_page.dart:103-141`）扩展，在加载空场景后：

```
a. ensureNote(noteId)
b. 读当前 NoteItem 的 kind
c. 若 kind == pdf：
     - 标记约束模式（contentBounds 待定，渲染后设置）
     - 检查 pendingPdfImportProvider 是否有值
       - 有：消费 bytes → PdfImporter.importPdf → importPdfPages
            → 计算 PDF 页并集 bounds → 写入 controller 的 contentBounds
            → fitToBounds 居中展示
            → 回填 subtitle（如 '<N页> · <filename>'）到 NoteItem 并 touchNote
            → 清除 pending provider
       - 渲染失败/抛异常 → catch → 删除笔记 → 提示 → 返回资料库
       - 无（用户直接打开已有 PDF 笔记）：loadScene 加载已存内容
            → 从 scene 的 PDF 页元素计算 contentBounds
d. 若 kind != pdf：原逻辑不变
```

#### 进度反馈

- 渲染期间显示简单 loading 遮罩（「正在导入 PDF…」）。
- 失败时弹 `SnackBar` / 对话框提示「导入失败」，并触发回退。

### 5.4 错误处理与边界情况

| 场景 | 处理 |
|---|---|
| 用户取消文件选择 | 静默返回，不创建笔记 |
| PDF 损坏/无法解析 | 渲染器抛异常 → catch → 删除刚创建的空 PDF 笔记 → 弹「导入失败」提示 → 返回资料库 |
| PDF 页数为 0 | 视为无效 PDF，同上处理 |
| PDF 部分页渲染失败 | 已成功页保留，继续导入；记录日志；可选提示「部分页面导入失败」 |
| 渲染期间用户退出 | pending provider 已消费；若笔记 scene 仍为空，下次进入视为空 PDF 笔记（用户可删除） |
| OHOS 原生通道未注册/失败 | `PlatformPdfPageRenderer` 抛异常 → 走渲染失败分支 |
| contentBounds 为空（kind=pdf 但 scene 无 PDF 页，如渲染中断的空笔记） | contentBounds 计算为 null → 不启用约束，退化为普通白板（用户可删除该空笔记） |
| PDF 单页极大 | 缩放 clamp 保证可见，fitToBounds 初始适配 |
| 窗口旋转/调整 | clamp 在每次视口变更时重算，自适应 |
| 重复导入同一 PDF | 第一版不做检测（非目标） |

## 6. 测试策略

### 6.1 测试分层

| 层 | 关注点 | 测试文件 |
|---|---|---|
| 数据层 | `createNote(kind:)` 产出 `kind: pdf` 的 NoteItem，序列化往返兼容 | 扩展 `library_repository_test.dart` |
| 画布约束-纯函数 | `clampToBounds` 逻辑（不越界、padding、空 bounds 退化） | 新增 `viewport_clamp_test.dart` |
| 画布约束-创建校验 | 落点在区域内允许、区域外拒绝 | 新增测试（mock controller） |
| 导入编排 | bytes→笔记→渲染→设 contentBounds 完整链路 | 新增 `pdf_note_import_test.dart` |
| 失败回退 | 渲染失败时笔记被删、pending provider 被清除 | 编排层测试（mock 渲染器抛异常） |
| UI 入口 | 资料库首页有「导入 PDF」卡片，点击触发选择器 | widget test |

### 6.2 关键测试用例

**画布约束（核心）**：
- `clampToBounds` 对 bounds 内的 offset 返回原值
- 超出 bounds 的 offset 被 clamp 回边界
- 缩放后 offset 仍落在边界内
- `contentBounds` 为 `null` 时不做任何 clamp（普通笔记不受影响）
- 落点在 `contentBounds` 内的元素创建成功，落点外的被拒绝

**导入编排**：
- 成功路径：选文件 → `createNote(kind: pdf)` → 跳转 → 渲染 N 页 → contentBounds = N 页并集 → fitToBounds
- 取消选择：不创建笔记
- 渲染失败：笔记被删除，返回资料库，提示错误

**回归保护**：
- 普通 `kind: notes` 笔记的创建、打开、保存行为完全不变（kind 默认值 + contentBounds 为 null）
- 现有白板内「导入 PDF」（导入到当前笔记）功能不受影响

### 6.3 不在单测范围

- 跨平台渲染器（pdfx / HarmonyOS 原生通道）已有测试（`platform_pdf_page_renderer_test.dart` 等），不重复。
- OHOS 原生 `PdfImportChannel.ets` 端到端需真机/模拟器，标注为**手动验证项**。

## 7. 涉及文件清单

### 新增

- `lib/features/library/widgets/import_pdf_card.dart` — 资料库首页「导入 PDF」卡片
- `lib/features/whiteboard/editor_core/src/rendering/viewport_clamp.dart`（或并入 `viewport_state.dart`）— `clampToBounds` 纯函数
- PDF 导入编排（`PdfNoteImportService` 或并入 `LibraryHomeViewModel`）
- `pendingPdfImportProvider`（Riverpod provider）
- 测试：`viewport_clamp_test.dart`、`pdf_note_import_test.dart` 等

### 修改

- `lib/features/library/repositories/library_repository.dart` — `createNote` 加 `kind` / `title` / `subtitle` 参数（两个实现 + `LibraryIndexNotifier`）
- `lib/features/library/view_models/library_home_view_model.dart` — `createNote` 透传新参数 + 导入编排入口
- `lib/features/library/views/library_home_page.dart` — 加入 `ImportPdfCard`
- `lib/features/whiteboard/editor_core/src/ui/markdraw_editor_config.dart` — 加 `contentBounds` 字段
- `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart` — 视口 clamp 注入 + 元素创建校验
- `lib/features/whiteboard/editor_core/src/editor/tools/hand_tool.dart` — 平移后 clamp
- `lib/features/whiteboard/editor_core/src/rendering/viewport_state.dart` — `clampToBounds` 实现（若不另开文件）
- `lib/features/whiteboard/views/whiteboard_page.dart` — 按 kind 启用约束 + 消费 pending 导入 + 渲染失败回退

### 复用（本次范围内零改动）

- `lib/features/whiteboard/editor_core/src/core/pdf/`（整个渲染抽象与各平台实现）—— 见第 8 节「已知限制」，存在独立的鸿蒙端债务，但本次不修
- `lib/features/whiteboard/editor_core/src/ui/markdraw_file_handler.dart`（`importPdf` / `importPdfSource`，供编排层调用）
- `lib/features/whiteboard/editor_core/src/core/scene/scene.dart`（`sceneBounds`）
- `lib/features/whiteboard/editor_core/src/core/math/bounds.dart`（`containsPoint` 等）
- `lib/features/whiteboard/repositories/whiteboard_scene_repository.dart`
- `lib/features/library/models/note_item.dart`（`LibraryFilter.pdf` 已存在）

## 8. 多端适配说明

PDF 笔记导入功能本身的多端能力**继承自现有 PDF 渲染链路**，无需为本次功能新增平台适配代码。分发机制如下（均已存在，本次复用）：

### 渲染层分发（`pdf_page_renderer_default.dart`）

| 平台 | 渲染路径 | 原生实现 |
|------|----------|----------|
| **OHOS** | 自建 `PlatformPdfPageRenderer` → MethodChannel(`flow_muse/pdf_import`) | `ohos/.../pdf/PdfImportChannel.ets`（华为 PDF Kit） |
| Android / iOS / macOS / Windows / Web | `PdfxPdfPageRenderer`（pdfx 包） | pdfx 自带，**无需自写原生代码** |
| Linux / Fuchsia | `UnsupportedPdfPageRenderer` | 明确不支持，抛 `UnsupportedError` |

> pdfx 在 OHOS 上没有原生实现（其 pubspec 只声明 android/ios/macos/windows/web），所以鸿蒙必须自建原生 channel——这是架构分叉的根因，属合理设计。

### UI 入口 / 文件选择分发（`markdraw_file_handler.dart:235-275`）

- **OHOS**：`pickFilesViaOhosChannel`（走 `FilePickerChannel.ets` 原生通道选文件）
- **其它平台**：`FilePicker.platform.pickFiles(...)`（FilePicker 插件跨平台）

本次新增的资料库首页「导入 PDF」入口会调用 `MarkdrawFileHandler.importPdf`，**自然继承上述多端分发**，无需在编排层再做平台判断。

### 各平台验证状态（诚实声明）

- **OHOS**：原生实现最完整，是本项目主目标平台。
- **Android / iOS / macOS / Windows / Web**：依赖 pdfx，理论上可用，但项目内无 PDF 导入的运行验证记录。本次功能在这些平台上的验证为**手动验证项**（与第 6.3 节一致）。

## 9. 已知限制（不在本次范围，登记备查）

以下为现有 PDF 链路中**已存在、与本次功能正交**的鸿蒙端债务。经确认本次不修，但记录在此避免误以为鸿蒙端是完美复用：

1. **`targetPageWidth` 被鸿蒙原生端丢弃**：Flutter 端 `platform_pdf_page_renderer.dart` 传了目标分辨率参数，但 `PdfImportChannel.ets` 未读取，直接用无参 `getPagePixelMap()`（原始分辨率）。官方指南 `harmonyos-guides/.../pdf-get-img.md` 提供了 `getAreaPixelMap(matrix, bitmapWidth, bitmapHeight, ...)` 可控分辨率。后果：大尺寸 PDF 页产生超大图片，可能卡顿/OOM。
2. **`pixelMap` 未释放**：每页 `getPagePixelMap()` 返回的 `image.PixelMap` 未调用 `release()`，多页导入内存压力大。
3. **`imagePacker` 未释放**：`PdfImportChannel.ets` 创建的 `image.createImagePacker()` 未调用 `release()`，轻微资源泄漏。

这三项偏离 `harmonyos-guides` 官方推荐用法，建议作为独立后续任务处理（修复 `PdfImportChannel.ets`，不动 Flutter 端抽象）。

## 10. 已确认决策清单

| # | 决策 | 选择 |
|---|---|---|
| 1 | 入口位置 | 资料库首页 |
| 2 | 内容形态 | 图片化 + 可批注（复用白板） |
| 3 | 实现方案 | 方案 A：白板 + 边界约束 |
| 4 | 创建 API | `createNote` 加 `kind` 参数（默认 notes，向后兼容） |
| 5 | 约束启用判断 | 按 `NoteItem.kind` 判断（以持久化数据为准） |
| 6 | 边界策略 | 锁定为初始 PDF 页并集，不随批注变化 |
| 7 | 移动 clamp | 第一版只做创建校验 + 平移/缩放 clamp |
| 8 | bytes 传递 | Riverpod `pendingPdfImportProvider` |
| 9 | 失败回退 | 自动删除空笔记 + 提示 + 返回资料库 |
| 10 | 鸿蒙端债务（targetPageWidth/pixelMap/packer） | 与本次功能正交，本次不修，登记为独立后续任务 |
