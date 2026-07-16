# FlowMuse 跨平台语音转文字实施计划

> 日期：2026-07-15  
> 分支：`语音转文字`  
> 实施范围：Android、HarmonyOS、Web  
> 计划目录沿用仓库既有约定：`docs/superpowers/plans/`

## 1. 目标

在白板编辑器中增加“语音转文字”入口。用户点击麦克风后开始识别，识别中的临时文字只在本地浮层预览；用户停止或平台返回最终结果后，将文字作为一个普通 `TextElement` 插入当前视口中央。

首版必须满足：

- Android 使用系统 `android.speech.SpeechRecognizer`。
- HarmonyOS 使用官方 Core Speech Kit 的 `speechRecognizer`。
- Web 使用浏览器 Web Speech API；浏览器不支持时明确显示不可用，不影响白板其他功能。
- 最终文字复用现有 `TextElement`、撤销、场景保存、Excalidraw 序列化和协作同步链路。
- 不保存原始录音，不新增数据库表，不修改协作协议，不调用 FlowMuse 服务端。

## 2. 非目标

本计划不包含：

- 保存、播放、导出原始录音。
- 长时间会议录音或后台持续转写。
- 自建或第三方云端 ASR 服务。
- 多语言自动检测；首版固定请求 `zh-CN`。
- 将每次中间识别结果写入白板或发送给协作对端。
- 把识别结果插入正在编辑文本框的光标位置；首版创建独立文本元素。
- iOS、macOS、Windows 的原生识别实现；这些平台必须安全返回“不可用”。

## 3. 已确认的代码事实

所有路径相对 `FlowMuse-App/`。

| 事实 | 代码位置 | 对方案的影响 |
| --- | --- | --- |
| 文本元素已有完整模型、渲染和序列化链路 | `lib/features/whiteboard/editor_core/src/core/elements/text_element.dart` | 不新增语音专用元素类型 |
| `pasteAsPlaintext()` 已能在视口中央创建文本元素 | `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart:3611` | 抽出通用 `insertPlainText()`，语音和剪贴板共同复用 |
| `applyResult()` 会进入历史、场景变化和现有保存链路 | `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart` | 最终结果只需提交一次普通 `AddElementResult` |
| 移动端和桌面端工具栏是两个组件 | `compact_toolbar.dart`、`desktop_toolbar.dart` | 两处只增加同一组回调和状态，不复制业务逻辑 |
| 编辑器局部交互状态由 `MarkdrawEditor` 自己持有 | `lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart` | 录音/识别状态不放 Riverpod，也不持久化 |
| Android 已在 `MainActivity` 注册多个 MethodChannel | `android/app/src/main/kotlin/com/example/flowmuse/MainActivity.kt` | 在同一 Activity 注册语音通道，避免新增插件 |
| 鸿蒙已有标准 Channel 注册模式 | `ohos/entry/src/main/ets/entryability/EntryAbility.ets` | 新建 `SpeechRecognitionChannel.ets` 并在此注册 |
| Web 已依赖 `web: ^1.1.0` | `pubspec.yaml` | 使用浏览器 API，不新增语音依赖 |

## 4. 官方能力与约束

### 4.1 Android

官方 API：

- <https://developer.android.com/reference/android/speech/SpeechRecognizer>
- <https://developer.android.com/reference/android/speech/RecognizerIntent>

实施约束：

- 需要 `android.permission.RECORD_AUDIO`，Android 6.0+ 运行时申请。
- Android 11+ 需要在 Manifest 的 `<queries>` 中声明 `android.speech.RecognitionService`。
- `SpeechRecognizer` 的创建、调用和销毁都在主线程执行。
- 注册 `RecognitionListener`，分别接收 `onPartialResults`、`onResults` 和 `onError`。
- 会话结束或 Activity 销毁时必须调用 `destroy()`。
- 系统识别服务可能把音频交给设备配置的远端服务；FlowMuse 自身不保存音频。
- 不做自动无限重启。官方明确该 API 不适合持续监听；首版每次点击只开启一个短会话。

### 4.2 HarmonyOS

本地官方资料：

```text
D:\Program\HarmonyOS\harmonyos-guides\AI\core-speech-kit-guide.md
D:\Program\HarmonyOS\harmonyos-guides\AI\Core Speech Kit（基础语音服务）\core-speech-introduction.md
D:\Program\HarmonyOS\harmonyos-guides\AI\Core Speech Kit（基础语音服务）\speechrecognizer-guide.md
```

在线官方入口：

