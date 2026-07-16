import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../account/repositories/auth_token_store.dart';
import '../../collaboration/collaboration_config.dart';
import '../../ink_recognition/native_http_client.dart';
import '../../view_models/whiteboard_view_model.dart';
import '../models/ai_agent_models.dart';

class AiAgentRepository {
  AiAgentRepository({
    required CollaborationConfig config,
    AuthTokenStore? tokenStore,
  }) : _serverUri = Uri.parse(config.serverUrl),
       _tokenStore = tokenStore ?? AuthTokenStore();

  final Uri _serverUri;
  final AuthTokenStore _tokenStore;

  Future<AiAgentResponse> run({
    required String instruction,
    required String noteTitle,
    required List<AiNoteText> texts,
  }) async {
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) {
      throw StateError('请先登录后使用 AI 笔记助手');
    }
    final response = await NativeHttpClient.post(
      url: _serverUri
          .replace(path: _joinPath(_serverUri.path, '/api/ai/agent'))
          .toString(),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'instruction': instruction.trim(),
        'noteTitle': noteTitle.trim(),
        'texts': [for (final text in texts) text.toJson()],
      }),
      connectTimeoutMs: 8000,
      readTimeoutMs: 130000,
    );
    if (response.statusCode == 401) {
      throw StateError('登录状态已失效，请重新登录');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('AI 服务暂时不可用（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('AI 响应格式无效');
    return AiAgentResponse.fromJson(Map<String, Object?>.from(decoded));
  }

  String _joinPath(String basePath, String suffix) {
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$normalizedBase$suffix';
  }
}

final aiAgentRepositoryProvider = Provider<AiAgentRepository>((ref) {
  return AiAgentRepository(config: ref.watch(collaborationConfigProvider));
});
