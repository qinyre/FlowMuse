/// HarmonyOS file picker service using native `DocumentViewPicker.select()`.
///
/// On OHOS the standard `file_picker` plugin is not available — the Flutter
/// engine does not auto-register plugins.  This service bridges to the OHOS-
/// specific `FilePickerChannel.ets` (registered in `EntryAbility`), which uses
/// `@kit.CoreFileKit`'s `DocumentViewPicker` to select files and return their
/// name + raw bytes.
library;

import 'package:flutter/services.dart';

/// A single file returned by the OHOS native picker.
class OhosPickedFile {
  final String name;
  final Uint8List bytes;

  const OhosPickedFile({required this.name, required this.bytes});

  factory OhosPickedFile._fromMap(Map<Object?, Object?> map) {
    final name = (map['name'] as String?) ?? 'unknown';
    Object? raw = map['bytes'];
    final Uint8List bytes = raw is Uint8List ? raw : Uint8List(0);
    return OhosPickedFile(name: name, bytes: bytes);
  }
}

/// Picks files via the OHOS `DocumentViewPicker` native UI.
///
/// [suffixFilters] are displayed to the user in the picker (e.g.
/// `['图片(.png,.jpg)|.png,.jpg']`).  [maxCount] limits how many files can be
/// selected (default 1).
///
/// Returns the list of picked files.  Throws [PlatformException] (or
/// [MissingPluginException]) on failure, including when the user cancels the
/// dialog.
///
/// This function is OHOS-only.  On other platforms the channel is not
/// registered and the call will throw [MissingPluginException].
Future<List<OhosPickedFile>> pickFilesViaOhosChannel({
  required List<String> suffixFilters,
  int maxCount = 1,
}) async {
  const channel = MethodChannel('flow_muse/file_picker');
  final result = await channel.invokeListMethod<Map<Object?, Object?>>(
    'pickFiles',
    <String, Object?>{
      'fileSuffixFilters': suffixFilters,
      'maxSelectNumber': maxCount,
    },
  );
  if (result == null || result.isEmpty) {
    throw PlatformException(
      code: 'FILE_PICK_FAILED',
      message: 'No files selected or user cancelled',
    );
  }
  return result.map(OhosPickedFile._fromMap).toList();
}
