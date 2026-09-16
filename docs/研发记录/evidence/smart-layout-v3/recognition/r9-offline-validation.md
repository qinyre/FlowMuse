# R9 非实机验证与评测工具使用

日期：2026-09-16；代码基线：R8 `672b3b4`。

## 本次已执行

| 检查 | 结果 |
| --- | --- |
| `dart analyze scripts/smart-layout-v3/recognition_eval.dart` | 零问题 |
| `dart run scripts/smart-layout-v3/recognition_eval.dart --self-test` | 34 项检查通过 |
| `FlowMuse-App`: `flutter analyze --no-pub` | 零问题 |
| `FlowMuse-App`: `flutter test --no-pub --reporter expanded` | 1646 项通过 |
| `FlowMuse-Server`: `go test ./...`、`go vet ./...` | 均通过 |
| 真实对照数据入口 | 缺少 cases.jsonl，评测程序退出 2，未生成效果通过报告 |

自检包括：字符替换/插入/删除、增补平面字符、空参考、按字符数加权的语料 CER、缺预测计删除、重复 ID、指纹错误、非法区域、不确定真值、AI 草稿不能过关、dev 不影响 holdout 阈值、sourceRefs/IoU 对齐、未对齐、并列歧义、显式多区域合并正文仅计一次、部分转换与完整拆分、数字小错误、文字正确而列表错序。子进程还实际校验 JSONL 读写、报告确定性和退出码 0/1/2。

自检输入全部为合成数据，仅用于验证程序；不会保存为真实评测数据。自检的临时文件只是数据和报告，完成后删除，不生成临时脚本。没有请求真实模型，也没有进行设备操作。

## 常驻入口

从仓库根运行（Dart 标准库，无额外依赖）：

```text
dart run scripts/smart-layout-v3/recognition_eval.dart --self-test
dart run scripts/smart-layout-v3/recognition_eval.dart --truth docs/研发记录/evidence/smart-layout-v3/recognition/cases.jsonl --v1 docs/研发记录/evidence/smart-layout-v3/recognition/predictions-v1.jsonl --v3 docs/研发记录/evidence/smart-layout-v3/recognition/predictions-v3.jsonl --out docs/研发记录/evidence/smart-layout-v3/recognition/results/report.json
```

退出 0：数据核对完成且留出集阈值通过；1：评测有效但未达阈值；2：数据缺失、非法或真值核对未完成。Windows 脚本调用方应检查 `$LASTEXITCODE`，不要用 PowerShell 会话本身的退出值代替评测器退出值。缺输入/非法输入时不刷新旧报告，不应忽略退出码阅读上次报告。

工具不会收集样例、调用模型、猜测缺失正文或自动把 AI 草稿改成人工核对完成。20 页以上、dev/holdout 均存在、全部 humanVerified 且无未确认文本区间才允许做通过判定；预测缺页仍按空预测计删除，不能从分母中移除。

## 数据约定

文件均为 UTF-8 JSONL，一行一个 caseId。完整字段遵循实现 spec §12。

- 真值：`caseId / split / sourceRef / contentFingerprint / referenceText / reviewStatus / uncertainRanges / regions / expect`。
- 预测：`caseId / contentFingerprint / pipeline / model / recognizedText / converted / preserved / regions / structure`。页面 converted/preserved 为布尔值；两者都真表示部分转换。
- bounds：`{left, top, width, height}`，各版本使用同一页面坐标系，尺寸为正。
- 真值区域含 `evalRegionId / referenceText / legible / sourceRefs / bounds`；预测区域含 `regionId / recognizedText / status / converted / sourceRefs / bounds`。
- `expect.orderedLists` 与 `structure.orderedLists` 为二维字符串数组，无列表填 `[]`；标题可使用 `title`。
- 如需显式裁决，在真值行写 `explicitAlignment: {v1: {运行时区域ID: [真值区域ID,...]}, v3: {...}}`。不同版本独立映射；预测行自报的 evalRegionId 不作为权威对齐依据。
- 无显式映射时先按 sourceRefs Jaccard ≥0.5，再按 IoU ≥0.5。并列最优单列歧义，不猜测；跨多个真值的合并预测需显式映射。歧义/未对齐预测作为多余文本计入区域指标，未对齐真值计漏识别。
- CER 使用 Unicode code point，保留大小写、数字与标点，统一忽略空白（防止分区合并/拆分人为增加换行错误）；另列去标点 CER。未确认范围按原参考正文 code point 下标标注，并阻止验收通过，不静默删除难例。

逐页报告包含模型标识、对齐分组与歧义；汇总提供 dev/holdout/all 三份、全页/可辨识区域/转换内容 CER、转换覆盖率、错误/严重错误转换率、保留率、缺预测和结构错误计数。阈值只判 holdout：CER ≤5%；若 V1 CER >5%，相对降幅还需 ≥20%；转换覆盖率 ≥90%；数字、标题及列表精确匹配，且无歧义/多余区域与缺失对照预测。错误转换率与严重错误转换率分别报告，不混用。

混合“可辨识/不可辨识”的跨区域合并不能自动拆正文；工具单列 mixedLegibilityGroups，留出集存在这种情况时不判通过，需整理对齐数据。端到端耗时、中位数/P95、模型调用数和峰值图像内存不是离线文本工具能测得的结果，必须由真实运行采集，当前明确标记未测量。

## 尚未完成（不与自动回归混淆）

1. 20 页固定输入（可重放 Scene/原始素材）、核对后的参考正文，以及相同输入指纹的 V1/V3 真实预测。仓库尚无对应 JSONL，不能计算可信 CER，也不能宣布效果优于 V1。
2. 真实 provider 链路与性能采集；本次未调用 provider，未宣称其可用或不可用。
3. 实机验证按用户要求暂缓，包括比赛设备上的完整交互和 #14 字号观察。

R9 当前结论：离线评测工具及软件自动验证完成；真实识别对照、性能和实机仍待完成。V1 与生产识别/排版代码本轮未修改。
