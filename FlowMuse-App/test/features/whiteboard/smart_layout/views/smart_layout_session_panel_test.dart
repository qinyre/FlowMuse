import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/views/smart_layout_session_panel.dart';
import 'package:google_fonts/google_fonts.dart';

/// 真实入口宿主回归：生产结构 = 根 ProviderScope（app 级）内嵌面板。
/// Riverpod 3 把未声明 dependencies 的 provider 解析到根容器，嵌套
/// ProviderScope 的 overrides 不生效——曾致 deps 默认工厂抛
/// UnimplementedError 且错误态被根容器缓存，面板整块渲染成
/// ErrorWidget（release 灰框、点开始零反馈）。修复后面板以
/// UncontrolledProviderScope 手工容器承载 override，本测试固定该
/// 生产嵌套结构不回归。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pageId = 'page-1';

  MarkdrawController pagedController() => MarkdrawController(
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

  Future<void> pumpProductionNesting(WidgetTester tester, Widget child) async {
    // 与生产一致：app 根 scope → 白板页 Stack → 面板（自带 scope）。
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Scaffold(body: Stack(children: [child]))),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('根 scope 内嵌面板：deps override 生效，idle 面板完整渲染', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final controller = pagedController();
    addTearDown(controller.dispose);
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
    );
    addTearDown(scope.dispose);

    await pumpProductionNesting(
      tester,
      SmartLayoutSessionPanel(scope: scope, onClose: () {}),
    );

    expect(find.text('智能排版（v3 实时预览）'), findsOneWidget);
    expect(find.text('开始智能排版'), findsOneWidget);
    expect(find.textContaining('排版范围 0 项'), findsOneWidget);
  });

  testWidgets('根 scope 内嵌面板：开始可点且 VM 真实工作（无引擎→失败可见）', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final controller = pagedController();
    addTearDown(controller.dispose);
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
    );
    addTearDown(scope.dispose);

    await pumpProductionNesting(
      tester,
      SmartLayoutSessionPanel(scope: scope, onClose: () {}),
    );

    // 无识别引擎：点击后 VM 以 capabilityOff 失败收敛（异常零吞没），
    // 证明 deps override 在生产嵌套结构下真实注入。
    await tester.tap(find.text('开始智能排版'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('失败'), findsWidgets);
    expect(find.text('关闭'), findsOneWidget);
  });
}
