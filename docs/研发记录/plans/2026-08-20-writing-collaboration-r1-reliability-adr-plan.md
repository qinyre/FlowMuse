# R1：最终协作操作可靠交付 ADR 前置计划

> 日期：2026-08-20  
> 状态：计划已批准；独立条件未触发，默认不启动  
> 预计：ADR 1～1.5 人日；条件 POC/设计 1.5～4 人日  
> 硬约束：ADR 批准前不修改生产 ACK、journal、outbox、数据库表或 wire semantics

## 1. 目标

确定最终 `SCENE_UPDATE` 的“已发送/服务端已接收/已持久化/对端已应用”语义，避免把 Socket.IO ACK 误当持久化或收敛。方案必须保持 AES-GCM 零知识：服务端不能解密正文，也不能按密文内 `opId` 去重。

R1 与 P0/P1/P3 无实现依赖；只有产品明确批准可靠性项目才启动。P3 的 volatile live ink 不进入 R1 的最终提交语义。

## 2. Task R1-0：现状和威胁模型

**负责人/复核：** Hongyu Chen / Enchograph；**估时：** 0.5d。

**执行状态：** `not_triggered`；尚未获得产品对“最终协作操作可靠交付”独立项目的明确批准，按硬约束不启动 ADR 工作。

### 只读检查

- `FlowMuse-App/lib/features/whiteboard/collaboration/services/realtime_transport.dart`
- `FlowMuse-App/lib/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart`
- `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`
- `FlowMuse-App/lib/features/whiteboard/collaboration/services/collaboration_crypto.dart`
- `FlowMuse-App/lib/features/whiteboard/collaboration/services/encrypted_scene_store.dart`
- `FlowMuse-Server/internal/collab/events.go`、`hub.go`

### 输出

- Create: `docs/研发记录/research/collaboration-delivery-current-state.md`
- Create: `docs/研发记录/research/collaboration-delivery-threat-model.md`

必须画出发送、socket buffer、hub、可选持久化、接收、解密、reconcile 和 UI apply 的状态；列出断线、重复、乱序、重放、密文/外层 ID 篡改、磁盘失败、ACK 丢失、客户端崩溃、房间密钥轮换与恶意成员。每个现有 API 标明它当前真正保证什么。

## 3. Task R1-1：提交语义 ADR

**负责人/复核：** Hongyu Chen / Enchograph；**估时：** 0.5～1d；**前置：** R1-0。

**执行状态：** `not_triggered`；R1-0 未启动，未修改 ACK、wire 语义或 `.agent/decisions.md`。

### 文件

- Create: `docs/研发记录/specs/2026-08-20-collaboration-delivery-semantics.md`
- Modify after approval: `.agent/decisions.md`（只追加最终选择和链接）

### 必须决策

1. 产品承诺是 at-most-once、at-least-once、best-effort eventual，还是“服务端密文 durable 后 ACK”；明确不承诺 exactly-once UI apply。
2. ACK 的精确发出点和客户端 UI 文案：socket accepted、memory accepted、durable、peer applied 四者不能混称。
3. 幂等 ID 放密文内还是不透明外层；若外置，如何由 AES-GCM AAD 认证，防止服务端/成员替换映射。
4. 服务端存什么密文、保存多久、按什么 opaque key 索引；密钥仍只在客户端。
5. 重连如何重放、何时删除 outbox、历史如何截断、最终如何证明 Scene 收敛。
6. 六平台离线存储/安全能力和数据删除合规。

ADR 至少比较：A 保持现状；B 客户端 outbox+服务端接收 ACK；C 服务端密文 journal+durable ACK。给出复杂度、失效模式、隐私、运维成本和明确选择；产品负责人、Flutter 协作负责人、Go 服务端负责人、安全复核人签字后才算批准。

## 4. Task R1-2：不透明 envelope/AAD/幂等 POC（条件）

**负责人/复核：** Enchograph / Hongyu Chen；**timebox：** 0.5～2d；**前置：** ADR 候选需要服务端去重。

**执行状态：** `not_triggered`；没有已批准 ADR 候选与冻结边界，不创建 POC 或生产类型。

### 仅测试文件

- Create: `FlowMuse-App/test/features/whiteboard/collaboration/services/delivery_envelope_poc_test.dart`
- Create: `FlowMuse-Server/internal/collab/delivery_journal_poc_test.go`

