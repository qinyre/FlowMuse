import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/speech_recognition_event.dart';
import 'sherpa_speech_recognition_service.dart';
import 'speech_recognition_service.dart';

SpeechRecognitionService createSpeechRecognitionService() =>
    MethodChannelSpeechRecognitionService();

class MethodChannelSpeechRecognitionService
    implements SpeechRecognitionService {
  MethodChannelSpeechRecognitionService({
    MethodChannel channel = const MethodChannel('flow_muse/speech_recognition'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final StreamController<SpeechRecognitionEvent> _events =
      StreamController<SpeechRecognitionEvent>.broadcast();
  int _generation = 0;
  bool _finalEmitted = false;
  bool _disposed = false;
  bool _useOffline = false;
  SherpaSpeechRecognitionService? _offline;
  StreamSubscription<SpeechRecognitionEvent>? _offlineSubscription;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  @override
  Future<bool> isAvailable() async {
    if (_disposed) return false;
    var nativeAvailable = false;
    try {
      nativeAvailable =
          await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      nativeAvailable = false;
    } on MissingPluginException {
      nativeAvailable = false;
    }
    if (nativeAvailable || !Platform.isAndroid) return nativeAvailable;
    _useOffline = true;
    return _ensureOffline().isAvailable();
  }

  @override
  Future<void> start({String locale = 'zh-CN'}) async {
    if (_disposed) return;
    if (_useOffline) return _ensureOffline().start(locale: locale);
    final generation = ++_generation;
    _finalEmitted = false;
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.starting));
    try {
      await _channel.invokeMethod<void>('start', {
        'locale': locale,
        'partialResults': true,
        'generation': generation,
      });
    } on PlatformException catch (error) {
      _emitPlatformError(error);
    } on MissingPluginException {
      _emit(
        const SpeechRecognitionFailed(SpeechRecognitionErrorCode.unavailable),
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_useOffline) {
      await _offline?.stop();
      return;
    }
    if (_disposed || _generation == 0) return;
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.stopping));
    try {
      await _channel.invokeMethod<void>('stop', {'generation': _generation});
    } on PlatformException catch (error) {
      _emitPlatformError(error);
    } on MissingPluginException {
      _emit(
        const SpeechRecognitionFailed(SpeechRecognitionErrorCode.unavailable),
      );
    }
  }

  @override
  Future<void> cancel() async {
    if (_useOffline) {
      await _offline?.cancel();
      return;
    }
    if (_disposed || _generation == 0) return;
    final activeGeneration = _generation;
    _finalEmitted = false;
    try {
      final cancelled =
          await _channel.invokeMethod<bool>('cancel', {
            'generation': activeGeneration,
          }) ??
          true;
      if (cancelled) _generation++;
    } on PlatformException {
      _generation++;
      // Cancelling is best-effort; the generation guard already drops callbacks.
    } on MissingPluginException {
      _generation++;
      // The platform has no active recognizer to release.
    }
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _channel.setMethodCallHandler(null);
    await _offlineSubscription?.cancel();
    _offlineSubscription = null;
    await _offline?.dispose();
    _offline = null;
    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException {
      // Resource cleanup remains best-effort when the native side is gone.
    } on MissingPluginException {
      // Other desktop platforms intentionally have no implementation.
    }
    await _events.close();
  }

  SherpaSpeechRecognitionService _ensureOffline() {
    final service = _offline ??= SherpaSpeechRecognitionService(
      channel: _channel,
    );
    _offlineSubscription ??= service.events.listen(_emit);
    return service;
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed) return;
    final arguments = Map<Object?, Object?>.from(
      call.arguments as Map? ?? const {},
    );
    final generation = arguments['generation'] as int?;
    if (generation != _generation) return;

    switch (call.method) {
      case 'onState':
        final state = _stateFrom(arguments['state'] as String?);
        if (state != null) _emit(SpeechRecognitionStateChanged(state));
      case 'onResult':
        final text = (arguments['text'] as String? ?? '').trim();
        final isFinal = arguments['final'] == true;
        if (text.isEmpty || (isFinal && _finalEmitted)) return;
        if (isFinal) _finalEmitted = true;
        _emit(SpeechRecognitionResult(text, isFinal: isFinal));
      case 'onError':
        _emit(
          SpeechRecognitionFailed(
            _errorFrom(arguments['code'] as String?),
            message: arguments['message'] as String? ?? '',
          ),
        );
        _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
    }
  }

  SpeechRecognitionState? _stateFrom(String? value) => switch (value) {
    'idle' => SpeechRecognitionState.idle,
    'starting' => SpeechRecognitionState.starting,
    'listening' => SpeechRecognitionState.listening,
    'stopping' => SpeechRecognitionState.stopping,
    _ => null,
  };

  SpeechRecognitionErrorCode _errorFrom(String? value) => switch (value) {
    'permissionDenied' => SpeechRecognitionErrorCode.permissionDenied,
    'unavailable' => SpeechRecognitionErrorCode.unavailable,
    'busy' => SpeechRecognitionErrorCode.busy,
    'noSpeech' => SpeechRecognitionErrorCode.noSpeech,
    'network' => SpeechRecognitionErrorCode.network,
    'cancelled' => SpeechRecognitionErrorCode.cancelled,
    _ => SpeechRecognitionErrorCode.unknown,
  };

  void _emitPlatformError(PlatformException error) {
    _emit(
      SpeechRecognitionFailed(
        _errorFrom(error.code),
        message: error.message ?? '',
      ),
    );
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
  }

  void _emit(SpeechRecognitionEvent event) {
    if (!_disposed) _events.add(event);
  }
}
