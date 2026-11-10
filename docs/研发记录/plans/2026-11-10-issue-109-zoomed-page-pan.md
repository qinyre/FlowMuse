# Issue #109：分页笔记放大后的双向平移

## Context

分页视口在每次约束时都将非翻页方向居中，覆盖抓手和双指产生的偏移。单指分页拖动仅传递翻页方向位移；分页滚轮入口也只处理 `dy`，忽略触控板横向滚动。

## 需求

- 分页空白笔记与 PDF 放大后可移动到页面两侧边缘；上下排列与右到左排列均适用。
- 页面在非翻页方向可完整显示时继续居中，超出时保留偏移并限制在当前页边界内。
- 抓手、单指、双指与横向滚轮共用既有视口约束；保留普通滚轮翻页、Ctrl/Cmd 缩放、页码导航与触底新增页。
- 不改变场景、历史、存储格式、协作协议或原生适配。

## 实现方案

调整 `computePagedViewportMetrics` 的非翻页方向约束，复用当前页边界与可见尺寸计算。单指拖动保留二维位移；滚轮接受二维信号，右到左布局保留纯纵向滚轮沿阅读方向翻页的行为。触底弹性只消费翻页方向，另一方向仍可平移。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/paged_viewport_metrics.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`
- `FlowMuse-App/test/features/whiteboard/editor_core/ui/paged_viewport_pan_test.dart`
- `docs/项目说明/项目需求.md`

## 验证方案

先用回归测试复现偏移被居中与横向滚轮被忽略，再覆盖两种排列、空白/PDF、边缘限制、缩小居中、混合尺寸切页、抓手/单指/双指及触底时的侧向移动。运行分页/滚轮/导航相关测试、静态分析与完整 App 回归；设备与真实触控板手感需实机验证。

## 实施步骤

1. 新建修复分支，保留工作区既有改动。
2. 补充故障回归，确认旧实现失败。
3. 修复共享约束和输入分派，同步分页需求。
4. 执行验证并记录实际结果，检查 diff。

## 验证结果（2026-11-10）

- 修复前新增的 10 项故障回归全部失败，复现侧向偏移被重置和横向滚动失效。
- 修复后 71 项定向回归通过，其中本议题新增 12 项，覆盖抓手、触控笔、单指、真实 Widget 双指事件、二维滚轮、混合尺寸切页、边界及触底新增页。
- `flutter analyze --no-pub` 无问题；完整 `flutter test --no-pub --reporter expanded` 共 2212 项通过、5 项按原条件跳过。
- 用户追加要求在连接的鸿蒙平板试运行。首次 HAP 构建暴露现有 `SystemNoticeChannel.ets` 的 `arkts-limited-throw` 编译错误，按[华为官方适配示例](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/arkts-more-cases/)将重新抛出值断言为 `Error`；只增加类型断言，不改变授权拒绝码或错误回传路径。该修正仅影响鸿蒙原生适配，不改其他端。

## 鸿蒙平板试运行（2026-11-10）

- 源码：分支 `codex/fix-109-zoomed-page-pan`，基线 `caf25aa5` 加本议题代码；构建与安装时尚未提交。
- 构建：`flutter build hap --release --no-pub --target=lib/main.dart`，显式设置 `FLOWMUSE_COLLAB_SERVER_URL=https://api.flowmuse.cloud`、`FLOWMUSE_SHARE_ORIGIN=https://app.flowmuse.cloud`、`FLOWMUSE_LAYERED_WET_INK=true`、`FLOWMUSE_LIVE_INK_V2=true`，本次重新构建成功。
- 产物：`FlowMuse-App/build/ohos/hap/entry-default-signed.hap`；SHA-256：`4b06d28a1b034a5f12e04720f7f73f7cca7dd86613a646e92f8270ac1851d7e9`。
- 设备：鸿蒙平板 `SLG-W50`。HDC `install -r` 覆盖安装成功，未卸载或清除数据；启动 `com.flowmuse.app/EntryAbility` 成功，能力与应用均为 `FOREGROUND`。
- 范围：已验证本次构建、安装和启动，已交给用户测试实际放大拖动效果。未宣称完成平板手势验收、其他五端设备验证、真实 Web 触控板手感或通知授权实测。
- `git diff --check` 通过；未将本地构建产物、生成的插件配置或原有演示视频改动纳入修复。
