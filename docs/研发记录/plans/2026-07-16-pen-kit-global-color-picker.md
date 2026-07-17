# HarmonyOS Pen Kit Global Color Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修通 HarmonyOS Pen Kit 系统全局取色，并在取消时保持原颜色、仅在能力不可用时降级到现有画布取色。

**Architecture:** 保留现有 `flow_muse/pen_color_picker` MethodChannel 和编辑器样式入口，只把 Channel 返回值从含混的 `String?` 改为带状态的 Map，再由 Dart 薄适配层转换为 record。鸿蒙构建继续使用当前 Hvigor `6.24.3` 和项目 `modelVersion 5.1.0`，仅修正本机 SDK 配置与 ArkTS 官方 API 调用。

**Tech Stack:** Flutter/Dart、MethodChannel、ArkTS、HarmonyOS Pen Kit、flutter_test、Hvigor/HAP

## Global Constraints

- 保持 `ohos/oh-package.json5` 与 `ohos/hvigor/hvigor-config.json5` 的 `modelVersion: "5.1.0"`。
- 本机编译 SDK 使用当前 Hvigor 支持的 `6.1.1(24)`；最低兼容版本保持 `5.1.0(18)`。
- 不新增第三方依赖，不接入 Pen Kit 报点预测、手写套件、一笔成形或原生画布。
- 不修改 Markdraw 元素模型、Excalidraw 序列化、数据库、后端或协作协议。
- 用户取消或普通失败保持原颜色；只有明确不可用才调用现有 `requestEyedropper()`。
- `ohos/build-profile.json5` 保持忽略，只修改版本字段，不覆盖或输出本地签名材料。
- 不提交自动生成插件注册文件；本计划不执行 Git commit，除非用户另行授权。

## File Map

- Create: `FlowMuse-App/test/features/color_picker/pen_color_picker_channel_test.dart` — 锁定 Channel 状态解析与异常降级。
- Modify: `FlowMuse-App/lib/features/color_picker/pen_color_picker_channel_ohos.dart` — 调用 `pickColor` 并返回 Dart record。
- Modify: `FlowMuse-App/lib/features/color_picker/pen_color_picker_channel_stub.dart` — Web fallback。
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart` — 按颜色和可用性分支处理。
- Modify: `FlowMuse-App/ohos/entry/src/main/ets/channels/PenColorPickerChannel.ets` — 使用官方 Pen Kit API 并返回状态 Map。
- Modify: `FlowMuse-App/ohos/entry/src/main/module.json5` — 移除未要求的屏幕捕获权限。
- Modify locally: `FlowMuse-App/ohos/build-profile.json5` — 恢复正确 SDK 兼容配置，保留签名。
- Modify: `docs/项目说明/项目需求.md` — 补充鸿蒙全局取色需求。

---

### Task 1: Lock the Dart Channel Contract

**Files:**
- Create: `FlowMuse-App/test/features/color_picker/pen_color_picker_channel_test.dart`
- Modify: `FlowMuse-App/lib/features/color_picker/pen_color_picker_channel_ohos.dart`
- Modify: `FlowMuse-App/lib/features/color_picker/pen_color_picker_channel_stub.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart:784`

**Interfaces:**
- Consumes: MethodChannel `flow_muse/pen_color_picker`, method `pickColor`, response Map with `status` and optional `color`.
- Produces: `Future<({String? color, bool unavailable})> PenColorPickerChannelOhos.pickColor()`.

- [ ] **Step 1: Write the failing MethodChannel tests**

Create `FlowMuse-App/test/features/color_picker/pen_color_picker_channel_test.dart`:

```dart
import 'package:flow_muse/features/color_picker/pen_color_picker_channel_ohos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flow_muse/pen_color_picker');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('鸿蒙全局取色返回规范化颜色', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return {'status': 'picked', 'color': '#12AB34'};
        });

    final result = await const PenColorPickerChannelOhos().pickColor();

    expect(captured?.method, 'pickColor');
    expect(result, (color: '#12ab34', unavailable: false));
  });

  test('鸿蒙全局取色不可用时请求画布降级', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'unavailable'},
        );

    expect(
      await const PenColorPickerChannelOhos().pickColor(),
      (color: null, unavailable: true),
    );
  });

  test('用户取消或返回无效颜色时保持原颜色', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'status': 'dismissed'},
    );
    expect(
      await const PenColorPickerChannelOhos().pickColor(),
      (color: null, unavailable: false),
    );

    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'status': 'picked', 'color': 'not-a-color'},
    );
    expect(
      await const PenColorPickerChannelOhos().pickColor(),
      (color: null, unavailable: false),
    );
  });

  test('缺少鸿蒙通道时降级，其他平台异常时保持原颜色', () async {
    expect(
      await const PenColorPickerChannelOhos().pickColor(),
      (color: null, unavailable: true),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'picker_failed'),
        );
    expect(
      await const PenColorPickerChannelOhos().pickColor(),
      (color: null, unavailable: false),
    );
  });
}
```

- [ ] **Step 2: Run the test and confirm the contract is missing**

Run:

```powershell
cd FlowMuse-App
flutter test test/features/color_picker/pen_color_picker_channel_test.dart
```

Expected: FAIL because `PenColorPickerChannelOhos.pickColor()` and the record return contract do not exist yet.

- [ ] **Step 3: Implement the minimal Dart adapter**

Replace the public method in `pen_color_picker_channel_ohos.dart` with:

```dart
Future<({String? color, bool unavailable})> pickColor() async {
  try {
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'pickColor',
    );
    final status = response?['status'];
    final color = response?['color'];
    if (status == 'picked' &&
        color is String &&
        RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      return (color: color.toLowerCase(), unavailable: false);
    }
    return (color: null, unavailable: status == 'unavailable');
  } on MissingPluginException {
    return (color: null, unavailable: true);
  } on PlatformException {
    return (color: null, unavailable: false);
  }
}
```

Replace the stub method in `pen_color_picker_channel_stub.dart` with:

```dart
Future<({String? color, bool unavailable})> pickColor() async =>
    (color: null, unavailable: true);
