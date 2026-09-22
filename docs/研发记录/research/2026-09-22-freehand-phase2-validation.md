# 自由书写第二轮：测量校准与页面工作流验证

本轮从 `feature/freehand-experience / 58760b7` 继续执行[第二轮计划](../plans/2026-09-22-freehand-performance-phase2.md)。需要本人持笔、录像及多设备参与的环节已经登记，本轮未发起新的人工确认。

## 结论

- 修复了完整白板页面直接销毁时，退出补存读取失效 `WidgetRef`、最后一笔未写入 SQLite 的问题。保存所需仓库在页面初始化时取得；保存与封面取同一场景快照，页面销毁后仍完成持久化，只在页面有效时更新 UI。
- 完整页面的五笔保存/重开、取消、撤销重做、后台/退出补存、PDF 底图和延迟识别均有自动回归。协作的落笔、远端合并、终笔和撤销消息广播也有内存加密链路验证。
- **性能验收仍未通过，`FLOWMUSE_LAYERED_WET_INK` 默认保持 false。** 本轮没有取得可用于正式五轮比较的数据，不宣称已证明性能收益或所有平台无回归。
- 另外复现了既有协作历史缺陷：本地落笔期间收到远端新增后，本地撤销可能同时删除远端元素，并广播其删除状态。它在缓存关闭与打开时均存在，不由本次保存修复引入。未在性能改动中重写协作历史规则。

## 测量入口修正

1. 安装的 Flutter SDK 中，`LiveTestWidgetsFlutterBinding` 默认使用 `fadePointers`；原 runner 没有覆盖。现在明确使用 `fullyLive`，保留应用请求的帧，输入通过没有测试十字光标的合成设备事件分发。仍经过真实 hit-test、Listener 和 EditorCanvas，不能解释为物理触控笔测量。
2. 与 `lib/main.dart` 一样先初始化 `PencilShader`，记录实际可用状态；原 runner 漏掉了这一步。汇总条件新增绘帧策略、输入来源及 shader 状态，避免混用不同条件。
3. 同一回放函数增加纯计时与空白 Listener 校准；逐点保留目标时间、实际分发时间、jitter 和同步分发耗时。校准显式标记 `replay_calibration_non_ui`，不进入正式画布统计。
4. 启动前持续保存 adb 日志，按本次进程 PID 查 VM service，直接连接 Dart driver。两次校准与整轮诊断均取得完整 JSON；不依赖可能被刷掉的 logcat 环形缓冲区。全程使用 `adb install -r -t`，未卸载或清除数据。
5. 原 `continuous_curve_30s` 电脑端 hash 为 `0ceeac0e...`，本次 Android 为 `d4487294...`，不能混用。新增独立的 `continuous_curve_30s_v2`，在测试样本生成时将坐标/压力固定到六位小数，冻结 hash 为 `6157deb0b0319c3e8dc0eaa6211ecd7ae9b9b3a0310f75d1880300754673356e`。不改生产采样，不改旧 fixture/hash。设备先校验 hash，失败立即停止。

## Android 诊断数据（无效轮次，不能用于收益结论）

设备为 OPD2404 / Android 16，profile / Vulkan Impeller。虽然前次设备报告为 120Hz，这次引擎报告及 `dumpsys display` 均为 **50Hz**，电池温度读数 29.1℃。冻结目标只覆盖 55–65Hz 及 100–165Hz，因此不拿型号中的高刷新率替代运行实值，也没有自行放宽目标。

首轮校准：

| 路径 | 注入 P95 / max | 分发 P95 / max | 收到事件 |
| --- | --- | --- | ---: |
| 仅计时 | 2.312 / 17.818 ms | 0.003 / 0.121 ms | 0（预期） |
| 空白 Listener | 3.394 / 20.053 ms | 0.242 / 8.032 ms | 3601 / 3601 |

即使空白页面，max 仍超过既定 16ms 上限；没有放宽 P95 4ms / max 16ms。

v2 独立校准的设备 hash 与电脑端完全一致。纯计时 P95/max 为 2.258/22.153ms，空白 Listener 为 2.517/21.368ms，后者收到 3601 个事件；精度问题已修复，但校准 max 仍失败，不能据此开启正式矩阵。

1000 元素、完整 Editor 控件、连续长笔 30 秒、五笔 × 两种模式各一轮：

| 笔刷 | 注入 P95：关闭 / 打开 | UI build P95：关闭 / 打开 | raster P95：关闭 / 打开 |
| --- | --- | --- | --- |
| 铅笔 | 46.790 / 16.200 ms | 54.027 / 22.161 ms | 14.874 / 18.990 ms |
| 圆珠笔 | 46.693 / 7.567 ms | 61.182 / 9.645 ms | 38.421 / 18.246 ms |
| 钢笔 | 45.862 / 7.900 ms | 57.995 / 9.816 ms | 39.783 / 17.381 ms |
| 毛笔 | 45.945 / 18.506 ms | 54.638 / 25.959 ms | 35.954 / 21.722 ms |
| 荧光笔 | 43.502 / 7.341 ms | 53.446 / 9.966 ms | 34.534 / 23.206 ms |

10 个场景都接受 3601 个样本、提交一条有效笔迹，codec 往返一致。同步输入分发 P95 为 0.091–0.350ms；长延迟主要出现在事件间调度/绘帧阶段。这只能作为热点方向，不能将差值直接解释为可靠收益。铅笔 raster 在候选模式下更高，也不符合无回归承诺。

