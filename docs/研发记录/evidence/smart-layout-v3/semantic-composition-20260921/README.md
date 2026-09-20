# V3 语义成组构图：A+B 离线检查记录

日期：2026-09-21。分支：`feature/v3-semantic-composition`。基线：`3356c9a`。
范围：计划 A+B；未推送、未部署、未操作平板或用户笔记。

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
- 测试日志、PNG 均位于忽略的 `build/`，不将构建副产物入库。

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

## 后续检查点

- C：同一 structure 请求的 composition 能力协商、章节、多图共用一次正文、软换行提示及语义纠错闭环；服务端目前未改动。
- D：实际渲染评分、原稿只读基线、推荐理由，以及 8 开发 + 4 留出页的统一效果评估；现有 9 项测试不是 9 个效果页。
- 真实猫图的原始元素元数据未取得，根因仍未复现；在线 provider 关系测试和平板预览→应用→撤销→重开未执行。
- 同机同字体基线/新实现各至少 10 次本地候选性能对比未执行，不宣称达到 p95 预算。

不增加逐任务子代理或执行回执。A+B 是计划允许的第一轮试用/换上下文检查点，不是全计划完成。
