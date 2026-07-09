import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

type FileSaveArgs = Map<string, ESObject>;

/**
 * HarmonyOS file save channel.
 *
 * Uses CoreFileKit's DocumentViewPicker in DOWNLOAD mode to save files
 * directly to the Downloads/<package>/ directory without showing a UI dialog,
 * then writes content via fileIo.
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
          .then((savedPath: string) => result.success(savedPath))
          .catch((error: BusinessError) => {
            result.error('FILE_SAVE_FAILED', error.message ?? `${error}`, error);
          });
      }
    });
  }

  private async saveFile(args: FileSaveArgs): Promise<string> {
    const fileName = args.get('fileName') as string;
    const bytes = args.get('bytes') as Uint8Array;
    if (!fileName || !bytes) {
      throw new Error('fileName and bytes are required');
    }

    // Use DOWNLOAD mode to save directly to Downloads/<package>/ without UI.
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [fileName];
    saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;

    const documentViewPicker = new picker.DocumentViewPicker(this.context);

    // Wrap the callback-based save() API in a Promise.
    const uris: string[] = await new Promise<string[]>((resolve, reject) => {
      documentViewPicker.save(saveOptions).then(
        (docSaveResult: string[]) => {
          if (!docSaveResult || docSaveResult.length === 0) {
            reject(new Error('User cancelled save'));
            return;
          }
          resolve(docSaveResult);
        }
      ).catch((err: BusinessError) => {
        reject(new Error(`Picker save failed: ${err.message ?? err}`));
      });
    });

    // Build the target file path under the returned download URI.
    const dirUri = uris[0];
    const targetPath = new fileUri.FileUri(`${dirUri}/${fileName}`).path;

    // Write bytes to the file.
    const file = fileIo.openSync(
      targetPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE
    );
    try {
      fileIo.writeSync(file.fd, bytes.buffer);
    } finally {
      fileIo.closeSync(file.fd);
    }

    return targetPath;
  }
}
