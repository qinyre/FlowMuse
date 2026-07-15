# 语音转文字（Speech-to-Text）功能规格说明

> **分支**：`语音转文字`
> **状态**：设计 / 待评审
> **关联**：本功能为全新增量。`REQUIREMENTS.md` 第 7 节"范围外"中的"语音/视频会议"指实时音视频通话，与本功能（录音转写为文本插入白板）不冲突；建议在 `REQUIREMENTS.md` 新增 4.11 章节明确边界。

---

## 1. 目标与范围

### 1.1 目标

在白板编辑器中提供"按住录音 → 语音识别 → 将文本作为文本元素插入画布"的能力，与现有手写识别（ink recognition）形成"语音输入"对偶功能。

### 1.2 MVP 范围（In Scope）

- 录音 UI：按住/点击麦克风按钮开始/停止录音，录音中有可视化状态指示。
- 录音采集：统一 PCM 16kHz / 单声道 / 16-bit（S16LE）。
- 识别：将语音转写为文本。
- 落地：识别文本作为文本元素插入当前白板（复用现有文本插入逻辑）。
- 三端：鸿蒙、Android、Web。

### 1.3 范围外（Out of Scope，MVP 不做）

- 实时流式转写显示（先用"录完→转写→插入"模式）。
- 多语言（MVP 仅中文普通话，沿用鸿蒙 CoreSpeechKit 的语言支持面）。
- 音频回放、音频文件持久化与协作同步（MVP 录音用完即弃，不入场景 JSON）。
- 说话人分离、标点优化、敏感词过滤等后处理。

### 1.4 非功能要求（对齐 `REQUIREMENTS.md` §5）

| 维度 | 要求 |
|---|---|
| 离线优先 | 移动端（鸿蒙/Android）默认端侧识别，不依赖服务端即可工作 |
| 跨端一致性 | 三端通过同一 Dart 抽象接口暴露，行为一致 |
| 隐私 | 移动端音频不出端；Web 端音频上传后端时走已认证通道，服务端不留存原始音频 |
| 性能 | 单条短语音（≤60s）识别在主流设备上 ≤3s 返回（端侧） |

---

## 2. 架构决策（已定）

| 决策项 | 选择 | 理由 |
|---|---|---|
| **ASR 总架构** | 混合：端侧优先 + 后端兜底 | 契合"离线可用"基调，Web 端有可靠落点 |
| **鸿蒙端 ASR** | `@kit.CoreSpeechKit`（端侧离线） | 官方原生能力，中文普通话，零额外模型 |
| **Android 端 ASR** | `sherpa_onnx`（端侧离线，Paraformer/Zipformer） | 覆盖国内国行机（无 GMS 设备），有现成 Flutter 插件 |
| **Web 端 ASR** | 上传 Go 后端识别 | 浏览器内 ASR 碎片化不可靠，后端方案跨浏览器一致 |
| **后端 ASR 引擎** | MVP：OpenAI 兼容 `/audio/transcriptions` 云 API；演进：本地 faster-whisper | 复用现有 `FLOWMUSE_AI_*` 配置体系，快速跑通；稳定后换本地以契合离线/隐私 |
| **落地顺序** | 三端同步推进，但接口先行 | 接口固化后各端并行，避免返工 |

### 2.1 架构图

```
                    ┌─────────────────────────────────────┐
                    │   Dart 层抽象 SpeechTranscriber      │
                    │   (Future<Result> transcribe(src))   │
                    └──────────┬──────────┬──────────┬─────┘
                               │          │          │
              ┌────────────────┘          │          └────────────────┐
              ▼                           ▼                           ▼
   ┌───────────────────┐      ┌───────────────────┐      ┌───────────────────┐
   │ HarmonyOs         │      │ Android           │      │ Web               │
   │ AudioCapturer →   │      │ record 插件 →     │      │ MediaRecorder →   │
   │ CoreSpeechKit     │      │ sherpa_onnx       │      │ 上传后端          │
   │ (端侧离线)         │      │ (端侧离线)         │      │                   │
   └───────────────────┘      └───────────────────┘      └─────────┬─────────┘
                                                                   │
                                                          POST /api/speech/transcribe
                                                                   │
                                                          ┌────────▼─────────┐
                                                          │ Go internal/speech│
                                                          │ (云 ASR / Whisper)│
                                                          └──────────────────┘
```

---

## 3. 客户端设计（FlowMuse-App）

### 3.1 目录结构

新增独立 feature 分层，与 `ink_recognition` 平行：

