# Issue #106：多选框内空白处拖动

## Context

选择工具先检查编辑点、缩放和旋转手柄，再命中元素本体。多条相隔较远的笔迹被框选后，从中间空白处拖动仍被分派为新框选；手指则会进入页面平移。

## 需求

- 多选框内部空白处可拖动整组选中对象，松手后可一次撤销、重做。
- 手柄和实际元素命中优先；框外仍可发起新框选，空白轻点仍取消选择。
- 保留锁定保护：含锁定元素的选区不通过空白处启动整组移动。
- 鼠标、触控笔和手指共用规则，不改场景格式、持久化、协作协议或平台适配。

## 实现方案

在 `SelectTool` 中复用 `SelectionOverlay` 的多选边界及模式间距，提供空白拖动命中。触摸分流复用同一判断；实际拖动越过阈值后才将其交给既有多选移动路径，轻点仍走原逻辑。元素本体、手柄优先级及单选规则不变。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/select_tool.dart`
- `FlowMuse-App/test/features/whiteboard/editor_core/editor/tools/select_tool_test.dart`
- `docs/项目说明/项目需求.md`

## 验证方案

先复现两条相隔较远的笔迹框选后从空白处拖动失败，再验证鼠标、触控笔、手指移动与一次撤销/重做。覆盖拖动阈值、手柄优先、锁定、实际元素优先、框外框选及空白点按；运行相关测试、完整 App 回归和静态分析。无实机时不宣称完成六端设备验证。

## 实施步骤

1. 补充回归测试，确认旧实现失败。
2. 在既有选择工具中补充命中与移动分派，同步需求描述。
3. 格式化、定向测试、静态检查及完整回归，检查最终 diff。

## 验证结果（2026-11-10）

- 修复前：新增测试中的鼠标、触控笔、手指及缩放后的手指拖动共 4 项失败，均表现为笔迹未移动。
- 修复后：选择工具、触摸选择、场景派生数据与 PDF 底图选择的 30 项定向回归通过。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --reporter expanded`：2191 项通过，5 项按既有条件跳过，无失败。
- `git diff --check`：通过。尚未进行六端真机操作或手写性能验证。

## 鸿蒙平板试运行（2026-11-10）

- 源码：`codex/fix-106-selection-blank-drag`，基线 `cb7c9f5d` 加本议题尚未提交的工作区改动。
- 构建：`flutter build hap --release --no-pub --target=lib/main.dart`，显式设置 `FLOWMUSE_COLLAB_SERVER_URL=https://api.flowmuse.cloud`、`FLOWMUSE_SHARE_ORIGIN=https://app.flowmuse.cloud`、`FLOWMUSE_LAYERED_WET_INK=true`、`FLOWMUSE_LIVE_INK_V2=true`；本次构建成功。
- 产物：`FlowMuse-App/build/ohos/hap/entry-default-signed.hap`，SHA-256：`6c13405e99a8b422fcd3b7204afd913cec57c5280752be1318378fe3032b20f1`。
- 设备：鸿蒙平板 `SLG-W50`。使用 HDC `install -r` 覆盖安装成功，未卸载或清除数据；启动 `com.flowmuse.app/EntryAbility` 成功，能力与应用均为前台状态。
- 验证范围：已验证本次构建、安装和启动；用户反馈鸿蒙平板测试正常。其他平台设备及量化手写性能未实测。
