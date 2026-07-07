# Flutter UI 生命周期断言排查经验

## 背景

本项目连续遇到过几类 Flutter debug assertion：

- `framework.dart`: `_dependents.isEmpty` / `_dependencies.isEmpty`
- `overlay.dart`: `!_skipMarkNeedsLayout`

这些错误通常不是某个控件本身损坏，而是 widget 子树、Inherited 依赖、focus、menu 或 overlay 在 Flutter 正在执行布局、关闭浮层、deactivate 子树时被同步改动。

## 本项目已确认的高风险模式

### 1. 长生命周期对象持有 GlobalKey

不要把 `GlobalKey` 放进 controller、repository、provider 等长生命周期对象里。白板切换、页面重建或 overlay 关闭时，旧子树还在 deactivate，新子树又尝试复用同一个 `GlobalKey`，容易触发 framework 依赖清理断言。

做法：`GlobalKey` 只由拥有对应 widget 子树的 `State` 持有，并随该 `State.dispose` 一起结束生命周期。

### 2. 强制销毁持有 controller/focus 的编辑器子树

不要在编辑器根部、`Scaffold` 或持有复杂 focus/overlay 的子树上使用会随业务 id 改变的 key，例如 `ValueKey(widget.noteId)`。这会让 Flutter 在 controller 仍被外部持有时强制卸载整个子树。

做法：业务 id 改变时通过 controller 加载新数据，不用 key 强制重建整棵编辑器。

### 3. 在 build 中创建 FocusNode / TextEditingController

`FocusNode()`、`TextEditingController()`、`ScrollController()`、`AnimationController()` 不能在 `build` 中匿名创建。它们必须属于 `State` 字段，并在 `dispose` 中释放。

对临时 dialog controller，使用 `try/finally` 或 `showDialog().then` 释放。

### 4. 菜单关闭时同步改 UI 树

`MenuAnchor`、`PopupMenuButton`、`showModalBottomSheet` 的菜单项点击后，Flutter 会先关闭自己的 overlay/route。如果同一个回调里立刻执行导航、打开新 dialog、修改 provider 状态或白板 controller，可能和菜单 overlay 的布局/卸载重入，触发 `overlay.dart` 断言。

做法：菜单项里只触发关闭，实际业务动作放到下一帧：

```dart
void runAfterUiFrame(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
}
```

尤其要覆盖：

- 菜单项内打开 dialog
- 菜单项内调用 `context.go` / `context.push` / `Navigator`
- 菜单项内修改 Riverpod/ChangeNotifier 状态
- bottom sheet 内先 `Navigator.pop` 再修改 controller

### 5. 自管 OverlayEntry 必须记录插入状态

`OverlayEntry` 可能被创建后还没真正插入，就因为 widget dispose 或状态变化进入 remove 流程。直接 `entry.remove()` 会让 overlay 生命周期和当前布局阶段交错。

做法：

- `OverlayEntry` 由 `State` 持有。
- 插入前确认 anchor 的 `RenderBox.attached`。
- 记录 `bool inserted`，只有已插入才 remove。
- 在 `SchedulerPhase.persistentCallbacks` 中插入/移除时延后到帧尾。
- `dispose` 中清理 entry，但不要恢复 focus 或触发业务状态。

### 6. await 后必须检查 mounted

所有 `await showDialog`、文件选择、网络、协作连接、导入导出完成后，如果继续使用 `context` 或 `State`，必须检查 `context.mounted` / `mounted`。

## 新增 UI 浮层代码检查清单

新增或修改 UI 浮层前，至少检查：

- 是否使用了 `GlobalKey`，它是否只属于本地 `State`。
- 是否有 `FocusNode()`、`TextEditingController()` 出现在 `build`。
- 菜单项是否同步执行了导航、弹窗、provider/controller 更新。
- bottom sheet 关闭后是否同步改状态。
- 自管 `OverlayEntry` 是否由 `State` 管理并记录插入状态。
- `await` 后是否还会访问 `context` 或 `setState`。

## 推荐策略

优先使用 Flutter 自带 `showDialog`、`showModalBottomSheet`、`MenuAnchor` 等组件。必须自管 `OverlayEntry` 时，把生命周期隔离在单独 `StatefulWidget` 中，不要让 controller 直接持有 overlay、key 或 focus。

