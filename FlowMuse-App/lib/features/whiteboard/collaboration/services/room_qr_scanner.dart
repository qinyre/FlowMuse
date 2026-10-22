import 'package:flutter/widgets.dart';

import '../models/collaboration_room.dart';
import 'room_qr_scanner_io.dart'
    if (dart.library.js_interop) 'room_qr_scanner_web.dart'
    as platform;

bool get canScanRoomQr => platform.canScanRoomQr;

Future<CollaborationRoom?> scanRoomQr(BuildContext context) =>
    platform.scanRoomQr(context);
