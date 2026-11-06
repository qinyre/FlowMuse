import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_agent_models.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_agent_presets.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_agent_config_store.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_agent_repository.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1×1 基准 PNG（含魔数，可跨过发送前的结构化校验）。
final Uint8List basePng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
);

class _FakePost {
  _FakePost(this.statusCode, {this.insertedText});
  final int statusCode;
  final String? insertedText;
  String? url;
  Map<String, String>? headers;
  Object? body;

  Future<NativeHttpResponse> call({
    required String url,
    Map<String, String> headers = const {},
    required String body,
    int connectTimeoutMs = 8000,
    int readTimeoutMs = 15000,
    NativeHttpCancelToken? cancelToken,
  }) async {
    this.url = url;
    this.headers = headers;
    this.body = jsonDecode(body);
    return NativeHttpResponse(
      statusCode: statusCode,
      body: jsonEncode({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '好的',
              if (insertedText != null)
                'tool_calls': [
                  {
                    'type': 'function',
                    'function': {
                      'name': 'insert_text',
                      'arguments': jsonEncode({'text': insertedText}),
                    },
                  },
                ],
            },
          },
        ],
      }),
    );
  }
}

AiAgentRepository _repositoryWith(_FakePost post) => AiAgentRepository(
  config: const AiAgentConfig(
    baseUrl: 'https://api.example.com/v1',
    apiKey: 'test-key',
    model: 'test-model',
  ),
  post: post.call,
);

void main() {
  test('官方预设测试发送图片并按服务商添加兼容参数', () async {
    for (final provider in AiAgentProvider.values) {
      final post = _FakePost(200, insertedText: 'Blue');
      final repository = AiAgentRepository(
        config: AiAgentConfig(
          baseUrl: provider.baseUrl,
          apiKey: 'test-key',
          model: provider.models.first,
        ),
        post: post.call,
      );
      expect(await repository.testConnection(), isTrue);
      expect(post.url, '${provider.baseUrl}/chat/completions');
      final body = post.body as Map;
      expect(body['model'], provider.models.first);
      expect(body['messages'].last['content'].last['type'], 'image_url');
      if (provider == AiAgentProvider.openai) {
        expect(body['reasoning_effort'], 'none');
      }
      if (provider == AiAgentProvider.anthropic) {
        expect(body['max_tokens'], greaterThan(0));
      }
      if (provider == AiAgentProvider.anthropic ||
          provider == AiAgentProvider.gemini) {
        expect(body.containsKey('temperature'), isFalse);
      }
    }
  });

  test('连接返回普通文本时不误报支持工具调用', () async {
    final post = _FakePost(200);
    await expectLater(
      _repositoryWith(post).testConnection(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('未返回所需的工具调用'),
        ),
      ),
    );
    expect((post.body as Map)['messages'].last['content'], isA<String>());
  });

  test('纯文本请求保持字符串 content 且携带鉴权头', () async {
    final post = _FakePost(200);
    await _repositoryWith(post).run(
      instruction: '总结笔记',
      noteTitle: '标题',
      texts: const [AiNoteText(id: 't1', text: '内容')],
    );
    expect(post.url, 'https://api.example.com/v1/chat/completions');
    expect(post.headers!['Authorization'], 'Bearer test-key');
    final userMessage =
        (post.body as Map)['messages'].last as Map<String, Object?>;
    expect(userMessage['content'], isA<String>());
  });

  test('带附件时 user content 变为 text+image_url 数组', () async {
    final post = _FakePost(200);
    final attachment = AiVisualAttachment(
      sourceLabel: '当前选区',
      mimeType: 'image/png',
      bytes: basePng,
      kind: AiVisualAttachmentKind.selection,
    );
    await _repositoryWith(post).run(
      instruction: '解释这里',
      noteTitle: '标题',
      texts: const [],
      attachments: [attachment],
    );
    final userMessage =
        (post.body as Map)['messages'].last as Map<String, Object?>;
    final content = userMessage['content'] as List<Object?>;
    expect(content.first, isA<Map<dynamic, dynamic>>());
    expect((content.first as Map)['type'], 'text');
    expect(content, hasLength(2));
    final imagePart = content.last as Map<String, Object?>;
    expect(imagePart['type'], 'image_url');
    final imageUrl = (imagePart['image_url'] as Map)['url'] as String;
    expect(imageUrl.startsWith('data:image/png;base64,'), isTrue);
    expect(
      imageUrl.substring('data:image/png;base64,'.length),
      base64Encode(basePng),
    );
  });

  test('附件超过数量上限被客户端拒绝', () async {
    final post = _FakePost(200);
    final attachments = [
      for (var i = 0; i < maxAiVisualAttachments + 1; i++)
        AiVisualAttachment(
          sourceLabel: '选区$i',
          mimeType: 'image/png',
          bytes: basePng,
          kind: AiVisualAttachmentKind.selection,
        ),
    ];
    expect(
      () => _repositoryWith(post).run(
        instruction: '解释这里',
        noteTitle: '标题',
        texts: const [],
        attachments: attachments,
      ),
      throwsFormatException,
    );
  });

  test('带附件遇到 HTTP 400 提示模型可能不支持视觉输入', () async {
    final post = _FakePost(400);
    final attachment = AiVisualAttachment(
      sourceLabel: '当前选区',
      mimeType: 'image/png',
      bytes: basePng,
      kind: AiVisualAttachmentKind.selection,
    );
    await expectLater(
      _repositoryWith(post).run(
        instruction: '解释这里',
        noteTitle: '标题',
        texts: const [],
        attachments: [attachment],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('视觉'),
        ),
      ),
    );
  });
}
