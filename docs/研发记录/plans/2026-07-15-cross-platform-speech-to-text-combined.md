# FlowMuse 跨平台语音转文字结合版实施计划

> 日期：2026-07-15  
> 分支：`语音转文字`  
> 适用平台：Android、HarmonyOS、Web  
> 方案定位：系统能力先行，离线模型和服务端兜底由实测数据触发

## 实施状态（2026-07-15）

- P0 共享文本插入、编辑器交互、Android、HarmonyOS、Web 适配均已实现。
- 自动化测试、Web 构建、Android debug APK、HarmonyOS debug HAP 已通过。
- P1-A/P1-B 的准入条件尚无实测数据触发，因此按本计划不实施。
- Android/HarmonyOS 当前未连接真机；固定语料与验收表已写入 `docs/研发记录/research/speech-to-text-capability-baseline.md`，真机质量数据仍须补录。

## 1. 结论先行

本计划合并两条路线的优点：

- **P0 用最小改动快速闭环**：Android 系统 `SpeechRecognizer`、HarmonyOS Core Speech Kit、Web Speech API。
- **保留实时体验**：平台提供的中间结果只在本地浮层预览，最终结果一次性写入白板。
- **保留离线和全浏览器上限**：Android `sherpa_onnx`、Web 后端 ASR 作为条件启用的 P1，不在没有数据时提前建设。
- **最终文字统一落地**：始终创建普通 `TextElement`，复用撤销、保存、导出和现有协作同步。
- **默认不保存录音**：任何阶段都不把录音写入笔记、数据库或对象存储。

推荐实施顺序：

```text
Phase 0 能力实测
        │
        ▼
P0 三端系统能力闭环
        │
        ├── Android 必需机型不达标 ──► P1-A sherpa_onnx 离线适配
        │
        └── Web 必需浏览器不达标 ───► P1-B 鉴权后端 ASR
```

## 2. 产品范围

### 2.1 P0 必须完成

- 工具栏提供“语音转文字”按钮。
- 点击开始识别，再次点击完成；同时提供取消操作。
- 识别中的文字在本地浮层实时预览。
- 最终文字作为一个独立 `TextElement` 插入当前视口中央。
- Android、HarmonyOS、Web 有各自可用实现或明确的 unavailable 降级。
- 权限拒绝、设备不支持、无语音、网络错误和引擎忙均不导致崩溃。
- 退出页面、应用退后台或取消操作后立即释放麦克风。
- 最终文字只触发一次场景变化和一次协作增量同步。

### 2.2 P1 条件能力

仅在 Phase 0/P0 指标未达标时启动：

- Android 使用 `sherpa_onnx` + 中文模型实现端侧离线识别。
- Web 使用 `MediaRecorder` 录音并上传到有鉴权、限流的 FlowMuse ASR 接口。
- HarmonyOS 直接麦克风识别不稳定时，评估 `AudioCapturer + writeAudio()` 显式 PCM 路径。

### 2.3 明确不做

- 原始录音保存、播放、导出和协作同步。
- 后台持续监听、会议录音和长时间转写。
- 说话人分离、语义摘要、敏感词过滤和自动翻译。
- 把中间识别结果写入 `Scene`。
- 修改 Excalidraw 元素格式或协作协议。
- 未经明确提示把移动端录音上传服务端。

## 3. 已确认的项目事实

所有代码路径相对 `FlowMuse-App/`，服务端路径相对 `FlowMuse-Server/`。

