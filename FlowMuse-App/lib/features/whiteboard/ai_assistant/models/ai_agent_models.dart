import 'dart:convert';

import 'package:flutter/foundation.dart';

const int maxAiAgentActions = 5;
const int maxAiAgentTitleLength = 100;
const int maxAiAgentTextLength = 5000;
const int maxAiAgentContextLength = 30000;
const int maxAiAgentInstructionLength = 1000;
const int maxAiAgentConversationTurns = 6;
const int maxAiAgentConversationLength = 12000;
const int maxAiMindmapNodes = 50;
const int maxAiMindmapDepth = 4;
const int maxAiMindmapNodeTextLength = 100;
const int maxAiMindmapJsonLength = 12000;

enum AiAgentTool { renameNote, insertText, generateMindmap, smartLayout }

@immutable
class AiAgentConversationTurn {
  const AiAgentConversationTurn({
    required this.instruction,
    required this.response,
  });

  final String instruction;
  final AiAgentResponse response;

  Map<String, Object?> toJson() => {
    'instruction': instruction,
    'response': response.toJson(),
  };
}

List<AiAgentConversationTurn> compactAiAgentConversation(
  Iterable<AiAgentConversationTurn> source,
) {
  final turns = source.toList(growable: false);
  final retained = <AiAgentConversationTurn>[];
  var totalLength = 0;
  for (
    var index = turns.length - 1;
    index >= 0 && retained.length < maxAiAgentConversationTurns;
    index--
  ) {
    final turn = turns[index];
    final instruction = turn.instruction.trim();
    if (instruction.isEmpty ||
        instruction.runes.length > maxAiAgentInstructionLength) {
      throw const FormatException('AI 会话指令长度无效');
    }
    final normalized = AiAgentConversationTurn(
      instruction: instruction,
      response: AiAgentResponse.fromJson(turn.response.toJson()),
    );
    final length = jsonEncode(normalized.toJson()).runes.length;
    if (totalLength + length > maxAiAgentConversationLength) break;
    retained.add(normalized);
    totalLength += length;
  }
  return List.unmodifiable(retained.reversed);
}

@immutable
class AiNoteText {
  const AiNoteText({
    required this.id,
    required this.text,
    this.pageIndex,
    this.x,
    this.y,
  });

  final String id;
  final String text;
  final int? pageIndex;
  final double? x;
  final double? y;

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    if (pageIndex != null) 'pageIndex': pageIndex,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
  };
}

@immutable
class AiNoteContext {
  const AiNoteContext({required this.texts, required this.truncated});

  final List<AiNoteText> texts;
  final bool truncated;

  factory AiNoteContext.fromTexts(Iterable<AiNoteText> source) {
    final texts = <AiNoteText>[];
    var totalLength = 0;
    var truncated = false;

    for (final item in source) {
      final runes = item.text.trim().runes.toList();
      if (runes.isEmpty) continue;
      var offset = 0;
      while (offset < runes.length && totalLength < maxAiAgentContextLength) {
        final length = [
          maxAiAgentTextLength,
          maxAiAgentContextLength - totalLength,
          runes.length - offset,
        ].reduce((left, right) => left < right ? left : right);
        texts.add(
          AiNoteText(
            id: offset == 0 && length == runes.length
                ? item.id
                : '${item.id}:${offset ~/ maxAiAgentTextLength}',
            text: String.fromCharCodes(runes.sublist(offset, offset + length)),
            pageIndex: item.pageIndex,
            x: item.x,
            y: item.y,
          ),
        );
        offset += length;
        totalLength += length;
      }
      if (offset < runes.length) {
        truncated = true;
        break;
      }
    }

    return AiNoteContext(texts: List.unmodifiable(texts), truncated: truncated);
  }
}

@immutable
class AiAgentAction {
  const AiAgentAction({required this.tool, required this.value});

  final AiAgentTool tool;
  final String value;

  String get label => switch (tool) {
    AiAgentTool.renameNote => '重命名笔记',
    AiAgentTool.insertText => '插入白板文字',
    AiAgentTool.generateMindmap => '生成思维导图',
    AiAgentTool.smartLayout => '智能排版手写内容',
  };

