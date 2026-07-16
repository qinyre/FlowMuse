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
          const response = new Map<string, Object>();
          response.set('status', 'picked');
          response.set('color', `#${red}${green}${blue}`);
          result.success(response);
        }).catch((error: BusinessError) => {
          const unavailable = error.code === 801 || error.code === 1013900003;
          const status = unavailable ? 'unavailable' : 'dismissed';
          console.warn(`[FlowMusePenColorPicker] status=${status} code=${error.code}`);
          const response = new Map<string, Object>();
          response.set('status', status);
          result.success(response);
        });
      }
    });
  }
}
