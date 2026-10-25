import { BusinessError } from '@kit.BasicServicesKit';
import { stylusInteraction } from '@kit.Penkit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

export class StylusDoubleTapChannel {
  private channel: MethodChannel | undefined;
  private enabled: boolean = false;
  private foreground: boolean = false;
  private subscribed: boolean = false;
  private generation: number = 0;
  private subscription: number = 0;
  private receiver: ((event: stylusInteraction.DoubleTapEvent) => void) | undefined;

  register(flutterEngine: FlutterEngine): void {
    this.channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/stylus_double_tap'
    );
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'setListening') {
          result.notImplemented();
          return;
        }
        if (!(call.args instanceof Map)) {
          result.error('INVALID_ARGS', 'Invalid stylus subscription', null);
          return;
        }
        const args = call.args as Map<string, Object>;
        const enabled = args?.get('enabled');
        const generation = args?.get('generation');
        if (typeof enabled !== 'boolean' || typeof generation !== 'number' ||
          !Number.isInteger(generation) || generation < 1) {
          result.error('INVALID_ARGS', 'Invalid stylus subscription', null);
          return;
        }
        this.enabled = enabled;
        this.generation = generation;
        this.updateSubscription();
        result.success(null);
      }
    });
  }

  setForeground(value: boolean): void {
    this.foreground = value;
    this.updateSubscription();
  }

  private updateSubscription(): void {
    try {
      if (this.enabled && this.foreground && !this.subscribed) {
        if (!canIUse('SystemCapability.Stylus.StylusService')) return;
        const subscription = ++this.subscription;
        this.receiver = (event: stylusInteraction.DoubleTapEvent): void => {
          if (!this.enabled || !this.foreground || subscription !== this.subscription) return;
          const args = new Map<string, Object>();
          args.set('generation', this.generation);
          args.set('timestamp', event.timestamp);
          this.channel?.invokeMethod('doubleTap', args);
        };
        stylusInteraction.on('doubleTap', this.receiver);
        this.subscribed = true;
      } else if ((!this.enabled || !this.foreground) && this.subscribed && this.receiver !== undefined) {
        this.subscription++;
        stylusInteraction.off('doubleTap', this.receiver);
        this.subscribed = false;
        this.receiver = undefined;
      }
    } catch (error) {
      console.warn(`[FlowMuseStylus] barrel gesture unavailable code=${(error as BusinessError).code}`);
    }
  }

  dispose(): void {
    this.enabled = false;
    this.updateSubscription();
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
  }
}
