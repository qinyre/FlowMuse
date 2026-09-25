import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

export class HuaweiAccountChannel {
  private pending: MethodResult | undefined;
  private channel: MethodChannel | undefined;

  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  register(engine: FlutterEngine): void {
    this.channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), 'flow_muse/huawei_account');
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'isAvailable') {
          result.success(true);
        } else if (call.method === 'login') {
          this.login(result);
        } else {
          result.notImplemented();
        }
      }
    });
  }

  private async login(result: MethodResult): Promise<void> {
    if (this.pending !== undefined) {
      result.error('busy', 'Login already in progress', null);
      return;
    }
    this.pending = result;
    try {
      const provider = new authentication.HuaweiIDProvider();
      const request = provider.createLoginWithHuaweiIDRequest();
      const state = util.generateRandomUUID();
      request.forceLogin = true;
      request.state = state;
      const controller = new authentication.AuthenticationController(this.context);
      const response = await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      if (this.pending !== result) {
        return;
      }
      if ((response.state && response.state !== state) || !response.data?.authorizationCode) {
        result.error('invalid_response', 'Invalid Huawei response', null);
      } else {
        result.success(response.data.authorizationCode);
      }
    } catch (error) {
      if (this.pending !== result) {
        return;
      }
      const code = (error as BusinessError).code;
      if (code === 1001502012) {
        result.success(null);
      } else {
        result.error(code === 1001502005 ? 'network' : 'authorization_failed', 'Huawei login failed', code);
      }
    } finally {
      if (this.pending === result) {
        this.pending = undefined;
      }
    }
  }

  dispose(): void {
    this.pending?.success(null);
    this.pending = undefined;
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
  }
}
