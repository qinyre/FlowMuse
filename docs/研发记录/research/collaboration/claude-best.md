# FlowMuse 实时协作优化方案 — 综合最佳版

> **整合来源**: codex-research + zcode-research + claude-research 三方调研
> **日期**: 2026-07-12
> **分支**: markdraw-harmonyos-probe
> **原则**: 取三方交集作为高优先级，各方的独特洞察作为补充，去重后形成统一方案

---

## 一、三方共识（交集 = 必须做）

三份独立调研在以下结论上**完全一致**：

| 共识 | codex | zcode | claude |
|------|-------|-------|--------|
| 出站广播必须加节流/批处理（50ms 窗口） | ✅ ChangeAccumulator | ✅ coalesce timer | ✅ batch window |
| 不能每 20s 全量同步 | ✅ 改闲置触发 | ✅ 改自适应间隔 | ✅ 改版本校验 |
| 不要迁移 Yjs/CRDT（当前阶段） | ✅ | ✅ | ✅ |
| LWW 对白板场景足够 | ✅ | ✅ | ✅ |
| Socket.IO 默认重连不够，需自定义 | ✅ outbox+ACK | ✅ 等 rejoin 确认 | ✅ 网络监听+指数退避 |
| 加密/序列化与发送必须解耦 | ✅ 拆分热路径 | ✅ 拆分三条路径 | ✅ 拆分三层 |
| 快照保存串行化，避免并发 409 | ✅ SnapshotScheduler | ✅ 未明确提及 | ✅ 明确分析 409 冲突 |

### 各方的独特贡献

| 独特洞察 | 来源 | 价值 |
|----------|------|------|
| 适配器 JSON 字符串中转是最大 CPU 浪费（序列化→解析→深拷贝） | zcode | **P2 高收益** |
| 实时通道未启用 zlib 压缩，但 `ExcalidrawBinaryCodec` 已有 zlib 能力 | zcode | **P0 极高收益** |
| Socket.IO JSON 数组编码导致 6x 数据膨胀 | claude | **P0 极高收益** |
| 消息解密串行队列导致多用户延迟累加 | claude | P1 |
| Outbox + ACK + opId 可靠投递协议 | codex | **P1 核心架构** |
| 服务端背压防止慢客户端拖垮房间 | zcode | P1 |
| join-room 读取整个加密场景（5MB+），应改为轻量存在性检查 | zcode | P1 |
| 强制 WebSocket 禁止 polling 回退 | zcode | P1 |
| 区域化广播（按 pageId 分区） | zcode | P2 |
| 完整测试验收矩阵 + SLO 目标 | codex | 质量保障 |
| ChangeAccumulator 按 elementId 覆盖合并 | codex | P0 |
| 连接状态机：connecting → joined → synced | codex | P1 |
| 平台网络状态监听 + App 生命周期管理 | claude | P2 |
| Figma/Google Docs/Excalidraw/Liveblocks 深度对比 | claude | 参考 |

---

## 二、综合根因分析

### 2.1 当前协作全链路

```
MarkdrawController.applyResult()
  └─ onSceneChanged (每次 scene-changing ToolResult)
      └─ WhiteboardPage._saveMarkdrawScene()
          ├─ serializeScene(全场景 JSON 字符串)     ← CPU 大头
          ├─ SQLite saveScene + 封面生成 + 资料库    ← I/O 大头
          └─ broadcastScene()
              ├─ currentScene()                      ← 又一次序列化往返!
              │   controller.serializeExcalidrawSceneJson()
              │   → String → jsonDecode → ExcalidrawScene.fromJson → copyWith
              ├─ _changedElements()                  ← O(n) 全量扫描
              ├─ message.toBytes()                   ← JSON 无压缩
              ├─ _crypto.encrypt()                   ← AES-GCM
              ├─ socket.emit(Uint8List→JSON数组)     ← 6x 膨胀!
              └─ unawaited(_saveSceneSnapshot())     ← 每次广播都存快照!
                  └─ HTTP PUT 全量加密场景 → 409 冲突 → reload → reconcile → retry
```

**每 20 秒额外**: `_startFullSceneSync()` → `broadcastScene(syncAll: true)` → 全量元素

### 2.2 根因矩阵

**🔴 P0: 热路径三重耦合**（codex 核心论点 + zcode/claude 验证）

每次 `onSceneChanged` 同时触发：本地持久化（serialize + SQLite + 封面）+ 实时网络（encrypt + Socket.IO）+ 远端快照（encrypt + HTTP PUT）。一笔手写 30-60 次触发，CPU/IO/网络三方争用。

代码证据: `whiteboard_page.dart:1373`、`:277`、`collaboration_repository.dart:236`

