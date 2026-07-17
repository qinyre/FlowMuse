import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_agent_models.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_agent_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('超长笔记上下文按单段和总长度限制安全裁剪', () {
    final context = AiNoteContext.fromTexts([
      AiNoteText(
        id: 'long',
        text: List.filled(maxAiAgentContextLength + 100, '字').join(),
      ),
    ]);

    expect(context.truncated, isTrue);
    expect(context.texts, hasLength(6));
    expect(
      context.texts.fold<int>(0, (sum, text) => sum + text.text.runes.length),
      maxAiAgentContextLength,
    );
    expect(
      context.texts.every(
        (text) => text.text.runes.length <= maxAiAgentTextLength,
      ),
      isTrue,
    );
  });

  test('解析受支持的多操作响应', () {
    final response = AiAgentResponse.fromOpenAiJson({
      'choices': [
        {
          'message': {
            'content': '准备应用',
            'tool_calls': [
              {
                'function': {
                  'name': 'rename_note',
                  'arguments': '{"title":"课堂笔记总结"}',
                },
              },
              {
                'function': {
                  'name': 'insert_text',
                  'arguments': {'text': '总结：今天学习了状态管理。'},
                },
              },
            ],
          },
        },
      ],
    });

    expect(response.actions, hasLength(2));
    expect(response.actions.first.tool, AiAgentTool.renameNote);
    expect(response.actions.first.value, '课堂笔记总结');
  });

  test('Base URL 自动补齐 Chat Completions 路径', () {
    const config = AiAgentConfig(
      baseUrl: 'https://example.com/v1/',
      apiKey: 'key',
      model: 'model',
    );

    expect(
      config.chatCompletionsUri.toString(),
      'https://example.com/v1/chat/completions',
    );
  });

  test('完整 Chat Completions URL 末尾斜杠不会重复拼接', () {
    const config = AiAgentConfig(
      baseUrl: 'https://example.com/v1/chat/completions/',
      apiKey: 'key',
      model: 'model',
    );

    expect(
      config.chatCompletionsUri.toString(),
      'https://example.com/v1/chat/completions',
    );
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