| 事实 | 位置 | 决策 |
| --- | --- | --- |
| 已有普通文本元素及完整序列化 | `lib/features/whiteboard/editor_core/src/core/elements/text_element.dart` | 不新增语音元素 |
| 已有视口中央文本插入逻辑 | `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart:3611` | 抽出 `insertPlainText()` 复用 |
| 编辑器局部状态由 `MarkdrawEditor` 管理 | `lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart` | 识别会话不放 Riverpod |
| 移动和桌面工具栏分离 | `compact_toolbar.dart`、`desktop_toolbar.dart` | 两处只接收状态和回调 |
| Android 已集中注册 MethodChannel | `android/app/src/main/kotlin/com/example/flowmuse/MainActivity.kt` | 继续在同一 Activity 注册 |
| HarmonyOS 已有 Channel 模式 | `ohos/entry/src/main/ets/entryability/EntryAbility.ets` | 新建并注册 ArkTS Channel |
| 当前 Flutter OHOS 枚举名为 `TargetPlatform.ohos` | 现有 PDF、图片选择等适配代码 | 禁止使用不存在的 `TargetPlatform.harmonyOS` |
| Web 已依赖 `package:web` | `pubspec.yaml` | P0 不新增 Web 录音依赖 |
| 服务端身份能力可复用 | `internal/auth/http_api.go:IdentityFromRequest` | P1-B 必须验证非访客身份 |
| 现有识别 HTTPAPI 没有通用鉴权中间件 | `internal/recognition/api.go` | P1-B 不能照搬成公开付费接口 |

## 4. 官方依据

### 4.1 Android

- <https://developer.android.com/reference/android/speech/SpeechRecognizer>
- <https://developer.android.com/reference/android/speech/RecognizerIntent>

约束：

- 声明并运行时申请 `android.permission.RECORD_AUDIO`。
- Android 11+ 在 `<queries>` 声明 `android.speech.RecognitionService`。
- `SpeechRecognizer` 在主线程创建和调用，会话结束必须 `destroy()`。
- 使用 `onPartialResults()` 和 `onResults()`。
- 系统实现可能联网，也可能在部分国产 ROM 上缺失，因此必须先检测 `isRecognitionAvailable()`。

### 4.2 HarmonyOS

本地官方 guide：

```text
D:\Program\HarmonyOS\harmonyos-guides\AI\core-speech-kit-guide.md
D:\Program\HarmonyOS\harmonyos-guides\AI\Core Speech Kit（基础语音服务）\core-speech-introduction.md
D:\Program\HarmonyOS\harmonyos-guides\AI\Core Speech Kit（基础语音服务）\speechrecognizer-guide.md
```

在线入口：

- <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/speechrecognizer-guide>
- <https://developer.huawei.com/consumer/cn/sdk/core-speech-kit>

约束：

- 使用 `@kit.CoreSpeechKit` 的 `speechRecognizer`。
- `createEngine()` 创建引擎，`setListener()` 接收结果。
- P0 优先验证官方示例的麦克风 `startListening()` 路径，不自行保存 PCM。
- `finish()` 完成、`cancel()` 取消、`shutdown()` 释放。
- `module.json5` 声明 `ohos.permission.MICROPHONE`，用户点击时才申请。
- 首版固定 `zh-CN`；地区、设备和系统版本限制必须真机核对。
- guide 的能力描述与示例参数存在需要真机确认的点，计划不在验证前承诺完全离线。

### 4.3 Web

- <https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition>
- <https://developer.mozilla.org/en-US/docs/Web/API/Web_Speech_API>
- <https://w3c.github.io/speech-api/speechapi.html>

约束：

- P0 使用 `SpeechRecognition`，兼容 `webkitSpeechRecognition`。
- 设置 `lang='zh-CN'`、`continuous=false`、`interimResults=true`。
- API 不是所有浏览器的 Baseline 能力，必须做构造器特性检测。
- Chrome 等浏览器可能使用远端识别服务；FlowMuse 不保存录音，但不能宣称浏览器完全本地处理。
- 麦克风能力要求 localhost 或 HTTPS 安全上下文。

### 4.4 Android 离线候选

- <https://pub.dev/packages/sherpa_onnx>
- <https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-paraformer/index.html>
- <https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-paraformer/index.html>

约束：

- `sherpa_onnx` 可离线识别，但 Flutter 包会引入原生运行库和模型文件。
- 实施前必须确定唯一模型、ABI、模型体积、内存峰值、分发方式和许可证。
- 不允许在模型分发仍待定时直接并入 P0。

## 5. 统一架构

### 5.1 数据流

