import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/speech_recognition_event.dart';
import 'speech_recognition_service.dart';

class SherpaSpeechRecognitionService implements SpeechRecognitionService {
  SherpaSpeechRecognitionService({
    MethodChannel channel = const MethodChannel('flow_muse/speech_recognition'),
  }) : _channel = channel;

  static bool _bindingsInitialized = false;

  final MethodChannel _channel;
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<SpeechRecognitionEvent> _events =
      StreamController<SpeechRecognitionEvent>.broadcast();
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _audioSubscription;
  bool _disposed = false;
  bool _listening = false;
  String _completedText = '';
  String _lastPreview = '';

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  @override
  Future<bool> isAvailable() async => !_disposed;

  @override
  Future<void> start({String locale = 'zh-CN'}) async {
    if (_disposed || _listening) return;
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.starting));
    try {
      if (!await _recorder.hasPermission()) {
        _fail(SpeechRecognitionErrorCode.permissionDenied);
        return;
      }
      await _ensureRecognizer();
      _stream?.free();
      _stream = _recognizer!.createStream();
      _completedText = '';
      _lastPreview = '';
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );
      final audio = await _recorder.startStream(config);
      _listening = true;
      _audioSubscription = audio.listen(
        _acceptAudio,
        onError: (_) => _fail(SpeechRecognitionErrorCode.unknown),
      );
      _emit(
        const SpeechRecognitionStateChanged(SpeechRecognitionState.listening),
      );
    } catch (error) {
      _fail(SpeechRecognitionErrorCode.unknown, error.toString());
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed || !_listening) return;
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.stopping));
    await _stopRecorder();
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return;
    stream.inputFinished();
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    final tail = recognizer.getResult(stream).text.trim();
    final text = '$_completedText$tail'.trim();
    if (text.isEmpty) {
      _fail(SpeechRecognitionErrorCode.noSpeech);
    } else {
      _emit(SpeechRecognitionResult(text, isFinal: true));
      _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
    }
    _releaseStream();
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    await _stopRecorder();
    _releaseStream();
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await cancel();
    _disposed = true;
    _recognizer?.free();
    _recognizer = null;
    _recorder.dispose();
    await _events.close();
  }

  Future<void> _ensureRecognizer() async {
    if (_recognizer != null) return;
    if (!_bindingsInitialized) {
      sherpa.initBindings();
      _bindingsInitialized = true;
    }
    final paths = Map<String, String>.from(
      await _channel.invokeMapMethod<String, String>('prepareOfflineModel') ??
          const {},
    );
    if (paths.length != 4) throw StateError('Offline speech model is missing');
    final model = sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: paths['encoder']!,
        decoder: paths['decoder']!,
        joiner: paths['joiner']!,
      ),
      tokens: paths['tokens']!,
      numThreads: 2,
      debug: false,
      modelType: 'zipformer',
    );
    _recognizer = sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(model: model),
    );
  }

  void _acceptAudio(Uint8List bytes) {
    final stream = _stream;
    final recognizer = _recognizer;
    if (!_listening || stream == null || recognizer == null) return;
    final data = ByteData.sublistView(bytes);
    final samples = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    stream.acceptWaveform(samples: samples, sampleRate: 16000);
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    final current = recognizer.getResult(stream).text.trim();
    if (recognizer.isEndpoint(stream)) {
      if (current.isNotEmpty) _completedText += current;
      recognizer.reset(stream);
    }
    final preview = '$_completedText$current'.trim();
    if (preview.isNotEmpty && preview != _lastPreview) {
      _lastPreview = preview;
      _emit(SpeechRecognitionResult(preview, isFinal: false));
    }
  }

  Future<void> _stopRecorder() async {
    if (!_listening) return;
    _listening = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
  }

  void _releaseStream() {
    _stream?.free();
    _stream = null;
    _completedText = '';
    _lastPreview = '';
  }

  void _fail(SpeechRecognitionErrorCode code, [String message = '']) {
    _listening = false;
    _emit(SpeechRecognitionFailed(code, message: message));
    _emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
    _releaseStream();
  }

  void _emit(SpeechRecognitionEvent event) {
    if (!_disposed) _events.add(event);
  }
}
