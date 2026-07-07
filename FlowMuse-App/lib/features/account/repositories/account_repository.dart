import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../whiteboard/collaboration/collaboration_config.dart';
import '../models/account_user.dart';
import '../models/auth_session.dart';
import 'auth_token_store.dart';

class AccountRepository {
  AccountRepository({
    required CollaborationConfig config,
    AuthTokenStore? tokenStore,
    http.Client? client,
  }) : _serverUri = Uri.parse(config.serverUrl),
       _tokenStore = tokenStore ?? AuthTokenStore(),
       _client = client ?? http.Client();

  final Uri _serverUri;
  final AuthTokenStore _tokenStore;
  final http.Client _client;
  static const Duration _requestTimeout = Duration(seconds: 15);

  Future<String?> readToken() {
    return _tokenStore.readToken();
  }

  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final session = await _postSession('/api/auth/register', {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
    await _tokenStore.writeToken(session.token);
    return session;
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final session = await _postSession('/api/auth/login', {
      'email': email,
      'password': password,
    });
    await _tokenStore.writeToken(session.token);
    return session;
  }

  Future<AccountUser?> loadCurrentUser() async {
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    final response = await _client
        .get(_uri('/api/auth/me'), headers: _headers(token: token))
        .timeout(_requestTimeout);
    if (response.statusCode == 401) {
      await _tokenStore.clear();
      return null;
    }
    _ensureSuccess(response, '加载账号失败');
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return AccountUser.fromJson(json['user']! as Map<String, Object?>);
  }

  Future<void> logout() async {
    final token = await _tokenStore.readToken();
    if (token != null && token.isNotEmpty) {
      await _client
          .post(_uri('/api/auth/logout'), headers: _headers(token: token))
          .timeout(_requestTimeout);
    }
    await _tokenStore.clear();
  }

  Future<AuthSession> _postSession(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client
        .post(_uri(path), headers: _headers(), body: jsonEncode(body))
        .timeout(_requestTimeout);
    _ensureSuccess(response, '账号请求失败');
    return AuthSession.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  Map<String, String> _headers({String? token}) {
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
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

  void _ensureSuccess(http.Response response, String fallback) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final body = utf8.decode(response.bodyBytes).trim();
    throw StateError(
      body.isEmpty ? '$fallback：HTTP ${response.statusCode}' : body,
    );
  }
}
