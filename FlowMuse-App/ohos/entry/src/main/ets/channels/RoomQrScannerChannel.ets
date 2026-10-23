import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

export class RoomQrScannerChannel {
  private scanning: boolean = false;
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/room_qr_scanner'
    );
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method !== 'scan') {
          result.notImplemented();
          return;
        }
        this.scan(result);
      }
    });
  }

  private async scan(result: MethodResult): Promise<void> {
    if (this.scanning) {
      result.error('busy', 'Scanner already open', null);
      return;
    }
    this.scanning = true;
    try {
      if (!canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
        result.error('unavailable', 'System scanner unavailable', null);
        return;
      }
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        this.context, ['ohos.permission.CAMERA']
      );
      if (permission.authResults.length === 0 || permission.authResults[0] !== 0) {
        result.error('permission_denied', 'Camera permission denied', null);
        return;
      }
      const scanned = await scanBarcode.startScanForResult(this.context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      });
      // 只返回数据，由 Dart 校验房间；不打开扫码 URL，不记录内容或原始异常。
      result.success(scanned.originalValue.length <= 4096 ? scanned.originalValue : '');
    } catch (error) {
      const code = (error as BusinessError).code;
      if (code === scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED) {
        result.success(null);
      } else {
        result.error('scan_failed', 'Unable to scan room QR', null);
      }
    } finally {
      this.scanning = false;
    }
  }
}
