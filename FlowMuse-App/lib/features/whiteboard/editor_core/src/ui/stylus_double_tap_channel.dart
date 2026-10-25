import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hardware barrel double-taps only; all editors share one native subscription.
class StylusDoubleTapChannel {
  StylusDoubleTapChannel._() {
    _events = StreamController<void>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }

  static final instance = StylusDoubleTapChannel._();
  static const _channel = MethodChannel('flow_muse/stylus_double_tap');
  late final StreamController<void> _events;
  int _generation = 0;
  num? _lastTimestamp;

  Stream<void> get events => _events.stream;

  void _start() {
    _generation++;
    _lastTimestamp = null;
    _channel.setMethodCallHandler(_onNativeCall);
    unawaited(_setListening(true));
  }

  void _stop() {
    _generation++;
    _lastTimestamp = null;
    _channel.setMethodCallHandler(null);
    unawaited(_setListening(false));
  }

  Future<void> _setListening(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setListening', {
        'enabled': enabled,
        'generation': _generation,
      });
    } on MissingPluginException {
      // Other platforms keep the ordinary toolbar.
    } on PlatformException catch (error) {
      debugPrint(
        '[FlowMuseCreateNote] stylus shortcut unavailable: ${error.code}',
      );
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final args = call.arguments;
    if (call.method != 'doubleTap' ||
        !_events.hasListener ||
        args is! Map ||
        args['generation'] != _generation) {
      return;
    }
    final timestamp = args['timestamp'];
    if (timestamp is! num || !timestamp.isFinite || timestamp < 0) return;
    final last = _lastTimestamp;
    if (last != null && timestamp - last < 300) return;
    _lastTimestamp = timestamp;
    _events.add(null);
  }
}
