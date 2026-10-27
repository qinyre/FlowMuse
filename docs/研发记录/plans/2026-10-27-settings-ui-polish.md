# 设置界面视觉优化

## Context

PR #92 已合并至 main `350e5510`。按用户要求清理本地/远端已合并的 `chore/project-cleanup`、`fix/library-sidebar-motion`、`fix/settings-panel-motion`、`fix/web-ctrl-wheel-zoom`，保留 main 与未合并的 gh-pages 发布分支；从最新主线建立 `feature/settings-ui-polish`。

## 范围与设计

- 沿用纸面/青绿主题与现有组件，设置导航按账户与数据、外观与书写、应用与隐私分组，选中项内收并保留标题居中。
- 正文限制阅读宽度，统一设置卡片边框、标题/说明层级、输入框与选择器样式；不修改账户、备份、AI、编辑器参数的业务逻辑和权限。
- 主题选择由小色块改为六张实际配色/壁纸的工作区预览卡，显示说明及选中标记；支持键盘和无障碍，窄屏/大字号自动减列。
- 保留已有分类切换控制器及设置主体身份。正文滚动归正文控制器管理，切换分类回到顶部，同分类主题变化保持位置。
- 不增加依赖，不引入模糊滤镜或逐项动画控制器，不触及平台适配、存储格式、协作或后端。

## 验证

设置/账户相关回归优先；补充主题切换、窄屏大字号和切换后滚动归零验证，随后运行 analyze、全量测试、本地 Web release 与浏览器视觉检查。分次提交，开发阶段先完成本地验收，正式发布另行记录。

## 自动回归结果

- 5 项新增验证：六种主题及点击/键盘切换、选中语义反馈，浅色与深色下 360px 双倍字号预览滚动，600px 下说明换行时主题卡仍等高，主题滚动后切至长工具页归零且仍可滚动。
- 设置布局、切换动效、主题卡片及账户相关测试 26 通过；既有状态身份保留及快速切换/销毁用例保持通过。
- analyze 无问题；完整 Flutter 测试 **2095 通过、5 个既有跳过**。
- 本地日志位于 `FlowMuse-App/build/settings-visual-polish/`，不入库。分支清理通过提交祖先关系、无待审 PR 与远端 lease 校验；没有删除 gh-pages 或未合并提交。

## 本地 Web 验收

- 实现源码 `c0298a23855ab4239ad793fbc1313b304e7d5b35` 的 Web release 构建通过，生产 API/分享域名及两个墨迹开关保持现有配置；该构建用于首轮本地检查。
- 使用隔离的访客浏览器环境，在 1600×1000 与 600×900 下检查分组导航、主题预览及文档设置；选择夜间并刷新后，选中语义仍为 `aria-current=true`，原有文档类型选择器正常回调。
- 600px 下六张主题卡均为 186px 高，说明换行时保持对齐；浏览器未出现 pageerror。浅色、深色及窄屏截图已人工检查，360px 双倍字号由 widget 测试覆盖。
- 本轮未构建安卓/鸿蒙包，未检查实机帧率。

### 截图

- [日间主题预览](../images/2026-10-27-settings-ui-theme-day.png)
- [夜间主题预览](../images/2026-10-27-settings-ui-theme-night.png)
- [普通设置卡片与选择器](../images/2026-10-27-settings-ui-document.png)
- [窄屏主题预览](../images/2026-10-27-settings-ui-compact.png)

## 正式 Web 发布

- 用户授权后，2026-10-27 15:22（北京时间）已发布至 [正式设置页](https://app.flowmuse.cloud/settings?section=theme)，发布 ID `settings-polish-20261027-dfecada`。
- 从 `dfecada1f27f27281f884a35d09256d57eb980eb` 重新构建 Web release，基线为 main `350e5510`。参数：`--no-web-resources-cdn --pwa-strategy=none --base-href /`，API 为 `https://api.flowmuse.cloud`，分享入口为 `https://app.flowmuse.cloud`，`FLOWMUSE_LAYERED_WET_INK=true`、`FLOWMUSE_LIVE_INK_V2=true`。
- 主脚本 SHA-256：`eaec059613b20c149f02e49969d8ae0050bd6089c750cb1b32196738fd5ca106`。公网入口、版本信息、主脚本、扫码脚本、三套字体及许可证、CanvasKit JS/Wasm 共 10 项均返回 200，哈希匹配、Cache-Control 为 no-cache。
- 公网隔离访客浏览器验证分组导航、六种主题、夜间选择后刷新保留状态、文档类型选择器及 600px 等高布局通过，未捕获 pageerror；首屏截图已人工核对。Web 启动脚本 2 项、预压缩脚本 1 项通过。
- Nginx 配置校验及 reload 成功，后端容器与镜像保持原样且健康。服务器及本地临时上传归档、服务器临时部署脚本已清除，保留构建结果和必要的发布回退目录。
- 发布与公网验证记录位于本地 `FlowMuse-App/build/settings-visual-polish/`。后续推送分支并向 main 提交 PR，不等待 CI/审查，不自动合并。
