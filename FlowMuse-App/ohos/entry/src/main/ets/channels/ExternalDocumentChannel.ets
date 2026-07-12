import { AbilityConstant, Want } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

interface PendingDocument {
  name: string;
  bytes: Uint8Array;
}

export class ExternalDocumentChannel {
  private static readonly maxItems: number = 3;
  private static readonly maxBytes: number = 20 * 1024 * 1024;
  private static readonly pending: PendingDocument[] = [];
  private static channel: MethodChannel | null = null;

  static utdForExtension(ext: string, isImage: boolean): string {
    if (ext === 'markdraw') {
      return 'com.example.flowmuse.markdraw';
    }
    if (ext === 'excalidraw') {
      return 'com.example.flowmuse.excalidraw';
    }
    const fallback = isImage
      ? utd.UniformDataType.IMAGE
      : utd.UniformDataType.PLAIN_TEXT;
    return utd.getUniformDataTypeByFilenameExtension(`.${ext}`, fallback);
  }

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/external_document'
    );
    ExternalDocumentChannel.channel = channel;
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'takeNext') {
          result.notImplemented();
          return;
        }
        result.success(ExternalDocumentChannel.pending.shift() ?? null);
      }
    });
  }

  static enqueueWant(want: Want): void {
    const uri = want.uri;
    if (uri !== undefined) {
      ExternalDocumentChannel.enqueueUri(uri);
    }
  }

  static enqueueUri(uri: string): void {
    if (ExternalDocumentChannel.pending.length >= ExternalDocumentChannel.maxItems) {
      return;
    }
    const name = ExternalDocumentChannel.fileName(uri);
    if (!name.endsWith('.markdraw') && !name.endsWith('.excalidraw')) {
      return;
    }
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size > ExternalDocumentChannel.maxBytes) {
        fileIo.closeSync(file.fd);
        return;
      }
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file.fd);
      ExternalDocumentChannel.pending.push({ name: name, bytes: new Uint8Array(buffer) });
      ExternalDocumentChannel.notifyDocumentEnqueued();
    } catch (_) {
      // 外部 URI 失效或无权限时静默忽略，绝不记录 URI 或文件内容。
    }
  }

  private static notifyDocumentEnqueued(): void {
    ExternalDocumentChannel.channel?.invokeMethod('onDocumentEnqueued', null);
  }

  private static fileName(uri: string): string {
    const index = uri.lastIndexOf('/');
    return decodeURIComponent(index >= 0 ? uri.substring(index + 1) : uri);
  }
}
