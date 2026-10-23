import 'dart:async';

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/widgets/room_qr_scanner_dialog.dart';
import 'package:flow_muse/features/whiteboard/collaboration/widgets/join_room_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class _Camera extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  MobileScannerException? error;
  int starts = 0;
  int stops = 0;
  int disposals = 0;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => Stream.value(TorchState.off);
  @override
  Stream<double> get zoomScaleStateStream => Stream.value(1);
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (error != null) throw error!;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}
}

void main() {
  late MobileScannerPlatform original;
  late _Camera camera;
  setUp(() {
    original = MobileScannerPlatform.instance;
  });
  tearDown(() async {
    MobileScannerPlatform.instance = original;
    await camera.captures.close();
  });

  Future<void> open(
    WidgetTester tester,
    void Function(CollaborationRoom?) onResult, {
    MobileScannerErrorCode? error,
  }) async {
    camera = _Camera();
    if (error != null) camera.error = MobileScannerException(errorCode: error);
    MobileScannerPlatform.instance = camera;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  onResult(
                    await showDialog<CollaborationRoom>(
                      context: context,
                      builder: (_) => const RoomQrScannerDialog(),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('无效码可重试，同一帧多码与连续有效帧只返回一次', (tester) async {
    final room = CollaborationRoom.newRoom();
    CollaborationRoom? result;
    var results = 0;
    await open(tester, (value) {
      result = value;
      results++;
    });
    camera.captures.add(
      const BarcodeCapture(
        barcodes: [Barcode(rawValue: 'https://unrelated.example')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('这不是有效的协作房间二维码'), findsOneWidget);
    final valid = BarcodeCapture(
      barcodes: [
        const Barcode(rawValue: 'invalid'),
        Barcode(
          rawValue: room.toLink(
            origin: 'https://app.flowmuse.cloud',
            path: '/whiteboard/collaboration',
          ),
        ),
      ],
    );
    camera.captures
      ..add(valid)
      ..add(valid);
    await tester.pumpAndSettle();
    expect(result?.roomKey == room.roomKey, isTrue);
    expect(results, 1);
    expect(find.byType(MobileScanner), findsNothing);
    expect(camera.stops, greaterThan(0));
    expect(camera.disposals, 1);
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消动画期间迟到识别不会退出上一层页面', (tester) async {
    var results = 0;
    await open(tester, (_) => results++);
    final callback = tester
        .widget<MobileScanner>(find.byType(MobileScanner))
        .onDetect!;
    await tester.tap(find.byTooltip('关闭扫码'));
    callback(
      BarcodeCapture(
        barcodes: [
          Barcode(rawValue: CollaborationRoom.newRoom().toRoomValue()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(results, 1);
    expect(find.text('打开'), findsOneWidget);
    expect(camera.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  for (final error in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.genericError,
  ]) {
    testWidgets('相机错误 ${error.name} 可返回粘贴且窄屏无溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await open(tester, (_) {}, error: error);
      expect(
        find.textContaining(
          error == MobileScannerErrorCode.permissionDenied
              ? '未获得相机权限'
              : '无法打开摄像头',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('返回使用链接加入'));
      await tester.tap(find.text('返回使用链接加入'));
      await tester.pumpAndSettle();
      expect(camera.disposals, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('切到后台停止相机，返回前台恢复，关闭释放资源', (tester) async {
    await open(tester, (_) {});
    expect(camera.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(camera.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.starts, 2);
    await tester.tap(find.byTooltip('关闭扫码'));
    await tester.pumpAndSettle();
    expect(camera.disposals, 1);
  });

  testWidgets('扫码页返回房间后加入弹窗正确完成，游客无需好友页面', (tester) async {
    camera = _Camera();
    MobileScannerPlatform.instance = camera;
    final room = CollaborationRoom.newRoom();
    CollaborationRoom? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<CollaborationRoom>(
                    context: context,
                    builder: (_) => JoinRoomDialog(
                      scanner: (context) {
                        return showDialog<CollaborationRoom>(
                          context: context,
                          builder: (_) => const RoomQrScannerDialog(),
                        );
                      },
                    ),
                  );
                },
                child: const Text('加入入口'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('加入入口'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫码加入房间'));
    await tester.pumpAndSettle();
    camera.captures.add(
      BarcodeCapture(barcodes: [Barcode(rawValue: room.toRoomValue())]),
    );
    await tester.pumpAndSettle();
    expect(result?.roomKey == room.roomKey, isTrue);
    expect(find.byType(JoinRoomDialog), findsNothing);
    expect(find.byType(RoomQrScannerDialog), findsNothing);
    expect(camera.stops, 1);
    expect(camera.disposals, 1);
  });

  testWidgets('系统返回关闭扫码也会释放摄像头', (tester) async {
    await open(tester, (_) {});
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(camera.disposals, 1);
    expect(find.text('打开'), findsOneWidget);
  });
}