  factory AiAgentAction.edited({
    required AiAgentTool tool,
    required String value,
  }) {
    final argumentKey = switch (tool) {
      AiAgentTool.renameNote => 'title',
      AiAgentTool.insertText => 'text',
      AiAgentTool.generateMindmap => 'root',
      AiAgentTool.smartLayout => '',
    };
    return AiAgentAction.fromJson({
      'tool': switch (tool) {
        AiAgentTool.renameNote => 'rename_note',
        AiAgentTool.insertText => 'insert_text',
        AiAgentTool.generateMindmap => 'generate_mindmap',
        AiAgentTool.smartLayout => 'smart_layout',
      },
      'arguments': tool == AiAgentTool.smartLayout
          ? <String, Object?>{}
          : {
              argumentKey: tool == AiAgentTool.generateMindmap
                  ? _decodeMindmap(value)
                  : value,
            },
    });
  }

  Map<String, Object?> toJson() => {
    'tool': switch (tool) {
      AiAgentTool.renameNote => 'rename_note',
      AiAgentTool.insertText => 'insert_text',
      AiAgentTool.generateMindmap => 'generate_mindmap',
      AiAgentTool.smartLayout => 'smart_layout',
    },
    'arguments': switch (tool) {
      AiAgentTool.renameNote => {'title': value},
      AiAgentTool.insertText => {'text': value},
      AiAgentTool.generateMindmap => {'root': _decodeMindmap(value)},
      AiAgentTool.smartLayout => <String, Object?>{},
    },
  };

  Map<String, Object?> get mindmapRoot {
    if (tool != AiAgentTool.generateMindmap) {
      throw StateError('当前操作不是思维导图');
    }
    final decoded = _decodeMindmap(value);
    if (decoded is! Map) throw const FormatException('思维导图根节点无效');
    return Map<String, Object?>.from(decoded);
  }

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
        value: _markdownToPlainText(
          _requiredText(args, key: 'text', maxLength: maxAiAgentTextLength),
        ),
      ),
      'generate_mindmap' => AiAgentAction(
        tool: AiAgentTool.generateMindmap,
        value: _requiredMindmap(args),
      ),
      'smart_layout' when args.isEmpty => const AiAgentAction(
        tool: AiAgentTool.smartLayout,
        value: '',
      ),
      'smart_layout' => throw const FormatException('智能排版参数无效'),
      _ => throw FormatException('不支持的 AI 操作：$tool'),
    };
  }

  static Object? _decodeMindmap(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      throw const FormatException('思维导图 JSON 格式无效');
    }
  }

  static String _requiredMindmap(Map<String, Object?> arguments) {
    if (arguments.length != 1 || !arguments.containsKey('root')) {
      throw const FormatException('思维导图参数无效');
    }
    var nodeCount = 0;

    Map<String, Object?> validateNode(Object? value, int depth) {
      if (value is! Map || value.keys.any((key) => key is! String)) {
        throw const FormatException('思维导图节点格式无效');
      }
      final node = Map<String, Object?>.from(value);
      if (!node.containsKey('text') ||
          node.keys.any((key) => key != 'text' && key != 'children')) {
        throw const FormatException('思维导图节点字段无效');
      }
      if (depth > maxAiMindmapDepth) {
        throw const FormatException('思维导图层级过深');
      }
      final text = node['text'];
      final children = node.containsKey('children')
          ? node['children']
          : const <Object?>[];
      if (text is! String ||
          text.trim().isEmpty ||
          text.trim().runes.length > maxAiMindmapNodeTextLength ||
          children is! List) {
        throw const FormatException('思维导图节点内容无效');
      }
      nodeCount++;
      if (nodeCount > maxAiMindmapNodes) {
        throw const FormatException('思维导图节点过多');
      }
      return {
        'text': text.trim(),
        'children': [
          for (final child in children) validateNode(child, depth + 1),
        ],
      };
    }

    final root = validateNode(arguments['root'], 1);
    return const JsonEncoder.withIndent('  ').convert(root);
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

String _markdownToPlainText(String source) {
  var text = source
      .replaceAll(RegExp(r'^\s*```[^\n]*$', multiLine: true), '')
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '')
      .replaceAllMapped(
        RegExp(r'^(\s*)[-*+]\s+', multiLine: true),
        (match) => '${match[1]}• ',
      )
      .replaceAllMapped(
        RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
        (match) => match[1] ?? '',
      )
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]*\)'),
        (match) => match[1] ?? '',
      );
  for (final marker in ['**', '__', '~~', '`']) {
    text = text.replaceAll(marker, '');
  }
  final result = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (result.isEmpty) throw const FormatException('AI 插入内容为空');
  return result;
}

