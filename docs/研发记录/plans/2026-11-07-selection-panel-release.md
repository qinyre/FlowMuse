# 选区侧栏正式 Web 发布

- 2026-11-07 10:32:52（北京时间）发布至 [正式 Web](https://app.flowmuse.cloud/library)。发布 ID `web-selection-panel-20261107-937d56c8`，源码提交 `937d56c8997872793fe7b031dbb4a0e4fc2a8de8`，回退版本 `web-note-split-20261107-0f10abb0`。
- 采用 Web release、根路径、随包 CanvasKit、启动字体优化和 gzip 预压缩。使用正式 API 和分享地址，湿墨分层与实时墨迹 V2 均开启。主脚本 SHA-256 为 `ed2e788ac4ecae1aef9628d0c15f409f3f43579259ad9a92f96e9bced70aeaf7`。
- 发布前的定向回归覆盖笔迹侧栏收高、归属卡片与 AI 菜单。发布后 Nginx 配置校验和 reload 成功，27 项公网检查通过，主脚本哈希匹配，API 健康，Go 容器启动时间一致。干净 Chrome 成功打开资料库，无页面异常，单次冷启动首帧约 75 秒。

## 混合选区修正

- 2026-11-07 10:44:08（北京时间）发布 `web-mixed-selection-20261107-8c5d7db9`，源码提交 `8c5d7db947073d0b09d8eeb1ab1aea541aa49f90`。混合选区默认只显示常用控件，详细样式与排列操作分别展开。沿用上述发布参数，回退版本为 `web-selection-panel-20261107-937d56c8`。
- 白板相关测试 36 项通过，本地 Chrome 样稿覆盖矩形、文字和笔迹的混合选区。发布后 27 项公网检查通过，主脚本 SHA-256 为 `8a817cb1de252ed3ecd12de6a12ab2f89d5e2305586db05166917e5af5c6c287`。API 健康，Go 容器启动时间一致。干净 Chrome 打开资料库无页面异常，单次冷启动首帧约 48 秒。