```text
Speech button
    │
    ▼
MarkdrawEditor（状态、预览、取消/完成）
    │
    ▼
SpeechRecognitionService
    ├── P0 Android：MethodChannel → SpeechRecognizer
    ├── P0 Harmony：MethodChannel → Core Speech Kit
    ├── P0 Web：Web Speech API
    ├── P1-A Android：sherpa_onnx（同一接口）
    └── P1-B Web：MediaRecorder → 鉴权 HTTP ASR（同一接口）
    │
    ▼
SpeechRecognitionEvent
    ├── partial：仅更新本地预览
    ├── final：insertPlainText()
    ├── state：更新按钮/浮层
    └── error：SnackBar + 清理会话
```

### 5.2 最小公共接口

目录：

```text
lib/features/whiteboard/speech_recognition/
├── models/speech_recognition_event.dart
├── services/speech_recognition_service.dart
├── services/speech_recognition_service_factory.dart
├── services/speech_recognition_service_io.dart
└── services/speech_recognition_service_web.dart
```

接口：

```dart
abstract interface class SpeechRecognitionService {
  Future<bool> isAvailable();
  Stream<SpeechRecognitionEvent> get events;
  Future<void> start({String locale = 'zh-CN'});
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}
```

统一事件：

```text
result(text, isFinal)
state(starting|listening|stopping|idle)
error(permissionDenied|unavailable|busy|noSpeech|network|cancelled|unknown)
```

设计约束：

- P1 实现必须替换底层 service，不修改工具栏、浮层或文本插入 API。
- Dart 工厂只用条件导入区分 Web/IO。
- Android 和 HarmonyOS 共用同名 MethodChannel；原生是否注册决定可用性。
- 其他平台遇到 `MissingPluginException` 返回 unavailable，不崩溃。
- 不为 P1 提前建立 `AudioSource`、录音仓库或模型管理器；只有门槛触发后才新增。

### 5.3 MethodChannel 协议

通道：

```text
flow_muse/speech_recognition
```

Dart → 原生：

| 方法 | 参数 |
| --- | --- |
| `isAvailable` | 无 |
| `start` | `{locale:'zh-CN', partialResults:true, generation:int}` |
| `stop` | `{generation:int}` |
| `cancel` | `{generation:int}` |
| `dispose` | 无 |

原生 → Dart：

| 方法 | 参数 |
| --- | --- |
| `onState` | `{state:String, generation:int}` |
| `onResult` | `{text:String, final:bool, generation:int}` |
| `onError` | `{code:String, message:String, generation:int}` |

约束：

- 同一时刻只允许一个会话。
- 空文本不回传结果。
- cancel/dispose 后 generation 失效，旧回调直接丢弃。
- final 每个 generation 最多提交一次。

### 5.4 编辑器状态

状态只保留在 `_MarkdrawEditorState`：

```text
unavailable → idle → starting → listening → stopping → idle
                         ├── cancel ───────────────► idle
                         └── error ────────────────► idle
```

页面生命周期：

- `initState()` 创建服务并检测可用性。
- `paused/inactive/detached` 取消识别，不提交临时文字。
- `dispose()` 先使 generation 失效，再取消订阅和释放服务。
- partial 只更新一个字符串，不进入 controller。
- final 非空时只调用一次 `insertPlainText()`。

## 6. 文本插入和协作边界

在 `MarkdrawController` 抽出：

```dart
void insertPlainText(String text, {Size? canvasSize})
```

要求：

1. trim 后为空直接返回。
2. 复用 `pasteAsPlaintext()` 的视口中心、文本测量和默认样式。
3. 只 push 一次历史快照。
4. 只 apply 一次 `AddElementResult + SetSelectionResult`。
5. `pasteAsPlaintext()` 改为调用新方法。
6. 最终仍是标准 `TextElement`，不增加 JSON 字段。

协作规则：

- partial 不调用 `onSceneChanged`。
- final 只形成一个 changed element。
- 不新增 Socket.IO 消息类型，不改服务端协作代码。
- 对端只看到最终文字，不同步录音和口述过程。

## 7. UI 与隐私

### 7.1 工具栏

修改：

```text
lib/features/whiteboard/editor_core/src/ui/compact_toolbar.dart
lib/features/whiteboard/editor_core/src/ui/desktop_toolbar.dart
lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart
```

规则：

