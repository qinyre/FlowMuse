import 'dart:async';

import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_agent_models.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_agent_repository.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_prompt_store.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/shared/storage/local_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('快捷指令可填充输入且只应用勾选动作', (tester) async {
    AiAgentResponse? applied;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onApply: (response) async => applied = response,
    );

    await tester.tap(find.text('提取待办事项'));
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '提取待办事项',
    );

    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '重命名笔记'));
    await tester.pump();
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();

    expect(applied!.actions, hasLength(1));
    expect(applied!.actions.single.tool, AiAgentTool.insertText);
  });

  testWidgets('追问携带上一轮动作且编辑后的内容才会应用', (tester) async {
    final repository = _FakeAiAgentRepository();
    AiAgentResponse? applied;
    await _openDialog(
      tester,
      repository: repository,
      onApply: (response) async => applied = response,
    );

    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '再精简一点');
    await tester.tap(find.text('追问修改'));
    await tester.pumpAndSettle();

    expect(repository.previousResponses.last, isNotNull);
    expect(repository.previousResponses.last!.actions, hasLength(2));
    final insertField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == '精简后的总结',
    );
    await tester.enterText(insertField, '用户修改后的总结');
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();

    expect(
      applied!.actions
          .singleWhere((action) => action.tool == AiAgentTool.insertText)
          .value,
      '用户修改后的总结',
    );
  });

  testWidgets('取消生成会终止令牌并忽略迟到响应', (tester) async {
    final completer = Completer<AiAgentResponse>();
    final repository = _FakeAiAgentRepository(completer: completer);
    await _openDialog(tester, repository: repository, onApply: (_) async {});

    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.tap(find.text('取消生成'));
    await tester.pump();

    expect(repository.cancelToken!.isCancelled, isTrue);
    expect(find.text('已取消生成'), findsOneWidget);
    completer.complete(_FakeAiAgentRepository.firstResponse);
    await tester.pump();
    expect(find.text('准备应用'), findsNothing);
  });

  testWidgets('空笔记可直接对话且不显示应用操作', (tester) async {
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(
        response: const AiAgentResponse(message: '这是直接回答', actions: []),
      ),
      texts: const [],
      onApply: (_) async {},
    );

    await tester.enterText(find.byType(TextField).first, '帮我构思一个故事');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.text('这是直接回答'), findsOneWidget);
    expect(find.text('确认后将执行：'), findsNothing);
    expect(find.text('确认应用'), findsNothing);
    expect(find.text('追问修改'), findsOneWidget);
  });

  testWidgets('思维导图动作展示结构并经确认应用', (tester) async {
    final action = AiAgentAction.fromJson({
      'tool': 'generate_mindmap',
      'arguments': {
        'root': {
          'text': '中心主题',
          'children': [
            {'text': '分支', 'children': <Object?>[]},
          ],
        },
      },
    });
    AiAgentResponse? applied;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(
        response: AiAgentResponse(message: '已生成', actions: [action]),
      ),
      onApply: (response) async => applied = response,
    );

    await tester.tap(find.text('根据当前内容生成思维导图'));
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.text('生成思维导图'), findsOneWidget);
    expect(find.textContaining('中心主题'), findsOneWidget);
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();
    expect(applied!.actions.single.tool, AiAgentTool.generateMindmap);
  });
}

Future<void> _openDialog(
  WidgetTester tester, {
  required AiAgentRepository repository,
  required Future<void> Function(AiAgentResponse) onApply,
  List<AiNoteText> texts = const [AiNoteText(id: 'text-1', text: '测试内容')],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAiAgentDialog(
            context: context,
            repository: repository,
            promptStore: AiPromptStore(_MemorySettings()),
            noteTitle: '测试笔记',
            texts: texts,
            onApply: onApply,
          ),
          child: const Text('打开'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

class _FakeAiAgentRepository extends AiAgentRepository {
  _FakeAiAgentRepository({this.completer, this.response = firstResponse});

  static const firstResponse = AiAgentResponse(
    message: '准备应用',
    actions: [
      AiAgentAction(tool: AiAgentTool.renameNote, value: '新标题'),
      AiAgentAction(tool: AiAgentTool.insertText, value: '总结内容'),
    ],
  );
  final Completer<AiAgentResponse>? completer;
  final AiAgentResponse response;
  final previousResponses = <AiAgentResponse?>[];
  NativeHttpCancelToken? cancelToken;

  @override
  Future<AiAgentResponse> run({
    required String instruction,
    required String noteTitle,
    required List<AiNoteText> texts,
    AiAgentResponse? previousResponse,
    NativeHttpCancelToken? cancelToken,
  }) async {
    previousResponses.add(previousResponse);
    this.cancelToken = cancelToken;
    if (completer != null) return completer!.future;
    if (previousResponse != null) {
      return const AiAgentResponse(
        message: '已按追问修改',
        actions: [
          AiAgentAction(tool: AiAgentTool.renameNote, value: '新标题'),
          AiAgentAction(tool: AiAgentTool.insertText, value: '精简后的总结'),
        ],
      );
    }
    return response;
  }
}

class _MemorySettings extends LocalSettingsRepository {
  _MemorySettings() : super(() async => throw UnsupportedError('unused'));

  final values = <String, String>{};

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }
}
