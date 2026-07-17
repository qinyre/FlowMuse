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

  test('上下文切分保留页面和坐标元数据', () {
    final context = AiNoteContext.fromTexts(const [
      AiNoteText(id: 'text', text: '页面文字', pageIndex: 2, x: 30, y: 40),
    ]);

    expect(context.texts.single.toJson(), {
      'id': 'text',
      'text': '页面文字',
      'pageIndex': 2,
      'x': 30.0,
      'y': 40.0,
    });
  });

  test('用户编辑后的动作仍执行长度校验', () {
    expect(
      () => AiAgentAction.edited(
        tool: AiAgentTool.renameNote,
        value: List.filled(maxAiAgentTitleLength + 1, '字').join(),
      ),
      throwsFormatException,
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

  test('思维导图内容树通过校验并可编辑往返', () {
    final action = AiAgentAction.fromJson({
      'tool': 'generate_mindmap',
      'arguments': {
        'root': {
          'text': '软件工程',
          'children': [
            {'text': '需求分析', 'children': <Object?>[]},
          ],
        },
      },
    });

    expect(action.tool, AiAgentTool.generateMindmap);
    expect(action.mindmapRoot['text'], '软件工程');
    expect(
      AiAgentAction.edited(tool: action.tool, value: action.value).toJson(),
      action.toJson(),
    );
  });

  test('思维导图拒绝未知字段和超过四层的树', () {
    expect(
      () => AiAgentAction.fromJson({
        'tool': 'generate_mindmap',
        'arguments': {
          'root': {'text': '根', 'children': <Object?>[], 'x': 10},
        },
      }),
      throwsFormatException,
    );
    expect(
      () => AiAgentAction.fromJson({
        'tool': 'generate_mindmap',
        'arguments': {'root': _mindmapChain(5)},
      }),
      throwsFormatException,
    );
  });

  test('思维导图最多允许五十个节点', () {
    expect(
      () => AiAgentAction.fromJson({
        'tool': 'generate_mindmap',
        'arguments': {
          'root': {
            'text': '根',
            'children': [
              for (var index = 0; index < maxAiMindmapNodes; index++)
                {'text': '分支 $index', 'children': <Object?>[]},
            ],
          },
        },
      }),
      throwsFormatException,
    );
  });

  test('思维导图与插入文字不能在同一响应中混用', () {
    expect(
      () => AiAgentResponse.fromJson({
        'actions': [
          {
            'tool': 'generate_mindmap',
            'arguments': {
              'root': {'text': '根', 'children': <Object?>[]},
            },
          },
          {
            'tool': 'insert_text',
            'arguments': {'text': '重复内容'},
          },
        ],
      }),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _mindmapChain(int depth) => {
  'text': '第 $depth 层',
  'children': depth == 1 ? <Object?>[] : [_mindmapChain(depth - 1)],
};
