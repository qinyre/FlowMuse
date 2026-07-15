# FlowMuse 语音转文字能力基线

> 日期：2026-07-15  
> 分支：`语音转文字`  
> 目的：记录 P0 构建与自动化证据，并明确仍需真机执行的语音质量测试。

## 1. 当前环境

| 项目 | 结果 |
| --- | --- |
| Flutter | 3.41.10-ohos-0.0.1-canary1（项目工具链） |
| Windows | 10.0.22631.4602 |
| Chrome | 150.0.7871.115 |
| Edge | 138.0.3351.55 |
| Android 真机 | 当前未连接，尚未执行语料测试 |
| HarmonyOS 真机 | 当前未连接，尚未执行语料测试 |

## 2. 固定普通话语料

1. 今天下午三点开项目评审会。
2. 请把第一页移动到第二页后面。
3. FlowMuse 支持 Android、HarmonyOS 和 Web。
4. 二零二六年七月十五日，温度是二十八摄氏度。
5. 这是一条三秒左右的短句。
6. 我们需要检查逗号、停顿，以及最后的句号。
7. 请创建一个标题为产品方案的文本框。
8. 会议编号是一零二四，预算为三万五千元。
9. 语音转文字只提交最终结果，中间结果不会同步到协作房间。
10. 请连续口述约三十秒，覆盖正常语速、短暂停顿、中英文混合和数字日期。

## 3. 已完成的自动化与构建证据

| 验证项 | 结果 | 证据 |
| --- | --- | --- |
| 空白结果不修改场景 | 通过 | `speech_text_insertion_test.dart` |
| final 创建一个标准 TextElement | 通过 | `speech_text_insertion_test.dart` |
| 一次 undo 完整撤销 | 通过 | `speech_text_insertion_test.dart` |
| partial 不修改场景 | 通过 | `speech_recognition_ui_test.dart` |
| 重复 final 不重复插入 | 通过 | `speech_recognition_ui_test.dart` |
| cancel 不插入 | 通过 | `speech_recognition_ui_test.dart` |
| IO Channel 映射与 generation 隔离 | 通过 | `speech_recognition_service_io_test.dart` |
| Web release 构建 | 通过 | `flutter build web --no-pub` |
| Android debug APK | 通过 | `flutter build apk --debug --no-pub` |
| HarmonyOS debug HAP | 通过 | `flutter build hap --debug --no-pub` |

## 4. 待真机填写

每个平台逐句记录：是否成功、首个 partial 延迟、final 延迟、识别文本、字符错误率、错误码和网络状态。

| 平台/设备 | 网络 | 成功数/10 | partial P95 | final P95 | 结论 |
| --- | --- | --- | --- | --- | --- |
| Android 设备 1 | 在线 | 待测 | 待测 | 待测 | 待测 |
| Android 设备 2 | 在线 | 待测 | 待测 | 待测 | 待测 |
| Android 设备 1 | 断网（至少 3 句） | 待测 | 待测 | 待测 | 待测 |
| HarmonyOS 目标机 | 在线 | 待测 | 待测 | 待测 | 待测 |
| HarmonyOS 目标机 | 断网（至少 3 句） | 待测 | 待测 | 待测 | 待测 |
| Chrome localhost/HTTPS | 在线 | 待测 | 待测 | 待测 | 待测 |
| Edge localhost/HTTPS | 在线 | 待测 | 待测 | 待测 | 待测 |

同时验证：权限允许/拒绝、完成、取消、应用退后台、离开白板、麦克风图标及时消失和协作对端只收到一个最终文本。

## 5. P1 决策

- P1-A Android sherpa_onnx：**暂不启动**。当前没有真机证据证明系统 SpeechRecognizer 在必需设备不可用、成功率低于 90% 或 final P95 超过 3 秒。
- P1-B Web 后端 ASR：**暂不启动**。当前验收浏览器为 Chrome/Edge，尚无证据要求支持缺少 Web Speech API 的浏览器或统一云端供应商。
- HarmonyOS 显式 PCM 管线：**暂不启动**。HAP 已编译通过，但必须先在目标机验证 Core Speech Kit 直接麦克风路径。

在上表补齐前，本文件只证明代码与构建闭环，不宣称真机识别质量已验收。
