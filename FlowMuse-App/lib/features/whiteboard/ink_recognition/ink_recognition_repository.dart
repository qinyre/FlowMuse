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
        developer.log(
          '手写识别请求失败: HTTP ${response.statusCode}',
          name: _logTag,
          level: 1000,
          time: startTime,
        );
        _throwForNonSuccessStatus(response.statusCode, response.body, '手写识别');
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

  /// 视觉优先智能排版：整页截图交由服务端 VLM 一次判定风格/内容/粗位置。
  Future<SmartLayoutVisionResponse> visionSmartLayout(
    SmartLayoutVisionRequest request,
  ) async {
    final bodyJson = jsonEncode(request.toJson());
    final url = _serverUri
        .replace(
          path: _joinPath(_serverUri.path, '/api/ink/smart-layout/vision'),
        )
        .toString();
    final token = await _readTokenForRequest();
    final NativeHttpResponse response;
    try {
      response = await NativeHttpClient.post(
        url: url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: bodyJson,
        connectTimeoutMs: _connectTimeoutMs,
        readTimeoutMs: _smartLayoutReadTimeoutMs,
      );
    } on Exception catch (error) {
      throwReadableNetworkError(error);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForNonSuccessStatus(response.statusCode, response.body, '视觉排版');
    }
    return SmartLayoutVisionResponse.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  /// 低置信裁剪重问：单块局部截图无上下文转写（上下文隔离降幻觉）。
  Future<SmartLayoutTranscribeResponse> transcribeCrop(
    SmartLayoutTranscribeRequest request,
  ) async {
    final bodyJson = jsonEncode(request.toJson());
    final url = _serverUri
        .replace(
          path: _joinPath(_serverUri.path, '/api/ink/smart-layout/transcribe'),
        )
        .toString();
    final token = await _readTokenForRequest();
    final NativeHttpResponse response;
    try {
      response = await NativeHttpClient.post(
        url: url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: bodyJson,
        connectTimeoutMs: _connectTimeoutMs,
        readTimeoutMs: _smartLayoutReadTimeoutMs,
      );
    } on Exception catch (error) {
      throwReadableNetworkError(error);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForNonSuccessStatus(response.statusCode, response.body, '单块转写');
    }
    return SmartLayoutTranscribeResponse.fromJson(
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

  /// 非 2xx 统一转用户可读中文：原始响应体不进异常消息（可能含英文/JSON 摘要，
  /// 也不排除回显内部信息）；日志只记录状态码与响应长度（脱敏，不落 body 内容）。
  Never _throwForNonSuccessStatus(int statusCode, String body, String scenario) {
    debugPrint(
      '[$_logTag] ❌ $scenario失败 | HTTP $statusCode | 响应长度: ${body.length}',
    );
    throw StateError(switch (statusCode) {
      401 || 403 => '识别服务鉴权失败，请检查服务配置',
      404 => '识别服务版本过旧，请联系管理员升级服务端',
      >= 500 && <= 599 => '识别服务异常（状态码 $statusCode），请稍后重试',
      _ => '识别服务请求失败（状态码 $statusCode）',
    });
  }

  /// 网络/通道异常统一转用户可读中文（服务未启动、断网、超时是演示现场最常见
  /// 的故障形态，英文堆栈对用户毫无意义）。按 runtimeType 匹配而非直接 import
  /// dart:io：SocketException/ClientException 在 Web 端不可用，共享代码不得引入；
  /// TimeoutException（dart:async）与 PlatformException（flutter/services）可直接
  /// 类型判断。无法识别的异常原样抛出（保留既有语义，由调用方兜底）。
  @visibleForTesting
  Never throwReadableNetworkError(Exception error) {
    final typeName = error.runtimeType.toString();
    final message = switch (typeName) {
      'SocketException' => '无法连接识别服务，请检查网络与服务地址',
      'TimeoutException' => '识别服务响应超时，请稍后重试',
      'ClientException' => '网络请求失败，请检查网络与服务地址',
      _ => error is PlatformException ? '网络通道异常（${error.code}），请检查网络与服务地址' : null,
    };
    // 日志脱敏：异常消息可能含 URL/系统错误详情，只记类型名。
    debugPrint('[$_logTag] ❌ 网络请求异常 | ${error.runtimeType}');
    if (message != null) {
      throw StateError(message);
    }
    throw error;
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