- <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/speechrecognizer-guide>
- <https://developer.huawei.com/consumer/cn/sdk/core-speech-kit>

实施约束：

- 从 `@kit.CoreSpeechKit` 导入 `speechRecognizer`。
- 使用 `createEngine()` 创建 `SpeechRecognitionEngine`。
- 首版参数使用 `language: 'zh-CN'`、短语音模式；实现前以当前 SDK 类型定义核对 `online` 和 `extraParams` 的合法值。
- 用 `RecognitionListener.onResult()` 接收中间结果和最终结果；以 SDK 返回字段判断最终态，若 SDK 不提供明确最终标志，则只在 `onComplete()` 时把最后一次非空结果标记为最终结果。
- 使用 `startListening()` 开始麦克风识别；首版不创建 PCM 文件、不调用 `writeAudio()` 喂本地录音文件。
- `module.json5` 声明 `ohos.permission.MICROPHONE`，并且只在用户点击麦克风后申请权限。
- 结束调用 `finish()`，取消调用 `cancel()`，释放调用 `shutdown()`。
- 官方当前能力以中文普通话为主；真机验收不承诺其他语言。
- 目标设备不支持、引擎忙、初始化超时等错误必须映射为可读错误，不能让 Flutter 页面崩溃。

### 4.3 Web

规范和兼容性资料：

- <https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition>
- <https://developer.mozilla.org/en-US/docs/Web/API/Web_Speech_API>
- <https://w3c.github.io/speech-api/speechapi.html>

实施约束：

- 使用 `SpeechRecognition`，并兼容 Chromium 的 `webkitSpeechRecognition` 构造器。
- 配置 `lang = 'zh-CN'`、`continuous = false`、`interimResults = true`、`maxAlternatives = 1`。
- `result` 事件中读取 transcript 和 `isFinal`。
- `stop()` 尝试产出最终结果；`abort()` 用于取消且不提交文本。
- Web Speech API 不是所有浏览器的 Baseline 能力。构造器不存在时返回 unavailable，UI 显示“当前浏览器不支持语音识别”。
- Chrome 等浏览器可能使用服务端识别且离线不可用；UI 首次使用提示“语音可能由系统或浏览器识别服务处理”。
- Web 真机验收至少覆盖最新版 Chrome 和 Edge；Firefox 不作为首版通过条件。

## 5. 架构设计

### 5.1 数据流

```text
工具栏麦克风按钮
        │
        ▼
MarkdrawEditor（会话状态、临时文字、错误提示）
        │
        ▼
SpeechRecognitionService
        ├── IO：MethodChannel('flow_muse/speech_recognition')
        │      ├── Android SpeechRecognizer
        │      └── HarmonyOS Core Speech Kit
        └── Web：SpeechRecognition / webkitSpeechRecognition
        │
        ▼
SpeechRecognitionEvent(text, isFinal)
        ├── isFinal=false：仅更新本地浮层
        └── isFinal=true：controller.insertPlainText(text)
                              │
                              ├── HistoryManager
                              ├── onSceneChanged / 自动保存
                              ├── Excalidraw JSON
                              └── 现有协作增量同步
```

### 5.2 Dart 公共协议

创建目录：

```text
lib/features/whiteboard/speech_recognition/
├── models/speech_recognition_event.dart
├── services/speech_recognition_service.dart
├── services/speech_recognition_service_factory.dart
├── services/speech_recognition_service_io.dart
└── services/speech_recognition_service_web.dart
```

公共接口保持最小：

```dart
abstract interface class SpeechRecognitionService {
  Future<bool> isAvailable();
  Stream<SpeechRecognitionEvent> get events;
  Future<void> start({String locale = 'zh-CN'});
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class SpeechRecognitionEvent {
  const SpeechRecognitionEvent.result(this.text, {required this.isFinal});
  const SpeechRecognitionEvent.state(this.state);
  const SpeechRecognitionEvent.error(this.code, this.message);
}
```

实现原则：

- 工厂只通过条件导入区分 Web 与 IO，不在共享代码中使用 `Platform.is*`。
- IO 实现对 Android、HarmonyOS 使用同一个 MethodChannel 协议；其他 IO 平台遇到 `MissingPluginException` 时返回 unavailable。
- `events` 使用单一广播流；`dispose()` 关闭流并解除 Channel handler。
- 同一时刻只允许一个会话。重复 `start()` 返回 `alreadyListening`，不叠加引擎。
- 所有平台统一错误码：`permissionDenied`、`unavailable`、`busy`、`noSpeech`、`network`、`cancelled`、`unknown`。

