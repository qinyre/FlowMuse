# 智能排版 v3 比赛交付 Runbook（V3-705A）

> 口径：比赛交付（competition_delivery）。**不宣称生产发布完成**；
> 生产部署、生产指标窗口与消费者 census 不在比赛范围。
> 机器审计：`docs/研发记录/evidence/smart-layout-v3/competition/v3-705a-delivery-audit.json`
> （生成命令：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/CompetitionDeliveryAudit.ps1`）。

## 1. 演示步骤（可重放）

四类演示均为常规测试命令，任何 clone 可复跑（字体仓库捆绑零网络；
fixture 服务测试内自建 loopback；Go 需 1.25 在 PATH）：

| 步骤 | 命令 | 证明 | 证据 |
|---|---|---|---|
| 客户端演示 smoke | `cd FlowMuse-App && flutter test test/features/whiteboard/smart_layout/rollout` | 四场景：默认关（零请求零 Draft）/ 阳性开启真实全链（入口→候选→commit→undo→reopen 深度一致）/ kill 跳闸只关不换 / 服务故障 500→fail closed Scene 零副作用→失败率告警→自动关闭→重开 disabled | `competition/v3-700a-demo-smoke.json` |
| 服务端 analyzer 启动 | `cd FlowMuse-Server && go test ./internal/recognition/...` | httptest 启动真实 `RegisterSmartLayoutV3` 端点：合法 200+冻结 schema、非法 400+错误 envelope | `competition/v3-700a-server-smoke.json` |
| 合成稳定性矩阵 | `cd FlowMuse-App && flutter test test/features/whiteboard/smart_layout/rollout/synthetic_stability_evaluator_test.dart` | 48 冻结样本 × 8 故障 384 次重放：critical=0，错误率 1.0（全注入必失败或被拒），每故障结果类符合语义 | `competition/v3-702a-stability-report.json` |
| 客户端 v2 隔离 | `cd FlowMuse-App && flutter test test/features/whiteboard/smart_layout/v2_client_isolation_matrix_test.dart` | 公开入口面零 v2 路由符号/零 v2 import/唯一 v3 端点串/v2 私有 9 lib+8 测试原位保留 | `competition/v3-703a-client-isolation.json` |
| 服务端路由隔离 | `cd FlowMuse-Server && go test ./internal/recognition/ -run RouteIsolation` | 同 mux 6 旧端点+v3 无路径冲突；各路由独立命中（GET 405 / 旧 POST 502 / v3 smoke 全绿） | `competition/v3-704a-route-isolation.json` |

证据均为一次性生成（`FLOWMUSE_GENERATE_V3_70xA_EVIDENCE=1` env 门控），
常规运行只读校验不重写（防 sha 漂移）。

## 2. 架构与接口速览

- 客户端唯一公开入口：`SmartLayoutPublicEntry`（gateways，V3-100A）
  只暴露 editor/http 两个 gateway；切流门禁 `SmartLayoutRolloutEntryGate`
  （rollout，V3-701A）组合 capability+kill switch，不过则零请求零 Draft。
- 分析链：真实 Session 四检守卫 → `V3AnalysisRepository`（有限重试+迟到
  响应防线）→ `/api/ink/smart-layout/analyze/v3` → 真实候选链 →
  compare-and-commit（undo 单事务精确回滚）。
- 服务端：`RegisterSmartLayoutV3`（strict decode/sanitize，V3Err* 冻结
  envelope）；旧端点 6 条路由独立共存。

## 3. 已知边界（诚实披露）

1. `v3_flow_policy` 为 v3 放置语义确定性代表策略，非生产全管线复刻
   （606A dev 线限制；T4 优效 RD=-0.1458, p=0.0005 与预注册一致）。
2. `HUMAN_VALIDATION_NOT_PERFORMED`：冻结实验未做人工验收。
3. `PRODUCTION_RELEASE_NOT_AUTHORIZED`：比赛交付口径。
4. 平台矩阵：android/web 实构建 built；windows/ohos/ios/macos 按
   `release_deferred` 如实记录（605A）。
5. 客户端 v2 私有实现原位保留（不删除/不迁移/不加兼容 wrapper，703A）。
6. 服务端旧端点仅为比赛版本兼容保留（不做 census/不返 410/不删除，704A）。
7. 可观测性为进程内合成指标（零网络）；生产端点不在比赛范围（700B）。

## 4. 回滚说明

- 切流回滚策略：`SmartLayoutRollbackPolicy`（701A）——独立切流提交
  allowlist 机器判定；回滚完整性=残余 diff 为空（恰为切流提交逆集）；
  关闭重开四条检查单。
- 熔断：`SmartLayoutKillSwitch` 只关不换（类型面无 v2 回退 API）；跳闸
  后入口 disabled；失败率滑动窗口告警自动关闭（700A 场景 4 可重放）；
  复位需人工 `reset()`（锁定口径）。

## 5. 任务与门禁索引

- 69 张任务卡状态/证据/提交 SHA：见机器审计 JSON `task_cards.index`
  （逐卡 result.json/commands.json 路径可索引）。
- 门禁 G0～G5 全 passed（`evidence/smart-layout-v3/gates/*/gate-result.json`）；
  FINAL 复验：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId FINAL`（需 go 在 PATH）。