**🔴 P0: 实时通道 JSON 无压缩**（zcode 发现 zlib 能力闲置 + claude 发现 JSON 数组编码膨胀）

| 膨胀源 | 机制 | 膨胀倍数 | 发现方 |
|--------|------|----------|--------|
| JSON 无 zlib 压缩 | 大量重复字段名、默认值 | 5-10x | zcode |
| Socket.IO JSON 数组编码 | `Uint8List`→`[255,128,...]` | 4-6x | claude |
| **叠加** | | **20-60x** | |

**🔴 P0: 出站无批处理/节流**（三方共识）

拖拽元素 1 秒触发几十次 `onSceneChanged`，每次都全链路。version 门控在拖拽场景无效。

**🟡 P1: 适配器 JSON 字符串中转**（zcode 独特洞察）

```dart
controller.serializeExcalidrawSceneJson()  // 内核 → JSON 字符串
→ jsonDecode(str)                           // 字符串 → Map
→ ExcalidrawScene.fromJson(map)             // Map → 深拷贝
```

每次出站/入站各执行一次，大画板下是单次操作中最大 CPU 开销。

**🟡 P1: 消息解密串行队列**（claude 独特洞察）

```dart
_messageDecodeQueue = _messageDecodeQueue
    .then((_) => _handleEncryptedPayload(room, payload));
```

10 人房间队列深度 5-10 条，尾部延迟累加。

**🟡 P1: 20 秒全量同步定时器**（三方共识）

大画板每次全量同步发送数百 KB，即使场景完全无变化。

**🟡 P2: 连接可靠性**

| 子问题 | 发现方 |
|--------|--------|
| 重连后不等 rejoin 确认就发广播 | zcode |
| 服务端无背压，慢客户端拖垮房间 | zcode |
| join-room 每次读全量加密场景（5MB+） | zcode |
| polling 回退导致大帧超时 | zcode |
| 无平台网络监听 | claude |
| 无 outbox，断线编辑丢失 | codex |
| Socket.IO 默认重连参数未调优 | claude |

**🟢 P3: 其他**

O(n) 全量扫描 ×3/broadcast（claude）、copyWith 深拷贝 GC 压力（zcode）、快照冲突 reload 风暴（codex+claude）、服务端全局锁竞争（zcode）。

### 2.3 已有可复用基础

- `SceneReconciler` — 基于 Excalidraw version/versionNonce 的增量合并，不需要替换
- `EncryptedSceneStore` — 已有乐观锁快照元数据，适合灾难恢复而非热路径
- `RealtimeTransport` — 已抽象传输层，可在不污染编辑器的前提下加入 ACK
- `ExcalidrawBinaryCodec` — 已有 zlib 压缩能力，只是没用对地方
- volatile 通道 — 已有 presence/document 两类消息的基础区分
- AES-GCM-128 + E2E 加密 — 安全模型正确，保持不变

---

## 三、成熟产品参考

### 3.1 跨产品对比

| 维度 | FlowMuse 当前 | Figma | Excalidraw+Yjs | Google Docs | Liveblocks |
|------|--------------|-------|----------------|-------------|------------|
| 冲突解决 | LWW(元素级) | LWW(属性级) | CRDT(YATA) | OT(Jupiter) | CRDT |
| 同步粒度 | 增量元素 JSON | 属性级 delta | 二进制 delta | 操作变换 | Yjs delta |
| 全量同步 | **每 20s** ❌ | 仅首次 | 仅首次 | 仅首次 | 仅首次 |
| 消息编码 | **JSON 数组(6x膨胀)** ❌ | 二进制 WS | 二进制 Uint8Array | 二进制 WS | 二进制 WS |
| 批处理 | **无** ❌ | 33ms 窗口 | 16ms(Yjs 事务) | ACK 规则 | Yjs 事务 |
| 存在感 | volatile ✅ | ephemeral | Awareness CRDT | ephemeral | Presence API |
| 连接恢复 | **全量场景** ❌ | 状态差量 | 状态向量差量 | revision log | Yjs 差量 |
| 离线支持 | **无** | 有限 | 原生(Yjs) | Buffer+Reconcile | Yjs |

### 3.2 Figma — 最相关参考

Figma 与 FlowMuse 架构模型高度相似（白板 + LWW + 中心化）。关键借鉴：

- **33ms 批处理窗口**：客户端合并所有变更，30fps 发送
- **存在感不持久化**：disconnect = 立即消失（FlowMuse 已实现 ✅）
- **乐观本地更新**：pending ACK 期间丢弃冲突的远端更新

### 3.3 为什么暂不集成 Yjs

1. Flutter 端无原生 Yjs，需 `dart:js` interop 或 port
2. Yjs delta 同步需服务端理解文档结构，与 E2E 零知识架构矛盾
3. Figma 证明了 LWW 对白板充分，无需升级到 CRDT

