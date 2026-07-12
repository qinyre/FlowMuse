import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { ExternalDocumentChannel } from './ExternalDocumentChannel';

type ShareArgs = Map<string, Object>;

export class SystemShareChannel {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/system_share'
    );
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'share') {
          result.notImplemented();
          return;
        }
        this.share(call.args as ShareArgs)
          .then((status: string) => result.success(status))
          .catch(() => result.error('SYSTEM_SHARE_FAILED', 'Unable to open system share', null));
      }
    });
  }

  private async share(args: ShareArgs): Promise<string> {
    const kind = args.get('kind') as string;
    const title = args.get('title') as string;
    const text = args.get('text') as string | undefined;
    const filePath = args.get('filePath') as string | undefined;
    const fileName = args.get('fileName') as string | undefined;
    let data: systemShare.SharedData;

    if (text !== undefined) {
      data = new systemShare.SharedData({
        utd: utd.UniformDataType.HYPERLINK,
        content: text,
        title: title,
      });
    } else if (filePath !== undefined && fileName !== undefined) {
      const ext = fileName.includes('.') ? fileName.split('.').pop()! : '';
      const utdType = ExternalDocumentChannel.utdForExtension(ext, kind === 'png');
      data = new systemShare.SharedData({
        utd: utdType,
        uri: fileUri.getUriFromPath(filePath),
        title: title,
      });
    } else {
      throw new Error('Invalid share payload');
    }

    const controller = new systemShare.ShareController(data);
    await controller.show(this.context as common.UIAbilityContext, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT,
    });
    return 'completed';
  }
}
