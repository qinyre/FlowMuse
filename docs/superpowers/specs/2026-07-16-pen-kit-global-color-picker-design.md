# HarmonyOS Pen Kit 全局取色设计

> 日期：2026-07-16
> 分支：`feature/canvas-color-picker`
> 范围：仅实现 Pen Kit 全局取色，不接入报点预测、手写套件或一笔成形

## 1. 背景

FlowMuse 已有跨平台画布取色和鸿蒙 `flow_muse/pen_color_picker` MethodChannel，但当前鸿蒙实现存在三类问题：

1. `build-profile.json5` 指向本机不存在的 `6.6.1(26)` SDK；实际 Hvigor 为 `6.24.3`，本机支持的编译 SDK 为 `6.1.1(24)`。
2. ArkTS 调用与本机 Pen Kit SDK 声明不一致：正确入口是 `@kit.Penkit`，接口为 `imageFeaturePicker.pickForResult()`，颜色位于 `PickedColorInfo.color`。
3. 当前用 `null` 同时表示取消、不支持和异常，导致用户取消系统取色后仍会打开画布取色。

## 2. 目标

- HarmonyOS 支持设备点击取色笔后拉起 Pen Kit 系统全局取色器。
- 取色成功后复用现有 `MarkdrawController.applyStyleChange()` 应用 `#rrggbb` 描边颜色。
- 设备或 API 不支持时自动降级到现有画布取色。
- 用户取消或其他非能力错误时保持原颜色，不打开第二个取色器。
- 保持最低兼容版本 `5.1.0(18)`，不因新功能淘汰旧设备。
- 不影响 Android、iOS、macOS、Windows、Web 的既有取色和编辑行为。

## 3. 非目标

- 不接入 Pen Kit 报点预测、手写套件、一笔成形或原生画布。
- 不修改 Markdraw 元素模型、Excalidraw 序列化、撤销历史或协作协议。
- 不升级 Flutter OHOS、DevEco Studio、Hvigor 或项目 `modelVersion`。
- 不新增第三方依赖或通用 Pen Kit 框架。

## 4. 构建配置

- `ohos/oh-package.json5` 与 `ohos/hvigor/hvigor-config.json5` 继续使用 `modelVersion: "5.1.0"`。
- 本机 `ohos/build-profile.json5` 保留现有签名配置，将 `compatibleSdkVersion` 恢复为 `5.1.0(18)`，移除错误的 `compileSdkVersion: "6.6.1(26)"`，由当前 Hvigor 使用其支持的 `6.1.1(24)` 编译 SDK。
- `ohos/build-profile.json5` 按仓库现有策略保持忽略，不提交本地签名材料。
- 移除 `ohos.permission.SCREEN_CAPTURE`。Pen Kit 官方全局取色接入不要求该权限，应用也没有其他调用者。

## 5. 组件设计

### 5.1 ArkTS Channel

保留独立 Channel `flow_muse/pen_color_picker`，只处理 `pickColor`：

- 调用 `imageFeaturePicker.pickForResult()`，由系统选择默认初始位置。
- 从 `PickedColorInfo.color` 读取 RGB，输出小写 `#rrggbb`。
- 返回纯 Map：
  - `{ status: "picked", color: "#rrggbb" }`
  - `{ status: "unavailable" }`
  - `{ status: "dismissed" }`
- 官方错误码 `801` 或服务不可用映射为 `unavailable`；其他错误映射为 `dismissed`，并只记录脱敏后的错误码。
- 不保存截图，不返回色域对象、平台对象或其他屏幕信息。

### 5.2 Dart 适配层

保留现有条件导出结构，不新增抽象接口：

- OHOS 实现调用 `pickColor` 并解析 Channel Map。
- 返回 Dart record `({String? color, bool unavailable})`。
- Web 使用 stub，返回 `(color: null, unavailable: true)`。
- Android、iOS 和桌面端会沿用当前 `dart.library.io` 包装；对应 Channel 未注册时，`MissingPluginException` 视为不可用并进入现有画布取色。
- 其他异常保持原颜色，不触发二次取色。

### 5.3 编辑器调用

`WhiteboardPage._onEyedropperPressed()` 按以下顺序处理：

1. `color != null`：调用现有 `applyStyleChange(ElementStyle(strokeColor: color))`。
2. `unavailable == true`：调用现有 `requestEyedropper()`，进入画布取色。
3. 其他结果：不修改颜色，不打开画布取色。

`applyStyleChange()` 已负责更新选中元素或后续绘制的默认样式，不新增颜色状态。

## 6. 数据流

```text
点击取色笔
  -> Dart pickColor()
  -> MethodChannel flow_muse/pen_color_picker
  -> ArkTS imageFeaturePicker.pickForResult()
     -> picked: #rrggbb -> applyStyleChange()
     -> unavailable: requestEyedropper()
     -> dismissed/error: 保持原颜色
```

## 7. 错误与安全

- Channel 未注册、设备不支持或 Pen Kit 服务不可用均不得导致应用崩溃。
- 用户取消不显示 SnackBar，不打开画布取色。
- 非能力错误只记录状态与错误码，不记录画布内容、屏幕位置、协作密钥、token 或场景数据。
- 取色结果只是普通样式颜色；协作仍通过现有元素更新与加密协议同步，不新增消息字段。

## 8. 测试与验收

### 8.1 自动验证

- 新增一个 Channel 单元测试文件，复用现有 MethodChannel mock 模式，覆盖 `picked`、`unavailable`、`dismissed`、无效结果和 Channel 异常。
- 运行相关测试。
- 运行 `flutter analyze`。
- 运行全量 `flutter test`。
- 运行 `flutter build hap`，验证 ArkTS、Flutter Hvigor 插件、CMake/SQLite 和现有 Channel 共同构建。

### 8.2 HarmonyOS 真机

- 支持设备可拉起系统全局取色并应用颜色。
- 用户取消后保持原颜色，不打开画布取色。
- 不支持设备或 API 返回不支持时自动进入画布取色。
- 回归应用启动、SQLite、文件/PDF、系统分享和协作入口。

### 8.3 Android 平板

- 取色笔按钮仍进入现有画布取色。
- 取色成功后样式更新正常。
- 不要求 Windows 验证。

## 9. 影响范围

直接修改范围限定为：

- 鸿蒙 Pen Kit Channel 实现与注册权限。
- Dart Pen Kit Channel 适配层。
- 白板页取色结果分支。
- 一个对应的 Channel 测试。
- 本机忽略的鸿蒙构建配置。

不修改数据库、后端、协作协议、路由、编辑器数据模型或其他平台原生工程。

## 10. 完成标准

- 自动验证全部通过，`flutter build hap` 成功。
- HarmonyOS 真机三条结果路径均符合设计。
- Android 平板画布取色无回归。
- `git diff` 不包含本地签名材料、自动生成插件注册文件或其他无关改动。
