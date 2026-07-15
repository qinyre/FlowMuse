# Sprint 2 安全加固挑战实施计划

## Context

Sprint 2 验收要求按 OWASP Top 10 自查并修复至少三个安全问题，附修复前后对比。本次仅修改服务端 HTTP 信任边界，不部署线上服务。

## 目标

1. 禁止通配 CORS 与 credentials 同时启用。
2. 房主密钥哈希使用恒定时间比较，降低计时侧信道风险。
3. 限制账户和房间元数据 JSON 请求体大小。
4. 为三项修复提供自动化回归测试与验收报告。

## 关键文件

- `FlowMuse-Server/cmd/flowmuse-collab-server/main.go`
- `FlowMuse-Server/internal/config/config.go`
- `FlowMuse-Server/internal/auth/http_api.go`
- `FlowMuse-Server/internal/collab/http_api.go`
- `FlowMuse-Server/internal/storage/room_store.go`
- `docs/acceptance/sprint2-security-hardening.md`

## 验证

```powershell
cd FlowMuse-Server
go test ./...
go vet ./...
```

## 实施步骤

1. 先写能够覆盖三项安全边界的最小测试。
2. 实施 CORS、密钥和请求体限制。
3. 运行格式化、全量测试和静态检查。
4. 记录 OWASP 分类、修复前后行为与验证证据。
