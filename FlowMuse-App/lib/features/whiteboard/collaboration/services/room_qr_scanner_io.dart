import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../models/collaboration_room.dart';
import '../widgets/room_qr_scanner_dialog.dart';

bool get canScanRoomQr => Platform.isAndroid;

Future<CollaborationRoom?> scanRoomQr(BuildContext context) async {
  if (!canScanRoomQr) return null;
  return showDialog<CollaborationRoom>(
    context: context,
    builder: (_) => const RoomQrScannerDialog(),
  );
}
