# 研发记录导航

本目录保留实现依据与证据。日期代表当时基线，不表示目前仍需执行；当前产品范围以[项目需求](../项目说明/项目需求.md)和[决赛进度](plans/2026-10-24-finals-product-optimization-plan.md)为准。不要把历史“未合并”、包路径或实验指令当成当前部署状态。

## 常用主题

| 主题 | 当前阅读入口 |
| --- | --- |
| 决赛主线与剩余功能 | [总计划](plans/2026-10-24-finals-product-optimization-plan.md) |
| 协作感知与笔交互 | [F1](plans/2026-10-24-f1-collaboration-awareness.md)、[F2](plans/2026-10-24-f2-stylus-double-tap.md)、[重压橡皮](plans/2026-10-25-issue84-pressure-eraser.md) |
| 同步稳定性与拥堵 | [链路分析](plans/2026-10-21-collaboration-fluidity-and-convergence-plan.md)、[修复与恢复](plans/2026-10-22-collaboration-repair-congestion.md)、[后端开销](plans/2026-10-22-backend-relay-overhead.md) |
| 保存与备份 | [数据完整性](plans/2026-10-20-finals-data-integrity.md)、[失败退出保护](plans/2026-10-21-save-failure-exit.md) |
| PDF 与取色 | [本地书写](plans/2026-10-25-pdf-local-writing-jank.md)、[取色读图优化](plans/2026-10-25-web-eyedropper-performance.md) |
| 设置与资料库 UI | [最新设置发布](plans/2026-10-27-settings-ui-polish.md)、[侧栏动效](plans/2026-10-26-library-sidebar-motion.md)、[搜索/多选](plans/2026-10-26-search-selection-polish.md) |
| 早期综合调研 | [笔迹管线结论](research/pen/codex-best.md)、[协作结论](research/collaboration/codex-best.md)，仅作历史决策依据 |
| 智能排版契约与门禁 | [协议](specs/smart-layout-v3/protocol/protocol.md)、[Agent 手册](plans/smart-layout-v3-agent/README.md)、[禁飞区](../../.agent/forbidden_zones.md) |
| 故障与授权 | troubleshooting/、third_party/；保留可复现原因与使用边界 |

plans/ 存实现计划，specs/ 存设计或契约，research/ 存调研与验证，troubleshooting/ 存排障，evidence/ 存脱敏证据，archive/ 存迁移历史。无需为同一结论再复制“最终版/最佳版”；新的研究应链接采用的实现与测量条件。

已清理原始重复提案的来源可在 main `97c2a6c4` 的 Git 树中查阅；详见[清理清单](plans/2026-10-27-documentation-refresh.md)。保留历史完整性不要求把每轮 AI 草稿留在当前文档入口。
