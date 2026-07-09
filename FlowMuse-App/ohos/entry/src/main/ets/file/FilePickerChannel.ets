import { fileIo, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

type PickFilesArgs = Map<string, ESObject>;
interface PickedFile {
  name: string;
  bytes: Uint8Array;
}

/**
 * HarmonyOS file picker channel using CoreFileKit's DocumentViewPicker.
 *
 * Unlike the standard `file_picker` Flutter plugin (which is not auto-registered
 * on OHOS), this channel directly invokes the native `DocumentViewPicker.select()`
 * API.  It supports filtering by file suffix and returns the name + raw bytes of
 * each selected file.
 */
export class FilePickerChannel {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/file_picker'
    );
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'pickFiles') {
          result.notImplemented();
          return;
        }
        this.pickFiles(call.args as PickFilesArgs)
          .then((files: PickedFile[]) => result.success(files))
          .catch((error: BusinessError) => {
            result.error('FILE_PICK_FAILED', error.message ?? `${error}`, error);
          });
      }
    });
  }

  private async pickFiles(args: PickFilesArgs): Promise<PickedFile[]> {
    const rawFilters = args.get('fileSuffixFilters') as string[] | undefined;
    const fileSuffixFilters: string[] = rawFilters ?? [];
    const maxSelectNumber = (args.get('maxSelectNumber') as number | undefined) ?? 1;

    const selectOptions = new picker.DocumentSelectOptions();
    selectOptions.maxSelectNumber = maxSelectNumber;
    selectOptions.selectMode = picker.DocumentSelectMode.FILE;
    if (fileSuffixFilters.length > 0) {
      selectOptions.fileSuffixFilters = fileSuffixFilters;
    }

    const documentViewPicker = new picker.DocumentViewPicker(this.context);

    // Wrap callback-based API in a Promise.
    const uris: string[] = await new Promise<string[]>((resolve, reject) => {
      documentViewPicker.select(selectOptions).then(
        (docSelectResult: string[]) => {
          if (!docSelectResult || docSelectResult.length === 0) {
            reject(new Error('User cancelled selection'));
            return;
          }
          resolve(docSelectResult);
        }
      ).catch((err: BusinessError) => {
        reject(new Error(`Picker select failed: ${err.message ?? err}`));
      });
    });

    // Read bytes from each selected URI.
    const files: PickedFile[] = [];
    for (const uri of uris) {
      try {
        const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buffer);
        fileIo.closeSync(file.fd);

        // URI paths percent-encode non-ASCII filenames.
        let name = 'unknown';
        const lastSlash = uri.lastIndexOf('/');
        if (lastSlash >= 0) {
          const encodedName = uri.substring(lastSlash + 1);
          try {
            name = decodeURIComponent(encodedName);
          } catch (_) {
            name = encodedName;
          }
        }

        files.push({ name: name, bytes: new Uint8Array(buffer) });
      } catch (e) {
        // Skip unreadable files but continue with the rest.
        console.error(`Failed to read ${uri}: ${e}`);
      }
    }
    if (files.length === 0) {
      throw new Error('No files could be read from selection');
    }
    return files;
  }
}
