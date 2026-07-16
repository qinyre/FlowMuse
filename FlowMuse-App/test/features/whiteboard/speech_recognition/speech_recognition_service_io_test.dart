import 'package:flow_muse/features/whiteboard/speech_recognition/models/speech_recognition_event.dart';
import 'package:flow_muse/features/whiteboard/speech_recognition/services/speech_recognition_service_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flow_muse/speech_recognition_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('映射中间结果且每代最终结果只发一次', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    final service = MethodChannelSpeechRecognitionService(channel: channel);
    addTearDown(service.dispose);
    final events = <SpeechRecognitionEvent>[];
    final subscription = service.events.listen(events.add);
    addTearDown(subscription.cancel);

    await service.start();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onResult', {
          'text': '中间',
          'final': false,
          'generation': 1,
        }),
      ),
      (_) {},
    );
    for (var i = 0; i < 2; i++) {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onResult', {
            'text': '最终',
            'final': true,
            'generation': 1,
          }),
        ),
        (_) {},
      );
    }
    await Future<void>.delayed(Duration.zero);

    final results = events.whereType<SpeechRecognitionResult>().toList();
    expect(results.map((event) => event.text), ['中间', '最终']);
  });

  test('取消后丢弃旧代回调', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    final service = MethodChannelSpeechRecognitionService(channel: channel);
    addTearDown(service.dispose);
    final events = <SpeechRecognitionEvent>[];
    final subscription = service.events.listen(events.add);
    addTearDown(subscription.cancel);

    await service.start();
    await service.cancel();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onResult', {
          'text': '迟到结果',
          'final': true,
          'generation': 1,
        }),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<SpeechRecognitionResult>(), isEmpty);
  });

  test('缺少原生实现时安全返回不可用', () async {
    final service = MethodChannelSpeechRecognitionService(channel: channel);
    addTearDown(service.dispose);

    expect(await service.isAvailable(), isFalse);
  });

  test('系统识别界面打开时保留返回结果', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'cancel' ? false : true,
    );
    final service = MethodChannelSpeechRecognitionService(channel: channel);
    addTearDown(service.dispose);
    final events = <SpeechRecognitionEvent>[];
    final subscription = service.events.listen(events.add);
    addTearDown(subscription.cancel);

    await service.start();
    await service.cancel();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onResult', {
          'text': '系统识别结果',
          'final': true,
          'generation': 1,
        }),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<SpeechRecognitionResult>().single.text, '系统识别结果');
  });
}
