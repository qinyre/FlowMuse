/// V3-700A：比赛演示 smoke 测试——四场景全绿 + 证据一致性。
///
/// 真实链组成（与 V3-505C real_wiring 同口径）：
/// - 真实 [MarkdrawController]（canvas 页框 + typed 文本）；
/// - 本地 loopback analyzer（测试内自建，healthy=冻结 v3 响应 fixture，
///   failing=500）——"演示环境的 v3 analyzer"客户端侧；服务端真实
///   analyzer 的启动 smoke 在 FlowMuse-Server smart_layout_v3_demo_smoke
///   _test.go；
/// - 真实 [SmartLayoutRealSessionScope]（无 fake provider）→ 候选 →
///   compare-and-commit → undo 精确回滚 → serialize/reopen 深度一致。
///
/// 证据生成：FLOWMUSE_GENERATE_V3_700A_EVIDENCE=1 一次性写入
/// docs/研发记录/evidence/smart-layout-v3/competition/
/// v3-700a-demo-smoke.json；常规 flutter test 只读校验不重写。
library;

import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rollout/smart_layout_demo_smoke.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rollout/smart_layout_rollout_entry_gate.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';

const pageId = 'page-1';
const pageCustomData = {
  'flowMuse': {'role': 'page', 'pageId': pageId},
};
const onPageCustomData = {
  'flowMuse': {'pageId': pageId},
};

String bodyForRegions(List<Object?> jsonRegions) => jsonEncode({
  'protocolVersion': 3,
  'requestId': 'req-demo-1',
  'regions': jsonRegions,
  'warnings': <String>[],
});

/// 冻结响应：单一 body region 全额认领 text-1（与 real_wiring 同款）。
final healthyAnalyzerBody = bodyForRegions([
  {
    'id': 'g1',
    'role': 'body',
    'sourceIds': ['text-1'],
    'readingOrder': 0,
    'confidence': 0.9,
    'relations': <String>[],
  },
]);

RectangleElement canvasPage() => RectangleElement(
  id: const ElementId('page-frame'),
  x: 0,
  y: 0,
  width: 1200,
  height: 800,
  seed: 7,
  versionNonce: 11,
  updated: 1000,
  customData: pageCustomData,
);

TextElement pageText() => TextElement(
  id: const ElementId('text-1'),
  x: 200,
  y: 300,
  width: 320,
  height: 40,
  text: '正文内容文本',
  fontSize: 20,
  fontFamily: 'Excalifont',
  seed: 7,
  versionNonce: 11,
  updated: 1000,
  customData: onPageCustomData,
);

MarkdrawController controllerWithPageContent() {
  final controller = MarkdrawController();
  controller.applyResult(AddElementResult(canvasPage()));
  controller.applyResult(AddElementResult(pageText()));
  return controller;
}

/// 演示会话句柄：真实容器 + 真实 scope + 真实控制器；close 语义 =
/// 零残留（容器→scope→控制器，幂等）。
class DemoSessionHandle implements SmartLayoutV3SessionHandle {
  DemoSessionHandle._(this._container, this._scope, this._controller);

  static DemoSessionHandle build(Uri serverUri) {
    final controller = controllerWithPageContent();
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: serverUri,
      pageId: pageId,
    );
    final container = ProviderContainer(
      overrides: [
        smartLayoutSessionDependenciesProvider.overrideWithValue(
          scope.dependencies,
        ),
      ],
    );
    return DemoSessionHandle._(container, scope, controller);
  }

  final ProviderContainer _container;
  final SmartLayoutRealSessionScope _scope;
  final MarkdrawController _controller;
  bool _closed = false;

  dynamic get vm =>
      _container.read(smartLayoutSessionViewModelProvider.notifier);
  MarkdrawController get controller => _controller;

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _container.dispose();
    _scope.dispose();
    _controller.dispose();
  }
}

