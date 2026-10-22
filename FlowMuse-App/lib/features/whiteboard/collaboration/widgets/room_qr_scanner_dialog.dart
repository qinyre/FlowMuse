import 'dart:async';
import 'dart:math' as math;

import 'package:flow_muse/shared/widgets/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/collaboration_room.dart';

class RoomQrScannerDialog extends StatefulWidget {
  const RoomQrScannerDialog({super.key});

  @override
  State<RoomQrScannerDialog> createState() => _RoomQrScannerDialogState();
}

class _RoomQrScannerDialogState extends State<RoomQrScannerDialog>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _finished = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_finished || !_controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.start());
    } else if (state == AppLifecycleState.inactive) {
      unawaited(_controller.stop());
    }
  }

  void _close([CollaborationRoom? room]) {
    if (_finished) return;
    _finished = true;
    unawaited(_controller.stop());
    Navigator.of(context).pop(room);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _detect(BarcodeCapture capture) {
    if (!mounted ||
        _finished ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      final room = value.length <= 4096
          ? CollaborationRoom.parse(value).room
          : null;
      if (room != null) {
        _close(room);
        return;
      }
    }
    if (capture.barcodes.isNotEmpty && _error == null) {
      setState(() => _error = '这不是有效的协作房间二维码，请对准房主分享的二维码。');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.controlGap * 2),
      child: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.compactPageInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '扫码加入房间',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭扫码',
                      onPressed: _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.listGap),
                SizedBox(
                  height: math.min(
                    360,
                    MediaQuery.sizeOf(context).height * 0.45,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    child: MobileScanner(
                      controller: _controller,
                      onDetect: _detect,
                      errorBuilder: (_, error) => ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(
                              AppSpacing.compactPageInset,
                            ),
                            child: Text(
                              error.errorCode ==
                                      MobileScannerErrorCode.permissionDenied
                                  ? '未获得相机权限。请在系统或浏览器设置中允许相机，或返回粘贴房间链接。'
                                  : '无法打开摄像头。请确认设备有可用摄像头，也可以返回粘贴房间链接。',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.controlGap * 2),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error ?? '对准房间二维码，识别后直接进入协作，无需添加好友。',
                    textAlign: TextAlign.center,
                    style: _error == null
                        ? null
                        : TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                const SizedBox(height: AppSpacing.listGap),
                OutlinedButton(
                  onPressed: _close,
                  child: const Text('返回使用链接加入'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
