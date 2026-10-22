import 'package:flutter/material.dart';
import 'package:flow_muse/shared/widgets/app_spacing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/collaboration_room.dart';

class RoomInviteQr extends StatelessWidget {
  const RoomInviteQr({super.key, required this.roomLink});

  final String roomLink;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(roomLink);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        !CollaborationRoom.parse(roomLink).isValid) {
      return const Text('邀请链接不可用，请复制房间码加入。');
    }
    return Column(
      children: [
        Center(
          child: SizedBox.square(
            dimension: 240,
            child: QrImageView(
              data: roomLink,
              size: 240,
              padding: const EdgeInsets.all(20),
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              semanticsLabel: '协作房间邀请二维码',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.controlGap),
        const Text('扫码进入房间，无需加好友', textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          '手机系统相机扫码可直接打开 Web',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