@immutable
class AiAgentResponse {
  const AiAgentResponse({required this.message, required this.actions});

  final String message;
  final List<AiAgentAction> actions;

  Map<String, Object?> toJson() => {
    'message': message,
    'actions': [for (final action in actions) action.toJson()],
  };

  factory AiAgentResponse.fromOpenAiJson(Map<String, Object?> json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const FormatException('AI 未返回有效结果');
    }
    final choice = Map<String, Object?>.from(choices.first as Map);
    final rawMessage = choice['message'];
    if (rawMessage is! Map) throw const FormatException('AI 响应格式无效');
    final message = Map<String, Object?>.from(rawMessage);
    final toolCalls = message['tool_calls'];
    if (toolCalls != null && toolCalls is! List) {
      throw const FormatException('AI 工具调用格式无效');
    }
    final calls = toolCalls is List ? toolCalls : const <Object?>[];
    return AiAgentResponse.fromJson({
      'message': message['content'],
      'actions': [for (final call in calls) _actionFromToolCall(call)],
    });
  }

  factory AiAgentResponse.fromJson(Map<String, Object?> json) {
    final rawActions = json['actions'];
    if (rawActions is! List || rawActions.length > maxAiAgentActions) {
      throw const FormatException('AI 返回的操作数量无效');
    }
    final actions = rawActions.map(AiAgentAction.fromJson).toList();
    if (actions
            .where((action) => action.tool == AiAgentTool.renameNote)
            .length >
        1) {
      throw const FormatException('AI 返回了多个重命名操作');
    }
    final mindmapCount = actions
        .where((action) => action.tool == AiAgentTool.generateMindmap)
        .length;
    if (mindmapCount > 1) {
      throw const FormatException('AI 返回了多个思维导图操作');
    }
    if (mindmapCount == 1 &&
        actions.any((action) => action.tool == AiAgentTool.insertText)) {
      throw const FormatException('思维导图与插入文字不能同时执行');
    }
    final smartLayoutCount = actions
        .where((action) => action.tool == AiAgentTool.smartLayout)
        .length;
    if (smartLayoutCount > 1 ||
        (smartLayoutCount == 1 && actions.length != 1)) {
      throw const FormatException('智能排版必须单独执行');
    }
    final message = json['message'];
    final normalizedMessage = message is String ? message.trim() : '';
    if (normalizedMessage.runes.length > maxAiAgentTextLength) {
      throw const FormatException('AI 回复内容过长');
    }
    if (actions.isEmpty && normalizedMessage.isEmpty) {
      throw const FormatException('AI 未返回有效内容');
    }
    return AiAgentResponse(
      message: normalizedMessage.isNotEmpty ? normalizedMessage : '已生成可执行的笔记操作',
      actions: List.unmodifiable(actions),
    );
  }

  static Map<String, Object?> _actionFromToolCall(Object? value) {
    if (value is! Map) throw const FormatException('AI 工具调用格式无效');
    final call = Map<String, Object?>.from(value);
    final rawFunction = call['function'];
    if (rawFunction is! Map) throw const FormatException('AI 工具调用格式无效');
    final function = Map<String, Object?>.from(rawFunction);
    final name = function['name'];
    final rawArguments = function['arguments'];
    final arguments = switch (rawArguments) {
      String() => jsonDecode(rawArguments),
      Map() => rawArguments,
      _ => throw const FormatException('AI 工具参数格式无效'),
    };
    if (name is! String || arguments is! Map) {
      throw const FormatException('AI 工具调用缺少必要字段');
    }
    return {'tool': name, 'arguments': arguments};
  }
}