```
lib/features/whiteboard/speech_to_text/
├── speech_transcriber.dart            # 抽象接口 + 数据模型
├── speech_recorder.dart               # 录音采集抽象（统一 PCM16/16k/mono）
├── speech_transcriber_provider.dart   # Riverpod provider，按平台注入实现
├── harmony_speech_transcriber.dart    # 鸿蒙实现：Platform Channel + CoreSpeechKit
├── android_speech_transcriber.dart    # Android 实现：record + sherpa_onnx
├── web_speech_transcriber.dart        # Web 实现：录音 + 上传后端
├── backend_speech_transcriber.dart    # 后端兜底实现（移动端 fallback / 通用）
└── widgets/
    └── speech_input_button.dart       # 录音按钮 UI
```

### 3.2 核心抽象接口

`speech_transcriber.dart`：

```dart
/// 统一的音频源：移动端传 PCM 字节流/文件路径，Web 传上传用 Blob。
sealed class AudioSource {
  const AudioSource();
}
class PcmFileSource extends AudioSource { final String path; ... }
class PcmStreamSource extends AudioSource { final Stream<Uint8List> stream; ... }
class UploadableBlobSource extends AudioSource { final Uint8List bytes; final String mime; ... }

/// 识别结果。
class SpeechTranscriptionResult {
  final String text;              // 转写文本
  final bool isFinal;             // 是否最终结果（流式时区分中间/最终）
  final String? provider;         // 'corespeech' | 'sherpa' | 'backend'
  const SpeechTranscriptionResult({...});
}

/// 转写器抽象。三端各提供一个实现，由 provider 按平台注入。
abstract class SpeechTranscriber {
  /// 一次性转写（录完后调用）。
  Future<SpeechTranscriptionResult> transcribe(AudioSource source);

  /// 是否可用（端侧能力/模型未就绪时返回 false，调用方应回退后端）。
  Future<bool> get isAvailable;

  void dispose();
}
```

> 设计要点：接口与 `InkRecognitionRepository` 同层、同风格（Riverpod `Provider`，构造注入 `CollaborationConfig`）。错误沿用 `StateError` + `PlatformException` 分支，日志用 `[$_logTag]` emoji 风格对齐 `ink_recognition_repository.dart`。

### 3.3 录音采集约定（全端统一）

| 参数 | 值 | 说明 |
|---|---|---|
| 采样率 | 16000 Hz | 鸿蒙 CoreSpeechKit / Whisper / sherpa_onnx 一致要求 |
| 声道 | 单声道 | |
| 采样格式 | 16-bit PCM (S16LE) | |
| 缓冲块 | 1280 bytes / 块 | 对齐鸿蒙 `writeAudio` 的 "640 或 1280" 约束 |

`speech_recorder.dart` 提供 `start()` / `stop()`，产出 `AudioSource`。

### 3.4 鸿蒙端实现

- **录音**：`@kit.AudioKit` `AudioCapturer`，`AudioCapturerOptions` 配置 16k / CHANNEL_1 / SAMPLE_FORMAT_S16LE / SOURCE_TYPE_MIC。
- **识别**：`@kit.CoreSpeechKit` `speechRecognizer`，`AudioInfo { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 }`，`writeAudio(sessionId, chunk)` 喂流，`RecognitionListener.onResult` 收文字。
- **桥接**：新增 `ohos/entry/src/main/ets/channels/SpeechChannel.ets`，`MethodChannel('flow_muse/speech')`，方法 `startRecording` / `writeAudio` / `finish` / `cancel`。照搬 `HttpChannel.ets` 的 `register(flutterEngine)` + `setMethodCallHandler` 模式。
- **权限**：`module.json5` `requestPermissions` 加 `ohos.permission.MICROPHONE`（`user_grant`，`when: inuse`，abilities 含 `EntryAbility`）；运行时 `abilityAccessCtrl.createAtManager().requestPermissionsFromUser(...)`。
- **约束提示**：CoreSpeechKit 仅中文普通话、仅中国境内、Phone/Tablet/PC；在 UI 上对不支持设备/语言降级提示。

### 3.5 Android 端实现

- **录音**：依赖 `record`（产出 PCM16 文件/流，API 对齐 `AudioEncoder.pcm16bits` + 16k + mono）。
- **识别**：依赖 `sherpa_onnx`，模型选 Paraformer（中文）或 Zipformer-small。模型分发见 §6.3。
- **权限**：`AndroidManifest.xml` 加 `RECORD_AUDIO`；运行时 `permission_handler` 的 `Permission.microphone.request()`。
- **降级**：`sherpa_onnx` 模型未就绪 / `isAvailable == false` 时，provider 注入 `BackendSpeechTranscriber`。

### 3.6 Web 端实现

