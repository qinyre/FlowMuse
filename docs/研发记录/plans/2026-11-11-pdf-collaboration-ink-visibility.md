# PDF 协作笔迹可见性修复

## Context

基线 main `ab117719`。双端 PDF 协作出现新笔迹不可见但可选中；现有代码可确定性复现“补出的数字 index 小于 PDF 的字母 index，导致底图覆盖新笔迹”。详见[排查记录](../troubleshooting/2026-11-11-pdf-collaboration-invisible-ink.md)。修复分支：`codex/fix-pdf-collaboration-ink-visibility`。

## 需求

- 接收远端元素后，本机和对端新笔迹均保持可见；保留旧字、选择、撤销、保存重开与普通插图前景语义。
- 历史错误索引场景无需用户删除或重新导入 PDF 即可显示笔迹。
- 不改 LWW 的 version/nonce 仲裁、归属深合并、密文传输、Excalidraw 字段、数据库、平台工程及书写热路径。

## 实现方案

1. `SceneReconciler` 按既有 index/id 顺序合并后，复用 `FractionalIndex.generateAfter` 顺次修复缺失或非递增索引。已严格递增的索引与原对象不变；重复索引及与修复号冲突的后继向后续排，避免再次碰撞和改变合并后的相对顺序。空字符串按缺失索引处理。只复制需修复的 Map，不改输入或版本字段。
2. 在 `Scene` 已有绘制序列分组中把 PDF 背景置于普通内容之前；各组内部仍保留 fractional index。复用此序列的画布、缩略图、PNG/PDF 与 SVG 同时受益，原始 orderedElements 与序列化不重排。普通插图继续置顶。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/collaboration/services/scene_reconciler.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/scene/scene.dart`
- `FlowMuse-App/test/features/whiteboard/collaboration/`：排序修复及 Repository 增量/双端场景回归。
- `FlowMuse-App/test/features/whiteboard/editor_core/`：历史错误排序的画布与导出像素回归。

## 验证方案

先补会在原实现失败的回归：字母/数字混合、缺失/空索引、连续重复及后继冲突、输入不变与幂等、单次对端增量修复本机四笔、两端绘制与可选中、旧场景底图遮挡及导出/缩略图。随后静态分析、相关回归和完整 App 测试。共享纯 Dart 修改覆盖各端同一路径，不新增平台分支；鸿蒙/安卓持笔实机和现场版本仍须单独复验，不能用软件测试替代。

## 实施步骤

1. 创建分支、勘察调用方、固定失败测试。
2. 修复排序号与 PDF 绘制顺序，运行相关测试。
3. 执行静态分析与完整 App 回归，记录结果和未验证范围。

本轮只交付本地分支与可审查改动，不自动提交、推送或发布。协作合并属于 `.agent/forbidden_zones.md` 的人工验收范围；后续提交/MR 的责任岗位为协作模块维护者、审查岗位为编辑器维护者，需由实际承担者理解、改写并复核。本文仅记录岗位与测试证据，不宣称已完成人工审查。

## 实施与验证结果

已完成两处业务修复及三份正式回归测试。新增 7 项回归在修复前均失败，修复后全部通过：

- `test/features/whiteboard/collaboration/services/scene_reconciler_index_test.dart`：缺失/空索引、数字/字母混用、连续重复与后继冲突、相对顺序、确定性、输入不变及重复合并幂等。
- `test/features/whiteboard/collaboration/pdf_ink_visibility_test.dart`：1/220 页合成 PDF 场景，真实内存 Repository 的单次远端增量对本机四笔补号，两端 Controller 应用后笔迹可见、可框选、像素一致，后续新笔及保存重开仍可见。
- `test/features/whiteboard/editor_core/pdf_background_order_test.dart`：历史错误 index 也不遮挡批注；点选、普通插图前景和源 JSON 顺序不变；检查区域 PNG、普通 PNG、封面、页面缩略图、SVG 先后顺序及实际 PDF JPEG 批注像素，覆盖保存重开和撤销重做。

最终执行（从 `FlowMuse-App` 目录）：

```powershell
flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
flutter test --no-pub --reporter expanded
```

- 静态分析：`No issues found`。修复前临时诊断文件的两项空值写法提示与新增测试的一项括号提示均已清理。
- 完整 App 回归：**2249 通过，5 跳过，0 失败**，运行约 3 分 14 秒。跳过沿用现有在线/本地原件/历史对照/显式基准条件，没有新增 skip 或缩小测试选路。
- `git diff --check` 通过；依赖清单与锁文件无变更。
- 没有后端、数据库、协议字段、原生 Channel 或平台工程变更，无需服务端迁移或重启；共享纯 Dart 路径没有新增平台判断或 I/O。
- 未构建安装平板包、未发布 Web，未完成 MatePad/一加平板持笔验收；现场版本和日志缺失，因此不把本地回归通过描述为原偶发故障的实机闭环。

完整回归与分析日志在本机 Git 忽略目录 `FlowMuse-App/build/diagnostics/pdf-ink-visibility/` 的 `full-regression.log`、`analyze-final.log`，正式测试已入 `test/` 范围供后续 CI 重跑。

## 后续鸿蒙安装验证

用户随后授权把当前工作区运行到已连接的 MatePad 11.5S。已执行 `flutter build hap --debug --no-pub --target=lib/main.dart`，显式指定正式 API/分享地址、湿墨分层与 Live Ink V2 为 true，构建通过。源码为 `ab117719` 基线加本分支未提交修复，不能把基线提交单独当作产物源版本。

- 产物：`FlowMuse-App/build/ohos/hap/entry-default-signed.hap`，214901562 字节。
- SHA-256：`6b66b32a689b3888c2dd3fd266591df9b256f354819529e78aeaa88ed1232e25`。
- 平板完成 USB 调试授权后，`hdc install -r` 覆盖安装成功，未执行卸载或清除数据；`aa start -a EntryAbility -b com.flowmuse.app` 返回启动成功，后续再次查询进程仍存在。
- 本次证据为构建、安装及启动，不包括持笔书写、双端 PDF 协作或性能验收；调试版帧率不能代表 release 表现。一加平板和正式 Web 尚未发布本分支。

本机回执与构建日志位于同一忽略目录的 `hap-debug-receipt.json`、`hap-debug-build.log`。
