# 协作书写流畅度优化：调研、计划与验收

日期：2026-09-23。起点：`origin/main` / `e90a1ad`；实施分支：`fix/collaboration-writing-performance`。

用户反馈：协作时偶发卡顿，对方书写长笔画时更明显。本轮要求先分析和调研，再在新分支实现；**不安装应用、不连接平板、不进行实机测试**。软件测试结果不得表述为触控笔物理延迟或 Android / 鸿蒙实机帧率改善。

## 1. 成熟产品可借鉴的设计

以下为官方公开文章或源码，查阅日期同上；区分公开实现与本项目推导，不推测闭源产品内部协议。

| 来源 | 已核实的做法 | 对 FlowMuse 的具体价值与边界 |
| --- | --- | --- |
| [Excalidraw Portal.tsx](https://github.com/excalidraw/excalidraw/blob/31df3e6ef245c646b18a055ccf858cd6117c7768/excalidraw-app/collab/Portal.tsx) | 按元素版本筛选变化，文档与 volatile presence 分开；保留全量同步入口。 | 继续使用标准完整元素、版本与墓碑；优化客户端内存与调度，不把正式笔迹放入可丢包通道。 |
| [tldraw diff.ts](https://github.com/tldraw/tldraw/blob/db5d20befa38213384d17059e7f61dc9c7c29de8/packages/sync-core/src/lib/diff.ts) | 对象差量修改时按需浅复制；数组可以带 offset 追加，无法追加时退回替换。 | 未变化笔迹应共享既有数据；增长笔迹只处理本次相关对象。数组追加思想已体现在本项目 Live Ink V2，不能直接把 tldraw 的明文服务端协议移植进来。 |
| [tldraw TLSyncClient.ts](https://github.com/tldraw/tldraw/blob/db5d20befa38213384d17059e7f61dc9c7c29de8/packages/sync-core/src/lib/TLSyncClient.ts) | 网络同步有独立帧调度，汇集未发送变化和入站 diff；presence 单独处理。 | 批处理窗口必须有截止时间，持续消息不能反复把提交推后；光标更新只刷新需要它的绘制层。 |
| [Figma 多人协作技术说明（2019）](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/) | 本地编辑立即应用；冲突时保护尚未确认的本地值以避免闪回；重连重新取得状态并恢复本地变化。 | 本地输入、预览、终笔不等待网络；保留本项目 selected/editing 保护和 LWW。Figma 的服务器排序与属性级语义不等同于本项目的元素级 LWW，不替换现有算法。 |
| [Yjs Awareness 文档](https://docs.yjs.dev/getting-started/adding-awareness) | 光标、在线状态是短暂信息，不属于文档持久化。 | 沿用现有 presence，不让光标牵动文档、保存或整个编辑器 UI；不引入 Yjs 依赖。 |

## 2. 当前链路与问题

默认配置 `FLOWMUSE_LAYERED_WET_INK=false`、`FLOWMUSE_LIVE_INK_V2=false`。已存在的 V2 具有 64 点上限、独立加密 volatile 通道、背压、远端湿墨和可靠终笔；它没有默认启用，因此不能以“已有 V2”认定当前用户链路已优化。

默认链路：本地输入 → FreedrawTool → 定时完整活动元素 → JSON → repository → AES-GCM → Socket.IO → 解密 / JSON → 页面合并窗口 → LWW → 元素解析 → Scene → 绘制。

| 已核实的代码行为 | 影响 | 本轮处理 |
| --- | --- | --- |
| `ExcalidrawScene.copyWith(elements:)` 深复制每个元素及所有 points / customData；出站增量合并复制全场景，入站又复制两次。 | 一笔变化的成本随历史总点数增长，增加分配和 GC；长笔与多人相乘。 | 在保持输入隔离的前提下共享未变元素，消除入站重复的全场景复制；测试未知字段、嵌套扩展与旧快照不受修改。 |
| `reconcileRemoteElements` 先选原始 remote winners，再运行完整 reconciler。 | 额外遍历入站元素；返回值未必包含 reconciler 的 owner 回填、绑定文字或 index 修复。 | 去掉额外的原始赢家筛选，依据既有合并的实际结果取得变化；保持既有胜出规则，加入归属和绑定修复回归。 |
| ChangeAccumulator 和页面入站 16ms 窗口每次消息都 cancel / 重启。 | 多人消息间隔小于 16ms 时提交可能一直延期，形成“停笔才刷新”。 | 改为从首条消息开始计时，窗口内按原 LWW 汇集；连续流也按窗口交付，终笔不丢。 |
| 远端增量 `applyRemoteElements` 使用完整 `notifyListeners`。 | 工具栏、面板与远端长笔重复重建，抢占本地书写帧预算。 | 普通远端笔迹使用已有画布通知；页框、选中 / 正在编辑对象等会改变 UI 的更新保留完整通知。 |
| WhiteboardPage watch 整个协作状态，包含每次 pointer presence。 | 光标移动重建页面、工具栏及画布。 | 用 Riverpod listen 更新现有页面状态，将光标 / 选择指示交给 ValueListenableBuilder 与独立 RepaintBoundary；成员身份、连接和保存状态变化仍更新页面。 |
| 每次远端元素更新都安排 `_loadMissingImageFiles`，后者序列化完整场景。 | 普通笔迹也周期性触发图片扫描和全场景序列化。 | 仅图片变更 / 初始恢复触发；直接从原生 Scene 取图片 ID，确实有文件变化时才应用结果。 |
| 旧实时笔迹仍重复构建完整增长元素，AES / JSON 也可能占用 UI isolate。 | 单笔越长，单包处理成本越高。 | 先用真实加密长笔基准分离此成本；已有背压继续只保留最新临时状态，必要时用现有 SDK 能力处理大包，不改采样、压力和最终点集。 |

## 3. 实施顺序与验收

### P0：基线与可重复证据

- [x] 复用 `collaboration_scenarios.dart` 与真实 repository / AES-GCM / MemoryRealtimeTransport，补充 2 / 5 人、短 / 长笔、历史笔迹场景；记录基线和候选耗时、收敛、消息量。
- [x] 先跑既有协作与书写工作流测试，明确已有跳过项；计时不作为 CI 绝对速度阈值，结构性回归用确定性断言。

### P1：场景增量与复制

- [x] 新输入保持深复制隔离，未变对象结构共享；正式格式和 unknown customData 原样保留。
- [x] 入站只合并一次；原始 remote 不直接绕过 owner / index 规范化；测试旧客户端归属回填、绑定文字、保护集合、删除、乱序与重复消息。
- [x] 用大量历史点的回放验证成本下降；直接检验不再遍历 / 复制未变 points，而非仅测几个矩形。

### P2：稳定交付与队列

- [x] 出站 / 入站窗口变为从首条消息起计时的 16ms 批处理；连续 5ms 消息测试确认发送未结束前已交付，不再因新消息延期。系统繁忙与调度等待不计为硬实时保证。
- [x] 保持同 ID 最新临时帧、正式终笔和墓碑可靠发送；断开 / 换房后旧的待发消息、待应用场景及图片结果不得进入新房间。
- [x] 根据 P0 的 AES / JSON 数据决定大包处理；不为了通过基准降低采样数或同步频率。

### P3：画布与 presence 隔离

- [x] 普通远端笔迹不重建 DesktopToolbar，画布、页码、选区、正在编辑内容仍更新。
- [x] 多次 cursor 更新不重建整页 / 工具栏，远端光标与选区可见；成员加入退出、昵称、离开状态、归属聚焦继续更新。
- [x] 图片同步由相关变化驱动，普通笔迹不反复序列化全场景查图片。

### P4：软件回归与交付

- [x] 定向测试覆盖并行本地书写 / 远端长笔、终笔、取消、撤销广播、保存 / 重开、归属与导出、V1 和已启用时的 V2。
- [x] 全量 `flutter test`、`flutter analyze`；Android APK / Web 构建验证共享代码。无 OHOS 原生 / vendor / Channel 改动时不增加 HAP 必跑门禁。
- [x] 核对协议 / 服务端边界：本轮未修改共享协议或 Go 代码，不额外运行 Go 门禁。
- [x] 更新需求 / 前端架构中相关行为，以及本计划的实测表、限制和完成状态。

## 4. 不可退让的体验与可靠性边界

本地 PointerDown / Move / Up 不等待网络，不减少 accepted 点、不修改滤波与压力、笔型种子、视觉边界和终笔坐标；保持新旧五笔一致性。正式元素仍通过可靠加密通道，离线恢复、冲突保护、墓碑和未知字段保留。聚焦仅本机生效，不改变全局 z 序、创建者或导出净化。不能用延长同步间隔、暂停远端到本地抬笔后才更新来“优化”帧率。

默认分层和 Live Ink V2 开关保持现状。本轮优化必须惠及默认 V1；待实机门禁通过再决定 V2 默认推广。V1 完整元素兼容路径对单条增长笔画仍有 O(笔画点数) 的序列化成本，这一上限必须在结果中明确，不声称恒定成本。

已有协作整场景撤销回退远端新增的跳过测试，单独记录于上轮自由书写验证。本轮必须确认没有新增回归；若不改历史模型，该既有缺陷不能被计为通过。

## 5. 后续人工项目（本轮不执行）

| 项目 | 条件和内容 |
| --- | --- |
| Android / HarmonyOS 实机 | 同设备交替版本，2 / 5 人长短笔，带大 PDF；测 UI / Raster P95、输入延迟、功耗和内存。 |
| 真实网络 | LAN / 公网 / 弱网，长笔同时书写、重连、远端图片、最终收敛。 |
| 触控笔手感 | 同一笔与笔刷的小字、长线、转折、压感和抬笔；高速录像才用于物理笔尖延迟。 |
| H10 人工复核 | 本轮保持 LWW 规则。涉及合并集成的差量选择与元数据回填，按 `.agent/forbidden_zones.md` 在合并审查时登记责任人、审查人和下面的测试证据；不将自动测试代替人工讲解。 |

## 6. 执行结果

### 6.1 最终实现与边界

本轮未增加依赖、协议字段、平台判断或服务端改动。保持分层湿墨和 Live Ink V2 默认关闭；默认 V1 已获得复制、固定窗口、画布通知和 presence 绘制隔离的优化。

- `ExcalidrawScene` 在输入边界深复制并冻结 Map/List，后续只复制新元素；未知嵌套 customData、appState 和 files 保留。对象身份断言确认 10000 点的历史笔迹直接共享，外部输入修改和通过快照修改均不会污染旧场景。
- `reconcileRemoteElements` 返回一次现有合并后的真实差量，包含绑定文字、归属与 index 修复；本地正在书写的 strokeId 纳入保护集合，避免规范化回填把湿墨提前提交成正式元素。版本和 nonce 胜出规则未改变。
- 入站与出站窗口从首条消息开始计时；每 5ms 的持续消息测试确认发送未结束前已交付。保留临时状态背压、可靠终笔及墓碑；加密、排队和页面应用在换房后丢弃过期工作，广播版本表按房间重置。
- 远端普通笔迹不重建工具栏；远端光标独立重绘，选区边界与本机视口仍同步，昵称变化仍更新成员栏。选中笔迹的远端属性变化保留完整 UI 通知。
- 普通笔迹不再调度缺图检查；相关图片查询读取原生 Scene，确实返回新文件或错误状态时才序列化并应用场景。远端湿墨在正式笔迹进入画布后清除，已完成笔迹不会被迟到分片复活。

### 6.2 可重复 CPU 对比

环境：Windows x64，仓库现有 OpenHarmony Flutter SDK，Dart 3.11.1。基线 `e90a1ad`，候选为本分支；同一测试机与同一回放脚本。每组 3 轮，每轮预热 5 次、测量 25 次，表中为三轮 P95 的中位数，单位 ms。历史场景为 1000 条各 128 点的笔迹；当前笔迹为 32 / 2048 点。计时无绝对 CI 门槛，结构性回归另用确定性断言。

| 人数 | 历史笔迹数 | 当前笔迹点数 | 基线 P95 | 本轮 P95 |
| --- | --- | --- | --- | --- |
| 2 | 0 | 32 | 0.789 | 1.084 |
| 2 | 0 | 2048 | 10.867 | 10.030 |
| 2 | 1000 | 32 | 70.026 | 1.730 |
| 2 | 1000 | 2048 | 72.853 | 10.259 |
| 5 | 0 | 32 | 1.229 | 1.450 |
| 5 | 0 | 2048 | 23.866 | 22.462 |
| 5 | 1000 | 32 | 164.103 | 3.985 |
| 5 | 1000 | 2048 | 182.863 | 25.572 |

有历史笔迹的 5 人长笔场景约降低 86%。空白文档短笔的两组出现约 0.22–0.30ms 增加，因此不声称所有场景耗时都下降。基线与候选各 24 组均零错误、最终场景哈希收敛；每轮发送均为 25 条，32 点笔迹发送总字节均为 24094，2048 点均为 1186219（包含 IV），没有通过减少点数或消息换取成绩。

`roundTrip` 从构建变化场景起，覆盖真实 JSON / AES-GCM / 内存 transport / 所有接收方合并。为隔离 CPU 成本，回放绕过 16ms 出站批窗口、关闭周期同步；不包含真实 Socket.IO 网络、页面入站窗口、UI/Raster 或物理笔尖延迟。该结果证明历史场景复制开销下降，不能推导为 Android / 鸿蒙实机帧率。

复现入口：`FlowMuse-App/tool/collaboration_cpu_benchmark.dart`，复用 `integration_test/fixtures/collaboration_scenarios.dart`。对比基线需使用同一回放脚本与新增 roundTrip 探针，业务文件保持基线版本。忽略目录中的原始记录为 `build/collaboration-cpu-before-roundtrip.log`、`build/collaboration-cpu-final.log`；输出仅含合成数据的计数/耗时/字节数，最终哈希不打印。

### 6.3 未采用的实验

试过对 ≥32KiB 加密包使用 SDK `compute`；它在原生端运行独立 isolate，在 Web 仍运行于当前事件循环（[Flutter 官方文档](https://api.flutter.dev/flutter/foundation/compute.html)）。5 人场景有收益，但空白文档 2 人长笔 P95 中位数从基线 10.867ms 增至 12.434ms；每包创建 worker 的开销不适合全面默认启用。实验已移除，生产 `collaboration_crypto.dart` 无改动，仅保留 256KiB 互通与篡改拒绝测试。今后只有实机证明加密是剩余瓶颈时，才评估长期 worker 的收益与复杂度。

### 6.4 软件验收

测试与构建命令均在 `FlowMuse-App` 下执行；使用项目现有 SDK。本轮不执行安装、ADB、HDC 或设备截图。

```powershell
flutter test test/features/whiteboard/collaboration test/features/whiteboard/views/whiteboard_writing_workflow_test.dart
flutter test test/features/whiteboard/views/whiteboard_writing_workflow_test.dart test/features/whiteboard/collaboration/services test/features/whiteboard/editor_core/ui/markdraw_controller_test.dart --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build apk --debug
flutter build web
flutter test tool/collaboration_cpu_benchmark.dart --reporter expanded
```

确定性测试包括：不可变结构共享、入站/出站连续消息截止、归属及绑定回填、本地落笔期间接收远端 256→512→1024→2048 点、光标及工具栏更新隔离、视口与远端选区跟随、成员昵称更新、终笔及撤销广播、湿墨交接、换房队列失效和 AES 大包互通。全量回归另覆盖现有保存/重开、导出净化、聚焦及笔刷一致性。

首次同时开启 V2 后运行整个 collaboration 目录时，`config/live_ink_flags_test.dart` 的“构建默认值关闭”断言如预期与显式开启参数冲突；正式双开关验证使用上列 V2 工作流/服务/控制器范围，默认关闭断言由默认全量测试保留验证，不删除或弱化断言。

| 验证 | 结果 |
| --- | --- |
| 改动前协作/书写回归 | 108 通过，1 既有跳过；不可变共享和连续批窗口新增断言在基线上失败 |
| 默认协作/书写定向回归 | 113 通过，1 既有跳过；随后补充的连续入站、视口/选区和湿墨交接断言也通过 |
| 最终默认全量测试 | 1718 通过，5 既有跳过 |
| V2 双开关工作流/服务/控制器 | 82 通过，1 既有跳过 |
| 静态检查 | 0 error，生产代码与测试无新增诊断；本机忽略目录 `build/nav_compact_screenshot_test.dart:199` 有一条既有 protected member 警告，未改动该临时脚本 |
| Android / Web 构建 | `flutter build apk --debug` 与 `flutter build web` 均通过；未安装或启动产物 |
| CPU 回放 | 基线与最终候选各 24 组，全收敛、零错误，见 6.2 |

全量测试首次发现 V3 兼容性用例通过原地修改快照检查哈希；改为 `copyWith` 构造变化场景，并新增原快照哈希不受污染的断言，保留原哈希敏感性验收后全量通过。5 个既有跳过包含需要真实输入/服务的验收项目，以及 `known_remote_undo_preserves_new_elements`：整场景撤销仍可能回退在本地书写期间新增的远端元素，本轮不把它算作通过，也不扩展为历史模型改造。
