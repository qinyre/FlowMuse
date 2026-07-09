import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../account/repositories/auth_token_store.dart';
import '../collaboration/collaboration_config.dart';
import '../editor_core/flow_muse_whiteboard_editor.dart';
import '../view_models/whiteboard_view_model.dart';

class InkRecognitionRepository {
  InkRecognitionRepository({
    required CollaborationConfig config,
    AuthTokenStore? tokenStore,
    http.Client? client,
  }) : _serverUri = Uri.parse(config.serverUrl),
       _tokenStore = tokenStore ?? AuthTokenStore(),
       _client = client ?? http.Client();

  final Uri _serverUri;
  final AuthTokenStore _tokenStore;
  final http.Client _client;
  static const Duration _requestTimeout = Duration(seconds: 25);

  Future<InkRecognitionResult> recognize(InkRecognitionRequest request) async {
    final token = await _tokenStore.readToken();
    final response = await _client
        .post(
          _uri('/api/ink/recognize'),
          headers: _headers(token: token),
          body: jsonEncode(request.toJson()),
        )
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = utf8.decode(response.bodyBytes).trim();
      throw StateError(
        body.isEmpty ? '字迹识别失败：HTTP ${response.statusCode}' : body,
      );
    }
    return InkRecognitionResult.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  Map<String, String> _headers({String? token}) {
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) {
    return _serverUri.replace(path: _joinPath(_serverUri.path, path));
  }

  String _joinPath(String basePath, String suffix) {
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$normalizedBase$suffix';
  }
}

final inkRecognitionRepositoryProvider = Provider<InkRecognitionRepository>((
  ref,
) {
  return InkRecognitionRepository(
    config: ref.watch(collaborationConfigProvider),
  );
});
