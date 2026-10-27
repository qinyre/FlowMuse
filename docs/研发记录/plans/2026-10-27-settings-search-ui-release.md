# 设置、搜索及批量操作栏发布

## 版本与验证

- 源码 `abbd5d52dd3aea17ba59eb2b286c898caed491c4`，分支 `fix/settings-panel-motion`；已合入主线 `2089145d`，包含 PR #91 已合并的资料库侧栏/网格过渡，避免覆盖线上改进。
- 合入后 analyze 无问题，完整 Flutter 测试 **2090 通过、5 个既有跳过**；Web 启动脚本 2 项、预压缩脚本 1 项测试通过。
- Web 和 Android 均显式开启湿墨分层、实时墨迹 V2，使用正式 API 与分享入口。此次不更新后端。

## Web

- 2026-10-26 22:26（北京时间）已上线 [正式 Web](https://app.flowmuse.cloud/library)。发布 ID `settings-ui-20261026-abbd5d5`，Nginx 验证及 reload 成功，后端容器/镜像不变且健康。
- 主脚本 SHA-256：`90c8a8f98785a15cd360bf3dddf8784b329cd75124e067c829306cf3dbf60855`。
- 公网入口、版本信息、主脚本、扫码脚本、三套字体及许可证、CanvasKit JS/Wasm 共 10 项资源返回 200，哈希一致、Cache-Control 均为 no-cache。
- 公网全新访客上下文仅创建合成笔记：搜索输入、匹配数量、范围菜单、600px 下查询文字保留、多选零状态/选择/取消通过；批量栏实测宽度 760px。设置标题居中、快速分类切换（99 次帧采样最多一个标题）、减少动画、600px 布局及返回资料库通过。帧采样不代表真实 FPS。
- 无障碍焦点边界：输入框保持聚焦、打开范围菜单后调整窗口大小，Chrome 辅助功能模拟捕获到 Flutter Web 文本输入焦点路径的 null-check 异常；用旧线上 `cc182d4f` 主脚本在相同 HTTPS 页面同样复现。常规输入后失焦再调整窗口的流程无未捕获错误；未禁用产品无障碍或修改 SDK 掩盖异常，留作独立问题排查。

## Android

- 2026-10-27 已在一加 Pad Pro（OPD2404，Android 16）覆盖安装并启动 `com.example.flowmuse`，未卸载或清除数据。首次安装时间仍为 2026-09-21，系统记录本次更新时间为 2026-10-27 14:18。
- APK 为 release 通用包，含 arm64-v8a、armeabi-v7a、x86_64，大小 268712523 字节；签名校验通过，设备上的 base.apk 与本地产物 SHA-256 一致：`f5c6fde067b89777dcb7dd67a23449f2cc478d0a78f380394def3f9a37aba6b8`。
- 主 Activity 冷启动成功，进程存活，启动日志未发现 FATAL/Unhandled Exception；未将设备现有笔记或界面导出为截图，未验收真实手写性能。
- 构建期间解决 GitHub 原生依赖下载超时：仅本次构建进程使用已有本机代理；重新执行正常 pub get/build 后刷新插件生成文件，排除陈旧 integration_test 注册。依赖锁文件、应用源码和 SDK 均未因此修改。

## 收尾

- 本地及服务器临时上传 tar、服务器临时部署脚本已删除；保留编译产物、发布验证记录和必要回退目录。
- 构建/公网/安卓核验日志保存在本地 `FlowMuse-App/build/settings-ui-release/`，不入库。
- 后续推送分支并向 main 发出 PR；不等待 CI/审查完成，不自动合并。
