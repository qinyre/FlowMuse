import 'dart:async';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/speech_recognition/models/speech_recognition_event.dart';
import 'package:flow_muse/features/whiteboard/speech_recognition/services/speech_recognition_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('中间结果不改场景，最终结果只插入一次', (tester) async {
    final controller = MarkdrawController();
    final service = _FakeSpeechRecognitionService();
    addTearDown(controller.dispose);
    var sceneChangeCount = 0;
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1000,
          height: 700,
          child: MarkdrawEditor(
            controller: controller,
            speechRecognitionService: service,
            onSceneChanged: (_, _) => sceneChangeCount++,
          ),
        ),
      ),
    );
    await tester.pump();

    service.emit(
      const SpeechRecognitionStateChanged(SpeechRecognitionState.listening),
    );
    service.emit(const SpeechRecognitionResult('中间文字', isFinal: false));
    await tester.pump();
    expect(find.text('中间文字'), findsOneWidget);
    expect(controller.editorState.scene.activeElements, isEmpty);
    expect(sceneChangeCount, 0);

    service.emit(const SpeechRecognitionResult('最终文字', isFinal: true));
    service.emit(const SpeechRecognitionResult('重复最终文字', isFinal: true));
    await tester.pump();
    final elements = controller.editorState.scene.activeElements;
    expect(elements, hasLength(1));
    expect((elements.first as TextElement).text, '最终文字');
    expect(sceneChangeCount, 1);
  });

  testWidgets('取消识别不插入文字', (tester) async {
    final controller = MarkdrawController();
    final service = _FakeSpeechRecognitionService();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdrawEditor(
          controller: controller,
          speechRecognitionService: service,
        ),
      ),
    );
    service.emit(
      const SpeechRecognitionStateChanged(SpeechRecognitionState.listening),
    );
    service.emit(const SpeechRecognitionResult('不会提交', isFinal: false));
    await tester.pump();

    await tester.tap(find.text('取消'));
    await tester.pump();

    expect(service.cancelCount, 1);
    expect(controller.editorState.scene.activeElements, isEmpty);
  });

  testWidgets('应用退后台会取消识别并释放临时结果', (tester) async {
    final controller = MarkdrawController();
    final service = _FakeSpeechRecognitionService();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdrawEditor(
          controller: controller,
          speechRecognitionService: service,
        ),
      ),
    );
    service.emit(
      const SpeechRecognitionStateChanged(SpeechRecognitionState.listening),
    );
    service.emit(const SpeechRecognitionResult('临时结果', isFinal: false));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(service.cancelCount, 1);
    expect(find.text('临时结果'), findsNothing);
    expect(controller.editorState.scene.activeElements, isEmpty);
  });
}

class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  final _events = StreamController<SpeechRecognitionEvent>.broadcast();
  int cancelCount = 0;

  void emit(SpeechRecognitionEvent event) => _events.add(event);

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> start({String locale = 'zh-CN'}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {
    cancelCount++;
    emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.idle));
  }

  @override
  Future<void> dispose() => _events.close();
}