- **录音**：`getUserMedia({audio:true})` + `MediaRecorder` 产出 webm/opus（或用 `flutter_recorder` 直接出 WAV）。
- **识别**：录音 Blob → `MultipartRequest` POST `/api/speech/transcribe` → 拿回文本。必须 HTTPS。
- **JS 互操作**：用 `package:web` + `dart:js_interop`（不用 `dart:html`，兼容 Wasm 编译）。
- **权限**：浏览器原生弹窗；部署须 HTTPS（localhost 视为安全上下文）。

### 3.7 Provider 装配

`speech_transcriber_provider.dart`：

```dart
final speechTranscriberProvider = Provider<SpeechTranscriber>((ref) {
  final config = ref.watch(collaborationConfigProvider);
  if (kIsWeb) return WebSpeechTranscriber(config: config);
  switch (defaultTargetPlatform) {
    case TargetPlatform.harmonyOS: // 注：harmonyOS 为自定义目标，按工程实际平台判定
      return HarmonySpeechTranscriber(config: config);
    case TargetPlatform.android:
      return AndroidSpeechTranscriber(config: config);
    default:
      return BackendSpeechTranscriber(config: config); // iOS/桌面兜底后端
  }
});
```

### 3.8 UI 集成

- 在白板工具栏新增麦克风按钮（复用现有工具栏图标/状态管理风格）。
- 交互：点击 → 申请权限 → 录音中（按钮变红 + 波形/计时器）→ 再点击停止 → 转写 → 文本插入光标处（复用文本元素插入路径）。
- 错误态：权限拒绝、ASR 不可用、转写失败分别 toast 提示。

---

## 4. 服务端设计（FlowMuse-Server）

### 4.1 新增模块

```
internal/speech/
├── api.go              # HTTPAPI + Register(mux)，照搬 recognition/api.go 结构
├── transcriber.go      # Transcriber 接口
├── openai_transcriber.go   # MVP: OpenAI 兼容 /audio/transcriptions 云实现
├── whisper_transcriber.go  # 演进: 本地 faster-whisper 实现（CGo / 子进程）
└── types.go            # 请求/响应类型
```

### 4.2 Transcriber 接口

`transcriber.go`：

```go
type Transcriber interface {
    Transcribe(ctx context.Context, req TranscribeRequest) (TranscribeResponse, error)
}

type TranscribeRequest struct {
    Audio      []byte // 原始音频字节（webm/wav/pcm）
    Format     string // "webm" | "wav" | "pcm"
    Language   string // "zh"（默认）
}

type TranscribeResponse struct {
    Text string `json:"text"`
}
```

### 4.3 HTTP 端点

`api.go`，路由 `POST /api/speech/transcribe`：

- multipart/form-data，字段 `audio`（音频文件）+ 可选 `language`。
- `http.MaxBytesReader` 设独立上限（建议 25MB，区别于 ink 的 512KB / smart-layout 的 32MB）。
- 独立超时（建议 `cfg.SpeechTimeout`，默认 120s，区别于 `AITimeout`）。
- **不留存**：识别后立即丢弃音频字节，不写 fileStore / S3。
- 复用 `withCORS`、`writeJSON`、`contextWithTimeout` 等现成 helper。

> 参照：`recognition/api.go:38-43` 的 `Register(mux)` 模式；`main.go:113-117` 的挂载方式。

### 4.4 配置项（`internal/config/config.go`）

新增字段：

```go
SpeechProvider  string        // "openai" | "whisper"，默认 "openai"
SpeechBaseURL   string        // OpenAI 兼容端点，复用 FLOWMUSE_AI_BASE_URL 体系
SpeechAPIKey    string
SpeechModel     string        // 如 whisper-1
SpeechTimeout   time.Duration // 默认 120s
```

环境变量：`FLOWMUSE_SPEECH_PROVIDER` / `FLOWMUSE_SPEECH_BASE_URL` / `FLOWMUSE_SPEECH_API_KEY` / `FLOWMUSE_SPEECH_MODEL` / `FLOWMUSE_SPEECH_TIMEOUT`。

### 4.5 main.go 挂载（`cmd/flowmuse-collab-server/main.go`）

在 `recognition.NewHTTPAPI(...).Register(mux)` 之后追加：

```go
var speechTranscriber speech.Transcriber
switch cfg.SpeechProvider {
case "whisper":
    speechTranscriber = speech.NewWhisperTranscriber(...)
default:
    speechTranscriber = speech.NewOpenAITranscriber(speech.OpenAIConfig{
        BaseURL: cfg.SpeechBaseURL, APIKey: cfg.SpeechAPIKey,
        Model: cfg.SpeechModel, Timeout: cfg.SpeechTimeout,
    })
}
speech.NewHTTPAPI(speechTranscriber, cfg.SpeechTimeout).Register(mux)
```

---

## 5. 权限与隐私

