import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

export class HttpChannel {
  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/http'
    );
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'post') {
          result.notImplemented();
          return;
        }
        this.doPost(call.args as Map<string, Object>)
          .then((responseMap: Map<string, Object>) => result.success(responseMap))
          .catch((error: BusinessError) => result.error('HTTP_REQUEST_FAILED', error.message ?? `${error}`, ''));
      }
    });
  }

  private async doPost(args: Map<string, Object>): Promise<Map<string, Object>> {
    const req = http.createHttp();
    try {
      const response = await req.request(args.get('url') as string, {
        method: http.RequestMethod.POST,
        header: (args.get('headers') as Object) ?? new Object(),
        extraData: (args.get('body') as string) ?? '',
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: (args.get('connectTimeoutMs') as number) ?? 8000,
        readTimeout: (args.get('readTimeoutMs') as number) ?? 15000,
      });
      const map = new Map<string, Object>();
      map.set('statusCode', response.responseCode);
      map.set('body', (response.result as string) ?? '');
      return map;
    } finally {
      req.destroy();
    }
  }
}
