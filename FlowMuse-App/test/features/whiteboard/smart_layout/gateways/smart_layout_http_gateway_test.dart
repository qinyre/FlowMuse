import 'dart:async';
import 'dart:io';

import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final serverUri = Uri.parse('http://127.0.0.1:48931');

  NativeHttpResponse ok([String body = '{"ok":true}']) =>
      const NativeHttpResponse(statusCode: 200, body: '{"ok":true}');

  test('resolveUri 拼接服务器地址与 API 路径', () {
    final gateway = SmartLayoutHttpGateway(serverUri: serverUri);
    expect(
      gateway.resolveUri('/api/ink/smart-layout/v3/analyze'),
      Uri.parse('http://127.0.0.1:48931/api/ink/smart-layout/v3/analyze'),
    );
    expect(gateway.serverUri, serverUri);
  });

  test('resolveUri 拒绝不以 / 开头的路径', () {
    final gateway = SmartLayoutHttpGateway(serverUri: serverUri);
    expect(() => gateway.resolveUri('api/x'), throwsArgumentError);
  });

  test('postJson 传递 url/头/体/超时/取消令牌并返回 2xx 体', () async {
    late String capturedUrl;
    late Map<String, String> capturedHeaders;
    late String capturedBody;
    late int capturedConnectTimeout;
    late int capturedReadTimeout;
    NativeHttpCancelToken? capturedCancelToken;
    final gateway = SmartLayoutHttpGateway(
      serverUri: serverUri,
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            capturedUrl = url;
            capturedHeaders = headers;
            capturedBody = body;
            capturedConnectTimeout = connectTimeoutMs;
            capturedReadTimeout = readTimeoutMs;
            capturedCancelToken = cancelToken;
            return ok();
          },
    );
    final token = NativeHttpCancelToken();
    final body = await gateway.postJson(
      path: '/api/ink/smart-layout/v3/analyze',
      body: '{"page":1}',
      bearerToken: 'tok-1',
      cancelToken: token,
      readTimeoutMs: 65000,
    );
    expect(body, '{"ok":true}');
    expect(
      capturedUrl,
      'http://127.0.0.1:48931/api/ink/smart-layout/v3/analyze',
    );
    expect(capturedHeaders['content-type'], 'application/json');
    expect(capturedHeaders['authorization'], 'Bearer tok-1');
    expect(capturedBody, '{"page":1}');
    expect(capturedConnectTimeout, 8000);
    expect(capturedReadTimeout, 65000);
    expect(capturedCancelToken, same(token));
  });

  test('无 token 时不带 authorization 头；空 token 同样省略', () async {
    final headerSets = <Map<String, String>>[];
    final gateway = SmartLayoutHttpGateway(
      serverUri: serverUri,
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            headerSets.add(headers);
            return ok();
          },
    );
    await gateway.postJson(path: '/a', body: '{}');
    await gateway.postJson(path: '/a', body: '{}', bearerToken: '');
    expect(headerSets, hasLength(2));
    expect(headerSets.every((h) => !h.containsKey('authorization')), isTrue);
  });

  test('非 2xx 状态映射为 badStatus 异常并保留状态码与响应体', () async {
    final gateway = SmartLayoutHttpGateway(
      serverUri: serverUri,
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async =>
              const NativeHttpResponse(statusCode: 429, body: 'rate limited'),
    );
    await expectLater(
      gateway.postJson(path: '/a', body: '{}'),
      throwsA(
        isA<SmartLayoutHttpException>()
            .having((e) => e.kind, 'kind', SmartLayoutHttpErrorKind.badStatus)
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.detail, 'detail', 'rate limited'),
      ),
    );
  });

  test('网络异常（SocketException/TimeoutException 等）映射为 network 异常', () async {
    for (final error in [
      const SocketException('refused'),
      TimeoutException('read timeout', Duration(seconds: 1)),
      Exception('native channel returned null'),
    ]) {
      final gateway = SmartLayoutHttpGateway(
        serverUri: serverUri,
        post:
            ({
              required url,
              headers = const {},
              required body,
              connectTimeoutMs = 8000,
              readTimeoutMs = 15000,
              cancelToken,
            }) async {
              throw error;
            },
      );
      await expectLater(
        gateway.postJson(path: '/a', body: '{}'),
        throwsA(
          isA<SmartLayoutHttpException>()
              .having((e) => e.kind, 'kind', SmartLayoutHttpErrorKind.network)
              .having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
    }
  });

  test('传输层取消映射为 SmartLayoutHttpCancelledException', () async {
    final gateway = SmartLayoutHttpGateway(
      serverUri: serverUri,
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            throw const NativeHttpCancelledException();
          },
    );
    await expectLater(
      gateway.postJson(path: '/a', body: '{}'),
      throwsA(isA<SmartLayoutHttpCancelledException>()),
    );
  });

  test('默认读超时对齐 v2 智能排版 130s，可按请求覆盖', () async {
    late int defaultReadTimeout;
    final gateway = SmartLayoutHttpGateway(
      serverUri: serverUri,
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            defaultReadTimeout = readTimeoutMs;
            return ok();
          },
    );
    await gateway.postJson(path: '/a', body: '{}');
    expect(defaultReadTimeout, 130000);
  });
}