/// loopback analyzer（测试内自建；[handler] 决定健康/故障行为）。
Future<(io.HttpServer, List<String> Function())> startAnalyzer(
  Future<(int, String)> Function(io.HttpRequest request) handler,
) async {
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  final received = <String>[];
  final sub = server.listen((request) async {
    final builder = BytesBuilder();
    await for (final chunk in request) {
      builder.add(chunk as List<int>);
    }
    received.add(utf8.decode(builder.takeBytes()));
    final (status, body) = await handler(request);
    request.response.statusCode = status;
    if (status == 200) {
      request.response.headers.contentType = io.ContentType.json;
      request.response.write(body);
    }
    await request.response.close();
  });
  addTearDown(() async {
    await sub.cancel();
    await server.close();
  });
  return (server, () => List<String>.unmodifiable(received));
}

/// 摘除 flutter_test 假 HttpOverrides（真实传输必需），完成后复原
/// （V3-203A/505C 同口径）。
Future<T> withRealHttp<T>(Future<T> Function() body) async {
  final previous = io.HttpOverrides.current;
  io.HttpOverrides.global = null;
  try {
    return await body();
  } finally {
    io.HttpOverrides.global = previous;
  }
}

/// 内容等价投影：剥离版本域三字段与 index（装载规范化，600A 口径）。
Map<String, Object?> projectContent(Map<String, dynamic> json) {
  const excluded = {'version', 'versionNonce', 'updated', 'index'};
  return {
    for (final entry in json.entries)
      if (!excluded.contains(entry.key)) entry.key: entry.value,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('四场景演示 smoke 全绿 + 证据一致性', () async {
    final (healthyServer, healthyReceived) = await startAnalyzer(
      (_) async => (200, healthyAnalyzerBody),
    );
    final (failingServer, failingReceived) = await startAnalyzer(
      (_) async => (500, ''),
    );
    final healthyUri = Uri.parse('http://127.0.0.1:${healthyServer.port}');
    final failingUri = Uri.parse('http://127.0.0.1:${failingServer.port}');

    Future<SmartLayoutDemoChainResult> healthyChain(
      SmartLayoutV3SessionHandle handle,
    ) {
      return withRealHttp(() async {
        final demo = handle as DemoSessionHandle;
        addTearDown(demo.close);
        final vm = demo.vm..addScopeSource('text-1');
        final controller = demo.controller;
        final beforeText = controller.currentScene.elements.firstWhere(
          (e) => e.id.value == 'text-1',
        );

        // 候选：真实链产出入审候选。
        await vm.startAnalysis();
        var state = _readState(demo);
        expect(state.phase, SmartLayoutSessionPhase.reviewing);
        expect(state.validatedCards, isNotEmpty);

        // commit：compare-and-commit 落地，typed 文本移入页内容区。
        await vm.applySelectedCandidate();
        state = _readState(demo);
        expect(state.phase, SmartLayoutSessionPhase.applied);
        final afterText = controller.currentScene.elements.firstWhere(
          (e) => e.id.value == 'text-1',
        );
        expect(afterText.version, greaterThan(beforeText.version));
        expect(afterText.x, greaterThanOrEqualTo(48));
        expect(afterText.y, greaterThanOrEqualTo(48));

        // undo：一次 undo 精确回提交前。
        controller.undo();
        expect(
          controller.currentScene.elements
              .firstWhere((e) => e.id.value == 'text-1')
              .x,
          beforeText.x,
        );

        // reopen：重做后序列化→新控制器重开，内容深度一致。
        controller.redo();
        final committedScene = controller.currentScene;
        final content = controller.serializeScene(
          format: DocumentFormat.excalidraw,
        );
        final reopened = MarkdrawController();
        reopened.loadFromContent(content, 'demo-reopen.excalidraw');
        final reopenedScene = reopened.currentScene;
        final committedIds = [
          for (final e in committedScene.activeElements) e.id.value,
        ]..sort();
        final reopenedIds = [
          for (final e in reopenedScene.activeElements) e.id.value,
        ]..sort();
        // 重开超集：装载期页面工件（页框 customData 生成的 page-1）为
        // 规范化新增，不破坏内容口径；提交元素必须全数存活。
        expect(reopenedIds.toSet(), containsAll(committedIds));
        final expected = {
          for (final e in committedScene.activeElements) e.id.value: e,
        };
        for (final element in reopenedScene.activeElements) {
          if (!expected.containsKey(element.id.value)) continue;
          expect(
            projectContent(ExcalidrawJsonCodec.elementToJson(element))
                .toString(),
            projectContent(
              ExcalidrawJsonCodec.elementToJson(
                expected[element.id.value]!,
              ),
            ).toString(),
            reason: '重开内容漂移：${element.id.value}',
          );
        }
        reopened.dispose();
        demo.close();

        final requests = healthyReceived().length;
        return SmartLayoutDemoChainResult(
          passed: requests > 0,
          detail:
              '真实链 reviewing→applied→undo 精确→reopen 深度一致；'
              'analyzer 请求 $requests 次',
          requestCount: requests,
        );
      });
    }

    Future<SmartLayoutDemoChainResult> failingChain(
      SmartLayoutV3SessionHandle handle,
    ) {
      return withRealHttp(() async {
        final demo = handle as DemoSessionHandle;
        addTearDown(demo.close);
        final vm = demo.vm..addScopeSource('text-1');
        final controller = demo.controller;
        final beforeFingerprint = SceneFingerprint.of(
          controller.currentScene,
        );

        // 服务故障：分析 fail closed，Scene 零副作用。
        await vm.startAnalysis();
        final state = _readState(demo);
        expect(state.phase, SmartLayoutSessionPhase.failed);
        expect(state.failure, isNotNull);
        expect(SceneFingerprint.of(controller.currentScene),
            beforeFingerprint, reason: '故障路径不得触碰 Scene');
        demo.close();

        final requests = failingReceived().length;
        return SmartLayoutDemoChainResult(
          passed: requests > 0,
          detail: 'analyzer 500 → failed（fail closed，Scene 零副作用）；'
              '请求 $requests 次',
          requestCount: requests,
        );
      });
    }

    final smoke = SmartLayoutDemoSmoke(
      healthyChain: healthyChain,
      failingChain: failingChain,
      sessionFactory: () => DemoSessionHandle.build(healthyUri),
      failingSessionFactory: () => DemoSessionHandle.build(failingUri),
      nowMs: 1800000000000,
    );
    final report = await smoke.run();

    // ---- 四场景全绿 ----
    expect(report.allPassed, isTrue);
    final byId = {
      for (final s in report.scenarios) s.id: s,
    };
    expect(byId.keys, {
      'default-off',
      'enabled-full-chain',
      'kill-switch',
      'service-failure',
    });
    expect(
      byId['default-off']!.factoryCalls,
      0,
      reason: '默认关闭=会话工厂零调用（零请求零 Draft 机制保证）',
    );
    expect(byId['enabled-full-chain']!.requestCount, greaterThan(0));
    expect(byId['kill-switch']!.factoryCalls, 0);
    expect(
      byId['service-failure']!.detail,
      contains('kill_tripped=true'),
    );

    // ---- synthetic observability 快照：告警闭环落账 ----
    final snapshot = report.observabilitySnapshot;
    expect(snapshot['schema_version'], 1);
    expect(snapshot['event_count'], greaterThan(0));
    expect(snapshot['alert_count'], greaterThanOrEqualTo(1));

    // ---- 证据生成（一次性）与只读一致性 ----
    final appDir = io.Directory.current.path;
    final target = io.File(
      '$appDir/../docs/研发记录/evidence/smart-layout-v3/competition/'
      'v3-700a-demo-smoke.json',
    );
    final generate =
        io.Platform.environment['FLOWMUSE_GENERATE_V3_700A_EVIDENCE'] == '1';
    if (generate) {
      target.createSync(recursive: true);
      target.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(report.toJson()),
        flush: true,
    );
    }
    if (target.existsSync()) {
      final persisted = jsonDecode(target.readAsStringSync());
      expect(persisted['all_passed'], isTrue);
      expect(persisted['scenarios'].length, 4);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}

dynamic _readState(DemoSessionHandle demo) =>
    demo._container.read(smartLayoutSessionViewModelProvider);
