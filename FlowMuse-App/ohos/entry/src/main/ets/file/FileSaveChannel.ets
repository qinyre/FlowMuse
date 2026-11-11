import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

type FileSaveArgs = Map<string, ESObject>;

/**
 * HarmonyOS file save channel.
 *
 * Uses CoreFileKit's DocumentViewPicker to save to Downloads or to a location
 * selected by the user, then writes content via fileIo.
 */
export class FileSaveChannel {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/file_save'
    );
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'saveFile') {
          result.notImplemented();
          return;
        }
        this.saveFile(call.args as FileSaveArgs)
          .then((savedPath: string | null) => result.success(savedPath))
          .catch((error: BusinessError) => {
            result.error('FILE_SAVE_FAILED', error.message ?? `${error}`, null);
          });
      }
    });
  }

  private async saveFile(args: FileSaveArgs): Promise<string | null> {
    const fileName = args.get('fileName') as string;
    const bytes = args.get('bytes') as Uint8Array;
    if (!fileName || !bytes) {
      throw new Error('fileName and bytes are required');
    }

    const chooseLocation = args.get('chooseLocation') === true;
    const saveOptions = new picker.DocumentSaveOptions();
    if (chooseLocation) {
      saveOptions.newFileNames = [fileName];
    } else {
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    }

    const documentViewPicker = new picker.DocumentViewPicker(this.context);
    const uris = await documentViewPicker.save(saveOptions);
    if (!uris || uris.length === 0) return null;

    const target = chooseLocation ? uris[0] : new fileUri.FileUri(`${uris[0]}/${fileName}`).path;
    const mode = fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC |
      (chooseLocation ? 0 : fileIo.OpenMode.CREATE);
    const file = fileIo.openSync(target, mode);
    try {
      const buffer = bytes.byteLength === bytes.buffer.byteLength
        ? bytes.buffer
        : bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      if (fileIo.writeSync(file.fd, buffer) !== bytes.byteLength) {
        throw new Error('Incomplete file write');
      }
    } finally {
      fileIo.closeSync(file.fd);
    }

    return target;
  }
}
