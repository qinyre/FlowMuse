/// HarmonyOS file save service using native DocumentViewPicker.
///
/// On OHOS the standard `file_picker` plugin is not available — the Flutter
/// engine does not auto-register plugins and the `file_picker` native channel
/// handler does not exist.  This service bridges to the OHOS-specific
/// `FileSaveChannel.ets` (registered in `EntryAbility`), which uses
/// `@kit.CoreFileKit`'s `DocumentViewPicker`.
library;

import 'package:flutter/services.dart';

/// Saves [bytes] to Downloads, or shows the system picker with [chooseLocation].
///
/// Returns the saved path or URI, or null if the user cancels the picker.
/// Throws a [PlatformException] (or [MissingPluginException]) on failure.
///
/// This function is OHOS-only.  On other platforms the channel is not
/// registered and the call will throw [MissingPluginException].
Future<String?> saveFileViaOhosChannel(
  String fileName,
  Uint8List bytes, {
  bool chooseLocation = false,
}) async {
  const channel = MethodChannel('flow_muse/file_save');
  final path = await channel.invokeMethod<String>('saveFile', <String, Object?>{
    'fileName': fileName,
    'bytes': bytes,
    if (chooseLocation) 'chooseLocation': true,
  });
  if (chooseLocation && path == null) return null;
  if (path == null || path.isEmpty) {
    throw PlatformException(
      code: 'FILE_SAVE_FAILED',
      message: 'Save returned null or empty path',
    );
  }
  return path;
}
