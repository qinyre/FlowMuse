import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/repositories/auth_token_store.dart';
import '../collaboration/collaboration_config.dart';
import '../editor_core/flow_muse_whiteboard_editor.dart';
import '../view_models/whiteboard_view_model.dart';
import 'native_http_client.dart';

const String _logTag = 'InkRecognition';

class InkRecognitionRepository {
  InkRecognitionRepository({
    required CollaborationConfig config,
    AuthTokenStore? tokenStore,
  }) : _serverUri = Uri.parse(config.serverUrl),
       _tokenStore = tokenStore ?? AuthTokenStore();

  final Uri _serverUri;
  final AuthTokenStore _tokenStore;
  static const int _connectTimeoutMs = 8000;
  static const int _readTimeoutMs = 15000;
  static const int _smartLayoutReadTimeoutMs = 130000;

  Future<InkRecognitionResult> recognize(InkRecognitionRequest request) async {
    final totalPoints = request.strokes.fold<int>(
      0,
      (sum, s) => sum + s.points.length,
    );
    final bodyJson = jsonEncode(request.toJson());
    final bodyBytes = utf8.encode(bodyJson).length;
    final startTime = DateTime.now();

    final url = _serverUri
        .replace(path: _joinPath(_serverUri.path, '/api/ink/recognize'))
        .toString();

    debugPrint(
      '[$_logTag] 📤 发送手写识别请求 | '
      'sessionId: ${request.sessionId} | '
      'hint: ${request.hint} | '
      '笔画数: ${request.strokes.length} | '
      '总点数: $totalPoints | '
      'body大小: ${_formatBytes(bodyBytes)} | '
      '服务器: ${_serverUri.host}:${_serverUri.port}',
    );
    developer.log('发送手写识别请求', name: _logTag, level: 0, time: startTime);

    debugPrint(
      '[$_logTag] 🔗 发起请求 | '
      '连接超时: ${_connectTimeoutMs}ms | 读取超时: ${_readTimeoutMs}ms',
    );

    String? token;
    try {
      token = await _tokenStore.readToken().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('[$_logTag] ⚠️ Token 读取超时，将在无认证下发送请求');
          return null;
        },
      );
    } catch (_) {
      debugPrint('[$_logTag] ⚠️ Token 读取失败，将在无认证下发送请求');
      token = null;
    }
    debugPrint(
      '[$_logTag] 🔑 Token 状态 | hasToken: ${token != null && token.isNotEmpty}',
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    try {
      final response = await NativeHttpClient.post(
        url: url,
        headers: headers,
        body: bodyJson,
        connectTimeoutMs: _connectTimeoutMs,
        readTimeoutMs: _readTimeoutMs,
      );

      final elapsed = DateTime.now().difference(startTime);
      debugPrint(
        '[$_logTag] 📨 收到响应 | HTTP ${response.statusCode} | '
        '耗时: ${elapsed.inMilliseconds}ms | 响应大小: ${_formatBytes(response.body.length)}',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final snippet = response.body.isEmpty
            ? '(空)'
            : response.body.substring(0, response.body.length.clamp(0, 200));
        debugPrint(
          '[$_logTag] ❌ 请求失败 | HTTP ${response.statusCode} | 响应: $snippet',
        );
        developer.log(
          '手写识别请求失败: HTTP ${response.statusCode}',
          name: _logTag,
          level: 1000,
          time: startTime,
        );
        throw StateError(
          response.body.isEmpty
              ? '字迹识别失败：HTTP ${response.statusCode}'
              : response.body,
        );
      }

      final result = InkRecognitionResult.fromJson(
        jsonDecode(response.body) as Map<String, Object?>,
      );
      final typeSummary = _summarizeTypes(result);
      debugPrint(
        '[$_logTag] ✅ 识别成功 | HTTP ${response.statusCode} | '
        '耗时: ${elapsed.inMilliseconds}ms | 识别元素数: ${result.elements.length} | 元素类型: $typeSummary',
      );
      developer.log(
        '手写识别成功: ${result.elements.length} 个元素 [$typeSummary]',
        name: _logTag,
        level: 0,
        time: startTime,
      );
      return result;
    } on StateError {
      rethrow;
    } on PlatformException catch (e) {
      final elapsed = DateTime.now().difference(startTime);
      debugPrint(
        '[$_logTag] ❌ 网络通道异常 | 耗时: ${elapsed.inMilliseconds}ms | code: ${e.code} | ${e.message}',
      );
      developer.log(
        '手写识别网络通道异常',
        name: _logTag,
        level: 1000,
        error: e,
        time: startTime,
      );
      rethrow;
    } catch (e, stack) {
      final elapsed = DateTime.now().difference(startTime);
      debugPrint(
        '[$_logTag] ❌ 请求异常 | 耗时: ${elapsed.inMilliseconds}ms | ${e.runtimeType}: $e',
      );
      developer.log(
        '手写识别请求异常',
        name: _logTag,
        level: 1000,
        error: e,
        stackTrace: stack,
        time: startTime,
      );
      rethrow;
    }
  }

  Future<SmartLayoutResponse> smartLayout(SmartLayoutRequest request) async {
    final bodyJson = jsonEncode(request.toJson());
    final url = _serverUri
        .replace(path: _joinPath(_serverUri.path, '/api/ink/smart-layout'))
        .toString();
    final token = await _readTokenForRequest();
    final response = await NativeHttpClient.post(
      url: url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: bodyJson,
      connectTimeoutMs: _connectTimeoutMs,
      readTimeoutMs: _smartLayoutReadTimeoutMs,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        response.body.isEmpty
            ? '智能排版失败：HTTP ${response.statusCode}'
            : response.body,
      );
    }
    return SmartLayoutResponse.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  Future<String?> _readTokenForRequest() async {
    try {
      return await _tokenStore.readToken().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  String _summarizeTypes(InkRecognitionResult result) {
    if (result.elements.isEmpty) return '(无)';
    final counts = <String, int>{};
    for (final el in result.elements) {
      counts[el.type] = (counts[el.type] ?? 0) + 1;
    }
    return counts.entries.map((e) => '${e.key}:${e.value}').join(', ');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
