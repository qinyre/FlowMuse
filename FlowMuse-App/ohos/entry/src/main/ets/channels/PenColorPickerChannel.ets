import { imageFeaturePicker } from '@kit.PenKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

/**
 * PenColorPickerChannel — 鸿蒙 Pen Kit 全局取色通道。
 *
 * Dart 侧调用 `pickColorAt({x, y})` → ArkTS 侧调用
 * `imageFeaturePicker.pickForResult({ displayX, displayY })` 启动
 * 系统全局取色 UI，用户在屏幕任意位置取色后返回 16 进制色值字符串。
 *
 * 设备要求：Tablet、PC/2in1（HarmonyOS 5.0+），Phone（5.1.1(19)+）。
 * 不支持的设备或 API 异常时返回 null，Dart 侧静默降级到画布取色。
 */
export class PenColorPickerChannel {
  private static readonly CHANNEL_NAME = 'flow_muse/pen_color_picker';

  register(flutterEngine: FlutterEngine): void {
    const ch = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      PenColorPickerChannel.CHANNEL_NAME
    );

    ch.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'pickColorAt') {
          result.notImplemented();
          return;
        }
        const args = call.args as Record<string, number>;
        const x = args['x'] ?? 0;
        const y = args['y'] ?? 0;

        imageFeaturePicker.pickForResult({
          displayX: x,
          displayY: y,
        }).then((colorResult) => {
          // 返回 '#rrggbb' 格式，与 Dart sampleColorFromImage 保持一致。
          const r = colorResult.red.toString(16).padStart(2, '0');
          const g = colorResult.green.toString(16).padStart(2, '0');
          const b = colorResult.blue.toString(16).padStart(2, '0');
          result.success(`#${r}${g}${b}`);
        }).catch((_err: Error) => {
          // 用户取消、设备不支持或 API 错误，返回 null，Dart 侧不修改颜色。
          result.success(null);
        });
      }
    });
  }
}