### 5.1 权限清单

| 平台 | 权限 | 声明位置 | 申请方式 |
|---|---|---|---|
| 鸿蒙 | `ohos.permission.MICROPHONE` | `module.json5` requestPermissions | `abilityAccessCtrl` 运行时 |
| Android | `RECORD_AUDIO` | `AndroidManifest.xml` | `permission_handler` 运行时 |
| Web | getUserMedia | — | 浏览器原生弹窗，须 HTTPS |
| iOS | `NSMicrophoneUsageDescription` | Info.plist | 系统弹窗（若纳入范围） |

### 5.2 隐私要求

- 移动端音频不出端（端侧识别）。
- Web 端音频上传经 `Authorization: Bearer` 认证通道；服务端识别后**不落盘、不入库**。
- 录音 UI 须有明显状态指示（符合敏感行为规范）。
- 首次使用须向用户说明数据流向（移动端本地 / Web 上传）。

---

## 6. 风险与验证

### 6.1 风险登记

| ID | 风险 | 等级 | 缓解 |
|---|---|---|---|
| R1 | 鸿蒙 CoreSpeechKit 在目标机型不可用（地区/设备限制） | 中 | `isAvailable` 探测 + 降级后端 |
| R2 | Android `sherpa_onnx` 模型推理延迟/体积 | 中 | 选 small 模型；按需下载；基准测试 |
| R3 | Web 浏览器 MediaRecorder 格式与后端期望不一致 | 中 | 后端兼容多格式，或前端转 WAV |
| R4 | 录音权限被拒后无法重新弹窗（Web） | 低 | 引导用户改浏览器站点设置 |
| R5 | 服务端云 ASR 费用 / 延迟 | 中 | MVP 云，演进本地 Whisper |
| R6 | 三端抽象接口设计不当导致返工 | 中 | **接口先冻结**，三端再并行 |

### 6.2 验收标准（MVP）

1. 鸿蒙真机：按住录音说中文 → 松开 → 文本出现在白板。断网可用（端侧）。
2. Android 国行机（无 GMS）：同上，断网可用（端侧 sherpa_onnx）。
3. Web（Chrome，HTTPS）：录音 → 上传后端 → 文本出现。
4. 权限拒绝时优雅降级，不崩溃。
5. 服务端 `/api/speech/transcribe` 不留存音频（可审计）。

### 6.3 待定子决策（实施时定）

- **Android 模型分发**：随 APK 打包 vs 首启按需下载。倾向按需下载（控制 APK 体积）。
- **后端 ASR 引擎**：MVP 先 OpenAI 兼容云 API（最小改动），稳定后评估换本地 faster-whisper。

---

## 7. 落地里程碑

> 三端并行，但 **M0（接口冻结）是所有并行工作的前置门禁**。

| 里程碑 | 内容 | 门禁 |
|---|---|---|
| **M0** | 冻结 Dart `SpeechTranscriber` 接口 + `AudioSource` 模型 + PCM 采集约定 | 接口 review 通过，三端可据此并行 |
| **M1** | 鸿蒙端闭环：录音 → CoreSpeechKit → 插白板 | 真机断网可用 |
| **M2** | Go `internal/speech` + `/api/speech/transcribe`（云 ASR） | curl 上传音频返回文本 |
| **M3** | Web 端闭环：录音 → 上传 → 插白板 | Chrome HTTPS 可用 |
| **M4** | Android 端闭环：record + sherpa_onnx | 国行机断网可用 |
| **M5** | 权限/隐私/降级路径打磨 + 文档（REQUIREMENTS 补 4.11） | 验收标准全过 |

---

## 8. 与现有架构的对称性（对照表）

| 维度 | 手写识别（已有） | 语音转文字（本 spec） |
|---|---|---|
| 客户端 feature | `lib/features/whiteboard/ink_recognition/` | `lib/features/whiteboard/speech_to_text/` |
| 客户端仓库 | `InkRecognitionRepository` | `SpeechTranscriber` |
| 服务端模块 | `internal/recognition/` | `internal/speech/` |
| 服务端接口 | `Recognizer` + `HTTPAPI.Register` | `Transcriber` + `HTTPAPI.Register` |
| HTTP 路由 | `/api/ink/recognize` | `/api/speech/transcribe` |
| 配置体系 | `FLOWMUSE_MYSCRIPT_*` / `FLOWMUSE_AI_*` | `FLOWMUSE_SPEECH_*` |
| 鸿蒙桥接 | `HttpChannel.ets` 等 | `SpeechChannel.ets` |
| 插入画布 | 文本/图形元素 | 文本元素（复用） |

> 本功能是手写识别链路的"语音对偶"，沿用同一套架构约定，无新架构概念引入。