```

Replace `_onEyedropperPressed()` in `whiteboard_page.dart` with:

```dart
Future<void> _onEyedropperPressed() async {
  final result = await const PenColorPickerChannelOhos().pickColor();
  final color = result.color;
  if (color != null) {
    _markdrawController.applyStyleChange(ElementStyle(strokeColor: color));
    return;
  }
  if (result.unavailable) {
    _markdrawController.requestEyedropper();
  }
}
```

Update adjacent documentation comments to describe the three outcomes rather than treating every `null` as fallback.

- [ ] **Step 4: Format and verify the Dart task**

Run:

```powershell
cd FlowMuse-App
dart format lib/features/color_picker/pen_color_picker_channel_ohos.dart lib/features/color_picker/pen_color_picker_channel_stub.dart lib/features/whiteboard/views/whiteboard_page.dart test/features/color_picker/pen_color_picker_channel_test.dart
flutter test test/features/color_picker/pen_color_picker_channel_test.dart
```

Expected: formatter exits 0 and all Pen Color Picker Channel tests pass.

---

### Task 2: Repair the HarmonyOS Pen Kit Build Path

**Files:**
- Modify locally: `FlowMuse-App/ohos/build-profile.json5`
- Modify: `FlowMuse-App/ohos/entry/src/main/ets/channels/PenColorPickerChannel.ets`
- Modify: `FlowMuse-App/ohos/entry/src/main/module.json5`

**Interfaces:**
- Consumes: `imageFeaturePicker.pickForResult(): Promise<PickedColorInfo>` from `@kit.Penkit`.
- Produces: MethodChannel response `{ status: 'picked', color: '#rrggbb' }`, `{ status: 'unavailable' }`, or `{ status: 'dismissed' }`.

- [ ] **Step 1: Reproduce the current HAP build failure**

Run:

```powershell
cd FlowMuse-App
flutter build hap --debug
```

Expected before the fix: FAIL with `SDK component missing` because the local profile requests `6.6.1(26)`.

- [ ] **Step 2: Restore the supported SDK configuration without touching signing**

In the existing product entry of ignored `ohos/build-profile.json5`, preserve `name`, `signingConfig`, `runtimeOS`, all signing material and all unrelated fields. Change only this fragment:

```json5
{
  "name": "default",
  "signingConfig": "default",
  "compatibleSdkVersion": "5.1.0(18)",
  "runtimeOS": "HarmonyOS"
}
```

The product entry must no longer contain `compileSdkVersion: "6.6.1(26)"` or `compatibleSdkVersion: "6.6.1(26)"`. Do not change either `modelVersion` file.

- [ ] **Step 3: Replace the ArkTS implementation with the official API shape**

Replace `PenColorPickerChannel.ets` with:

```ts
import { BusinessError } from '@kit.BasicServicesKit';
import { imageFeaturePicker } from '@kit.Penkit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

