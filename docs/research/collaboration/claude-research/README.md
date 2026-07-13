# 协作实时同步优化研究

> 分支: main
> 日期: 2026-07-12
> 问题: 实时同步速度过慢，容易被动断开连接

---

## 文档索引

| 文档 | 内容 | 预计阅读时间 |
|------|------|------------|
| [01-问题诊断与根因分析](01-问题诊断与根因分析.md) | 当前架构数据流、7 个根因详解、优先级矩阵 | 15 分钟 |
| [02-优化方案](02-优化方案.md) | 三阶段优化方案(含代码示例)、收益预估、实施建议 | 25 分钟 |
| [03-成熟产品参考分析](03-成熟产品参考分析.md) | Figma/Excalidraw/Google Docs/Liveblocks 技术对比 | 15 分钟 |

---

## 核心发现摘要

### 主要问题(按严重程度)

1. **Socket.IO JSON 编码导致 6x 数据膨胀** — 二进制数据被序列化为 JSON 数字数组
2. **消息解密串行队列** — 每条消息等前一条解密完才开始
3. **每 20 秒全量场景推送** — 即使场景无变化也发送全部元素
4. **无消息批处理** — 每次编辑立即独立发送
5. **连接稳定性不足** — 默认重连参数不适合移动网络

### 推荐实施路径

```
Phase 1 (1-2天)        预期: 延迟降低 50-70%
  ├─ 二进制传输替代 JSON 数组编码
  ├─ 并行解密 + 保序应用
  └─ Dirty Set 替代 O(n) 全量扫描

Phase 2 (3-5天)        预期: 延迟再降 30-50%
  ├─ 50ms 消息批处理窗口
  ├─ 取消 20s 全量同步(改为版本校验)
  └─ 新用户加入差量同步

Phase 3 (1-2周)        预期: 断连率降低 80%
  ├─ Socket.IO 参数调优 + 网络状态监听
  ├─ 快照增量保存
  └─ MessagePack 替代 JSON 序列化
```

### 不需要做的事(短期)

- **Yjs CRDT 集成**: 当前 LWW 策略足够，问题在工程实现不在算法
- **OT 算法切换**: 比 LWW 复杂得多，Google Docs 选择 OT 是因为文字编辑场景

---

## 关键代码文件

| 文件 | 位置 |
|------|------|
| Socket.IO 传输层 | `FlowMuse-App/lib/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart` |
| 协作核心仓库 | `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart` |
| 场景合并算法 | `FlowMuse-App/lib/features/whiteboard/collaboration/services/scene_reconciler.dart` |
| 加解密 | `FlowMuse-App/lib/features/whiteboard/collaboration/services/collaboration_crypto.dart` |
| 服务端 Hub | `FlowMuse-Server/internal/collab/hub.go` |
| 服务端 HTTP API | `FlowMuse-Server/internal/collab/http_api.go` |
