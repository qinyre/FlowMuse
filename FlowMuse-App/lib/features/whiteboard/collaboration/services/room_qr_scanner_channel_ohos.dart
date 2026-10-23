import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/collaboration_room.dart';

const _channel = MethodChannel('flow_muse/room_qr_scanner');

Future<CollaborationRoom?> scanRoomQrOhos(BuildContext context) async {
  String message;
  try {
    final value = await _channel.invokeMethod<String>('scan');
    if (value == null) return null; // 系统扫码页取消。
    final room = value.length <= 4096
        ? CollaborationRoom.parse(value).room
        : null;
    if (room != null) return room;
    message = '这不是有效的协作房间二维码，请扫描房主分享的二维码。';
  } on MissingPluginException {
    message = '当前版本未提供鸿蒙扫码，请粘贴房间链接。';
  } on PlatformException catch (error) {
    message = error.code == 'permission_denied'
        ? '未获得相机权限，请在系统设置中允许相机，或粘贴房间链接。'
        : '扫码暂不可用，请重试或粘贴房间链接。';
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
  return null;
}
