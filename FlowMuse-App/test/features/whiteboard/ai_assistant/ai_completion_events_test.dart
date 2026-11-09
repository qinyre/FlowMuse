import 'dart:convert';

import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_agent_models.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_completion_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String event(Map<String, Object?> delta, [String? finish]) =>
      'data: ${jsonEncode({
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
      })}\r\n\r\n';

  test('拆分 UTF-8 和工具参数，正文立即可见而操作只在结束时返回', () async {
    final bytes = utf8.encode(
      [
        event({'content': '公式：'}),
        event({
          'tool_calls': [
            {
              'index': 0,
              'function': {'name': 'insert_text', 'arguments': '{"text":'},
            },
          ],
        }),
        event({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '"示例"}'},
            },
          ],
        }, 'tool_calls'),
        'data: [DONE]\r\n\r\n',
      ].join(),
    );
    final seen = <String>[];
    final result = await readAiCompletionEvents(
      Stream.fromIterable(bytes.map((byte) => [byte])),
      seen.add,
    );
    expect(seen, ['公式：']);
    final response = AiAgentResponse.fromOpenAiJson(
      jsonDecode(result) as Map<String, Object?>,
    );
    expect(response.message, '公式：');
    expect(response.actions.single.value, '示例');
  });

  test('断流、截断和错误事件不会产生可写入的回复', () async {
    for (final tail in ['', event({}, 'length'), 'data: {"error":{}}\n\n']) {
      final seen = <String>[];
      await expectLater(
        readAiCompletionEvents(
          Stream.value(utf8.encode(event({'content': '部分正文'}) + tail)),
          seen.add,
        ),
        throwsFormatException,
      );
      expect(seen, ['部分正文']);
    }
  });
}
