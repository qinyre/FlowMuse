import 'dart:convert';

import '../models/ai_agent_models.dart';

/// Reassemble one Chat Completions choice and feed the existing final validator.
Future<String> readAiCompletionEvents(
  Stream<List<int>> bytes,
  void Function(String) onText,
) async {
  final text = StringBuffer();
  final calls = <int, ({StringBuffer name, StringBuffer arguments})>{};
  final data = <String>[];
  var eventLength = 0;
  String? finish;
  var done = false;
  await for (final line
      in utf8.decoder.bind(bytes).transform(const LineSplitter())) {
    if (line.startsWith('data:')) {
      final value = line.substring(5);
      final field = value.startsWith(' ') ? value.substring(1) : value;
      eventLength += field.length;
      if (eventLength > 128 * 1024) {
        throw const FormatException('AI 流式事件过长');
      }
      data.add(field);
    }
    if (line.isNotEmpty || data.isEmpty) continue;
    final payload = data.join('\n');
    data.clear();
    eventLength = 0;
    if (payload.trim() == '[DONE]') {
      done = true;
      break;
    }
    final event = jsonDecode(payload);
    if (event is! Map || event['error'] != null || event['choices'] is! List) {
      throw const FormatException('AI 流式响应格式无效');
    }
    for (final choice in event['choices'] as List) {
      if (choice is! Map) throw const FormatException('AI 流式响应格式无效');
      if (choice['index'] != null && choice['index'] != 0) continue;
      if (choice['finish_reason'] case final String reason) finish = reason;
      if (choice['delta'] case final Map delta) {
        if (delta['content'] case final String fragment) {
          text.write(fragment);
          if (text.length > maxAiAgentTextLength * 2) {
            throw const FormatException('AI 回复内容过长');
          }
          onText(fragment);
        }
        if (delta['tool_calls'] case final List updates) {
          for (final update in updates) {
            if (update is! Map ||
                update['index'] is! int ||
                (update['index'] as int) < 0 ||
                (update['index'] as int) >= maxAiAgentActions) {
              throw const FormatException('AI 流式工具调用无效');
            }
            final call = calls.putIfAbsent(
              update['index'] as int,
              () => (name: StringBuffer(), arguments: StringBuffer()),
            );
            if (update['function'] case final Map function) {
              if (function['name'] case final String name) {
                call.name.write(name);
              }
              if (function['arguments'] case final String arguments) {
                call.arguments.write(arguments);
              }
            }
          }
        }
      }
    }
  }
  if (finish != 'stop' &&
      finish != 'tool_calls' &&
      !(done && finish == null && calls.isEmpty)) {
    throw const FormatException('AI 流式回复未完整结束，请重试');
  }
  return jsonEncode({
    'choices': [
      {
        'message': {
          'content': text.toString(),
          'tool_calls': [
            for (final index in calls.keys.toList()..sort())
              {
                'function': {
                  'name': calls[index]!.name.toString(),
                  'arguments': calls[index]!.arguments.toString(),
                },
              },
          ],
        },
      },
    ],
  });
}
