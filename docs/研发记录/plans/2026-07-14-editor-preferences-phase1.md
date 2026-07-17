# 编辑器偏好设置第一批实施计划

## Context

设置页已有“工具设置 / 手写笔设置 / 手势设置”入口，但仍是占位内容。编辑器已经具备每种笔形的样式状态、真实压感、单指平移和双指缩放，本次只补持久化和开关，不改场景 JSON、协作协议或数据库结构。

## 实现范围

- 工具设置：默认工具、默认笔形、每种笔形的颜色和粗细记忆。
- 手写笔设置：压感开关、三档压感曲线、防误触开关。
- 手势设置：双指缩放、单指平移开关。
- 编辑器内修改笔形颜色、粗细和压感灵敏度时同步记忆。

## 实现方案

- 使用现有 `LocalSettingsRepository`，以单个版本化 JSON key 保存偏好；不增加表或依赖。
- 使用一个 Riverpod `AsyncNotifier` 作为设置页与白板页的共享状态。
- 控制器只接收纯 Dart 配置值，不依赖设置 feature；平台差异仍由现有输入策略处理。
- 设置关闭时走现有输入路径的最小分支，不新增手势识别器。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/models/editor_preferences.dart`
- `FlowMuse-App/lib/features/whiteboard/view_models/editor_preferences_view_model.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/lib/features/settings/views/settings_page.dart`
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`

## 验证方案

- 偏好 JSON 容错解析和往返测试。
- 控制器测试压感开关、曲线、手势开关及笔形状态应用。
- `flutter analyze` 与相关 `flutter test`。

## 实施步骤

1. 增加偏好模型和 Provider。
2. 给控制器增加最小配置入口和笔形状态回调。
3. 白板页加载并保存偏好。
4. 替换三个占位设置分区。
5. 格式化、静态分析和测试。
