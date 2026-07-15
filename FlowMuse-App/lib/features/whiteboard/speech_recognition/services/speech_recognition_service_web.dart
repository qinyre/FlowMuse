import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../models/speech_recognition_event.dart';
import 'speech_recognition_service.dart';

SpeechRecognitionService createSpeechRecognitionService() =>
    WebSpeechRecognitionService();

class WebSpeechRecognitionService implements SpeechRecognitionService {
  final StreamController<SpeechRecognitionEvent> _events =
      StreamController<SpeechRecognitionEvent>.broadcast();
  JSObject? _recognition;
  int _generation = 0;
  bool _finalEmitted = false;
  bool _disposed = false;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  JSFunction? get _constructor {
    final standard = globalContext.getProperty<JSAny?>(
      'SpeechRecognition'.toJS,
    );
    final webkit = globalContext.getProperty<JSAny?>(
      'webkitSpeechRecognition'.toJS,
    );
    final value = standard ?? webkit;
    return value?.isA<JSFunction>() == true ? value as JSFunction : null;
  }

  @override
  Future<bool> isAvailable() async => !_disposed && _constructor != null;

  @override
  Future<void> start({String locale = 'zh-CN'}) async {
    if (_disposed) return;
    final constructor = _constructor;
    if (constructor == null) {
      _emit(
        const SpeechRecognitionFailed(SpeechRecognitionErrorCode.unavailable),
      );
      return;
    }
    await cancel();
    final generation = ++_generation;
    _finalEmitted = false;
    final recognition = constructor.callAsConstructor<JSObject>();
    _recognition = recognition;
    recognition
      ..setProperty('lang'.toJS, locale.toJS)
      ..setProperty('continuous'.toJS, false.toJS)
      ..setProperty('interimResults'.toJS, true.toJS)
      ..setProperty(
        'onstart'.toJS,
        (() {
          if (_isCurrent(generation)) {
            _emit(
              const SpeechRecognitionStateChanged(
                SpeechRecognitionState.listening,
              ),
            );
          }
        }).toJS,
      )
      ..setProperty(
        'onresult'.toJS,
        ((JSObject event) => _handleResult(event, generation)).toJS,
      )
      ..setProperty(
        'onerror'.toJS,
        ((JSObject event) => _handleError(event, generation)).toJS,
      )
      ..setProperty(
        'onend'.toJS,
        (() {
          if (_isCurrent(generation)) {
            _recognition = null;
            _emit(
              const SpeechRecognitionStateChanged(SpeechRecognitionState.idle),
            );
          }
        }).toJS,
      );
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.starting));
    try {
      recognition.callMethod<JSAny?>('start'.toJS);
    } catch (error) {
      _emit(
        SpeechRecognitionFailed(
          SpeechRecognitionErrorCode.busy,
          message: error.toString(),
        ),
      );
      _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
    }
  }

  @override
  Future<void> stop() async {
    final recognition = _recognition;
    if (_disposed || recognition == null) return;
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.stopping));
    recognition.callMethod<JSAny?>('stop'.toJS);
  }

  @override
  Future<void> cancel() async {
    final recognition = _recognition;
    _generation++;
    _recognition = null;
    _finalEmitted = false;
    if (recognition != null) {
      recognition.callMethod<JSAny?>('abort'.toJS);
    }
    if (!_disposed) {
      _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await cancel();
    _disposed = true;
    await _events.close();
  }

  void _handleResult(JSObject event, int generation) {
    if (!_isCurrent(generation)) return;
    final results = event.getProperty<JSObject>('results'.toJS);
    final start = event.getProperty<JSNumber>('resultIndex'.toJS).toDartInt;
    final length = results.getProperty<JSNumber>('length'.toJS).toDartInt;
    for (var i = start; i < length; i++) {
      final result = results.getProperty<JSObject>(i.toJS);
      final alternative = result.getProperty<JSObject>(0.toJS);
      final text = alternative
          .getProperty<JSString>('transcript'.toJS)
          .toDart
          .trim();
      final isFinal = result.getProperty<JSBoolean>('isFinal'.toJS).toDart;
      if (text.isEmpty || (isFinal && _finalEmitted)) continue;
      if (isFinal) _finalEmitted = true;
      _emit(SpeechRecognitionResult(text, isFinal: isFinal));
    }
  }

  void _handleError(JSObject event, int generation) {
    if (!_isCurrent(generation)) return;
    final error = event.getProperty<JSString>('error'.toJS).toDart;
    _emit(SpeechRecognitionFailed(_mapError(error), message: error));
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
  }

  SpeechRecognitionErrorCode _mapError(String error) => switch (error) {
    'not-allowed' ||
    'service-not-allowed' => SpeechRecognitionErrorCode.permissionDenied,
    'audio-capture' => SpeechRecognitionErrorCode.unavailable,
    'network' => SpeechRecognitionErrorCode.network,
    'no-speech' => SpeechRecognitionErrorCode.noSpeech,
    'aborted' => SpeechRecognitionErrorCode.cancelled,
    _ => SpeechRecognitionErrorCode.unknown,
  };

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _emit(SpeechRecognitionEvent event) {
    if (!_disposed) _events.add(event);
  }
}
