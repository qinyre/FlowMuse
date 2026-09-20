# V3 语义成组构图：A+B 离线与首轮实机记录

日期：2026-09-21。分支：`feature/v3-semantic-composition`。基线：`3356c9a`。
范围：计划 A+B。代码提交 `5601f36` 已推送，PR #39 未合并；经用户授权，已覆盖安装 Android release 并测试原猫狗笔记。后端源码已与分支匹配，无需重建。C/D 仍未实现。

## 已实现

- A：V3 共用页面范围、固定内容保护、真实物化内容/图文关系/阅读序检查、过期候选拒绝，以及应用时不被当前工具默认样式覆盖。
- B：先组内真实测量，再整页流式放置；图上文下、左右图文、同级组两列；统一字号/行长/间距、实际图片像素限制、跨家族去重、放不下时整组保留。沿用现有 reducer、renderer、源账本与撤销链，无新增模型调用。
- 安全文字投影仅落基础契约；现阶段没有新协议提示，默认保留原有换行。C 将接入批准的 OCR 软换行、章节和多图共同说明。

## 验证结果

以下在 `FlowMuse-App/` 执行，退出码均为 0：

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter failures-only
flutter test --no-pub --dart-define=EXPORT_LAYOUT_EVIDENCE=true "--dart-define=LAYOUT_EVIDENCE_CJK_FONT=C:\Windows\Fonts\msyh.ttc" test/features/whiteboard/smart_layout/composition/semantic_composition_integration_test.dart --reporter failures-only
```

- 静态分析零问题；全量 1733 项通过、1 项原有跳过。
- 集中集成测试 9 项通过：双图三种构图/重复运行确定性/实际门禁/应用撤销重做；OCR、裁剪与强调色；低像素图；文字在图片前的阅读序；损坏资产；连续标题避障；超长内容整组保留；破坏最终位置的拒绝负例；原生闭包别名与输出映射。
- 既有长文测试改为新页面尺度下的 32 字行长上限，仍检查真实换行；极短页审阅测试改为只提供一个真实方案，不再要求重复候选。多候选切换及键盘选择仍由既有 session view 测试覆盖。
- 测试日志和完整导图位于忽略的 `build/`；仅挑选两张不含用户内容的合成 fixture 对照图入库供 PR 审阅，不提交其他构建副产物。

## 看图记录与证据边界

源 fixture 在 `test/features/whiteboard/smart_layout/composition/semantic_composition_integration_test.dart`，由真实原生文字、可选手写替代源、两幅合成插画构成。角色/关系独立给定，不是模型输出；不证明线上模型能识别猫狗，也不是用户原笔记复现。

导图使用真实 `DraftSceneRenderer`，字号测量与渲染均载入本机微软雅黑为 `LayoutEvidenceCJK`。测试导出时仅加纸色底，未移动截图内元素。默认 CI 不依赖本机字体；Windows 字体的效果不冒充 Android/OHOS 实机字体。

本机输出（可通过上述命令重建）：

| 文件（相对 `FlowMuse-App/build/semantic-composition-evidence/`） | 看图结论 |
| --- | --- |
| `01-original.png` | 两幅图很小且与说明远离，标题与正文缺少共同对齐线 |
| `01-single.png` | 标题、两幅图和对应说明按完整组顺序排列，比例/文字/强调色保留；但图片在短说明场景占比偏大，不能据此断言它该排第一 |
| `01-mediaSide.png` | 两组左右图文关系明确，同级图片等宽、段首对齐；标题层级和组间距清楚，下半页允许留白 |
| `01-peerGrid.png` | 两个同级图文组并列，文字各自在对应图下；适合短说明，页面较稀疏。是否优先推荐应由 D 的实际占用评价决定 |

以上是原稿与新构图对照，**没有**完成旧版候选算法与新默认第一候选的完整对照评测。B 的局部可编辑构图已验证；当前软评分仍是旧算法，不把“有一张合理候选”记成“默认推荐已验收”。

PR 对照图（均为离线合成样例，不是平板或真实 provider 证据）：[输入原稿](offline-original.png)、[同级图文并列](offline-peer-grid.png)。

## 2026-09-21 原猫狗笔记实机测试

### 版本与部署

- 设备：OPD2404，Android 16 / API 36，arm64，release 包；源提交 `5601f36`。APK SHA-256：`8cf958c3ecc5e70523f0b667065fbce28293fe96bf6157bcedb98c7b089517fa`。
- 构建：`flutter build apk --release --no-pub --target-platform android-arm64 --dart-define=FLOWMUSE_COLLAB_SERVER_URL=http://124.221.236.179:48931`，成功；`adb install -r` 成功，不卸载、不清数据。沿用已安装旧包的实际服务地址，而非无法连通的 443 域名端口。
- 服务端：运行目录不是 Git checkout；逐文件比较 55 个 Go 源码/依赖文件（仅统一 CRLF/LF）与当前分支完全一致，`/health` 返回 `ok`，本次没有需要部署的后端差异，因此未重启容器、未改配置或数据库。运行镜像 SHA 前缀 `d995dba9f859`；真实 provider 为 `doubao-seed-2-1-turbo-260628`。
- 更新前保留旧 APK，并通过系统“分享 .excalidraw → 保存到文件管理”导出原稿。备份与实机截图仅保存在本机 `FlowMuse-App/build/`；不将用户笔记 JSON、图片资产或 APK 随 PR 上传。

