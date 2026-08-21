import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_agent_models.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_agent_config_store.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_agent_repository.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePost {
  _FakePost(this.statusCode);
  final int statusCode;
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
            'message': {'role': 'assistant', 'content': '好的'},
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
    final attachment = AiVisualAttachment.validated(
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      sourceLabel: '当前选区',
      width: 10,
      height: 10,
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
      base64Encode([1, 2, 3, 4]),
    );
  });

  test('附件超过数量上限被客户端拒绝', () async {
    final post = _FakePost(200);
    final attachments = [
      for (var i = 0; i < maxAiVisualAttachments + 1; i++)
        AiVisualAttachment.validated(
          mimeType: 'image/png',
          bytes: Uint8List.fromList([1]),
          sourceLabel: '选区$i',
          width: 10,
          height: 10,
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
    final attachment = AiVisualAttachment.validated(
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1]),
      sourceLabel: '当前选区',
      width: 10,
      height: 10,
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
