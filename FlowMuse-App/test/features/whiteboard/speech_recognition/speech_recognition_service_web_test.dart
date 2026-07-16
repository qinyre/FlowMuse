@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flow_muse/features/whiteboard/speech_recognition/services/speech_recognition_service_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('浏览器构造器检测与实际全局能力一致', () async {
    final service = WebSpeechRecognitionService();
    addTearDown(service.dispose);
    final standard = globalContext.getProperty<JSAny?>(
      'SpeechRecognition'.toJS,
    );
    final webkit = globalContext.getProperty<JSAny?>(
      'webkitSpeechRecognition'.toJS,
    );

    expect(
      await service.isAvailable(),
      standard?.isA<JSFunction>() == true || webkit?.isA<JSFunction>() == true,
    );
  });

  test('浏览器缺少构造器时安全返回不可用', () async {
    final standard = globalContext.getProperty<JSAny?>(
      'SpeechRecognition'.toJS,
    );
    final webkit = globalContext.getProperty<JSAny?>(
      'webkitSpeechRecognition'.toJS,
    );
    addTearDown(() {
      globalContext
        ..setProperty('SpeechRecognition'.toJS, standard)
        ..setProperty('webkitSpeechRecognition'.toJS, webkit);
    });
    globalContext
      ..setProperty('SpeechRecognition'.toJS, null)
      ..setProperty('webkitSpeechRecognition'.toJS, null);

    final service = WebSpeechRecognitionService();
    addTearDown(service.dispose);

    expect(await service.isAvailable(), isFalse);
  });
}
