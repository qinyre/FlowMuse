import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/analysis_retry_policy.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_request.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_operation_guard.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RectangleElement rect(String id, {double x = 10}) => RectangleElement(
    id: ElementId(id),
    x: x,
    y: 10,
    width: 40,
    height: 30,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
  );

  const validResponseBody = '''
{"protocolVersion":3,"requestId":"req-1","regions":[
 {"id":"g1","role":"title","sourceIds":["text-1"],"readingOrder":0,"confidence":0.9,"relations":[]}
],"warnings":[]}''';

  SmartLayoutV3Request buildRequest() => SmartLayoutV3Request.fromJson({
    'protocolVersion': 3,
    'pageId': 'page-1',
    'sceneRevision': {
      'epoch': 0,
      'revision': 1,
      'fingerprint': '0123456789abcdef',
    },
    'assets': [
      {'key': 'clean|page', 'kind': 'clean', 'fingerprint': '0123456789abcdef'},
    ],
    'marks': [],
    'exactTexts': [
      {'sourceId': 'text-1', 'text': '标题'},
    ],
    'sourceRefs': ['text-1'],
  });

  (V3AnalysisRepository, MarkdrawController, SmartLayoutSession) setUpRepo({
    SmartLayoutHttpPost? post,
    bool capabilityEnabled = true,
    int readTimeoutMs = 15000,
  }) {
    final controller = MarkdrawController();
    final editor = SmartLayoutEditorGateway(controller);
    final tracker = SceneRevisionTracker(editor: editor);
    final session = SmartLayoutSession(
      editor: editor,
      revisions: tracker,
      pageId: 'page-1',
    );
    final http = SmartLayoutHttpGateway(
      serverUri: Uri.parse('http://127.0.0.1:48931'),
      post: post,
    );
    final repo = V3AnalysisRepository(
      http: http,
      session: session,
      capabilityEnabled: capabilityEnabled,
      readTimeoutMs: readTimeoutMs,
    );
    return (repo, controller, session);
  }

  NativeHttpResponse ok([String body = validResponseBody]) =>
      NativeHttpResponse(statusCode: 200, body: body);

  test('capability off：请求数为 0，稳定失败', () async {
    final (repo, controller, session) = setUpRepo(capabilityEnabled: false);
    final ticket = _begin(session);
    final outcome = await repo.analyze(request: buildRequest(), ticket: ticket);
    expect(outcome, isA<SmartLayoutAnalysisFailed>());
    final failed = outcome as SmartLayoutAnalysisFailed;
    expect(failed.kind, AnalysisFailureKind.capabilityOff);
    expect(repo.requestCount, 0);
    controller.dispose();
  });

  test('成功：单次请求解析响应', () async {
    final (repo, controller, session) = setUpRepo(
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async => ok(),
    );
    final ticket = _begin(session);
    final outcome = await repo.analyze(request: buildRequest(), ticket: ticket);
    expect(outcome, isA<SmartLayoutAnalysisSucceeded>());
    final succeeded = outcome as SmartLayoutAnalysisSucceeded;
    expect(succeeded.response.regions.single.id, 'g1');
    expect(succeeded.attempts, 1);
    expect(repo.requestCount, 1);
    controller.dispose();
  });

  test('429：重试一次后成功（有限重试）', () async {
    var call = 0;
    final (repo, controller, session) = setUpRepo(
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            call++;
            if (call == 1) {
              return const NativeHttpResponse(statusCode: 429, body: 'rate');
            }
            return ok();
          },
    );
    final ticket = _begin(session);
    final outcome = await repo.analyze(request: buildRequest(), ticket: ticket);
    expect(outcome, isA<SmartLayoutAnalysisSucceeded>());
    expect((outcome as SmartLayoutAnalysisSucceeded).attempts, 2);
    controller.dispose();
  });

  test('超时与 5xx：重试耗尽后稳定失败，无状态污染', () async {
    for (final behavior in [
      () async => throw TimeoutException('read'),
      () async => const NativeHttpResponse(statusCode: 500, body: 'boom'),
      () async => throw const io.SocketException('offline'),
    ]) {
      final (repo, controller, session) = setUpRepo(
        post:
            ({
              required url,
              headers = const {},
              required body,
              connectTimeoutMs = 8000,
              readTimeoutMs = 15000,
              cancelToken,
            }) => behavior(),
      );
      final ticket = _begin(session);
      final outcome = await repo.analyze(
        request: buildRequest(),
        ticket: ticket,
      );
      expect(outcome, isA<SmartLayoutAnalysisFailed>(), reason: '$behavior');
      final failed = outcome as SmartLayoutAnalysisFailed;
      expect(failed.attempts, 2, reason: '有限重试一次');
      expect(
        failed.kind,
        anyOf(
          AnalysisFailureKind.timeout,
          AnalysisFailureKind.network,
          AnalysisFailureKind.badStatus,
        ),
      );
      expect(repo.requestCount, 2);
      // 状态零污染：session 仍在 analyzing，无终态写入。
      expect(session.state.phase.toString(), contains('analyzing'));
      controller.dispose();
    }
  });

  test('400/404 不重试；bad schema 立即失败且不重试', () async {
    var call = 0;
    final (repo, controller, session) = setUpRepo(
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            call++;
            return const NativeHttpResponse(
              statusCode: 400,
              body: '{"error":{"code":"invalid_request","message":"x"}}',
            );
          },
    );
    var outcome = await repo.analyze(
      request: buildRequest(),
      ticket: _begin(session),
    );
    expect((outcome as SmartLayoutAnalysisFailed).attempts, 1);
    expect(call, 1);
    controller.dispose();

    var call2 = 0;
    final (repo2, controller2, session2) = setUpRepo(
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            call2++;
            return ok(
              '{"protocolVersion":3,"regions":[{"evil":1}],"warnings":[]}',
            );
          },
    );

    outcome = await repo2.analyze(
      request: buildRequest(),
      ticket: _begin(session2),
    );
    expect(outcome, isA<SmartLayoutAnalysisFailed>());
    expect(
      (outcome as SmartLayoutAnalysisFailed).kind,
      AnalysisFailureKind.badSchema,
    );
    expect(call2, 1, reason: 'schema 违例不重试');
    controller2.dispose();
  });

  test('迟到响应：请求期间远端内容变化 → 四检拒绝，零状态污染', () async {
    MarkdrawController? lateController;
    final (repo, controller, session) = setUpRepo(
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            // 响应落地前，远端元素到达 → revision 变化。
            lateController!.applyRemoteElements([rect('remote-late', x: 700)]);
            return ok();
          },
    );
    lateController = controller;
    final ticket = _begin(session);
    final outcome = await repo.analyze(request: buildRequest(), ticket: ticket);
    expect(outcome, isA<SmartLayoutAnalysisGuardRejected>());
    expect(
      (outcome as SmartLayoutAnalysisGuardRejected).reason,
      contains('revision-changed'),
    );
    // session 未被迟到响应推进（仍在 analyzing）。
    expect(session.state.phase.toString(), contains('analyzing'));
    controller.dispose();
  });

  test('协作取消：发送前 session.cancelOperation → 守卫拒绝且请求数 0', () async {
    final (repo, controller, session) = setUpRepo(
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async => ok(),
    );
    final ticket = _begin(session);
    session.cancelOperation();
    final outcome = await repo.analyze(request: buildRequest(), ticket: ticket);
    expect(outcome, isA<SmartLayoutAnalysisGuardRejected>());
    expect(
      (outcome as SmartLayoutAnalysisGuardRejected).reason,
      contains('cancelled'),
    );
    expect(repo.requestCount, 0);
    controller.dispose();
  });

  test('守卫前置失败（离页）：发请求前拒绝，请求数 0', () async {
    final (repo, controller, session) = setUpRepo(
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async => ok(),
    );
    final ticket = _begin(session);
    session.setActivePage('page-2');
    final outcome = await repo.analyze(request: buildRequest(), ticket: ticket);
    expect(outcome, isA<SmartLayoutAnalysisGuardRejected>());
    expect(
      (outcome as SmartLayoutAnalysisGuardRejected).reason,
      contains('page-changed'),
    );
    expect(repo.requestCount, 0);
    controller.dispose();
  });

  group('真实 synthetic server 联调（loopback HTTP）', () {
    test('全链：真实 socket 请求/响应，双方请求字节 hash 一致', () async {
      final server = await io.HttpServer.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      var receivedHash = '';
      var receivedPath = '';
      var receivedBody = '';
      late final StreamSubscription sub;
      sub = server.listen((request) async {
        receivedPath = request.uri.path;
        final builder = BytesBuilder();
        await for (final chunk in request) {
          builder.add(chunk as List<int>);
        }
        final bytes = builder;
        receivedBody = utf8.decode(bytes.takeBytes());
        final digest = _fnvHash(utf8.encode(receivedBody));
        receivedHash = digest;
        request.response.statusCode = 200;
        request.response.headers.contentType = io.ContentType.json;
        request.response.write(validResponseBody);
        await request.response.close();
      });
      addTearDown(() async {
        await sub.cancel();
        await server.close();
      });

      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      final editor = SmartLayoutEditorGateway(controller);
      final tracker = SceneRevisionTracker(editor: editor);
      addTearDown(tracker.dispose);
      final session = SmartLayoutSession(
        editor: editor,
        revisions: tracker,
        pageId: 'page-1',
      );
      // post=null：使用真实 NativeHttpClient（Windows 测试回退 package:http）。
      // flutter_test 注入的假 HttpClient 会拦截真实网络——临时摘除并复原。
      final previousOverrides = io.HttpOverrides.current;
      io.HttpOverrides.global = null;
      final http = SmartLayoutHttpGateway(
        serverUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final repo = V3AnalysisRepository(http: http, session: session);
      final request = buildRequest();
      final ticket = _begin(session);
      SmartLayoutAnalysisOutcome outcome;
      try {
        outcome = await repo.analyze(request: request, ticket: ticket);
      } finally {
        io.HttpOverrides.global = previousOverrides;
      }

      expect(receivedPath, '/api/ink/smart-layout/analyze/v3');
      expect(
        outcome,
        isA<SmartLayoutAnalysisSucceeded>(),
        reason: (outcome is SmartLayoutAnalysisFailed) ? outcome.detail : '',
      );
      // 双方 hash 一致：服务端收到的请求字节 == 客户端序列化字节。
      final clientBody = jsonEncode(request.toJson());
      expect(receivedBody, clientBody);
      expect(receivedHash, _fnvHash(utf8.encode(clientBody)));
    });
  });
}

SmartLayoutOperationTicket _begin(SmartLayoutSession session) =>
    session.beginOperation();

String _fnvHash(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h.toRadixString(16);
}

