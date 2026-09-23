import 'package:socket_io_client/socket_io_client.dart' as io;

class SocialRealtimeTransport {
  SocialRealtimeTransport(this.serverUrl, this.token);
  final String serverUrl, token;
  io.Socket? _socket;

  void start({
    required void Function() onHint,
    required void Function() onRevoked,
    required void Function(bool) onConnection,
  }) {
    if (_socket != null) return;
    final socket = io.io(
      '${serverUrl.replaceFirst(RegExp(r'/+$'), '')}/social',
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableForceNew()
          .disableMultiplex()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(15000)
          .setRandomizationFactor(0.5)
          .setAuth({'token': token})
          .build(),
    );
    _socket = socket;
    bool current() => identical(_socket, socket);
    socket.onConnect((_) {
      if (current()) {
        onConnection(true);
        onHint();
      }
    });
    socket.onDisconnect((_) {
      if (current()) onConnection(false);
    });
    socket.onConnectError((error) {
      if (!current()) return;
      onConnection(false);
      if (error == 'unauthorized' ||
          error is Map && error['message'] == 'unauthorized') {
        onRevoked();
      }
    });
    for (final event in [
      'relationship.changed',
      'conversation.changed',
      'invitation.changed',
    ]) {
      socket.on(event, (_) {
        if (current()) onHint();
      });
    }
    socket.on('session.revoked', (_) {
      if (current()) onRevoked();
    });
    socket.connect();
  }

  void close() {
    final socket = _socket;
    _socket = null;
    socket?.dispose();
  }
}