### 5.3 MethodChannel 协议

通道名：

```text
flow_muse/speech_recognition
```

Dart 调原生：

| 方法 | 参数 | 返回 |
| --- | --- | --- |
| `isAvailable` | 无 | `bool` |
| `start` | `{locale: 'zh-CN', partialResults: true}` | `null` 或 PlatformException |
| `stop` | 无 | `null` |
| `cancel` | 无 | `null` |
| `dispose` | 无 | `null` |

原生回调 Dart：

| 方法 | 参数 |
| --- | --- |
| `onState` | `{state: 'listening'|'stopped'}` |
| `onResult` | `{text: String, final: bool}` |
| `onError` | `{code: String, message: String}` |

协议要求：

- 空白 transcript 不发送 `onResult`。
- `cancel` 后到达的迟发回调必须忽略，不能插入文字。
- 每个会话生成递增 `sessionGeneration`；Dart 和原生实现至少一侧检查 generation，防止旧会话回调污染新会话。
- `stop` 可以等待最终结果；UI 在收到 final、error 或 stopped 后结束忙碌状态。

### 5.4 编辑器状态

状态保留在 `_MarkdrawEditorState`，不进入 Riverpod：

```text
unavailable → idle → starting → listening → stopping → idle
                         └──────── error ──────────────┘
```

需要的最小字段：

- `SpeechRecognitionService? _speechService`
- `StreamSubscription? _speechSubscription`
- `SpeechRecognitionStatus _speechStatus`
- `String _speechPreview`
- `int _speechGeneration`
- `bool _speechAvailable`

生命周期规则：

- `initState()` 创建服务并异步检查可用性。
- `dispose()` 先递增 generation，再取消订阅、取消识别、释放服务。
- 页面退到后台时首版不继续监听；在 `AppLifecycleState.paused/inactive/detached` 调用 `cancel()`。
- 取消、报错、页面销毁均不提交当前临时文字。
- 只有带 `isFinal=true` 的非空结果调用一次 `insertPlainText()`。
- 如果平台只在 complete 时给最终态，适配层负责生成一次 final 事件，UI 不猜测。

## 6. 文本插入与协作边界

在 `MarkdrawController` 中抽出同步方法：

```dart
void insertPlainText(String text, {Size? canvasSize})
```

行为：

1. `trim()` 后为空则直接返回。
2. 优先使用传入尺寸，否则使用 controller 已记录的 `_canvasSize`。
3. 尺寸无效时使用视口已有安全默认中心，不能产生 NaN/Infinity。
4. 复用当前 `pasteAsPlaintext()` 的 `TextElement` 创建、`TextRenderer.measure()`、默认样式和选择逻辑。
5. 只 push 一次历史快照，只调用一次 `applyResult()`。
6. `pasteAsPlaintext()` 改为读取剪贴板后调用该方法。

协作约束：

- 中间结果只存在 `_speechPreview`，不进入 `Scene`。
- 最终结果只新增一个 `TextElement`，因此沿现有 changed-element 增量广播发送一次。
- 不新增 Socket.IO 消息类型，不修改服务端。
- 接收端看到的是最终文本，不显示对方的实时口述过程。
- 协作会话中语音插入失败时不产生空元素或半成品。

## 7. UI 设计

### 7.1 工具栏按钮

修改：

```text
lib/features/whiteboard/editor_core/src/ui/compact_toolbar.dart
lib/features/whiteboard/editor_core/src/ui/desktop_toolbar.dart
lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart
```

按钮规则：

- 图标使用 Material `Icons.mic_none`；监听中使用 `Icons.stop_circle_outlined`。
- tooltip：空闲为“语音转文字”，监听中为“停止语音识别”。
- unavailable 时按钮保持可见但禁用，便于用户理解功能存在；点击不可用提示不依赖按钮点击。
- `starting/stopping` 时禁用重复操作并显示小型进度状态。
- 只在可编辑模式显示；`viewMode` 下不显示。
- 工具栏只接收 `onSpeechPressed`、`speechActive`、`speechAvailable`，不直接依赖识别服务。

### 7.2 临时结果浮层

在 `MarkdrawEditor` 的现有 Stack 中增加一个轻量浮层：

- 显示“正在聆听…”或当前 `_speechPreview`。
- 提供“取消”和“完成”两个按钮。
- “取消”调用 `cancel()`，不插入文字。
- “完成”调用 `stop()`，等待平台 final 回调。
- 不使用阻断式 Dialog。
- 错误通过 `ScaffoldMessenger` 显示一次 SnackBar。
- 浮层具备语义标签，按钮可由键盘聚焦。