汇总器判定有效轮次 **0/10**，原因包括注入超门槛、50Hz 不在冻结目标内、诊断工作区 dirty、旧长笔 fixture hash 不匹配；关闭模式还出现帧覆盖不足。按计划停止扩展 100/1000/5000 × 短长笔 × 五轮矩阵，避免堆积同类无效数据。

保存的场景中，除荧光笔外，A/B 的识别 `sessionId`、`startedAt`、`pointTimes` 随运行改变；后者来自 `FreedrawTool` 的系统时间。因此不能仅凭全场景 hash 不同断言笔形变化，也不能为了过门禁直接忽略这些识别字段。后续需明确测试时钟或单独验证识别时间语义；本轮继续保留严格失败结果。

原始证据均在 `FlowMuse-App/build/`（不提交大体积测试数据）：

- `freehand-phase2/calibration/writing-perf-2026-09-21T17-51-15.462384Z.json`
- `freehand-phase2/diagnostic/writing-perf-2026-09-21T18-01-42.957498Z.json`
- `freehand-phase2/diagnostic-summary.md` 与同名 CSV
- `freehand-phase2-calibration-device.log`、`freehand-phase2-diagnostic-device.log` 及对应 driver 日志
- 新样本设备校准位于 `freehand-phase2/calibration-v2/`

## 完整页面回归与边界

`test/features/whiteboard/views/whiteboard_writing_workflow_test.dart` 使用真实 WhiteboardPage、MarkdrawEditor、指针输入与临时目录中的真实 SQLite。账号使用本地访客替身，平台服务卡片通道被模拟，没有外发数据。

| 场景 | 覆盖 | 边界 |
| --- | --- | --- |
| 五笔书写 | 保存、全部笔迹几何/样式/数据重开一致；撤销/重做；取消不提交 | 合成 stylus 事件，不代表持笔手感 |
| 自动保存关闭 | 暂不自动写入；后台与直接销毁时补存最后提交笔迹 | 页面生命周期测试，不模拟系统强杀 |
| PDF | 图片解码、背景页边界、叠写、撤销/重做、文件数据重开 | 输入为模拟 PDF 栅格结果，PDF 解码器另有既有测试 |
| 延迟识别 | 请求等待时继续落笔；结果只替换所属笔画；撤销恢复、保存 | 识别结果由可控 Future 返回，不代表服务端速度/准确率 |
| 协作 | 内存房间真实加密/解密、落笔中合并远端、终笔及撤销广播 | 无真实网络、多人实机或网络抖动结论 |

关闭/打开分层开关均运行这些用例。既有协作撤销问题保留一个明确跳过的失败用例，不将其计为通过。单独运行可复现：

```powershell
flutter test test/features/whiteboard/views/whiteboard_writing_workflow_test.dart --run-skipped --plain-name known_remote_undo_preserves_new_elements
```

期望远端矩形保留，实际为 0；日志为 `build/freehand-phase2-known-remote-undo.log`。根因是 HistoryManager 恢复整场景快照，而 `applyRemoteElements/applyRemoteScene` 不更新历史；修复应涵盖远端新增、更新、删除、重做与同元素并发，且不能把历史栈重写成本放进高频收包/书写路径。这是后续协作历史专项的自动工作项，不是等待用户回答的问题。

## 后续门禁

1. 使用 v2 fixture，在稳定且受支持的刷新率、干净构建身份下重新校准。
   当前回放计时与 UI 同处一个 isolate，超时既包含调度误差也包含 UI 阻塞。后续用 CPU trace/平台输入时间核对，不把阻塞简单扣成“工具误差”，也不以 busy-wait 伪造低 jitter。
2. 保留识别时序验证，解决 A/B 身份与时间字段的可比性；不靠删除字段过门禁。
3. 校准通过后才扩展正式五轮矩阵，并检查首点、UI/raster、终笔、保存及内存；任何笔刷或场景退化都阻止推广。
4. 协作历史缺陷单独修复与验收；真实笔尖延迟、掌触、盲测、HarmonyOS 和多设备协作按计划中的人工清单继续保留。

## 收尾验证

- `flutter analyze`：No issues found。
- `flutter test --reporter expanded`：1809 项通过，5 项跳过；其中 4 项为既有跳过，1 项为上面的已知协作撤销缺陷。后者单独强制运行确实失败，未宣称修复。
- 分层开启的页面工作流、fixture 与汇总器专项：34 项通过，同一已知缺陷跳过 1 项。
- Android arm64 release 构建成功（172.6MB）；Web release 构建成功。本轮未改原生插件、平台通道、数据库 schema 或 Excalidraw 格式。构建仍有既有 CupertinoIcons 字体提示，未把它解释为静态检查错误。
- 正常 release 已用保留数据方式装回平板，重新打开 `Freehand-QA-20260922`，原五笔和铅笔点仍在，页面显示“已保存”。截图 `FlowMuse-App/build/freehand-phase2-reopened.png`。日志采集进程已结束。
- APK：`FlowMuse-App/build/freehand-experience-release.apk`。验证日志：`build/freehand-phase2-analyze.log`、`build/freehand-phase2-full-tests.log`、`build/freehand-phase2-layered-workflow-test.log`、`build/freehand-phase2-release-build.log`、`build/freehand-phase2-web-build.log`。

代码提交：`ae29732`（退出补存及页面回归）、`9aa9805`（校准与跨架构 fixture）。仍在功能分支，没有合并或推送。
