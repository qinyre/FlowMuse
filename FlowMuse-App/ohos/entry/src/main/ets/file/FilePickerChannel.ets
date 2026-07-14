import { fileIo, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

type PickFilesArgs = Map<string, ESObject>;
interface PickedFile {
  name: string;
  bytes: Uint8Array;
}

/**
 * HarmonyOS file picker channel using CoreFileKit's pickers.
 *
 * Unlike the standard `file_picker` Flutter plugin (which is not auto-registered
 * on OHOS), this channel directly invokes the native picker APIs and returns the
 * name + raw bytes of each selected file.  Two methods are exposed:
 *
 * - `pickFiles`  → `DocumentViewPicker` (full file manager; lets the user pick
 *   from either the file manager or the gallery).  Used for general file import.
 * - `pickImage`  → `photoAccessHelper.PhotoViewPicker` (gallery only; opens the
 *   album directly with no source-selection prompt).  Used for toolbar "import image".
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
        if (call.method === 'pickFiles') {
          this.pickFiles(call.args as PickFilesArgs)
            .then((files: PickedFile[]) => result.success(files))
            .catch((error: BusinessError) => {
              result.error('FILE_PICK_FAILED', error.message ?? `${error}`, error);
            });
          return;
        }
        if (call.method === 'pickImage') {
          this.pickImage(call.args as PickFilesArgs)
            .then((files: PickedFile[]) => result.success(files))
            .catch((error: BusinessError) => {
              result.error('FILE_PICK_FAILED', error.message ?? `${error}`, error);
            });
          return;
        }
        result.notImplemented();
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

    return this.readFilesFromUris(uris);
  }

  /**
   * Picks images directly from the system gallery (album) via
   * `photoAccessHelper.PhotoViewPicker`.  Unlike `pickFiles` (which uses
   * `DocumentViewPicker` and therefore prompts the user to choose between the
   * file manager and the gallery), this method opens the gallery immediately —
   * no source-selection dialog.
   *
   * Only image MIME types are offered.  The `suffixFilters` argument is
   * accepted for API parity with `pickFiles` but ignored, since the gallery
   * exposes media by MIME type rather than file extension.
   *
   * NOTE: per the Media Library Kit guidance, a media URI cannot be opened via
   * `fileIo.openSync` inside the picker's own callback.  `select` is awaited
   * here so the read happens after the picker resolves.
   */
  private async pickImage(args: PickFilesArgs): Promise<PickedFile[]> {
    const maxSelectNumber = (args.get('maxSelectNumber') as number | undefined) ?? 1;

    const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    photoSelectOptions.maxSelectNumber = maxSelectNumber;
    photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;

    const photoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const photoSelectResult: photoAccessHelper.PhotoSelectResult =
      await photoViewPicker.select(photoSelectOptions);
    if (!photoSelectResult || !photoSelectResult.photoUris || photoSelectResult.photoUris.length === 0) {
      throw new Error('User cancelled selection');
    }

    return this.readFilesFromUris(photoSelectResult.photoUris);
  }

  /**
   * Reads name + bytes from each file URI returned by a picker.  Gallery URIs
   * sometimes omit a filename; in that case a generic `image` name is used.
   */
  private readFilesFromUris(uris: string[]): PickedFile[] {
    const files: PickedFile[] = [];
    for (const uri of uris) {
      try {
        const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buffer);
        fileIo.closeSync(file.fd);

        // URI paths percent-encode non-ASCII filenames.
        let name = 'image';
        const lastSlash = uri.lastIndexOf('/');
        if (lastSlash >= 0) {
          const encodedName = uri.substring(lastSlash + 1);
          if (encodedName.length > 0) {
            try {
              name = decodeURIComponent(encodedName);
            } catch (_) {
              name = encodedName;
            }
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
