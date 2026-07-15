import '../models/speech_recognition_event.dart';

abstract interface class SpeechRecognitionService {
  Future<bool> isAvailable();

  Stream<SpeechRecognitionEvent> get events;

  Future<void> start({String locale = 'zh-CN'});

  Future<void> stop();

  Future<void> cancel();

  Future<void> dispose();
}