不得在 `lib/` 或生产 Go package 增加 POC 类型/表。Dart 测试内用现有 crypto 原语构造候选 `{version, opaqueOperationId, nonce, ciphertext}`，并把 version+opaqueOperationId 作为 AAD；Go 测试只把 envelope 当 bytes，以 opaqueOperationId 验证重复接收和返回同一状态。

POC 必须证明：

- 同一 op 重试密文不同或相同时的去重键语义明确；
- 替换 opaqueOperationId/version/nonce/ciphertext 任一项都会在客户端认证失败；
- 服务端无需正文/op 类型即可持久化和去重；
- 伪造 ACK、ACK 丢失、并发重复不会导致错误删除客户端候选 outbox；
- 现有最大合法最终消息和 ADR 候选边界值下的开销、存储与吞吐可接受；边界值必须在 ADR 中先冻结，POC 不自行发明常量。

POC 失败则回到 ADR，禁止通过取消 AAD 或把明文 opId 暴露给服务端绕过。

```powershell
Push-Location FlowMuse-App
flutter test test/features/whiteboard/collaboration/services/delivery_envelope_poc_test.dart
Pop-Location

Push-Location FlowMuse-Server
go test ./internal/collab -run DeliveryJournalPOC
Pop-Location
```

## 5. Task R1-3：journal/checkpoint 设计（条件，仅文档）

**负责人/复核：** Hongyu Chen / Enchograph；**估时：** 0.5～1d；**前置：** ADR 选择 durable 服务端语义且 R1-2 Go。

**执行状态：** `not_triggered`；没有 durable 服务端语义决策。

在 ADR 附录定义最小 schema、唯一键、事务边界、durable ACK 点、room/user 授权、TTL/compaction、quota、备份恢复、key rotation、删除请求和指标。不得在本任务创建 migration 或数据库客户端依赖；实现另行评审估时。

## 6. Task R1-4：客户端 outbox 设计（条件，仅文档）

**负责人/复核：** Hongyu Chen / 任逸青；**估时：** 0.5～1d；**前置：** ADR **明确选择客户端 outbox/retry**，并且 R1-2 Go（若使用外层幂等 ID）。

**执行状态：** `not_triggered`；没有 outbox/retry 决策，生产客户端保持现状。

定义单一状态机 `queued → sending → accepted/durable → removable`、重试 backoff+jitter、容量/TTL、应用崩溃恢复、密钥不可用、登出/删房间清理、最终 Scene snapshot checkpoint。若 ADR 只选保持现状或无 outbox 的 server durable 方案，本任务标 `not_triggered`。

不允许以 ACK 到达直接表示 peer applied；UI 状态必须使用 ADR 的精确术语。

## 7. Task R1-5：确定性故障规格（条件，仅测试规范）

**负责人/复核：** Hongyu Chen / 任逸青；**估时：** 0.5d；**前置：** ADR 批准。

**执行状态：** `not_triggered`；ADR 未批准；P3 的 live-ink 故障夹具不反向扩展最终提交语义。

### 输出

- Create: `docs/研发记录/specs/2026-08-20-collaboration-delivery-fault-matrix.md`

覆盖 drop/duplicate/reorder/delay、断线、客户端/服务端在各 ACK 点崩溃、磁盘满/事务失败、重放、过期、密钥变化和恶意外层篡改；每项写初始状态、操作、预期 durable/outbox/Scene 状态和可收集证据。

若 P3 已有 `fault_injecting_realtime_transport.dart`，规范可引用它作为未来实现夹具；若不存在，只写规范/伪接口，不创建生产 transport，也不反向依赖或启动 P3。自动化实现属于 ADR 后独立执行计划。

## 8. 审批门禁与禁止项

R1 计划 completed（允许进入实现排期）要求：现状/威胁模型/ADR/故障矩阵齐全；条件 POC 有原始测试结果或明确 not_triggered；R1-3/4 与 ADR 选择一致；零知识与 ACK 语义获非作者安全复核；`.agent/decisions.md` 已同步批准结论。

ADR 前禁止：修改 transport send 返回生产 ACK、创建数据库 migration、实现 outbox/retry、按加密正文 opId 要求服务端去重、复用 P3 live 事件承载 final、把 socket ACK 描述成持久化或对端应用。

## 9. 常规校验命令

```powershell
Push-Location FlowMuse-App
flutter analyze
flutter test test/features/whiteboard/collaboration
Pop-Location

Push-Location FlowMuse-Server
go test ./...
go vet ./...
Pop-Location
```
