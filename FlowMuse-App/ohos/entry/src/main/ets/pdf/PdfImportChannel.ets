import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

type PdfImportArgs = Map<string, ESObject>;

export class PdfImportChannel {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/pdf_import'
    );
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'renderPdfPages') {
          result.notImplemented();
          return;
        }
        const args = call.args as PdfImportArgs;
        const progressName = args.get('progressChannel') as string | undefined;
        const progress = progressName?.startsWith('flow_muse/pdf_import/progress/')
          ? new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), progressName)
          : undefined;
        this.renderPdfPages(args, progress)
          .then((pages: ESObject[]) => result.success(pages))
          .catch((error: BusinessError) => {
            result.error('PDF_IMPORT_FAILED', error.message ?? `${error}`, error);
          });
      }
    });
  }

  private async renderPdfPages(args: PdfImportArgs, progress?: MethodChannel): Promise<ESObject[]> {
    const name = (args.get('name') as string | undefined) ?? `import-${Date.now()}.pdf`;
    const pathArg = args.get('path') as string | undefined;
    const bytes = args.get('bytes') as Uint8Array | undefined;
    const maxPages = args.get('maxPages') as number | undefined;
    const sourcePath = bytes ? this.writeTempPdf(name, bytes) : pathArg;
    if (!sourcePath) {
      throw new Error('No PDF bytes or path provided');
    }

    const pdfDocument = new pdfService.PdfDocument();
    try {
      const loadResult = pdfDocument.loadDocument(sourcePath);
      if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        throw new Error(`PDF load failed: ${loadResult}`);
      }

      const pageCount = pdfDocument.getPageCount();
      const limit = Math.min(pageCount, maxPages ?? pageCount);
      const pages: ESObject[] = [];
      await this.reportProgress(progress, 0, limit);
      for (let index = 0; index < limit; index++) {
        const page = pdfDocument.getPage(index);
        const pixelMap = page.getPagePixelMap();
        if (!pixelMap) {
          throw new Error(`PDF page ${index + 1} could not be rendered`);
        }
        try {
          const packed = await this.pixelMapToPng(pixelMap);
          pages.push({
            bytes: new Uint8Array(packed),
            mimeType: 'image/png',
            width: page.getWidth(),
            height: page.getHeight(),
            pageNumber: index + 1
          });
        } finally {
          await pixelMap.release();
        }
        await this.reportProgress(progress, index + 1, limit);
      }
      return pages;
    } finally {
      try {
        pdfDocument.releaseDocument();
      } finally {
        if (bytes) {
          try {
            fileIo.unlinkSync(sourcePath);
          } catch (_) {
            console.warn('[FlowMuseCreateNote] PDF temporary file cleanup failed');
          }
        }
      }
    }
  }

  private reportProgress(channel: MethodChannel | undefined, completed: number, total: number): Promise<void> {
    if (!channel) return Promise.resolve();
    return new Promise<void>((resolve, reject) => {
      channel.invokeMethod('progress', new Map<string, number>([
        ['completed', completed], ['total', total]
      ]), {
        success: (keepGoing: ESObject): void => {
          if (keepGoing === false) reject(new Error('PDF import cancelled'));
          else resolve();
        },
        error: (): void => reject(new Error('PDF progress channel unavailable')),
        notImplemented: (): void => resolve()
      });
    });
  }

  private writeTempPdf(name: string, bytes: Uint8Array): string {
    const safeName = name.replace(/[\\\\/:*?"<>|]/g, '_');
    const path = `${this.context.cacheDir}/${Date.now()}-${safeName}`;
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    try {
      fileIo.writeSync(file.fd, bytes.buffer);
    } finally {
      fileIo.closeSync(file.fd);
    }
    return path;
  }

  private async pixelMapToPng(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    const packer = image.createImagePacker();
    const options: image.PackingOption = { format: 'image/png', quality: 100 };
    try {
      return await packer.packToData(pixelMap, options);
    } finally {
      await packer.release();
    }
  }
}
