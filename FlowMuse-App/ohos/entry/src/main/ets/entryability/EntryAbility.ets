
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { FilePickerChannel } from '../file/FilePickerChannel';
import { FileSaveChannel } from '../file/FileSaveChannel';
import { PdfImportChannel } from '../pdf/PdfImportChannel';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    new PdfImportChannel(this.context).register(flutterEngine)
    new FileSaveChannel(this.context).register(flutterEngine)
    new FilePickerChannel(this.context).register(flutterEngine)
  }
}
