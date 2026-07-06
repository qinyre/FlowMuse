# 组件化应用框架改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 FlowMuse 的草稿式单文件首页改造成基于成熟 Flutter 库的组件化页面框架。

**Architecture:** 应用入口使用 `MaterialApp.router` 和 `go_router` 管理页面层级；文件库状态由 Riverpod ViewModel 管理；页面按 feature 拆分为 library 与 whiteboard。UI 使用 Flutter Material 3 组件和 Lucide 图标，去掉手绘图标、手绘封面、手绘装饰。

**Tech Stack:** Flutter Material 3、go_router、flutter_riverpod、lucide_icons_flutter。

---

### Task 1: 依赖和测试约束

**Files:**
- Modify: `pubspec.yaml`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: 写入依赖**

在 `pubspec.yaml` 的 `dependencies` 加入：

```yaml
  flutter_riverpod: ^3.3.2
  go_router: ^17.3.0
  lucide_icons_flutter: ^3.1.14
```

- [ ] **Step 2: 写失败测试**

更新 widget 测试，使它断言首页、筛选和路由跳转仍然可用。

- [ ] **Step 3: 拉取依赖**

Run: `C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe pub get`

Expected: 依赖解析成功。

### Task 2: 应用路由与主题

**Files:**
- Create: `lib/app/flow_muse_app.dart`
- Create: `lib/app/app_router.dart`
- Create: `lib/app/app_theme.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: 用 `GoRouter` 建立 `/library` 与 `/whiteboard/:title`**
- [ ] **Step 2: 入口改为 `ProviderScope` + `FlowMuseApp`**
- [ ] **Step 3: 使用 `MaterialApp.router`**

### Task 3: 文件库 MVVM 与组件拆分

**Files:**
- Create: `lib/features/library/models/notebook_item.dart`
- Create: `lib/features/library/view_models/library_home_view_model.dart`
- Create: `lib/features/library/views/library_home_page.dart`
- Create: `lib/features/library/widgets/library_sidebar.dart`
- Create: `lib/features/library/widgets/library_content.dart`
- Create: `lib/features/library/widgets/notebook_card.dart`
- Create: `lib/features/library/widgets/create_notebook_card.dart`

- [ ] **Step 1: 把样例数据和筛选状态迁移到 Riverpod ViewModel**
- [ ] **Step 2: 用 `NavigationRail`、`SearchBar`、`SegmentedButton`、`Card` 替代手绘结构**
- [ ] **Step 3: 用 Lucide 图标替换 Material Icons**

### Task 4: 白板占位页面组件化

**Files:**
- Create: `lib/features/whiteboard/views/whiteboard_page.dart`
- Create: `lib/features/whiteboard/widgets/whiteboard_toolbar.dart`
- Create: `lib/features/whiteboard/widgets/zoom_controls.dart`

- [ ] **Step 1: 白板页面从路由参数接收标题**
- [ ] **Step 2: 工具栏使用 Material 3 `IconButton` 和 Lucide 图标**
- [ ] **Step 3: 缩放控件使用正式按钮组件**

### Task 5: 验证与提交

**Files:**
- Modify: all touched files

- [ ] **Step 1: 运行格式化**

Run: `C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe format lib test`

- [ ] **Step 2: 运行测试**

Run: `C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe test`

- [ ] **Step 3: 检查工作树并提交**

Run: `git status --short`

Commit message: `组件化应用框架并引入正式路由和图标库`
