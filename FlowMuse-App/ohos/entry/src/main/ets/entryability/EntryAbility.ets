
import { AbilityConstant, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { FilePickerChannel } from '../file/FilePickerChannel';
import { FileSaveChannel } from '../file/FileSaveChannel';
import { PdfImportChannel } from '../pdf/PdfImportChannel';
import { HttpChannel } from '../channels/HttpChannel';
import { SystemShareChannel } from '../channels/SystemShareChannel';
import { ExternalDocumentChannel } from '../channels/ExternalDocumentChannel';
import { PenColorPickerChannel } from '../channels/PenColorPickerChannel';
import { ServiceWidgetChannel } from '../channels/ServiceWidgetChannel';
import { SpeechRecognitionChannel } from '../channels/SpeechRecognitionChannel';
import { UrlLauncherChannel } from '../channels/UrlLauncherChannel';
import { HuaweiAccountChannel } from '../channels/HuaweiAccountChannel';
import { RoomQrScannerChannel } from '../channels/RoomQrScannerChannel';
import { StylusDoubleTapChannel } from '../channels/StylusDoubleTapChannel';

export default class EntryAbility extends FlutterAbility {
  private huaweiAccountChannel: HuaweiAccountChannel | undefined;
  private stylusDoubleTapChannel: StylusDoubleTapChannel | undefined;

  onDestroy(): void {
    this.stylusDoubleTapChannel?.dispose();
    this.stylusDoubleTapChannel = undefined;
    this.huaweiAccountChannel?.dispose();
    this.huaweiAccountChannel = undefined;
    super.onDestroy();
  }

  onForeground(): void {
    super.onForeground();
    this.stylusDoubleTapChannel?.setForeground(true);
  }

  onBackground(): void {
    this.stylusDoubleTapChannel?.setForeground(false);
    super.onBackground();
  }
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam)
    if (want?.parameters?.params) {
      try {
        const params = JSON.parse(want.parameters.params as string) as Record<string, Object>;
        if (params.action === 'resumeLastWhiteboard' || params.action === 'createNote') {
          ServiceWidgetChannel.enqueueLaunchAction(params.action as string);
        }
      } catch (_e) {
        // malformed params — silently skip widget launch action
      }
    }
    ExternalDocumentChannel.enqueueWant(want)
    this.enqueueSharedDocuments(want)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam)
    if (want?.parameters?.params) {
      try {
        const params = JSON.parse(want.parameters.params as string) as Record<string, Object>;
        if (params.action === 'resumeLastWhiteboard' || params.action === 'createNote') {
          ServiceWidgetChannel.enqueueLaunchAction(params.action as string);
        }
      } catch (_e) {
        // malformed params — silently skip widget launch action
      }
    }
    ExternalDocumentChannel.enqueueWant(want)
    this.enqueueSharedDocuments(want)
  }

  private enqueueSharedDocuments(want: Want): void {
    systemShare.getSharedData(want).then((data: systemShare.SharedData) => {
      data.getRecords().forEach((record: systemShare.SharedRecord) => {
        if (record.uri !== undefined) {
          ExternalDocumentChannel.enqueueUri(record.uri)
        }
      })
    }).catch(() => {})
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    new PdfImportChannel(this.context).register(flutterEngine)
    new FileSaveChannel(this.context).register(flutterEngine)
    new FilePickerChannel(this.context).register(flutterEngine)
    new HttpChannel().register(flutterEngine)
    new SystemShareChannel(this.context).register(flutterEngine)
    new ExternalDocumentChannel().register(flutterEngine)
    new RoomQrScannerChannel(this.context).register(flutterEngine)
    new PenColorPickerChannel().register(flutterEngine)
    this.stylusDoubleTapChannel?.dispose();
    this.stylusDoubleTapChannel = new StylusDoubleTapChannel();
    this.stylusDoubleTapChannel.register(flutterEngine);
    new ServiceWidgetChannel(this.context).register(flutterEngine)
    new SpeechRecognitionChannel(this.context).register(flutterEngine)
    new UrlLauncherChannel(this.context).register(flutterEngine)
    this.huaweiAccountChannel?.dispose();
    this.huaweiAccountChannel = new HuaweiAccountChannel(this.context);
    this.huaweiAccountChannel.register(flutterEngine);
  }
}
