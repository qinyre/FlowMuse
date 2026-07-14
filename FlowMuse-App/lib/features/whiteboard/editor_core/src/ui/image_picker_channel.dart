/// Cross-platform gallery image picker.
///
/// On HarmonyOS the gallery is opened via the native `PhotoViewPicker` (channel
/// `flow_muse/file_picker` method `pickImage`, wired in `FilePickerChannel.ets`).
/// On Android it uses the system Photo Picker `ActivityResultContracts.PickVisualMedia`
/// (channel `flow_muse/image_picker`, wired in `MainActivity`).
///
/// Both paths open the system gallery directly — no "file manager / gallery"
/// source-selection prompt — and return the picked image's name + bytes.
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

import 'file_picker_channel_ohos.dart';

/// A single image returned by the gallery picker.
class PickedImage {
  final String name;
  final Uint8List bytes;

  const PickedImage({required this.name, required this.bytes});

  factory PickedImage._fromMap(Map<Object?, Object?> map) {
    final name = (map['name'] as String?) ?? 'image';
    Object? raw = map['bytes'];
    final Uint8List bytes = raw is Uint8List ? raw : Uint8List(0);
    return PickedImage(name: name, bytes: bytes);
  }
}

/// Picks an image directly from the system gallery (album).
///
/// Opens the gallery immediately — no source-selection dialog.  Returns the
/// picked image, or `null` if the user cancelled.
///
/// Supported platforms: Android (Photo Picker) and HarmonyOS (`PhotoViewPicker`).
/// Throws [UnsupportedError] on other platforms — callers should fall back to
/// `file_picker` there.
Future<PickedImage?> pickImageFromGallery() async {
  final List<Map<Object?, Object?>> raw;
  if (defaultTargetPlatform == TargetPlatform.ohos) {
    final files = await pickImageViaOhosChannel();
    raw = files.map((f) => <Object?, Object?>{'name': f.name, 'bytes': f.bytes}).toList();
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    const channel = MethodChannel('flow_muse/image_picker');
    final result = await channel.invokeListMethod<Map<Object?, Object?>>('pickImage');
    raw = result ?? const [];
  } else {
    throw UnsupportedError(
      'pickImageFromGallery only supports Android and HarmonyOS; '
      'use file_picker on other platforms.',
    );
  }
  if (raw.isEmpty) return null;
  return PickedImage._fromMap(raw.first);
}
