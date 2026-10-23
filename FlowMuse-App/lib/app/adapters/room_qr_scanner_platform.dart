import 'dart:io' show Platform;

enum RoomQrScannerPlatform { android, ohos, unsupported }

RoomQrScannerPlatform get roomQrScannerPlatform =>
    switch (Platform.operatingSystem) {
      'android' => RoomQrScannerPlatform.android,
      'ohos' => RoomQrScannerPlatform.ohos,
      _ => RoomQrScannerPlatform.unsupported,
    };
