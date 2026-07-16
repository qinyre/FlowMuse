# FlowMuse 鸿蒙最近白板服务卡片设计

日期：2026-07-15

## 背景

FlowMuse 是跨平台协同白板/笔记应用，鸿蒙端已经具备 Flutter 容器、ArkTS Platform Channel、文件选择/保存、PDFKit 渲染、ShareKit 分享和外部文档 Want 接入。为了参加鸿蒙创意大赛，本功能选择稳妥可落地的鸿蒙系统入口能力：服务卡片。

本设计目标是做一张可演示、可同步最近白板数据的鸿蒙服务卡片，而不是搭建复杂卡片系统。

## 目标

用户在鸿蒙桌面看到 FlowMuse 服务卡片，卡片展示最近打开或保存的白板标题和更新时间。点击“继续创作”后拉起 FlowMuse，并回到最近白板；如果没有最近白板，则打开资料库。

比赛演示路径：

1. 鸿蒙桌面添加 FlowMuse 服务卡片。
2. 打开 FlowMuse 中任意白板。
3. 返回桌面，卡片显示该白板标题和更新时间。
4. 点击卡片“继续创作”。
5. 应用打开最近白板，继续手写、PDF 批注或协作演示。

## 非目标

首版不做以下内容：

- 不显示多个最近白板。
- 不显示白板缩略图。
- 不显示协作房间在线状态。
- 不同步白板内容到卡片。
- 不让卡片直接创建、删除、分享白板。
- 不新增大依赖，不重构白板内核。

## 用户可见功能

### 有最近白板时

卡片显示：

- `FlowMuse`
- `最近白板`
- 最近白板标题，例如 `线代课堂笔记`
- 最近更新时间，例如 `今天 15:30`
- 按钮：`继续创作`

点击卡片后打开最近白板。

### 无最近白板时

卡片显示：

- `FlowMuse`
- `开始你的第一块白板`
- 按钮：`打开资料库`

点击卡片后打开资料库。

## 架构

首版只增加鸿蒙卡片层和一条最小同步通道，不改变现有白板内核、协作协议、Excalidraw 数据格式或数据库 schema。

### 数据流

```text
WhiteboardPage 打开/保存白板
  ↓
Dart 写入 local_settings：service_widget.lastWhiteboard
  ↓
Dart 调 OHOS MethodChannel：flow_muse/service_widget
  ↓
ArkTS 保存卡片展示数据并 updateForm
  ↓
桌面服务卡片刷新标题和时间
```

### 点击流

```text
桌面卡片 router 事件
  ↓
EntryAbility 收到 action=resumeLastWhiteboard
  ↓
Flutter 启动后读取 local_settings 中的最近 noteId
  ↓
GoRouter 跳转 /whiteboard/:noteId
```

如果最近白板不存在或数据异常，则跳转 `/library`。

## 组件设计

### Dart 侧

1. 新增一个轻量服务用于记录最近白板。
   - 复用 `LocalSettingsRepository`。
   - key：`service_widget.lastWhiteboard`。
   - value：JSON 字符串，字段为 `noteId`、`title`、`updatedAt`。

2. 在白板打开成功后同步最近白板。
   - 位置靠近 `WhiteboardPage` 现有打开流程。
   - 使用当前 `NoteItem` 的 `id`、`title`、`updatedAt`。

3. 在本地保存成功后刷新更新时间。
   - 位置靠近现有 `saveScene` 和 `_touchNoteWithCurrentCover` 流程。
   - 不在每一笔输入时同步。

4. 新增 OHOS MethodChannel 封装。
   - channel：`flow_muse/service_widget`。
   - method：`updateLastWhiteboard`。
   - 参数：`noteId`、`title`、`updatedAt`。
   - 捕获 `MissingPluginException` 和 `PlatformException`，失败不影响白板保存。

5. 启动后处理卡片意图。
   - 若启动参数表示 `resumeLastWhiteboard`，读取 `service_widget.lastWhiteboard`。
   - note 存在则跳转 `AppRoutes.whiteboardPath(noteId: noteId)`。
   - note 不存在、JSON 损坏或读取失败则保持/跳转资料库。

### ArkTS 侧

1. 新增 `ServiceWidgetChannel.ets`。
   - 注册 `flow_muse/service_widget` MethodChannel。
   - 接收 Dart 传来的最近白板数据。
   - 保存给 FormExtensionAbility 使用。
   - 触发卡片刷新。

2. 新增 `EntryFormAbility.ets`。
   - 实现 `FormExtensionAbility`。
   - `onAddForm` 返回默认或最近白板数据。
   - `onUpdateForm` 刷新绑定数据。
   - 不执行长时间后台任务。

3. 新增服务卡片页面与 profile。
   - 卡片 UI 使用静态 ArkTS 卡片页面。
   - profile 配置支持首版尺寸，优先 2×2；如展示拥挤再用 2×4。
   - 点击事件用 router 拉起 `EntryAbility`，传递 `action=resumeLastWhiteboard`。

4. 更新 `module.json5`。
   - 在 `extensionAbilities` 注册 FormExtensionAbility。
   - metadata 指向卡片 profile。
   - 保留现有 `EntryAbility` skills、文件分享和 PDF 能力。

## 错误处理

- Dart 调 ArkTS 失败：捕获异常，不提示用户，主应用继续保存白板。
- 最近白板 JSON 损坏：当作无最近白板处理。
- 卡片更新失败：卡片保留旧数据或默认文案。
- 卡片点击后 noteId 已删除：打开资料库。
- 日志不记录白板内容、token、房间密钥、协作密钥或可还原的密文。

## 测试与验收

最小验收清单：

1. 新装应用后，卡片显示默认文案。
2. 打开任意白板后，桌面卡片刷新为该白板标题。
3. 编辑并保存白板后，卡片更新时间变化。
4. 点击卡片能回到最近白板。
5. 删除最近白板后，点击卡片回到资料库。
6. `cd FlowMuse-App && flutter analyze` 通过。
7. 涉及鸿蒙侧后，`cd FlowMuse-App && flutter build hap` 通过。
8. 真机或模拟器验证卡片添加、刷新、点击三条路径。

## 实施顺序

1. 新增最近白板 Dart 记录服务，先只写入 `local_settings`。
2. 在白板打开/保存成功路径调用记录服务。
3. 新增 OHOS `ServiceWidgetChannel`，让 Dart 能把最近白板数据传给 ArkTS。
4. 新增 FormExtensionAbility、卡片页面和 profile。
5. 配置 `module.json5`。
6. 处理卡片 router 启动参数，完成点击后恢复最近白板。
7. 跑 Flutter 静态检查和鸿蒙构建。
8. 真机/模拟器验证服务卡片闭环。

## 取舍

本方案优先保证比赛可演示闭环，复用现有白板、资料库、设置存储和鸿蒙 Platform Channel 模式。首版只同步一个最近白板，避免引入列表同步、缩略图生成和协作状态刷新带来的联调风险。
