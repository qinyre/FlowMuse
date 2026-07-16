import 'speech_recognition_service.dart';
import 'speech_recognition_service_io.dart'
    if (dart.library.js_interop) 'speech_recognition_service_web.dart'
    as platform;

SpeechRecognitionService createSpeechRecognitionService() =>
    platform.createSpeechRecognitionService();
