import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart';

void main() {
  test('live ink 只在 writable 时调用 volatile channel', () {
    final channel = _RecordingVolatileChannel();

    expect(
      emitLiveInkIfWritable(channel, 'server-live-ink', const [1]),
      isFalse,
    );
    expect(channel.events, isEmpty);
    expect(channel.sendBufferLength, 0);

    channel.writable = true;
    expect(
      emitLiveInkIfWritable(channel, 'server-live-ink', const [2]),
      isTrue,
    );
    expect(channel.events, ['server-live-ink']);
    expect(channel.sendBufferLength, 0);
  });
}

class _RecordingVolatileChannel implements LiveInkVolatileChannel {
  @override
  bool writable = false;

  final List<String> events = [];
  int sendBufferLength = 0;

  @override
  void emit(String event, Object data) {
    events.add(event);
  }
}
