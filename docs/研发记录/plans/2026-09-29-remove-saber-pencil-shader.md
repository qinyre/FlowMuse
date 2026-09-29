# 移除 Saber 铅笔着色器

## 背景与范围

用户已确认 `pencil.frag` 从 Saber 移植，并要求移除相关实现。当前新铅笔默认使用自然介质 V2；旧版及缺压感回退仍会使用该 shader。此次让 classicV1 铅笔统一沿用项目已有的确定性颗粒 Path，不改笔迹数据、版本字段、压力编码、协作协议或 V2 算法。

这是用户授权的旧版铅笔纹理变化：原 shader 平台改为既有颗粒外观；原降级平台沿用已有算法。ADR-020/021 的旧像素冻结要求在此项上被本次明确要求取代，其他笔形与 V2 仍保持原行为。

## 实施

1. 删除 `pencil.frag`、`PencilShader` 加载器、启动调用、pubspec 注册和专属测试。
2. 将原有 `PencilGrainHash` 移入现有 `freedraw_renderer.dart`，保持算式；去除 shader 分支及专用设备缩放透传、缓存可用状态和性能字段。
3. 保留并调整颗粒、预览、静态缓存、协作及导出回归测试，更新现行文档。历史性能报告的 `pencilShaderAvailable` 比较字段继续保留以区分旧数据，不用于加载 shader。历史移植和许可证据保留，不把当前删除表述为旧发布义务已消除。

## 验证

- 依赖解析、静态检查、相关渲染和序列化测试，随后按仓库要求运行全量测试。
- 检查运行源码、测试及构建配置无 shader 文件、加载器和专用缩放参数残留。
- 本机测试不能替代鸿蒙/Android 真机手感验证；软著统计与既有代码 Word 使用旧基准，需在登记版本重新冻结后更新。

## 结果

- 已移除 shader、加载器、启动/打包注册、专用设备缩放透传和静态缓存可用状态；旧报告比较字段仅用于读取历史性能数据。
- `PencilGrainHash` 算式及 `buildPencilGrainPath` 算法与删除前逐段对照一致；V2 目录无改动。
- `flutter analyze --no-pub`：无问题；相关测试 133 项通过；全量 `flutter test --no-pub`：1787 项通过、6 项既有跳过。日志保存在仓库同级软著资料目录的 `analysis/remove-saber-*.log`。
- `flutter pub get --offline` 已完成依赖解析，随后因本机 `DEVECO_SDK_HOME` 指向不存在的 `D:\Program\DevEco Studio\sdk` 而退出 1。未改动机器 SDK 配置、未下载新 SDK，HAP 构建与真机验证未完成。
- 源码、运行测试和打包配置无加载器/着色器引用；重新生成的 `build/unit_test_assets` 及 `AssetManifest.bin` 不含 `shaders/pencil.frag`；`git diff --check` 通过。
- 软著《软件修改说明》已标注删除前统计和代码 Word 的基准限制，待登记版本重新固定后更新；历史来源附件保留。
