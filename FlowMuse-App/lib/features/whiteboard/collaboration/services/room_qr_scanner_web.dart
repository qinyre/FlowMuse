import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:web/web.dart' as web;

import '../models/collaboration_room.dart';
import '../widgets/room_qr_scanner_dialog.dart';

bool get canScanRoomQr => true;

Future<CollaborationRoom?> scanRoomQr(BuildContext context) {
  // 使用随站点发布的解码器，现场扫码不依赖第三方 CDN。
  MobileScannerPlatform.instance
    ..setWebBarcodeReader(WebBarcodeReader.zxingJs)
    ..setBarcodeLibraryScriptUrl(
      Uri.parse(
        web.document.baseURI,
      ).resolve('scanner/zxing-0.23.0.min.js').toString(),
    );
  return showDialog<CollaborationRoom>(
    context: context,
    builder: (_) => const RoomQrScannerDialog(),
  );
}