- 空闲图标 `Icons.mic_none`，监听中 `Icons.stop_circle_outlined`。
- starting/stopping 禁止重复点击。
- 只读模式不显示。
- 不可用时禁用，并用 tooltip/说明文本告知原因。
- 工具栏只接收 `onSpeechPressed`、`speechActive`、`speechAvailable`。

### 7.2 本地预览浮层

- 显示“正在聆听…”或当前 partial 文本。
- 提供“取消”和“完成”。
- 取消不提交；完成等待 final。
- 不使用阻断式 Dialog。
- 错误通过一次 SnackBar 展示。
- 具备语义标签和键盘焦点。

### 7.3 隐私提示

首次使用提示：

```text
FlowMuse 默认不保存录音。语音可能由设备、浏览器或其识别服务处理。
```

P1-B Web 后端启用时必须改为：

```text
Web 端需要把本次音频临时上传到 FlowMuse 语音识别服务；服务完成识别后立即释放，不保存录音。
```

使用 `LocalSettingsRepository` 只保存提示状态：

```text
whiteboard.speechRecognitionNoticeSeen.v1
```

不得记录录音、识别内容和权限选择。

## 8. Phase 0：三端能力与质量基线

> 本阶段只写最小 spike 或调试代码，不接入正式工具栏。输出记录后删除临时代码。

### 8.1 固定测试语料

准备 10 条普通话短句，覆盖：

- 普通陈述句。
- 数字和日期。
- 中英文混合产品名。
- 逗号和停顿。
- 3 秒、10 秒、30 秒长度。

记录：可用性、成功次数、首个 partial 延迟、final 延迟、字符错误率、断网行为。

### 8.2 Android 基线

- [ ] 在至少两台实际验收 Android 设备调用 `SpeechRecognizer.isRecognitionAvailable()`。
- [ ] 完成 10 条在线识别。
- [ ] 断网重复至少 3 条，记录结果但不预设必须成功。
- [ ] 记录是否提供 partial、final P95 延迟和常见错误码。
- [ ] 明确必需支持的 ROM/机型清单。

触发 P1-A 的任一条件：

- 必需验收设备 `isRecognitionAvailable=false`。
- 固定语料成功率低于 90%。
- final P95 超过 3 秒且影响可用性。
- 产品明确要求 Android 首次安装后断网可用。

### 8.3 HarmonyOS 基线

- [ ] 按本地 guide 用 `createEngine + startListening` 完成真机最小 POC。
- [ ] 核对当前 SDK 的 `CreateEngineParams`、结果 final 标志和错误码。
- [ ] 完成 10 条识别并记录 partial/final 行为。
- [ ] 断网重复至少 3 条，确认官方离线模型是否在目标机可用。
- [ ] 验证 cancel、finish、shutdown 后麦克风释放。

若直接麦克风路径不稳定，才进入 `AudioCapturer + writeAudio()` POC；不得直接把显式 PCM 管线作为默认实现。

### 8.4 Web 基线

- [ ] Chrome、Edge 检测 `SpeechRecognition/webkitSpeechRecognition`。
- [ ] 如产品要求 Firefox/Safari，同步检测并记录，不假设支持。
- [ ] 在 localhost/HTTPS 完成权限允许和拒绝路径。
- [ ] 完成 10 条识别并记录 partial/final 和延迟。

触发 P1-B 的任一条件：

- 验收范围包含没有 SpeechRecognition 的浏览器。
- 固定语料成功率低于 90%。
- 产品要求浏览器识别供应商和结果一致。

### 8.5 Phase 0 产物

新增：

```text
docs/研发记录/research/speech-to-text-capability-baseline.md
```

必须包含设备/浏览器版本、网络状态、10 条语料结果和 P1-A/P1-B go/no-go。没有这份数据不得启动 sherpa 或后端 ASR。

## 9. P0 实施任务

### Task 1：通用文本插入

**Files**

- Modify: `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Test: `test/features/whiteboard/editor_core/speech_text_insertion_test.dart`

- [ ] 测试空白不插入。
- [ ] 测试有效文字只新增一个 `TextElement`。
- [ ] 测试尺寸有限且位于视口中央。
- [ ] 测试一次 undo 完整撤销。
- [ ] 实现 `insertPlainText()` 并复用到剪贴板粘贴。

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/editor_core/speech_text_insertion_test.dart
```