### 7.3 隐私提示

第一次开始识别前显示非阻断提示：

```text
FlowMuse 不保存录音；语音可能由设备或浏览器提供的识别服务处理。
```

只记录“已提示”布尔值，复用 `LocalSettingsRepository`，key 为：

```text
whiteboard.speechRecognitionNoticeSeen.v1
```

不记录语音、识别文本或权限选择。

## 8. 分阶段实施任务

### Task 1：抽出通用文本插入方法

**Files**

- Modify: `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Test: `test/features/whiteboard/editor_core/speech_text_insertion_test.dart`

- [ ] 写测试：空白文本不改变场景。
- [ ] 写测试：有效文本只新增一个 `TextElement`，内容经过 trim。
- [ ] 写测试：文本元素位于当前视口中心附近，尺寸为有限正数。
- [ ] 写测试：undo 能一次撤销该文本元素。
- [ ] 实现 `insertPlainText()`。
- [ ] 让 `pasteAsPlaintext()` 复用新方法。
- [ ] 运行：

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/editor_core/speech_text_insertion_test.dart
```

预期：PASS。

建议提交：

```text
refactor:复用白板纯文本插入链路
```

### Task 2：建立 Dart 识别协议和 IO Channel 适配

**Files**

- Create: `lib/features/whiteboard/speech_recognition/models/speech_recognition_event.dart`
- Create: `lib/features/whiteboard/speech_recognition/services/speech_recognition_service.dart`
- Create: `lib/features/whiteboard/speech_recognition/services/speech_recognition_service_factory.dart`
- Create: `lib/features/whiteboard/speech_recognition/services/speech_recognition_service_io.dart`
- Test: `test/features/whiteboard/speech_recognition/speech_recognition_service_io_test.dart`

- [ ] 定义最小公共接口和统一事件。
- [ ] IO 实现注册原生回调 handler。
- [ ] 映射 `onState/onResult/onError`。
- [ ] 捕获 `MissingPluginException` 和 `PlatformException`。
- [ ] generation 失效后忽略迟发回调。
- [ ] `dispose()` 解除 handler 并关闭 StreamController。
- [ ] 用 `TestDefaultBinaryMessenger` 模拟 MethodChannel。
- [ ] 验证 unavailable、partial、final、error、cancel 后迟发结果。
- [ ] 运行：

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/speech_recognition/speech_recognition_service_io_test.dart
```

预期：PASS。

建议提交：

```text
feat:建立跨平台语音识别协议
```

### Task 3：接入编辑器 UI 与本地状态机

**Files**

- Modify: `lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`
- Modify: `lib/features/whiteboard/editor_core/src/ui/compact_toolbar.dart`
- Modify: `lib/features/whiteboard/editor_core/src/ui/desktop_toolbar.dart`
- Test: `test/features/whiteboard/editor_core/speech_recognition_ui_test.dart`

- [ ] 给 `MarkdrawEditor` 增加可选 service 注入点，生产环境为空时走默认工厂，测试传 fake。
- [ ] 初始化并检查 `isAvailable()`。
- [ ] 增加麦克风按钮和状态切换。
- [ ] 增加临时结果浮层。
- [ ] partial 只刷新浮层，不修改 Scene。
- [ ] final 只调用一次 `insertPlainText()`。
- [ ] cancel、error、dispose 不插入文字。
- [ ] paused/inactive 时取消识别。
- [ ] 测试按钮状态、partial 不改场景、final 新增一个文本、cancel 不新增。
- [ ] 运行：

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/editor_core/speech_recognition_ui_test.dart
```

预期：PASS。

建议提交：

```text
feat:增加白板语音转文字交互
```

### Task 4：Android 原生实现

**Files**

- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/example/flowmuse/MainActivity.kt`

- [ ] Manifest 增加 `RECORD_AUDIO`。
- [ ] `<queries>` 增加 `android.speech.RecognitionService`。
- [ ] 注册 `flow_muse/speech_recognition` MethodChannel。
- [ ] `isAvailable` 调用 `SpeechRecognizer.isRecognitionAvailable()`。
- [ ] 用户点击 start 后检查并申请运行时权限。
- [ ] 权限通过后在主线程创建 recognizer 和 listener。
- [ ] `RecognizerIntent` 设置 `LANGUAGE_MODEL_FREE_FORM`、`zh-CN`、partial results。
- [ ] partial/final 统一回调 Dart。
- [ ] Android 错误码映射为公共错误码。
- [ ] stop/cancel/dispose/onDestroy 正确释放 recognizer。
- [ ] 已有图片选择 request code 为 `7011`；语音权限使用独立常量，避免冲突。
- [ ] 构建：

```bash
cd FlowMuse-App
flutter build apk --debug
```

预期：APK 构建成功。

真机检查：

- 首次点击弹出麦克风权限。
- 拒绝后不崩溃，再次点击给出可读提示。
- 普通话中间结果可见，停止后生成一个文本元素。
- 返回页面或杀掉 Activity 后麦克风指示立即消失。

建议提交：

```text
feat:接入Android系统语音识别
```

### Task 5：HarmonyOS Core Speech Kit 实现

**Files**

- Create: `ohos/entry/src/main/ets/channels/SpeechRecognitionChannel.ets`
- Modify: `ohos/entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `ohos/entry/src/main/module.json5`

- [ ] 按本计划 4.2 的本地 guide 再次核对当前 SDK 类型签名。
- [ ] `module.json5` 声明 `ohos.permission.MICROPHONE`、reason 和 in-use scene。
- [ ] Channel 构造函数接收 UIAbilityContext。
- [ ] start 时使用 `abilityAccessCtrl.createAtManager()` 请求权限。
- [ ] `createEngine()` 初始化 `SpeechRecognitionEngine`。
- [ ] 设置 `RecognitionListener`。
- [ ] 将 onStart/onResult/onComplete/onError 映射到 Dart 协议。
- [ ] 对 SDK 没有明确 final 标志的情况，在 onComplete 只提交最后一次非空结果一次。
- [ ] stop 使用 `finish()`；cancel 使用 `cancel()`；dispose 使用 `shutdown()`。
- [ ] 在 `EntryAbility.configureFlutterEngine()` 注册 Channel。
- [ ] 原生异常全部转成 `result.error` 或 `onError`，不得抛穿 Flutter。
- [ ] 构建：

```bash
cd FlowMuse-App
flutter build hap
```

预期：HAP 构建成功。

真机检查：

- 首次点击弹出麦克风权限。
- 中文普通话短句能得到结果。
- 引擎忙或不支持时显示可读错误，不出现 `unsupported_platform`。
- 停止、取消、离开页面都释放引擎和麦克风。
- 不生成本地 PCM 或其他录音文件。

建议提交：

```text
feat:接入鸿蒙Core Speech Kit语音识别
```

### Task 6：Web Speech API 实现

**Files**

- Create: `lib/features/whiteboard/speech_recognition/services/speech_recognition_service_web.dart`
- Test: `test/features/whiteboard/speech_recognition/speech_recognition_service_web_test.dart`（浏览器测试可行时）

- [ ] 使用 `dart:js_interop`/`package:web` 定义最小 SpeechRecognition 绑定。
- [ ] 优先查找 `SpeechRecognition`，回退 `webkitSpeechRecognition`。
- [ ] 构造器不存在时 `isAvailable()` 返回 false。
- [ ] 映射 result、error、start、end 事件。
- [ ] 设置 `zh-CN`、非 continuous、启用 interim results。
- [ ] stop 与 abort 分别对应完成和取消。
- [ ] generation 失效后忽略迟发 result/end。
- [ ] 不引入 `dart:html`，避免已弃用 API。
- [ ] 构建：

```bash
cd FlowMuse-App
flutter build web
```

预期：Web 构建成功。

浏览器检查：

- Chrome/Edge 在 localhost 或 HTTPS 下可申请麦克风并识别。
- 用户拒绝权限时显示权限错误。
- 不支持的浏览器按钮禁用，白板仍可正常使用。
- partial 不写 Scene，final 只新增一个文本元素。

建议提交：

```text
feat:接入Web Speech API语音识别
```

### Task 7：隐私提示、协作与回归验收

**Files**

- Modify: `lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`
- Test: `test/features/whiteboard/editor_core/speech_collaboration_boundary_test.dart`
- Optional docs: `FlowMuse-App/docs/architecture.md`

- [ ] 首次点击前显示一次隐私提示，复用 `LocalSettingsRepository`。
- [ ] 验证 partial 回调期间 `onSceneChanged` 调用次数为 0。
- [ ] 验证 final 回调只触发一次用户编辑场景变化。
- [ ] 验证最终元素可完成 Excalidraw JSON 往返。
- [ ] 验证协作 adapter 将其视为普通 changed element。
- [ ] 验证取消不会产生 undo 记录。
- [ ] 验证连续两次会话不会收到上一会话的迟发结果。
- [ ] 执行完整静态检查与测试：