### 实测结果

| 检查 | 真实结果 |
| --- | --- |
| 原稿范围 | 130 个活动元素：127 条笔迹、2 张图片、1 个页面框；猫图缺少 `customData.flowMuse.pageId`，狗图明确为 `page-1`，两图均在该唯一页面内且未锁定 |
| 旧漏图原因 | 原范围的精确 pageId 过滤会排除猫图；本轮真实元数据支持该原因，不再只是推测。新链临时纳入缺归属图片，没有回写原始 pageId |
| 本轮识别 | 真实在线请求 1 次 read + 1 次 structure；得到标题 41 源、图注 40 源、狗图 1 源、图注 46 源、猫图 1 源，共 129 源、5 块，0 保留；页面框不算识别源 |
| 关联与候选 | 本页两组说明均与正确图片相邻，没有遗漏或串图；提供单栏与同级图文并列 2 个候选。说明本轮被识别为 caption，不是 body，因此未生成左右正文轨道候选 |
| 预览与应用 | 选择并列候选应用成功；实际标题、文字颜色、字号、图文顺序和相对位置与预览一致；未复现旧工具默认样式覆盖。画布初始 100% 放大，缩小后可看完整页面 |
| 撤销与重开 | 应用→单次撤销→重做→再撤销→退出笔记→重新打开均执行，最终留在原稿。重新导出后，130 个原活动元素的已有字段逐项相同，2 张图片 dataURL 相同；资源 `created` 导出字段变化，不宣称整个 JSON 逐字相同 |

仅此一次真实页面运行，不能用“两组正确”宣称达到计划的多页 precision/recall 或重复 3 次验收要求。

客户端日志：识别链 `total_ms=24066`，`model_calls=2`；本地候选 `elapsed_ms=516`。服务端 read 为 6.680 秒；structure 约 15.892 秒，其中发送约 3.655 秒、等响应约 12.230 秒，结构请求约 1.70 MB。这里都是单样本耗时，不是 p95；主要时间仍在模型/请求传输，而非本地排版。

### 效果尚未达标的部分

1. 默认仍推荐单栏；本页单栏图片偏大、预览缩到适合内容后字偏小，并列更易对照。这验证了 D 的评分/推荐改造仍有必要。
2. 两段说明保留了原手写的 2/3 行碎行，没有利用可用宽度重排；猫说明末字独占一行，C 的软换行消费与角色边界需结合 caption 实例核对，不能只测试普通正文。
3. 并列两组的文字顶部一致，但因说明行数不同，图片顶部不一致；还需在组内布局/效果收口中解决同级媒体对齐，不能只靠分数调整。

本机截图：`build/flowmuse-ab-review.png`（默认单栏）、`build/flowmuse-ab-peer-grid-clean.png`（并列预览）、`build/flowmuse-ab-applied-readable.png`（应用后）、`build/flowmuse-ab-redone.png`、`build/flowmuse-ab-final-original.png`（最终原稿）。原始及恢复后导出：`build/semantic-composition-catdog-{original,restored}.excalidraw`。

结论：**漏图/图文失散、应用不一致及内容恢复在本页得到实际验证；“默认即达到预期排版效果”没有通过，不能提前宣告 C/D 或整体效果完成。**

## 后续检查点

- C：同一 structure 请求的 composition 能力协商、章节、多图共用一次正文、软换行提示及语义纠错闭环；服务端目前未改动。
- D：实际渲染评分、原稿只读基线、推荐理由，以及 8 开发 + 4 留出页的统一效果评估；现有 9 项测试不是 9 个效果页。
- 原猫狗页已按上节执行一次真实 provider + 实机流程；仍缺交叉摆放、多图共说明、长文、已排好页以及核心页重复运行，不把这次局部测试算作完整实机验收。
- 同机同字体基线/新实现各至少 10 次本地候选性能对比未执行，不宣称达到 p95 预算。

不增加逐任务子代理或执行回执。A+B 是计划允许的第一轮试用/换上下文检查点，不是全计划完成。
