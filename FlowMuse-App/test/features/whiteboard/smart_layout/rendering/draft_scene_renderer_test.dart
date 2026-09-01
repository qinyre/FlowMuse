import 'dart:ui' as ui;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rendering/draft_scene_renderer.dart';
import 'flow_muse_test_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实渲染：位图尺寸、层边界与编辑器几何一致，文本边界为实测墨迹盒', () async {
    final renderer = DraftSceneRenderer();
    addTearDown(renderer.dispose);
    final scene = buildTestScene();
    final snapshot = await renderer.render(
      scene: scene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: const Size(400, 300),
    );
    addTearDown(snapshot.dispose);

    expect(snapshot.image.width, 400);
    expect(snapshot.image.height, 300);
    expect(snapshot.missingFileIds, isEmpty);
    expect(snapshot.hasMissingResources, isFalse);

    final byId = {for (final layer in snapshot.layers) layer.elementId: layer};
    // 形状：painter 几何（元素盒）。
    final rectLayer = byId['shape-1']!;
    expect(rectLayer.bounds.left, 10);
    expect(rectLayer.bounds.top, 10);
    expect(rectLayer.bounds.size.width, 40);
    expect(rectLayer.bounds.size.height, 30);

    // 文本：真实 TextPainter 实测（与 V3-300A 同路径），非元素盒估算。
    final textLayer = byId['text-1']!;
    final measured = measureTestText();
    expect(textLayer.bounds.left, 100);
    expect(textLayer.bounds.top, 40);
    expect(textLayer.bounds.size.width, closeTo(measured.width, 1e-6));
    expect(textLayer.bounds.size.height, closeTo(measured.height, 1e-6));

    // 图片：显示盒 + resolved。
    final imageLayer = byId['img-1']!;
    expect(imageLayer.resourceStatus, DraftResourceStatus.resolved);
    expect(imageLayer.bounds.size.width, 20);
    expect(imageLayer.bounds.size.height, 20);

    // z 序按 orderedElements。
    final kinds = snapshot.layers.map((l) => l.elementId).toList();
    expect(kinds, ['shape-1', 'text-1', 'img-1']);
  });

  test('缺资源明确降级：引用缺失如实记录，不删除不伪造', () async {
    final renderer = DraftSceneRenderer();
    addTearDown(renderer.dispose);
    final scene = buildTestScene(withImageFile: false);
    final snapshot = await renderer.render(
      scene: scene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: const Size(200, 120),
    );
    addTearDown(snapshot.dispose);

    expect(snapshot.missingFileIds, ['file-1']);
    expect(snapshot.hasMissingResources, isTrue);
    final layer = snapshot.layers.firstWhere((l) => l.elementId == 'img-1');
    expect(layer.resourceStatus, DraftResourceStatus.missing);
    expect(layer.bounds.size.width, 20, reason: '元素仍在场景中，占位降级不删块');
  });

  test('资源归零：连续渲染后活资源为 0；取消在途渲染零残留', () async {
    final renderer = DraftSceneRenderer();
    addTearDown(renderer.dispose);
    final scene = buildTestScene();

    for (var i = 0; i < 3; i++) {
      final snapshot = await renderer.render(
        scene: scene,
        viewport: const ViewportState(zoom: 1),
        pixelSize: const Size(120, 90),
      );
      snapshot.dispose();
      expect(renderer.liveResourceCount, 0, reason: '第 ${i + 1} 次渲染后解码资源必须归零');
    }

    // 取消在途渲染：启动后立即作废，光栅化检查点抛取消且零残留。
    final pending = renderer.render(
      scene: scene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: const Size(120, 90),
    );
    renderer.cancelCurrent();
    await expectLater(pending, throwsA(isA<DraftRenderCancelled>()));
    expect(renderer.liveResourceCount, 0, reason: '取消后零残留');

    // 取消不影响后续渲染。
    final next = await renderer.render(
      scene: scene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: const Size(120, 90),
    );
    next.dispose();
    expect(renderer.liveResourceCount, 0);
  });

  test('释放后拒绝渲染', () async {
    final renderer = DraftSceneRenderer();
    renderer.dispose();
    expect(
      () => renderer.render(
        scene: buildTestScene(),
        viewport: const ViewportState(zoom: 1),
        pixelSize: const Size(10, 10),
      ),
      throwsStateError,
    );
  });

  test('平台 golden：真实 painter 绘制产物逐字节稳定（形状+图片）', () async {
    final renderer = DraftSceneRenderer();
    addTearDown(renderer.dispose);
    final scene = buildGoldenScene();
    final snapshot = await renderer.render(
      scene: scene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: const Size(64, 48),
    );
    addTearDown(snapshot.dispose);

    final bytes = await snapshot.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    expect(bytes, isNotNull);
    await expectLater(
      bytes!.buffer.asUint8List(),
      matchesGoldenFile('goldens/draft_render_shape_image.png'),
    );
  });
}
