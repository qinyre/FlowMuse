import 'package:flutter/foundation.dart';

const int maxAiAgentActions = 5;
const int maxAiAgentTitleLength = 100;
const int maxAiAgentTextLength = 5000;
const int maxAiAgentContextLength = 30000;

enum AiAgentTool { renameNote, insertText }

@immutable
class AiNoteText {
  const AiNoteText({required this.id, required this.text});

  final String id;
  final String text;

  Map<String, Object?> toJson() => {'id': id, 'text': text};
}

@immutable
class AiAgentAction {
  const AiAgentAction({required this.tool, required this.value});

  final AiAgentTool tool;
  final String value;

  String get label => switch (tool) {
    AiAgentTool.renameNote => '重命名笔记',
    AiAgentTool.insertText => '插入白板文字',
  };

  factory AiAgentAction.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('AI 操作格式无效');
    final json = Map<String, Object?>.from(value);
    final tool = json['tool'];
    final arguments = json['arguments'];
    if (tool is! String || arguments is! Map) {
      throw const FormatException('AI 操作缺少必要字段');
    }
    final args = Map<String, Object?>.from(arguments);
    return switch (tool) {
      'rename_note' => AiAgentAction(
        tool: AiAgentTool.renameNote,
        value: _requiredText(
          args,
          key: 'title',
          maxLength: maxAiAgentTitleLength,
        ),
      ),
      'insert_text' => AiAgentAction(
        tool: AiAgentTool.insertText,
        value: _requiredText(
          args,
          key: 'text',
          maxLength: maxAiAgentTextLength,
        ),
      ),
      _ => throw FormatException('不支持的 AI 操作：$tool'),
    };
  }

  static String _requiredText(
    Map<String, Object?> arguments, {
    required String key,
    required int maxLength,
  }) {
    if (arguments.length != 1 || arguments[key] is! String) {
      throw const FormatException('AI 操作参数无效');
    }
    final text = (arguments[key]! as String).trim();
    if (text.isEmpty || text.runes.length > maxLength) {
      throw const FormatException('AI 操作内容长度无效');
    }
    return text;
  }
}

@immutable
class AiAgentResponse {
  const AiAgentResponse({required this.message, required this.actions});

  final String message;
  final List<AiAgentAction> actions;

  factory AiAgentResponse.fromJson(Map<String, Object?> json) {
    final rawActions = json['actions'];
    if (rawActions is! List ||
        rawActions.isEmpty ||
        rawActions.length > maxAiAgentActions) {
      throw const FormatException('AI 返回的操作数量无效');
    }
    final actions = rawActions.map(AiAgentAction.fromJson).toList();
    if (actions
            .where((action) => action.tool == AiAgentTool.renameNote)
            .length >
        1) {
      throw const FormatException('AI 返回了多个重命名操作');
    }
    final message = json['message'];
    return AiAgentResponse(
      message: message is String && message.trim().isNotEmpty
          ? message.trim()
          : '已生成可执行的笔记操作',
      actions: List.unmodifiable(actions),
    );
  }
}
