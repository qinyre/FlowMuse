import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

export class HttpChannel {
  private readonly requests: Map<string, http.HttpRequest> = new Map();

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/http'
    );
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'cancel') {
          const requestId = call.args as string;
          this.requests.get(requestId)?.destroy();
          this.requests.delete(requestId);
          result.success(null);
          return;
        }
        if (call.method !== 'post') {
          if (call.method !== 'request') {
            result.notImplemented();
            return;
          }
          this.doRequest(call.args as Map<string, Object>)
            .then((responseMap: Map<string, Object>) => result.success(responseMap))
            .catch((error: BusinessError) => result.error(
              'HTTP_REQUEST_FAILED',
              `${error.code ?? ''}: ${error.message ?? error}`,
              ''
            ));
          return;
        }
        this.doPost(call.args as Map<string, Object>)
          .then((responseMap: Map<string, Object>) => result.success(responseMap))
          .catch((error: BusinessError) => result.error('HTTP_REQUEST_FAILED', error.message ?? `${error}`, ''));
      }
    });
  }

  private async doRequest(args: Map<string, Object>): Promise<Map<string, Object>> {
    const req = http.createHttp();
    const requestId = (args.get('requestId') as string) ?? '';
    if (requestId.length > 0) {
      this.requests.set(requestId, req);
    }
    try {
      const headers = JSON.parse(
        (args.get('headersJson') as string) ?? '{}'
      ) as Record<string, string>;
      const bodyBytes = args.get('bodyBytes') as Uint8Array;
      const options: http.HttpRequestOptions = {
        method: this.requestMethod((args.get('method') as string) ?? 'GET'),
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: (args.get('connectTimeoutMs') as number) ?? 8000,
        readTimeout: (args.get('readTimeoutMs') as number) ?? 15000,
        usingProtocol: http.HttpProtocol.HTTP1_1,
      };
      if (bodyBytes && bodyBytes.byteLength > 0) {
        options.extraData = bodyBytes.buffer;
      }
      const response = await req.request(args.get('url') as string, options);
      const map = new Map<string, Object>();
      map.set('statusCode', response.responseCode);
      map.set('bodyBytes', new Uint8Array(response.result as ArrayBuffer));
      map.set('headersJson', JSON.stringify(response.header ?? {}));
      return map;
    } finally {
      if (requestId.length > 0) {
        this.requests.delete(requestId);
      }
      req.destroy();
    }
  }

  private requestMethod(method: string): http.RequestMethod {
    switch (method.toUpperCase()) {
      case 'POST':
        return http.RequestMethod.POST;
      case 'PUT':
        return http.RequestMethod.PUT;
      case 'DELETE':
        return http.RequestMethod.DELETE;
      case 'GET':
        return http.RequestMethod.GET;
      default:
        throw new Error(`Unsupported HTTP method: ${method}`);
    }
  }

  private async doPost(args: Map<string, Object>): Promise<Map<string, Object>> {
    const req = http.createHttp();
    const requestId = (args.get('requestId') as string) ?? '';
    if (requestId.length > 0) {
      this.requests.set(requestId, req);
    }
    try {
      const headers = JSON.parse(
        (args.get('headersJson') as string) ?? '{}'
      ) as Record<string, string>;
      const response = await req.request(args.get('url') as string, {
        method: http.RequestMethod.POST,
        header: headers,
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
      if (requestId.length > 0) {
        this.requests.delete(requestId);
      }
      req.destroy();
    }
  }
}