### 3.4 跨产品共识（验证方向）

所有成熟产品共同选择：全量同步仅首次、批处理是刚需（16-50ms）、存在感与文档分离、二进制传输。FlowMuse 当前在这四个维度上均存在差距。

---

## 四、优化方案

### Phase 1 — 快速止血（1-2 天，不改协议，纯客户端）

**1.1 出站批处理 Coalesce**（三方共识）

```dart
static const Duration _batchWindow = Duration(milliseconds: 50);
Timer? _batchTimer;
final Map<String, Map<String, Object?>> _pendingElements = {};

Future<void> broadcastSceneCoalesced({
  required CollaborationRoom room,
  required ExcalidrawScene scene,
  bool initial = false,
  bool syncAll = false,
}) async {
  _latestScene = scene;
  if (initial || syncAll) {
    await _sendImmediate(room: room, scene: scene, initial: initial, syncAll: syncAll);
    return;
  }
  // 按 elementId 覆盖合并最新版本（codex ChangeAccumulator 思想）
  for (final element in _changedElements(scene.elements)) {
    _pendingElements[_id(element)] = element;
  }
  _batchTimer?.cancel();
  _batchTimer = Timer(_batchWindow, () {
    _batchTimer = null;
    final elements = _pendingElements.values.toList();
    _pendingElements.clear();
    if (elements.isEmpty) return;
    _flushBatch(room: room, elements: elements);
  });
}
```

**1.2 实时通道 zlib 压缩 + 二进制传输**（zcode + claude）

```dart
import 'dart:io'; // gzip

Future<void> _sendCompressed({
  required CollaborationRoom room,
  required CollaborationMessage message,
  bool volatile = false,
}) async {
  final jsonBytes = message.toBytes();
  final compressed = gzip.encode(jsonBytes);               // zcode: zlib 压缩
  final encrypted = await _crypto.encrypt(
    roomKey: room.roomKey, plainBytes: compressed,
  );
  socket.emit(
    volatile ? _eventServerVolatileBroadcast : _eventServerBroadcast,
    roomId,                       // string → JSON
    encrypted.encryptedBuffer,    // Uint8List → 原生二进制帧（claude: 避免 JSON 数组膨胀）
    encrypted.iv,                 // Uint8List → 原生二进制帧
  );
}
```

预期：JSON 压缩 5-10x + 二进制传输 4-6x = **总载荷减少 95%+**。

**1.3 拆分热路径**（codex）

```dart
void _onSceneChanged() {
  _localDraftScheduler.schedule();                       // 本地草稿: 500ms debounce
  _collaborationBroadcastScheduler.schedule(_latestScene); // 协作: 50ms batch
  // 封面生成: 仅显式保存/闲置时
}
```

**1.4 快照串行化**（codex SnapshotScheduler）

```dart
class SnapshotScheduler {
  Timer? _timer;
  bool _saving = false;
  void markDirty() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () => _flush()); // 闲置 2s 保存
  }
  Future<void> _flush() async {
    if (_saving) return;  // 同一房间只允许一个快照在飞
    _saving = true;
    try { await _saveSceneResolvingConflict(...); }  // 409 单次 reconcile 后重试
    finally { _saving = false; }
  }
}
```

**1.5 取消 20s 全量同步** — 改为 30s 版本校验（volatile，丢失也无妨），不匹配时从快照修复。

**1.6 指针位置节流** — 33ms throttle + trailing call，30fps。

### Phase 2 — 可靠传输（3-5 天，前后端协议扩展）

**2.1 加密 Outbox + ACK 协议**（codex）

协议扩展（服务端只读取外层帧标识，不解密内容）：

```json
// 外层帧（服务端可见）
{"frameId": "uuid", "kind": "scene-update", "ciphertext": "...", "iv": "..."}

// 明文载荷（加密前，服务端不可见）
{"opId": "clientId:monotonicSequence", "baseSnapshotVersion": 42, "elements": [...]}
```

客户端 outbox（SQLite 持久化未 ACK 消息，ACK 后删除，重启可恢复，同 elementId 覆盖合并）。

服务端去重 + ACK：`socketId + opId` 短期 TTL 去重，ACK 只确认密文帧已被服务器接受。

**2.2 重连状态机**（codex）

```
disconnected → reconnecting → resume(roomId, lastAckedOpId)
  → 服务端补漏 → 拉快照 + reconcile → 重放 outbox → synced
```

关键：区分 `joined`（socket 已连接）和 `synced`（漏包已补齐 + outbox 已清空）。UI 在 synced 之前显示"正在恢复"。

**2.3 服务端加固**（zcode）

