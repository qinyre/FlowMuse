import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_agent_models.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_agent_repository.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('快捷指令可填充输入且只应用勾选动作', (tester) async {
    AiAgentResponse? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAiAgentDialog(
              context: context,
              repository: _FakeAiAgentRepository(),
              noteTitle: '测试笔记',
              texts: const [AiNoteText(id: 'text-1', text: '测试内容')],
              onApply: (response) async => applied = response,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提取待办事项'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '提取待办事项',
    );

    await tester.tap(find.text('生成操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '重命名笔记'));
    await tester.tap(find.widgetWithText(CheckboxListTile, '插入白板文字'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认应用'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, '插入白板文字'));
    await tester.pump();
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();

    expect(applied!.actions, hasLength(1));
    expect(applied!.actions.single.tool, AiAgentTool.insertText);
  });
}

class _FakeAiAgentRepository extends AiAgentRepository {
  @override
  Future<AiAgentResponse> run({
    required String instruction,
    required String noteTitle,
    required List<AiNoteText> texts,
  }) async {
    return const AiAgentResponse(
      message: '准备应用',
      actions: [
        AiAgentAction(tool: AiAgentTool.renameNote, value: '新标题'),
        AiAgentAction(tool: AiAgentTool.insertText, value: '总结内容'),
      ],
    );
  }
}
