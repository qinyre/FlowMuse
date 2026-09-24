# Web 首次加载优化

## 现状

- 无缓存时主程序 gzip 约 2.39 MB，Chromium CanvasKit gzip 约 2.18 MB；完整字体清单 4,207,468 字节以未压缩 TTF/OTF 传输。引擎源码确认会等待这些字体下载后初始化。
- Nginx 已压缩 JS/WASM，但字体 MIME 为 `application/octet-stream`，不在压缩列表；HTTPS 未启用 HTTP/2。
- `index.html` 只有脚本，Flutter 第一帧前整页空白。本地主题读取还需要初始化 Web SQLite。

## 实施

1. 仅调整 Web 启动文件：增加无额外图片/字体依赖的加载页，按实际启动阶段更新提示，第一帧后移除；慢加载/失败时提供手动重试，不显示虚构百分比。
2. 在 HTML 中提前下载主程序与 SQLite WASM，保持 CanvasKit 的浏览器自动选择。
3. 提供标准库构建后处理脚本，预压缩 JS/WASM/字体等文本与二进制资源；Nginx 使用已有 gzip_static 模块并开启 HTTP/2。保留入口与资源的缓存校验策略，避免更新后使用旧包。
4. 复用当前 PDF、账户、本地数据库和协作流程，不调整原生平台启动或数据库结构。

## 验证

- Node 标准测试覆盖启动阶段、第一帧移除、初始化失败和慢加载；Python 验证预压缩资源解压与原始内容一致。
- Flutter analyze/test、Web release 构建；检查线上压缩编码、解压后的文件哈希、HTTP/2、入口与深链。
- 比较相同首屏资源集合的实际传输体积；网络耗时受带宽影响，不能把单文件时间当成完整首屏时间。
- 浏览器工具当前连接失败；若恢复则检查加载页与正常界面，否则明确记录未完成可视化验证。

参考：[Flutter 初始化](https://docs.flutter.dev/platform-integration/web/initialization)、[Nginx gzip_static](https://nginx.org/en/docs/http/ngx_http_gzip_static_module.html)。

## 发布前验证

- 同一组主程序、Chromium CanvasKit、SQLite、worker 与字体，线上无缓存实测传输 9,206,761 字节（HTTP/1.1 六并发，本次网络下下载 70.505 秒，不含解码和绘制）。本地相同资源预压缩约 6.91 MB，实际线上值发布后复测。
- Node 启动测试 2 项、Python 压缩测试 1 项通过，覆盖首帧时机、异常、慢加载与旧 `.gz` 清理。生产 Nginx 对配置片段的独立 `-t` 校验通过。
- Flutter 全量 1772 项通过、6 项既有跳过；分析仅有忽略的截图脚本既有警告；Web release 构建通过。
- 浏览器工具连接失败，尚未取得冷启动页面的实际截图或完整首帧计时；网络资源指标不冒充浏览器首帧指标。
