import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_response.dart';
import '../recognition/fake_recognition_transport.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:google_fonts/google_fonts.dart';

/// V3-505C 真实链闭环：loopback 真实 HTTP 服务（真实 NativeHttpClient）
/// + 真实 Scene（canvas page + typed 文本）+ 真实装配
/// （SmartLayoutRealSessionScope，无 fake provider）→ 候选 →
/// compare-and-commit。以及无解/重试/取消/离页分支。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pageId = 'page-1';
  const page2Id = 'page-2';
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
      // 既有 HTTP 仓库路径口径（/analyze/v3 实验/测试基础设施）；
      // 生产识别链（默认 true）由下方识别闭环组覆盖。
      useRecognitionPipeline: false,
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

  test(
    '真实 server→候选→commit：全链自动化 + Scene/History 精确',
    () async {
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
        expect((sent['exactTexts'] as List).single, {
          'sourceId': 'text-1',
          'text': '正文内容文本',
        });
        expect((sent['sourceRefs'] as List).toSet(), {'page-frame', 'text-1'});

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
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    '无解：锁定障碍吃满全部栏 → NoFeasibleLayout 空候选 + 重新分析',
    () async {
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
          useRecognitionPipeline: false,
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
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    '契约破坏：响应零认领（账目不守恒）→ fail closed 进 failed',
    () async {
      final (server, _) = await startServer(
        (_) async => (200, emptyRegionsBody),
      );
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
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('取消：分析在途立即取消；迟到响应按票据判旧、零残留', () async {
    final gate = Completer<void>();
    final (server, _) = await startServer((_) async {
      await gate.future;
      return (200, titleRegionBody);
    });
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

  test(
    '离页：分析在途切换页面 → 守卫拒绝收敛 failed，无 Scene 副作用',
    () async {
      final gate = Completer<void>();
      final (server, _) = await startServer((_) async {
        await gate.future;
        return (200, titleRegionBody);
      });
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
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    '重试：服务 500 → failed 可重试 → 服务恢复后 retry 全链成功',
    () async {
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
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

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

  group('生产识别链（recognize/v3 管线 → v3 确定性排版，零 v2 视觉链）', () {
    /// 手写页控制器：显式版式页 + canvas page 元素（快照页框/
    /// pageBounds）+ 单笔迹簇（session s1）+ 噪点笔画。
    MarkdrawController recognitionController() {
      final controller = MarkdrawController(
        config: MarkdrawEditorConfig(
          initialLayout: CanvasLayout(
            type: CanvasLayoutType.paged,
            pages: const [
              CanvasPage(
                id: pageId,
                index: 0,
                bounds: Rect.fromLTWH(0, 0, 1200, 800),
                template: CanvasPageTemplate.blank,
              ),
            ],
          ),
        ),
      );
      controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
      controller.applyResult(AddElementResult(canvasPage()));
      controller.applyResult(
        AddElementResult(
          FreedrawElement(
            id: const ElementId('k-s1'),
            x: 200,
            y: 150,
            width: 300,
            height: 60,
            points: const [Point(0, 0), Point(40, 20)],
            customData: {
              recognitionStrokeSessionKey: 's1',
              'flowMuse': {'pageId': pageId},
            },
          ),
        ),
      );
      // 噪点笔画（<8×8pt）：v3 口径不随方案静默删除——未成转写块的
      // 独立笔迹按保留处理（除非被就近并入宿主区域一并重识别）。
      controller.applyResult(
        AddElementResult(
          FreedrawElement(
            id: const ElementId('k-n1'),
            x: 210,
            y: 300,
            width: 6,
            height: 6,
            points: const [Point(0, 0), Point(4, 4)],
            customData: {
              'flowMuse': {'pageId': pageId},
            },
          ),
        ),
      );
      return controller;
    }

    /// recognize/v3 假传输：read/verify 按脚本应答（regionId 定制文本）。
    FakeRecognitionTransport recognitionTransport({
      String Function(String regionId)? textOf,
      String Function(String regionId)? statusOf,
    }) => FakeRecognitionTransport(
      responder: (body) async {
        final request = jsonDecode(body) as Map<String, Object?>;
        return buildBatchResponseBody(
          request,
          confidence: 0.9,
          textOf: textOf,
          statusOf: statusOf,
        );
      },
    );

    testWidgets(
      '高置信闭环：一次 read → 识别候选 → apply → undo',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        GoogleFonts.config.allowRuntimeFetching = false;
        final controller = recognitionController();
        addTearDown(controller.dispose);
        // 噪点笔画并入宿主区域（同一连通分量）：单一区域承载全部笔迹，
        // 转写文本统一返回。
        final transport = recognitionTransport(textOf: (_) => '手工记账流水');
        final statusSeen = <String>[];
        final scope = SmartLayoutRealSessionScope.build(
          controller: controller,
          serverUri: Uri.parse('http://127.0.0.1:9'),
          pageId: pageId,
          post: transport.post,
        );
        addTearDown(scope.dispose);
        scope.recognitionStatus.addListener(() {
          final value = scope.recognitionStatus.value;
          if (value != null) statusSeen.add(value);
        });

        final container = ProviderContainer(
          overrides: [
            smartLayoutSessionDependenciesProvider.overrideWithValue(
              scope.dependencies,
            ),
          ],
        );
        addTearDown(container.dispose);
        final vm = container.read(smartLayoutSessionViewModelProvider.notifier);
        final beforeStroke = controller.currentScene.elements.firstWhere(
          (e) => e.id.value == 'k-s1',
        );

        await tester.runAsync(vm.startAnalysis);
        var state = container.read(smartLayoutSessionViewModelProvider);
        expect(state.phase, SmartLayoutSessionPhase.reviewing);
        expect(state.validatedCards, isNotEmpty, reason: '识别链产出真候选');
        expect(state.failure, isNull);

        // 全部请求只打 recognize/v3（独立识别链；零 v2 视觉端点）。
        expect(transport.requests, isNotEmpty);
        for (final request in transport.requests) {
          expect(
            request.url,
            contains('/api/ink/smart-layout/recognize/v3'),
            reason: '生产链唯一识别端点',
          );
        }
        expect(
          scope.repository.requestCount,
          0,
          reason: '零 /analyze/v3 第二模型请求',
        );
        // 状态播报（spec §10 枚举）：至少经历准备/识别阶段。
        expect(statusSeen, isNotEmpty);
        expect(
          statusSeen.toSet().difference({
            '正在准备',
            '正在识别',
            '正在重分组',
            '正在复核',
            '正在恢复结构',
            '正在生成排版',
          }),
          isEmpty,
          reason: '状态文案限定在既定枚举内',
        );

        vm.chooseCandidate(state.validatedCards.first.candidateId);
        await tester.runAsync(vm.applySelectedCandidate);
        state = container.read(smartLayoutSessionViewModelProvider);
        expect(state.phase, SmartLayoutSessionPhase.applied);

        // Scene 真实变更（transcribed 变换）：源笔迹整组移除，新增确定性
        // 文本元素承载识别转写。
        final applied = controller.currentScene;
        expect(
          applied.elements.where((e) => e.id.value == 'k-s1' && !e.isDeleted),
          isEmpty,
          reason: 'transcribed 块源笔迹移除',
        );
        expect(
          applied.elements.where((e) => e.id.value == 'k-n1' && !e.isDeleted),
          isEmpty,
          reason: '并入宿主区域的噪点笔画随转写块一并替换',
        );
        expect(
          applied.elements.where(
            (e) => e is TextElement && !e.isDeleted && e.text == '手工记账流水',
          ),
          isNotEmpty,
          reason: '候选文本来自识别响应',
        );

        // 一次 undo 回到提交前（compare-and-commit 单事务）。
        controller.undo();
        final undone = controller.currentScene;
        expect(
          undone.elements.where((e) => e.id.value == 'k-s1' && !e.isDeleted),
          isNotEmpty,
          reason: 'undo 恢复源笔迹',
        );
        expect(
          undone.elements.where(
            (e) => e is TextElement && !e.isDeleted && e.text == '手工记账流水',
          ),
          isEmpty,
          reason: 'undo 移除新增文本',
        );
        expect(
          undone.elements.firstWhere((e) => e.id.value == 'k-s1').x,
          beforeStroke.x,
        );
        expect(
          undone.elements.where((e) => e.id.value == 'k-n1' && !e.isDeleted),
          isNotEmpty,
          reason: 'undo 恢复噪点笔画（单事务完整回滚）',
        );
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );

    testWidgets('空页：稳定无解——空候选 reviewing，非错误', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      GoogleFonts.config.allowRuntimeFetching = false;
      final controller = MarkdrawController(
        config: MarkdrawEditorConfig(
          initialLayout: CanvasLayout(
            type: CanvasLayoutType.paged,
            pages: const [
              CanvasPage(
                id: pageId,
                index: 0,
                bounds: Rect.fromLTWH(0, 0, 1200, 800),
                template: CanvasPageTemplate.blank,
              ),
            ],
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.applyResult(AddElementResult(canvasPage()));
      final transport = recognitionTransport();
      final scope = SmartLayoutRealSessionScope.build(
        controller: controller,
        serverUri: Uri.parse('http://127.0.0.1:9'),
        pageId: pageId,
        post: transport.post,
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
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier);

      await tester.runAsync(vm.startAnalysis);
      final state = container.read(smartLayoutSessionViewModelProvider);
      expect(state.phase, SmartLayoutSessionPhase.reviewing);
      expect(state.candidates, isEmpty, reason: '空页无解不是错误');
      expect(state.failure, isNull);
      expect(transport.requests, isEmpty, reason: '无区域不发识别请求');
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets(
      '识别全 nonText：全保留 → 空候选 + Scene 未动（不回退 V1）',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        GoogleFonts.config.allowRuntimeFetching = false;
        final controller = recognitionController();
        addTearDown(controller.dispose);
        final transport = recognitionTransport(statusOf: (_) => 'nonText');
        final before = controller.currentScene.elements
            .map((e) => e.id.value)
            .toSet();
        final scope = SmartLayoutRealSessionScope.build(
          controller: controller,
          serverUri: Uri.parse('http://127.0.0.1:9'),
          pageId: pageId,
          post: transport.post,
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
        final vm = container.read(smartLayoutSessionViewModelProvider.notifier);

        await tester.runAsync(vm.startAnalysis);
        final state = container.read(smartLayoutSessionViewModelProvider);
        expect(state.phase, SmartLayoutSessionPhase.reviewing);
        expect(state.candidates, isEmpty, reason: '无可转换内容=零修改保留');
        expect(state.failure, isNull);
        final after = controller.currentScene.elements
            .map((e) => e.id.value)
            .toSet();
        expect(after, containsAll(before), reason: '失败/无解保留原内容');
        expect(
          controller.currentScene.elements.where((e) => !e.isDeleted).length,
          before.length,
          reason: '无软删除副作用',
        );
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );

    FreedrawElement pageStroke(
      String id,
      double y,
      String pid,
      String session,
    ) => FreedrawElement(
      id: ElementId(id),
      x: 200,
      y: y,
      width: 300,
      height: 60,
      points: const [Point(0, 0), Point(40, 20)],
      customData: {
        recognitionStrokeSessionKey: session,
        'flowMuse': {'pageId': pid},
      },
    );

    /// 双页控制器：page-1 笔迹 k-s1、page-2 笔迹 k-s2（各自的页框 +
    /// 单笔迹簇；两页内容错位摆放）。
    MarkdrawController twoPageRecognitionController() {
      final controller = MarkdrawController(
        config: MarkdrawEditorConfig(
          initialLayout: CanvasLayout(
            type: CanvasLayoutType.paged,
            pages: const [
              CanvasPage(
                id: pageId,
                index: 0,
                bounds: Rect.fromLTWH(0, 0, 1200, 800),
                template: CanvasPageTemplate.blank,
              ),
              CanvasPage(
                id: page2Id,
                index: 1,
                bounds: Rect.fromLTWH(0, 0, 1200, 800),
                template: CanvasPageTemplate.blank,
              ),
            ],
          ),
        ),
      );
      controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
      controller.applyResult(AddElementResult(canvasPage()));
      controller.applyResult(
        AddElementResult(
          RectangleElement(
            id: const ElementId('page-frame-2'),
            x: 0,
            y: 0,
            width: 1200,
            height: 800,
            seed: 7,
            versionNonce: 11,
            updated: 1000,
            customData: {
              'flowMuse': {'role': 'page', 'pageId': page2Id},
            },
          ),
        ),
      );
      controller.applyResult(
        AddElementResult(pageStroke('k-s1', 150, pageId, 's1')),
      );
      controller.applyResult(
        AddElementResult(pageStroke('k-s2', 500, page2Id, 's2')),
      );
      return controller;
    }

    testWidgets(
      '切页重析：setActivePage 后分析与 apply 作用于新页',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        GoogleFonts.config.allowRuntimeFetching = false;
        final controller = twoPageRecognitionController();
        addTearDown(controller.dispose);
        final transport = recognitionTransport(
          textOf: (regionId) => regionId.contains('k-s2') ? '第二页手写内容' : '识别正文',
        );
        final scope = SmartLayoutRealSessionScope.build(
          controller: controller,
          serverUri: Uri.parse('http://127.0.0.1:9'),
          pageId: pageId,
          post: transport.post,
        );
        addTearDown(scope.dispose);
        // 生产切页路径：面板重开时 setActivePage 同步活页——此后识别、
        // 候选重跑都应作用于 page-2。
        scope.setActivePage(page2Id);
        final container = ProviderContainer(
          overrides: [
            smartLayoutSessionDependenciesProvider.overrideWithValue(
              scope.dependencies,
            ),
          ],
        );
        addTearDown(container.dispose);
        final vm = container.read(smartLayoutSessionViewModelProvider.notifier);

        await tester.runAsync(vm.startAnalysis);
        var state = container.read(smartLayoutSessionViewModelProvider);
        expect(state.phase, SmartLayoutSessionPhase.reviewing);
        expect(state.validatedCards, isNotEmpty);
        for (final request in transport.requests) {
          final decoded = jsonDecode(request.body) as Map<String, Object?>;
          expect(decoded['pageId'], page2Id, reason: '识别请求作用于新页');
        }

        vm.chooseCandidate(state.validatedCards.first.candidateId);
        await tester.runAsync(vm.applySelectedCandidate);
        state = container.read(smartLayoutSessionViewModelProvider);
        expect(state.phase, SmartLayoutSessionPhase.applied);

        final applied = controller.currentScene;
        expect(
          applied.elements.where((e) => e.id.value == 'k-s2' && !e.isDeleted),
          isEmpty,
          reason: '切页后分析新页：page-2 源笔迹被替换',
        );
        expect(
          applied.elements.where(
            (e) => e is TextElement && !e.isDeleted && e.text == '第二页手写内容',
          ),
          isNotEmpty,
          reason: '新页候选文本落地',
        );
        expect(
          applied.elements.where((e) => e.id.value == 'k-s1' && !e.isDeleted),
          isNotEmpty,
          reason: '旧页（page-1）笔迹不受切页分析影响',
        );
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );

    testWidgets('取消后立即重试：在途识别被主动取消，重试全链走通', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      GoogleFonts.config.allowRuntimeFetching = false;
      final controller = recognitionController();
      addTearDown(controller.dispose);
      final transport = recognitionTransport(textOf: (_) => '重试后的手写');
      final scope = SmartLayoutRealSessionScope.build(
        controller: controller,
        serverUri: Uri.parse('http://127.0.0.1:9'),
        pageId: pageId,
        post: transport.post,
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
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier);

      await tester.runAsync(() async {
        // 悬挂首批请求（模拟在途识别）；取消 → 主动取消信号，重试不等收尾。
        transport.blockRequests();
        final first = vm.startAnalysis();
        // 轮询等首批请求真正发出（测试体的 Completer 在 fake zone 创建、
        // runAsync 内完成会跨微任务队列死锁——只轮询普通可变状态）。
        while (transport.requests.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        vm.cancel();
        expect(
          container.read(smartLayoutSessionViewModelProvider).phase,
          SmartLayoutSessionPhase.cancelled,
        );
        vm.reset();
        final retry = vm.startAnalysis();
        transport.release();
        await first;
        await retry;
      });

      final state = container.read(smartLayoutSessionViewModelProvider);
      expect(state.phase, SmartLayoutSessionPhase.reviewing);
      expect(state.failure, isNull, reason: '迟到首轮按票据判旧，不影响重试');
      expect(state.validatedCards, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets(
      '面板重开复用 scope：终态会话复位，重开面板可直接再开始',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        GoogleFonts.config.allowRuntimeFetching = false;
        final controller = recognitionController();
        addTearDown(controller.dispose);
        final transport = recognitionTransport(textOf: (_) => '重开后的手写');
        final scope = SmartLayoutRealSessionScope.build(
          controller: controller,
          serverUri: Uri.parse('http://127.0.0.1:9'),
          pageId: pageId,
          post: transport.post,
        );
        addTearDown(scope.dispose);

        // 在途会话不被 setActivePage 复位（终态才复位）。
        scope.session.beginOperation();
        scope.setActivePage(pageId);
        expect(scope.session.state.phase, SmartLayoutSessionPhase.analyzing);
        scope.session.cancelOperation();

        // 模拟重开面板（关闭时 onClose 先取消 → 终态 cancelled；生产
        // 路径复用 scope 并走 setActivePage）：必须复位为 idle，否则新
        // 面板的初始 idle 视图与状态机终态错位，点开始将在
        // beginOperation 静默抛非法迁移（零反馈死按钮）。
        expect(scope.session.state.phase, SmartLayoutSessionPhase.cancelled);
        scope.setActivePage(pageId);
        expect(scope.session.state.phase, SmartLayoutSessionPhase.idle);

        final container = ProviderContainer(
          overrides: [
            smartLayoutSessionDependenciesProvider.overrideWithValue(
              scope.dependencies,
            ),
          ],
        );
        addTearDown(container.dispose);
        final vm = container.read(smartLayoutSessionViewModelProvider.notifier);
        await tester.runAsync(vm.startAnalysis);
        final state = container.read(smartLayoutSessionViewModelProvider);
        expect(state.phase, SmartLayoutSessionPhase.reviewing);
        expect(transport.requests, isNotEmpty, reason: '重开面板的首次分析真实走通识别链');
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });
}