### Task 2：Dart 协议和 IO Channel

**Files**

- Create: `lib/features/whiteboard/speech_recognition/models/speech_recognition_event.dart`
- Create: `lib/features/whiteboard/speech_recognition/services/speech_recognition_service.dart`
- Create: `lib/features/whiteboard/speech_recognition/services/speech_recognition_service_factory.dart`
- Create: `lib/features/whiteboard/speech_recognition/services/speech_recognition_service_io.dart`
- Test: `test/features/whiteboard/speech_recognition/speech_recognition_service_io_test.dart`

- [ ] 测试 MethodChannel unavailable。
- [ ] 测试 partial/final/error 映射。
- [ ] 测试每代 final 只发一次。
- [ ] 测试 cancel 后迟发回调被丢弃。
- [ ] dispose 解除 handler 并关闭 stream。

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/speech_recognition/speech_recognition_service_io_test.dart
```

### Task 3：编辑器 UI 和状态机

**Files**

- Modify: `lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`
- Modify: `lib/features/whiteboard/editor_core/src/ui/compact_toolbar.dart`
- Modify: `lib/features/whiteboard/editor_core/src/ui/desktop_toolbar.dart`
- Test: `test/features/whiteboard/editor_core/speech_recognition_ui_test.dart`

- [ ] service 可注入，测试使用 fake。
- [ ] partial 只更新浮层。
- [ ] final 插入一次。
- [ ] cancel/error/dispose 不插入。
- [ ] 页面进入后台取消会话。
- [ ] 加入首次隐私提示。

### Task 4：Android 系统识别

**Files**

- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/example/flowmuse/MainActivity.kt`

- [ ] 增加 `RECORD_AUDIO` 和 RecognitionService query。
- [ ] 注册统一 Channel。
- [ ] 使用独立权限 request code，不与图片选择 `7011` 冲突。
- [ ] 主线程创建 recognizer。
- [ ] 配置 `LANGUAGE_MODEL_FREE_FORM`、`zh-CN`、partial。
- [ ] 映射错误码。
- [ ] stop/cancel/dispose/onDestroy 释放资源。

```bash
cd FlowMuse-App
flutter build apk --debug
```

### Task 5：HarmonyOS Core Speech Kit

**Files**

