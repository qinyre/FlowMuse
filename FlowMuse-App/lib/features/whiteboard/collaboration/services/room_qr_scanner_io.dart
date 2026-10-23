import 'package:flutter/material.dart';

import '../../../../app/adapters/room_qr_scanner_platform.dart';
import '../models/collaboration_room.dart';
import '../widgets/room_qr_scanner_dialog.dart';
import 'room_qr_scanner_channel_ohos.dart';

bool get canScanRoomQr =>
    roomQrScannerPlatform != RoomQrScannerPlatform.unsupported;

Future<CollaborationRoom?> scanRoomQr(BuildContext context) async {
  if (!canScanRoomQr) return null;
  if (roomQrScannerPlatform == RoomQrScannerPlatform.ohos) {
    return scanRoomQrOhos(context);
  }
  return showDialog<CollaborationRoom>(
    context: context,
    builder: (_) => const RoomQrScannerDialog(),
  );
}