export class PenColorPickerChannel {
  private static readonly CHANNEL_NAME = 'flow_muse/pen_color_picker';

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      PenColorPickerChannel.CHANNEL_NAME
    );

    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'pickColor') {
          result.notImplemented();
          return;
        }

        imageFeaturePicker.pickForResult().then((colorInfo) => {
          const color = colorInfo.color;
          const red = color.red.toString(16).padStart(2, '0');
          const green = color.green.toString(16).padStart(2, '0');
          const blue = color.blue.toString(16).padStart(2, '0');
          const response: Record<string, string> = {
            status: 'picked',
            color: `#${red}${green}${blue}`,
          };
          result.success(response);
        }).catch((error: BusinessError) => {
          const unavailable = error.code === 801 || error.code === 1013900003;
          const status = unavailable ? 'unavailable' : 'dismissed';
          console.warn(`[FlowMusePenColorPicker] status=${status} code=${error.code}`);
          const response: Record<string, string> = { status };
          result.success(response);
        });
      }
    });
  }
}
```

In `module.json5`, remove only:

```json5
{"name" :  "ohos.permission.SCREEN_CAPTURE"}
```

Keep `INTERNET` and `GET_NETWORK_INFO` unchanged.

- [ ] **Step 4: Build the complete HarmonyOS application**

Run:

```powershell
cd FlowMuse-App
flutter build hap --debug
```

Expected: PASS and produce a debug HAP. If compilation reports a Pen Kit symbol or type error, compare the failing line against `F:/DevEco Studio/sdk/default/hms/ets/api/@hms.officeservice.imageFeaturePicker.d.ts`; do not change Hvigor or raise the compatible SDK floor.

---

### Task 3: Document and Verify the Feature

**Files:**
- Modify: `docs/项目说明/项目需求.md:114`
- Verify: all files from Tasks 1–2

**Interfaces:**
- Consumes: completed Dart status contract and successful HarmonyOS build.
- Produces: repository documentation plus static, automated, build and device verification evidence.

- [ ] **Step 1: Record the user-visible HarmonyOS requirement**

Add this row under `### 4.10 鸿蒙端特有` in `docs/项目说明/项目需求.md`:

```markdown
| Pen Kit 全局取色 | 支持设备调用系统全局取色器；不支持时降级到画布取色，用户取消时保持原颜色 |
```

- [ ] **Step 2: Run focused and full automated verification**

Run:

```powershell
cd FlowMuse-App
flutter test test/features/color_picker/pen_color_picker_channel_test.dart
flutter analyze
flutter test
flutter build hap
```

Expected:

- Focused test: all tests pass.
- Analyze: no new errors.
- Full test suite: zero failures.
- HAP build: exits 0 and produces the HarmonyOS artifact.

- [ ] **Step 3: Check the patch boundary**

Run:

```powershell
git diff --check
git status --short
git diff -- FlowMuse-App/lib/features/color_picker FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart FlowMuse-App/ohos/entry/src/main/ets/channels/PenColorPickerChannel.ets FlowMuse-App/ohos/entry/src/main/module.json5 FlowMuse-App/test/features/color_picker docs/项目说明/项目需求.md docs/研发记录
git check-ignore -v FlowMuse-App/ohos/build-profile.json5
```

Expected:

- No whitespace errors.
- `ohos/build-profile.json5` remains ignored and no signing material appears in the diff.
- No new generated plugin registrant files are added to this task's patch; preserve pre-existing user changes without staging or deleting them.
- No database, backend, collaboration protocol or editor model files are modified.

- [ ] **Step 4: Run the device acceptance matrix**

HarmonyOS real device:

```text
1. Open a whiteboard and note the current stroke color.
2. Tap the eyedropper and select a screen color: selected/default stroke color becomes #rrggbb.
3. Tap again and cancel: color remains unchanged and the canvas picker does not open.
4. On an unsupported device/capability path: the existing canvas picker opens.
5. Restart the app and smoke-test SQLite startup, file/PDF import, system share and collaboration entry.
```

Android tablet:

```text
1. Open a whiteboard and tap the eyedropper.
2. Confirm the existing canvas picker opens.
3. Pick a canvas color and confirm the selected/default stroke color changes.
```

Expected: all steps match the design; Windows verification is not required.

## Handoff Notes

- Design source: `docs/研发记录/specs/2026-07-16-pen-kit-global-color-picker-design.md`.
- The working tree already contains user-owned generated registrant and HarmonyOS changes. Do not discard, reset or stage unrelated files.
- Manual device acceptance requires the user's HarmonyOS real device and Android tablet; report automated evidence separately from device evidence.