- Create: `ohos/entry/src/main/ets/channels/SpeechRecognitionChannel.ets`
- Modify: `ohos/entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `ohos/entry/src/main/module.json5`

- [ ] 按 Phase 0 已验证参数创建引擎。
- [ ] 用户点击时申请麦克风权限。
- [ ] 设置 RecognitionListener。
- [ ] 直接麦克风 `startListening()`。
- [ ] 映射 partial/final；无明确 final 时由 onComplete 补最后一次非空结果。
- [ ] finish/cancel/shutdown 完整清理。
- [ ] EntryAbility 注册 Channel。

```bash
cd FlowMuse-App
flutter build hap
```

### Task 6：Web Speech API

**Files**

- Create: `lib/features/whiteboard/speech_recognition/services/speech_recognition_service_web.dart`
- Test: `test/features/whiteboard/speech_recognition/speech_recognition_service_web_test.dart`（浏览器环境可运行时）

- [ ] 用 `dart:js_interop` + `package:web` 建立最小绑定。
- [ ] 检测标准和 webkit 构造器。
- [ ] 映射 result/error/start/end。
- [ ] stop 完成、abort 取消。
- [ ] generation 丢弃旧事件。
- [ ] 不支持时返回 unavailable。

```bash
cd FlowMuse-App
flutter build web
```

### Task 7：P0 回归

- [ ] partial 期间 `onSceneChanged` 为 0 次。
- [ ] final 只产生一个文本元素和一次用户编辑事件。
- [ ] 取消不产生 history。
- [ ] Excalidraw JSON 往返不丢文字。
- [ ] 协作对端只出现一个最终文本。
- [ ] 不生成本地录音文件。

```bash
cd FlowMuse-App
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
flutter build apk --debug
flutter build hap
```

## 10. P1-A：Android sherpa_onnx 离线路径（条件实施）

### 10.1 准入门槛

只有 `speech-to-text-capability-baseline.md` 明确 P1-A=go 才实施。

### 10.2 先决决策

实施代码前必须在文档中固定：

- 唯一模型名称、下载地址、SHA-256 和许可证。
- 模型压缩包大小、解压大小和运行内存峰值。
- 只支持 arm64 还是包含更多 ABI。
- 随 APK 打包或首次按需下载。
- 下载失败、空间不足、校验失败和版本升级策略。

推荐默认：

- 先做 arm64 真机 spike。
- 选择一个中文 int8 小模型。
- 模型不直接塞入首版 APK；如采用下载，必须显式展示大小、Wi-Fi 建议、进度、取消和重试。
- 系统 SpeechRecognizer 仍为首选；sherpa 只在系统不可用或用户选择离线时启用。

### 10.3 文件范围

可能新增：

```text
lib/features/whiteboard/speech_recognition/services/sherpa_speech_recognition_service.dart
lib/features/whiteboard/speech_recognition/services/speech_model_store.dart
lib/features/whiteboard/speech_recognition/models/speech_model_manifest.dart
```

只在确实需要时增加录音流依赖；优先复用 sherpa 官方示例支持的输入路径。不得同时引入多个录音插件。

### 10.4 验收

- [ ] 目标国产 Android 无系统识别服务时可离线识别。
- [ ] 固定语料成功率不少于 P0 系统基线。
- [ ] final P95 不超过 3 秒，或有明确产品批准。
- [ ] 内存峰值、模型体积和下载时间已记录。
- [ ] 模型下载可取消、可校验、失败不会阻塞白板启动。
- [ ] 不影响 HarmonyOS 和 Web 构建。

## 11. P1-B：Web 鉴权后端 ASR（条件实施）

### 11.1 准入门槛

只有基线确认验收浏览器缺少 Web Speech API，或产品要求统一识别供应商，才实施。

### 11.2 客户端

新增：

```text
lib/features/whiteboard/speech_recognition/services/web_backend_speech_recognition_service.dart
```

行为：

- `getUserMedia + MediaRecorder` 生成浏览器支持的短音频。
- 录音上限 60 秒；停止后上传，P1-B 不承诺 partial。
- MIME 类型从 MediaRecorder 实际输出读取，不硬编码。
- 上传前显示明确的数据流向提示并获得用户操作确认。
- 请求携带现有账户 Bearer token；未登录用户不开放付费后端识别。
- 最终仍通过统一 service 事件返回 final。

### 11.3 服务端

新增：

```text
FlowMuse-Server/internal/speech/api.go
FlowMuse-Server/internal/speech/transcriber.go
FlowMuse-Server/internal/speech/openai_transcriber.go
FlowMuse-Server/internal/speech/types.go
```

接口：

```text
POST /api/speech/transcribe
Content-Type: multipart/form-data
Authorization: Bearer <account token>
```

安全边界：

- `HTTPAPI` 构造函数必须注入现有身份源，调用 `IdentityFromRequest()`。
- 访客或无效 token 返回 401，不能只读取 Header 而不验证。
- `http.MaxBytesReader` 首版上限 10 MiB。
- 只允许明确 MIME allowlist，文件名和客户端 format 不可信。
- 请求超时默认 120 秒，客户端断开应取消上游请求。
- 按已验证用户做频率限制；至少限制并发数和每分钟请求数。
- 音频只保留在请求内存/临时流中，不写数据库、MinIO 或日志。
- 上游错误不把 API key、URL 参数或完整响应泄露给客户端。
- 不实现 `faster-whisper`、CGo 或子进程，除非另立计划。

配置只在 P1-B 启用：

```text
FLOWMUSE_SPEECH_BASE_URL
FLOWMUSE_SPEECH_API_KEY
FLOWMUSE_SPEECH_MODEL
FLOWMUSE_SPEECH_TIMEOUT
```

未配置时接口返回 503，服务器其他功能照常启动。

### 11.4 服务端测试

- [ ] 无 token/无效 token 返回 401。
- [ ] 超过 10 MiB 返回 413。
- [ ] 非法 MIME 返回 415。
- [ ] 上游超时返回 504/502 且上下文取消。
- [ ] 正常请求只返回文本，不保存音频。
- [ ] 限流触发返回 429。

```bash
cd FlowMuse-Server
go test ./...
go vet ./...
```

## 12. 分阶段提交建议

| 提交 | 内容 |
| --- | --- |
| 1 | `docs:记录语音识别三端能力基线` |
| 2 | `refactor:复用白板纯文本插入链路` |
| 3 | `feat:建立跨平台语音识别协议` |
| 4 | `feat:增加白板语音转文字交互` |
| 5 | `feat:接入Android系统语音识别` |
| 6 | `feat:接入鸿蒙Core Speech Kit语音识别` |
| 7 | `feat:接入Web Speech API语音识别` |
| 8 | `test:补充语音转文字跨端回归验证` |

P1-A/P1-B 必须独立 PR/提交序列，不与 P0 混合，便于回滚。

## 13. P0 验收清单

### 13.1 共同

- [ ] 只读模式不显示语音输入。
- [ ] 开始、监听、完成、取消状态清晰。
- [ ] partial 不改场景。
- [ ] final 只新增一个标准文本元素。
- [ ] 文字可编辑、移动、删除、撤销和重做。
- [ ] 重开笔记、导出 `.markdraw/.excalidraw` 后文字存在。
- [ ] 协作对端只收到一次最终文字。
- [ ] 取消、权限拒绝、错误和页面退出不生成文本。
- [ ] 应用私有目录、数据库和对象存储没有录音。

### 13.2 Android

- [ ] 当前必需验收设备完成权限允许和拒绝。
- [ ] `isRecognitionAvailable=false` 时安全降级。
- [ ] Activity 销毁后麦克风立即释放。

### 13.3 HarmonyOS

- [ ] 真机完成权限、识别、完成、取消和释放。
- [ ] 不出现 `Unsupported operation: unsupported_platform`。
- [ ] 用完整 HAP 重编译验收，不以热重载替代原生验证。

### 13.4 Web

- [ ] Chrome/Edge 在 localhost 或 HTTPS 验收。
- [ ] 权限拒绝有可读提示。
- [ ] 构造器不存在时禁用能力，白板不白屏。

## 14. 风险、降级与回滚

| 风险 | 默认处理 | 升级路径 |
| --- | --- | --- |
| 国产 Android 缺系统识别 | unavailable，不阻塞白板 | 数据触发 P1-A sherpa |
| Android 系统识别不离线 | 如实提示，不伪称离线 | P1-A |
| Web API 浏览器碎片化 | 特性检测，首版 Chrome/Edge | 数据触发 P1-B |
| 鸿蒙直接麦克风路径不稳定 | 先 POC 核对参数 | 显式 PCM spike |
| partial 过于频繁 | 仅更新浮层；必要时 50ms 合并 | 不得写 Scene |
| 旧会话回调污染 | generation 丢弃 | 无需协议升级 |
| 麦克风未释放 | 生命周期 cancel + dispose | 平台真机回归 |
| 后端被滥用 | P0 不提供接口 | P1-B 强鉴权、限流、大小限制 |

每个平台实现独立提交。回滚某个平台后只会变为 unavailable；已经生成的 `TextElement` 始终可以正常打开。

## 15. 完成定义

### P0 完成

1. `speech-to-text-capability-baseline.md` 已填写。
2. Android、HarmonyOS、Web 构建通过。
3. Android 与 HarmonyOS 真机完成允许、拒绝、停止、取消和页面退出测试。
4. Web 完成支持与不支持两条路径。
5. 自动化测试证明 partial=0 次场景修改、final=1 次插入、cancel=0 次插入。
6. 全量 `flutter analyze` 和 `flutter test` 不新增失败。
7. 协作双方确认最终文字只出现一次，书写和同步无明显性能回退。
8. 没有录音持久化，也没有服务端改动。

### P1-A/P1-B 完成

必须分别满足对应章节的准入门槛、测试和真机/服务端验收；不能用“未来可能需要”作为启动理由。