```bash
cd FlowMuse-App
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
flutter build apk --debug
flutter build hap
```

预期：不新增 analyze error，全部既有测试通过，三端构建通过。

建议提交：

```text
test:补充语音转文字跨端回归验证
```

## 9. 验收清单

### 9.1 三端共同验收

- [ ] 可编辑白板显示麦克风按钮，只读模式不显示。
- [ ] 点击开始后有明确“正在聆听”状态。
- [ ] 中间结果更新浮层但不改变白板。
- [ ] 点击完成后只生成一个文本元素。
- [ ] 点击取消不生成元素。
- [ ] 空结果不生成元素。
- [ ] 生成文本可以移动、编辑、删除、撤销和重做。
- [ ] 关闭并重新打开笔记后文字存在。
- [ ] `.markdraw` 和 `.excalidraw` 导出后文字存在。
- [ ] 协作对端只收到最终文本，且只出现一次。
- [ ] 识别期间书写、缩放、平移和已有协作功能没有明显性能回退。
- [ ] FlowMuse 私有目录中没有新增录音文件。

### 9.2 Android

- [ ] 支持与拒绝麦克风权限路径均已测试。
- [ ] 至少一台国产 Android 真机完成普通话识别。
- [ ] 页面退出、应用退后台和 Activity 销毁都会释放麦克风。

### 9.3 HarmonyOS

- [ ] 真机完成权限申请、普通话识别、停止、取消和释放。
- [ ] 不出现 `Unsupported operation: unsupported_platform`。
- [ ] HAP 全量重编译后验收，不用热重载代替原生验证。

### 9.4 Web

- [ ] Chrome 和 Edge 在 localhost/HTTPS 验收。
- [ ] 权限拒绝有提示。
- [ ] 不支持 SpeechRecognition 的浏览器安全降级。
- [ ] Web 白屏、路由和现有协作功能无回归。

## 10. 风险与降级

| 风险 | 处理 |
| --- | --- |
| Android ROM 没有可用 RecognitionService | `isAvailable=false`，按钮禁用，不引入替代云服务 |
| Android/浏览器识别依赖网络 | 映射 network 错误并允许重试，不缓存音频 |
| 鸿蒙 SDK 参数或 final 语义随版本变化 | 实施前按本地 guide 和当前 SDK `.d.ts` 核对；onComplete 仅补一次最终结果 |
| Web 浏览器支持不一致 | 特性检测，不按 UA 判断；Chrome/Edge 是首版验收目标 |
| 迟发回调插入旧文字 | generation 令牌 + cancel/dispose 后丢弃旧事件 |
| partial 高频刷新拖慢画布 | 只更新一个浮层字符串；必要时按 50ms 合并 UI 更新，但绝不写 Scene |
| 协作产生大量同步 | 只有 final 进入 Scene，沿现有单元素增量同步一次 |
| 麦克风未释放 | 每个平台实现 stop/cancel/dispose，页面生命周期再做兜底 |
| 用户误以为录音被保存 | 首次使用提示“不保存录音”，代码不创建任何音频文件 |

## 11. 回滚边界

每个平台独立提交，出现问题时可以分别回滚：

- 回滚 Android 原生提交：Android 返回 unavailable，其他端不受影响。
- 回滚 HarmonyOS 原生提交：鸿蒙返回 unavailable，其他端不受影响。
- 回滚 Web 实现提交：Web 返回 unavailable，原生端不受影响。
- 回滚 UI 提交：保留底层适配但不暴露入口，不影响白板数据。
- 文本数据仍是标准 `TextElement`；即使整个功能回滚，已经生成的文字仍可正常打开。

## 12. 完成定义

只有同时满足以下条件才可声明完成：

1. Android、HarmonyOS、Web 三端构建通过。
2. Android 和 HarmonyOS 真机均完成一次权限允许、一次权限拒绝、一次停止、一次取消。
3. Web Chrome/Edge 完成支持路径，不支持浏览器完成降级路径。
4. 自动化测试证明 partial 不改变 Scene、final 只插入一次、cancel 不插入。
5. 全量 `flutter analyze` 和 `flutter test` 未新增失败。
6. 协作双方验收最终文字只同步一次，协作流畅度无明显回退。
7. 应用私有目录和数据库均未新增录音数据。
