import 'dart:convert';
import 'dart:typed_data';

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
  static const Duration _requestTimeout = Duration(seconds: 20);

  Future<String?> readToken() {
    return _tokenStore.readToken();
  }

  Future<AccountUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _post('/api/auth/register', {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return AccountUser.fromJson(json['user']! as Map<String, Object?>);
  }

  Future<AuthSession> verifyEmail(String token) async {
    final session = await _postSession('/api/auth/verify-email', {
      'token': token,
    });
    await _tokenStore.writeToken(session.token);
    return session;
  }

  Future<void> resendVerification(String email) async {
    await _post('/api/auth/resend-verification', {'email': email});
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
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _tokenStore.clear();
      return null;
    }
    _ensureSuccess(response, '加载账号失败');
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return AccountUser.fromJson(json['user']! as Map<String, Object?>);
  }

  Future<AccountUser> updateProfile({required String displayName}) async {
    final token = await _requireToken();
    final response = await _client
        .patch(
          _uri('/api/auth/me'),
          headers: _headers(token: token),
          body: jsonEncode({'displayName': displayName}),
        )
        .timeout(_requestTimeout);
    _ensureSuccess(response, '更新资料失败');
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return AccountUser.fromJson(json['user']! as Map<String, Object?>);
  }

  Future<AccountUser> uploadAvatar({
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final token = await _requireToken();
    final response = await _client
        .post(
          _uri('/api/auth/me/avatar'),
          headers: {
            'Content-Type': mimeType,
            'Content-Length': '${bytes.length}',
            'Authorization': 'Bearer $token',
          },
          body: bytes,
        )
        .timeout(_requestTimeout);
    _ensureSuccess(response, '上传头像失败');
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return AccountUser.fromJson(json['user']! as Map<String, Object?>);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final token = await _requireToken();
    final response = await _client
        .post(
          _uri('/api/auth/change-password'),
          headers: _headers(token: token),
          body: jsonEncode({
            'oldPassword': oldPassword,
            'newPassword': newPassword,
          }),
        )
        .timeout(_requestTimeout);
    _ensureSuccess(response, '修改密码失败');
    await _tokenStore.clear();
  }

  Future<void> requestPasswordReset(String email) async {
    await _post('/api/auth/request-password-reset', {'email': email});
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final response = await _client
        .post(
          _uri('/api/auth/reset-password'),
          headers: _headers(),
          body: jsonEncode({'token': token, 'newPassword': newPassword}),
        )
        .timeout(_requestTimeout);
    _ensureSuccess(response, '重置密码失败');
    await _tokenStore.clear();
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

  String resolveAvatarUrl(String avatarUrl) {
    if (avatarUrl.isEmpty || avatarUrl.startsWith('http')) {
      return avatarUrl;
    }
    return _uri(avatarUrl).toString();
  }

  Future<AuthSession> _postSession(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _post(path, body);
    return AuthSession.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) async {
    final response = await _client
        .post(_uri(path), headers: _headers(), body: jsonEncode(body))
        .timeout(_requestTimeout);
    _ensureSuccess(response, '账号请求失败');
    return response;
  }

  Future<String> _requireToken() async {
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) {
      throw StateError('未登录');
    }
    return token;
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
