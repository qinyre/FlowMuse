import 'dart:async';
import 'dart:io';

import 'package:flow_muse/features/social/services/social_realtime_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('临时 namespace 拒绝后，HTTP 恢复可重新连接且不触发登出', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    var attempts = 0, revoked = false;
    server.listen((request) async {
      expect(request.uri.queryParameters.containsKey('token'), isFalse);
      final ws = await WebSocketTransformer.upgrade(request);
      sockets.add(ws);
      ws.add(
        '0{"sid":"test-engine","upgrades":[],"pingInterval":25000,"pingTimeout":20000}',
      );
      ws.listen((data) {
        if (data is String && data.startsWith('40/social,')) {
          attempts++;
          ws.add(
            attempts == 1
                ? '44/social,{"message":"unavailable"}'
                : '40/social,{"sid":"test-social"}',
          );
        }
      });
    });
    final transport = SocialRealtimeTransport(
      'http://127.0.0.1:${server.port}',
      'public-test-value',
    );
    addTearDown(() async {
      transport.close();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    final failed = Completer<void>(), connected = Completer<void>();
    void start() => transport.start(
      onHint: () {},
      onRevoked: () => revoked = true,
      onConnection: (value) {
        final next = value ? connected : failed;
        if (!next.isCompleted) next.complete();
      },
    );
    start();
    await failed.future.timeout(const Duration(seconds: 5));
    start();
    await connected.future.timeout(const Duration(seconds: 5));
    expect(revoked, isFalse);
    expect(attempts, 2);
  });
}