- **轻量 join 检查**：`SELECT EXISTS(SELECT 1 FROM excalidraw_scenes WHERE room_id = $1)` 替代加载全量加密场景
- **背压保护**：发送缓冲区 >2MB 丢弃 volatile/回 error，>10MB 断开慢客户端
- **强制 WebSocket**：`.setTransports(['websocket'])` 去掉 polling 回退

**2.4 重连等 rejoin 确认**（zcode）— onReconnect 后复用 `_waitForRoomJoin()` 等待确认，不确认不发广播。

### Phase 3 — 深度优化（1-2 周，按数据决定）

| # | 优化项 | 来源 | 预期收益 |
|---|--------|------|----------|
| 3.1 | **适配器直通**: 消除 JSON 字符串中转，内核直接产出 Map | zcode | CPU -50% |
| 3.2 | **并行解密 + 保序应用**: 解密异步并行，应用层 FIFO | claude | 多用户延迟 -40% |
| 3.3 | **Dirty Set**: 替代 O(n) 全量扫描 | claude | CPU -20% |
| 3.4 | **平台网络监听**: connectivity_plus + AppLifecycle | claude | 断连恢复 <3s |
| 3.5 | **区域化广播**: 按 pageId 分区，只广播当前页面 | zcode | 多页载荷 -80% |
| 3.6 | **服务端指标**: 结构化日志 + 连接耗时/重连次数/outbox 长度/ACK RTT | codex | 可观测性 |

### 不改的事（三方一致同意）

- **不迁移 Yjs/Automerge/CRDT**：LWW 对白板足够，Figma 也用 LWW
- **不改变 E2E 加密**：服务端永远不解密
- **不改变 Excalidraw 元素兼容**：`id/version/versionNonce/index/isDeleted` 语义不变
- **不替换 Socket.IO**：当前问题在应用层，不在传输层

### 收益预估

| 场景 | 当前 | Phase 1 | Phase 2 | Phase 3 |
|------|------|---------|---------|---------|
| 单条消息体积 | ~10KB | ~500B | ~500B | ~400B |
| 拖拽广播频率 | 60次/s | 20次/s | 20次/s | 20次/s |
| 2人协作 P95 | ~200ms | ~60ms | ~40ms | ~30ms |
| 10人协作 P95 | ~1500ms | ~400ms | ~200ms | ~100ms |
| 断连检测 | 25-45s | 25-45s | 10-15s | <5s |
| 重连后状态 | 全量同步 | 全量同步 | 差量恢复 | 差量恢复 |
| 快照 HTTP PUT | ~10次/s | ≤1次/s | ≤1次/s | ≤1次/s |

---

## 五、测试与验收

### SLO 目标

| 指标 | 目标 |
|------|------|
| 本地编辑到对端可见 P95 | <250ms（良好网络，非图片） |
| 短断线恢复到 synced P95 | <5s |
| 正常编辑期 HTTP 快照频率 | ≤1 次/秒 |
| Socket 批次数（正常书写） | ≤20 次/秒 |
| 断连检测延迟 | <15s |
| 远端快照保存 P95 | <2s |

### 测试矩阵

**单元测试**: ChangeAccumulator 同元素合并/删除墓碑/版本倒退、Outbox ACK 删除/重启恢复/重放幂等/同元素覆盖、SceneReconciler 并发编辑不同元素/同元素 LWW。

**集成测试**: 两客户端编辑 60s 最终一致、30% 丢帧一致、乱序帧一致、重复帧一致。

**网络测试**: 10% 丢包 + 300ms RTT、10s 断网恢复、Wi-Fi↔蜂窝切换、断网期间持续编辑、慢客户端背压。

**性能测试**: 2 人 + 1000 元素书写 60s、5 人 + 5000 元素拖拽 30s、10 人空闲内存。

**跨端验收**: Android ↔ 鸿蒙 ↔ Web 各组合的加入/编辑/断线恢复/图片同步。

### Phase 验收门禁

- **Phase 1**: 两台设备书写 60s 帧率不降、HTTP PUT ≤1次/s、Socket batch ≤20次/s、消息体积 <1KB
- **Phase 2**: Wi-Fi/蜂窝切换自动恢复、断网 10s → outbox 清空 → synced、断网编辑全量到达、慢客户端不拖垮房间
- **Phase 3**: 恢复时间可量化、异常定位到具体层、区域化广播仅发当前页

---

## 六、性能打点建议

```dart
// 客户端指标
CollaborationMetrics {
  batchElementCount, batchEncryptedBytes, ackRttMs,
  outboxLength, snapshotDurationMs, snapshotConflictCount,
  reconnectCount, reconnectDurationMs,
}

// 服务端指标
ServerMetrics {
  joinLatencyMs, forwardDroppedCount, bufferSizePerSocket,
  activeRoomCount, opDedupHitCount,
}
```
