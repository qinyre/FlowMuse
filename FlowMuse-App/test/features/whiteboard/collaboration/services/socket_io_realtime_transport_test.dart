import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

void main() {
  test('live ink 只在 writable 时调用 volatile channel', () {
    final channel = _RecordingVolatileChannel();

    expect(
      emitLiveInkIfWritable(channel, 'server-live-ink', const [1]),
      isFalse,
    );
    expect(channel.events, isEmpty);

    channel.writable = true;
    expect(
      emitLiveInkIfWritable(channel, 'server-live-ink', const [2]),
      isTrue,
    );
    expect(channel.events, ['server-live-ink']);
  });

  test('生产 Socket.IO adapter 的 volatile emit 不进入真实 sendBuffer', () {
    final socket = io.io(
      'http://127.0.0.1:1',
      io.OptionBuilder().disableAutoConnect().build(),
    );
    addTearDown(socket.dispose);
    final channel = SocketIoLiveInkVolatileChannel(socket);

    expect(channel.writable, isFalse);
    channel.emit('server-live-ink', const [1]);

    expect(socket.sendBuffer, isEmpty);
  });
}

class _RecordingVolatileChannel implements LiveInkVolatileChannel {
  @override
  bool writable = false;

  final List<String> events = [];

  @override
  void emit(String event, Object data) {
    events.add(event);
  }
}
