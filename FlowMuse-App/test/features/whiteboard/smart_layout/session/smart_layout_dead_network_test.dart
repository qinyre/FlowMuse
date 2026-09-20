import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:google_fonts/google_fonts.dart';

import '../recognition/fake_recognition_transport.dart';

/// 真机事故回归（2026-09-17 OPD2404）：平板路由失效（ENETUNREACH 快败/
/// SYN 黑洞）时，分析卡死在「正在识别」数分钟无任何兜底。本测试令传输层
/// 全程抛网络故障，断言 startAnalysis 有界完成且 phase 离开 analyzing。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pageId = 'page-1';

  testWidgets('网络全程不可达：分析必须有界完成，不得卡死 analyzing', (
    tester,
  ) async {
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
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('page-frame'),
          x: 0,
          y: 0,
          width: 1200,
          height: 800,
          seed: 7,
          versionNonce: 11,
          updated: 1000,
          customData: {
            'flowMuse': {'role': 'page', 'pageId': pageId},
          },
        ),
      ),
    );
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
            'recognitionStrokeSessionKey': 's1',
            'flowMuse': {'pageId': pageId},
          },
        ),
      ),
    );

    // 全程网络故障：等价真机 ENETUNREACH（快败）。
    final transport = FakeRecognitionTransport(
      errorFactory: (_) async =>
          const SmartLayoutHttpException.network('ENETUNREACH (网络不可达)'),
    );
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

    // 健康管线对快败网络应秒级降级完成；卡死则此处 20s 超时失败。
    await tester.runAsync(
      () => vm.startAnalysis().timeout(const Duration(seconds: 20)),
    );

    final state = container.read(smartLayoutSessionViewModelProvider);
    expect(
      state.phase,
      anyOf(SmartLayoutSessionPhase.reviewing, SmartLayoutSessionPhase.idle),
      reason: '网络故障必须有界降级：离开 analyzing（reviewing 空候选或回 idle）',
    );
  });
}
