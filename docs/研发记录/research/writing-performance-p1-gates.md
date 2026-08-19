# FlowMuse P1 本地湿墨条件门禁记录

> 建档日期：2026-08-20  
> 当前状态：`deferred_device`  
> 基线：P1-2 commit `2ce461a`

## 1. 已完成结果

- P1-0：单一只读构建开关，默认关闭且可注入测试。
- P1-1：活动笔迹使用稳定 `strokeId` 和专用 notifier；100 个 move 不再线性通知整页 Controller。
- P1-2：静态 Scene 与交互前景之间接入本地湿墨画层，直接读取活动点列并复用现有 Freedraw renderer；final 同步接管且不重复绘制。
- P1-4：停止协作时等待房间订阅取消，清理 Timer；服务端 volatile 高频帧不逐帧记录成功日志。

上述自动化测试可证明状态、画层、回退和生命周期语义，不等价于真机性能验收。

## 2. 条件项判定

| 条件项 | 当前状态 | 缺少证据 | 当前决策 |
| --- | --- | --- | --- |
| P1-3 retained prefix | `not_evaluated` | P1-2 后同一 30 秒长笔的首/末 10 秒 wet raster P95/P99、deadline miss、Path 输入点和 retained layer/count | 不实现，避免无证据增加分段/栅格状态 |
| P1-G1 Path 派生缓存 | `not_evaluated` | completed-Freedraw 的 `getStroke + Path build` P95 及其 UI paint 占比 | 不实现，避免缓存键、预算和淘汰复杂度 |
| P1-G2 Scene 派生缓存 | `not_evaluated` | 排序/线性查找 P95 及 dry paint 占比 | 不实现，避免新增重复状态源 |

状态不是 `not_triggered`：没有真机数据就不能推断热点未达到阈值；也不是 `rejected`：尚无数据证明方案无效。

## 3. 真机恢复步骤

1. 使用 P0 固定 fixture，在同一真机、Profile 构建、相同刷新率和场景下分别运行 `FLOWMUSE_LAYERED_WET_INK=false/true`，各 5 轮。
2. 对 30 秒长笔单列首/末 10 秒；输出 wet raster、deadline miss、Path 输入点和 retained layer/count 原始证据。
3. 按上位方案阈值逐项写入 `triggered/not_triggered/rejected`，由负责人和复核人签名。
4. 仅对 `triggered` 项建立实现任务；每项单独提交、复测并保留 raw evidence。

## 4. 当前非真机验证

- P1 局部 Flutter 测试：18 项通过。
- 协作生命周期 Flutter 测试：10 项通过。
- 服务端 `go test ./...` 与 `go vet ./...`：通过。
- 真机 event-to-paint、stylus-to-photon、P95/P99 与内存峰值：`not_measured`。
