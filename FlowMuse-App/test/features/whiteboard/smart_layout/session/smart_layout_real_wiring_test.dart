import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_response.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';

/// V3-505C 真实链闭环：loopback 真实 HTTP 服务（真实 NativeHttpClient）
/// + 真实 Scene（canvas page + typed 文本）+ 真实装配
/// （SmartLayoutRealSessionScope，无 fake provider）→ 候选 →
/// compare-and-commit。以及无解/重试/取消/离页分支。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pageId = 'page-1';
  const pageCustomData = {
    'flowMuse': {'role': 'page', 'pageId': pageId},
  };
  const onPageCustomData = {
    'flowMuse': {'pageId': pageId},
  };

  String bodyForRegions(List<Object?> jsonRegions) => jsonEncode({
    'protocolVersion': 3,
    'requestId': 'req-1',
    'regions': jsonRegions,
    'warnings': <String>[],
  });

  final titleRegionBody = bodyForRegions([
    {
      'id': 'g1',
      'role': 'body',
      'sourceIds': ['text-1'],
      'readingOrder': 0,
      'confidence': 0.9,
      'relations': <String>[],
    },
  ]);
  final emptyRegionsBody = bodyForRegions([]);

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

  /// loopback 服务（真实 HTTP；[handler] 可延迟/改写响应以驱动分支）。
  Future<(io.HttpServer, List<String> Function())> startServer(
    Future<(int, String)> Function(io.HttpRequest request) handler,
  ) async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    final receivedBodies = <String>[];
    final sub = server.listen((request) async {
      final builder = BytesBuilder();
      await for (final chunk in request) {
        builder.add(chunk as List<int>);
      }
      receivedBodies.add(utf8.decode(builder.takeBytes()));
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
    return (server, () => List<String>.unmodifiable(receivedBodies));
  }

  /// 摘除 flutter_test 假 HttpOverrides（真实 NativeHttpClient 必需），
  /// body 完成后复原（V3-203A 同口径）。
  Future<T> withRealHttp<T>(Future<T> Function() body) async {
    final previous = io.HttpOverrides.current;
    io.HttpOverrides.global = null;
    try {
      return await body();
    } finally {
      io.HttpOverrides.global = previous;
    }
  }

  (ProviderContainer, SmartLayoutRealSessionScope, MarkdrawController)
  setUpScope(Uri serverUri) {
    final controller = controllerWithPageContent();
    addTearDown(controller.dispose);
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: serverUri,
      pageId: pageId,
    );
    addTearDown(scope.dispose);
    final container = ProviderContainer(
      overrides: [
        smartLayoutSessionDependenciesProvider.overrideWithValue(
          scope.dependencies,
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, scope, controller);
  }

  test('真实 server→候选→commit：全链自动化 + Scene/History 精确', () async {
    final (server, received) = await startServer(
      (_) async => (200, titleRegionBody),
    );
    final result = withRealHttp(() async {
      final (container, scope, controller) = setUpScope(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('text-1');
      final before = controller.currentScene;
      final beforeText = before.elements.firstWhere(
        (e) => e.id.value == 'text-1',
      );

      await vm.startAnalysis();
      final state = container.read(smartLayoutSessionViewModelProvider);
      expect(
        state.phase,
        SmartLayoutSessionPhase.reviewing,
        reason: '真实链应产出候选并进入 reviewing',
      );
      expect(state.validatedCards, isNotEmpty);
      expect(state.selectedValidatedCandidate, isNotNull);

      await vm.applySelectedCandidate();
      final applied = container.read(smartLayoutSessionViewModelProvider);
      expect(applied.phase, SmartLayoutSessionPhase.applied);

      // 请求体：真实快照装配（typed exactText + 全源 refs）。
      expect(received().length, 1);
      final sent = jsonDecode(received().single) as Map<String, Object?>;
      expect(sent['pageId'], pageId);
      expect(
        (sent['exactTexts'] as List).single,
        {'sourceId': 'text-1', 'text': '正文内容文本'},
      );
      final mark = (sent['marks'] as List).single as Map<String, Object?>;
      expect(mark['sourceId'], 'text-1');
      expect(mark['assetKey'], 'clean|page-1');
      expect(mark['label'], contains('kind=text'));
      expect(mark['label'], contains('bounds=200.0,300.0,320.0,40.0'));
      expect(
        (sent['sourceRefs'] as List).toSet(),
        {'page-frame', 'text-1'},
      );

      // Scene 真实变更：typed 文本被 V3-303A 变换移入页内容区
      //（inset 48 边距），版本前进。
      final afterText = controller.currentScene.elements.firstWhere(
        (e) => e.id.value == 'text-1',
      );
      expect(afterText.version, greaterThan(beforeText.version));
      expect(afterText.x, greaterThanOrEqualTo(48));
      expect(afterText.y, greaterThanOrEqualTo(48));
      expect(afterText.x + afterText.width, lessThanOrEqualTo(1200 - 48));
      expect(afterText.y + afterText.height, lessThanOrEqualTo(800 - 48));

      // History 精确：一次 undo 回提交前（compare-and-commit 单事务）。
      final historyCount = controller.historyManager.undoCount;
      expect(historyCount, greaterThan(0));
      controller.undo();
      expect(
        controller.currentScene.elements
            .firstWhere((e) => e.id.value == 'text-1')
            .x,
        beforeText.x,
        reason: '一次 undo 精确回滚到提交前',
      );
      return 0;
    });
    await result;
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('无解：锁定障碍吃满全部栏 → NoFeasibleLayout 空候选 + 重新分析', () async {
    final (server, received) = await startServer(
      (_) async => (200, titleRegionBody),
    );
    await withRealHttp(() async {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.applyResult(AddElementResult(canvasPage()));
      controller.applyResult(AddElementResult(pageText()));
      // 锁定障碍吃满页内容区（绕置无可用栏 → preflight 全拒）。
      controller.applyResult(
        AddElementResult(
          RectangleElement(
            id: const ElementId('lock-1'),
            x: 48,
            y: 48,
            width: 1104,
            height: 704,
            locked: true,
            seed: 7,
            versionNonce: 11,
            updated: 1000,
            customData: onPageCustomData,
          ),
        ),
      );
      final scope = SmartLayoutRealSessionScope.build(
        controller: controller,
        serverUri: Uri.parse('http://127.0.0.1:${server.port}'),
        pageId: pageId,
      );
      addTearDown(scope.dispose);
      final container = ProviderContainer(
        overrides: [
          smartLayoutSessionDependenciesProvider.overrideWithValue(
            scope.dependencies,
          ),
        ],
      );
      addTearDown(container.dispose);
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('text-1');

      await vm.startAnalysis();
      var state = container.read(smartLayoutSessionViewModelProvider);
      expect(state.phase, SmartLayoutSessionPhase.reviewing);
      expect(state.candidates, isEmpty, reason: '无解不伪装成功');
      expect(state.failure, isNull, reason: '无解不是错误');

      // 重新分析：移除障碍后同 scope 重走完整链并产出真候选。
      //（不能只解锁：解锁后成为未认领 movable 源，同样破坏账目守恒。）
      controller.applyResult(RemoveElementResult(const ElementId('lock-1')));
      vm.restartAnalysis();
      await Future<void>.delayed(Duration.zero);
      state = container.read(smartLayoutSessionViewModelProvider);
      while (state.phase == SmartLayoutSessionPhase.analyzing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        state = container.read(smartLayoutSessionViewModelProvider);
      }
      expect(state.phase, SmartLayoutSessionPhase.reviewing);
      expect(state.validatedCards, isNotEmpty, reason: '重分析产出真候选');
      // restart = reset+start（reset 归零尝试计数）：新会话从 1 计。
      expect(state.attemptCount, 1);
      expect(received().length, 2);
      return 0;
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('契约破坏：响应零认领（账目不守恒）→ fail closed 进 failed', () async {
    final (server, _) = await startServer((_) async => (200, emptyRegionsBody));
    await withRealHttp(() async {
      final (container, scope, controller) = setUpScope(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('text-1');

      await vm.startAnalysis();
      final state = container.read(smartLayoutSessionViewModelProvider);
      expect(state.phase, SmartLayoutSessionPhase.failed);
      expect(state.failure!.stage, 'generation');
      expect(state.failure!.reason, 'semantic-contract-broken');
      expect(state.failure!.retryable, isFalse);
      return 0;
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('取消：分析在途立即取消；迟到响应按票据判旧、零残留', () async {
    final gate = Completer<void>();
    final (server, _) = await startServer(
      (_) async {
        await gate.future;
        return (200, titleRegionBody);
      },
    );
    await withRealHttp(() async {
      final (container, scope, controller) = setUpScope(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('text-1');

      final analysis = vm.startAnalysis();
      // 同步取消：不等在途 future。
      vm.cancel();
      var state = container.read(smartLayoutSessionViewModelProvider);
      expect(state.phase, SmartLayoutSessionPhase.cancelled);
      expect(state.lastAnalysisResponse, isNull);

      // 放行迟到响应：票据已旧，结果全部丢弃。
      gate.complete();
      await analysis;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      state = container.read(smartLayoutSessionViewModelProvider);
      expect(state.phase, SmartLayoutSessionPhase.cancelled);
      expect(state.validatedCards, isEmpty);
      expect(state.candidates, isEmpty);
      return 0;
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('离页：分析在途切换页面 → 守卫拒绝收敛 failed，无 Scene 副作用', () async {
    final gate = Completer<void>();
    final (server, _) = await startServer(
      (_) async {
        await gate.future;
        return (200, titleRegionBody);
      },
    );
    await withRealHttp(() async {
      final (container, scope, controller) = setUpScope(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final before = controller.currentScene;
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('text-1');

      final analysis = vm.startAnalysis();
      // 离页：活页切换（会话守卫 four-check 拒绝旧票据续作）。
      scope.setActivePage('page-2');
      gate.complete();
      await analysis;
      var state = container.read(smartLayoutSessionViewModelProvider);
      if (state.phase == SmartLayoutSessionPhase.analyzing) {
        // 守卫在响应落地前检查；若响应已过检查点则生成链票据失配兜底。
        await Future<void>.delayed(const Duration(milliseconds: 50));
        state = container.read(smartLayoutSessionViewModelProvider);
      }
      expect(
        state.phase,
        SmartLayoutSessionPhase.failed,
        reason: '离页后旧票据必须被拒绝（guard/chain 失配 fail closed）',
      );
      expect(state.failure, isNotNull);
      expect(
        identical(controller.currentScene, before),
        isTrue,
        reason: '离页拒绝零 Scene 副作用',
      );
      return 0;
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('重试：服务 500 → failed 可重试 → 服务恢复后 retry 全链成功', () async {
    var failAll = true;
    final (server, _) = await startServer((request) async {
      if (failAll) return (500, '');
      return (200, titleRegionBody);
    });
    await withRealHttp(() async {
      final (container, scope, controller) = setUpScope(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('text-1');

      await vm.startAnalysis();
      var state = container.read(smartLayoutSessionViewModelProvider);
      expect(state.phase, SmartLayoutSessionPhase.failed);
      expect(state.failure!.retryable, isTrue);
      expect(state.canRetry, isTrue);

      failAll = false;
      await vm.retry();
      state = container.read(smartLayoutSessionViewModelProvider);
      expect(state.phase, SmartLayoutSessionPhase.reviewing);
      expect(state.validatedCards, isNotEmpty);
      expect(state.attemptCount, 2);
      return 0;
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('生成链票据失配（无捕获/离页迟到）：fail closed 不产出候选', () async {
    final controller = controllerWithPageContent();
    addTearDown(controller.dispose);
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:48931'),
      pageId: pageId,
    );
    addTearDown(scope.dispose);
    // 票据从未经过 requestBuilder（无捕获）→ 链入口 StateError。
    final ticket = scope.session.beginOperation();
    final response = SmartLayoutV3Response.fromJson(
      jsonDecode(titleRegionBody),
    );
    await expectLater(
      scope.dependencies.candidateChain!(response, ticket),
      throwsStateError,
    );
    // reset 仅终态合法：先取消（analyzing→cancelled）再复位。
    scope.session.cancelOperation();
    scope.session.reset();
  });
}
