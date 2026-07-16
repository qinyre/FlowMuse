import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_agent_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析受支持的多操作响应', () {
    final response = AiAgentResponse.fromJson({
      'message': '准备应用',
      'actions': [
        {
          'tool': 'rename_note',
          'arguments': {'title': '课堂笔记总结'},
        },
        {
          'tool': 'insert_text',
          'arguments': {'text': '总结：今天学习了状态管理。'},
        },
      ],
    });

    expect(response.actions, hasLength(2));
    expect(response.actions.first.tool, AiAgentTool.renameNote);
    expect(response.actions.first.value, '课堂笔记总结');
  });

  test('未知工具一律拒绝', () {
    expect(
      () => AiAgentResponse.fromJson({
        'actions': [
          {'tool': 'delete_note', 'arguments': <String, Object?>{}},
        ],
      }),
      throwsFormatException,
    );
  });

  test('超长插入内容一律拒绝', () {
    expect(
      () => AiAgentResponse.fromJson({
        'actions': [
          {
            'tool': 'insert_text',
            'arguments': {
              'text': List.filled(maxAiAgentTextLength + 1, '字').join(),
            },
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('多个重命名操作一律拒绝', () {
    expect(
      () => AiAgentResponse.fromJson({
        'actions': [
          {
            'tool': 'rename_note',
            'arguments': {'title': '标题一'},
          },
          {
            'tool': 'rename_note',
            'arguments': {'title': '标题二'},
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
