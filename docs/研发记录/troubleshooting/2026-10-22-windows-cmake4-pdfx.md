# Windows CMake 4 与 pdfx 子工程兼容

## 现象与定位

扫码入房分支合并前，Quality 与智能排版回归均通过，Windows 平台矩阵失败。此前主干也有相同平台失败：`39762932630`；本轮为 `39780726084`。原构建脚本将 stderr 放在 stdout 前拼接并截取末尾，实际错误被后续依赖解析输出挤出报告。先补充完整失败日志及更长的错误尾部，不跳过构建检查。

Windows runner 记录的镜像为 `windows-2025-vs2026`。当前 `pdfx 2.9.2` 的 `windows/DownloadProject.CMakeLists.cmake.in` 声明 `cmake_minimum_required(VERSION 2.8.12)`，而 CMake 4 已移除低于 3.5 的策略兼容。

诊断提交 `afd4a0c` 的远端运行 `39784430871` 已产出完整 Windows 失败报告：`CMakeLists.txt:4 (cmake_minimum_required)` 提示移除低于 3.5 的兼容，随后 `pdfx/windows/DownloadProject.cmake:171` 报 `CMake step for pdfium failed: 1`。与本地对照复现一致。

## 修复计划与边界

- 在 Windows 工程加载第三方插件前，为 CMake 4 的子进程导出 `CMAKE_POLICY_VERSION_MINIMUM=3.5`；保留调用者显式设置的环境值。
- 需要环境变量而不仅是父工程普通变量：pdfx 的下载器通过 `execute_process` 启动独立 CMake 子进程。
- 不修改 pub cache、vendor fork、应用运行时代码或工作流检查范围，不影响安卓/Web 已构建产物。
- 先用官方 CMake 4.1.2 和实际 pdfx 模板做失败/成功对照，再以远端 Windows 完整构建确认。

## 验证

本地临时探针位于 `FlowMuse-App/build/qr-join/probe_cmake_policy.py`。使用 Kitware 发布的 CMake 4.1.2 Windows 包，按官方 SHA-256 清单验证下载；实际 pdfx 模板、Ninja 和本地空载荷组成独立配置检查，不需要安装 Visual Studio，也不访问 PDF 下载服务。

对照结果：默认配置返回 1，包含 `Compatibility with CMake < 3.5 has been removed`；兼容环境参数配置返回 0。读取 Windows 工程真实配置片段后启动独立 CMake 子进程，默认策略 3.5 配置成功，调用者显式策略 3.10 也配置成功且值保留。远端完整 Windows 构建结果在 PR #70 检查中确认；本地探针不能代替 C++ 编译和运行验收。

本地提交前全量 Flutter 回归再次 1855 通过、5 项原有跳过；诊断脚本改动后的 analyze 无问题。

参考：[CMake 环境变量](https://cmake.org/cmake/help/latest/envvar/CMAKE_POLICY_VERSION_MINIMUM.html)、[第三方项目的兼容策略](https://cmake.org/cmake/help/latest/variable/CMAKE_POLICY_VERSION_MINIMUM.html)。
