/// HarmonyOS file save service using native DocumentViewPicker (DOWNLOAD mode).
///
/// On OHOS the standard `file_picker` plugin is not available — the Flutter
/// engine does not auto-register plugins and the `file_picker` native channel
/// handler does not exist.  This service bridges to the OHOS-specific
/// `FileSaveChannel.ets` (registered in `EntryAbility`), which uses
/// `@kit.CoreFileKit`'s `DocumentViewPicker` in DOWNLOAD mode to save files
/// directly to `Downloads/<package>/` without showing a file-picker UI.
library;

import 'package:flutter/services.dart';

/// Saves [bytes] to `Downloads/<package>/[fileName]` via OHOS native channel.
///
/// Returns the absolute file path on success, or throws a [PlatformException]
/// (or [MissingPluginException]) on failure.
///
/// This function is OHOS-only.  On other platforms the channel is not
/// registered and the call will throw [MissingPluginException].
Future<String> saveFileViaOhosChannel(String fileName, Uint8List bytes) async {
  const channel = MethodChannel('flow_muse/file_save');
  final path = await channel.invokeMethod<String>('saveFile', <String, Object?>{
    'fileName': fileName,
    'bytes': bytes,
  });
  if (path == null || path.isEmpty) {
    throw PlatformException(
      code: 'FILE_SAVE_FAILED',
      message: 'Save returned null or empty path',
    );
  }
  return path;
}
