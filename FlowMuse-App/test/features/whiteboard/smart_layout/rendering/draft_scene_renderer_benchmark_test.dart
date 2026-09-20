import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rendering/draft_scene_renderer.dart';

/// 常驻的本地渲染 microbenchmark。无网络、无 OCR，不代表平板端到端延迟。
/// 开启：flutter test --dart-define=SMART_LAYOUT_RENDER_BENCH=true <本文件>
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '三页固定场景各五轮：记录本地渲染中位数/最慢值与像素哈希',
    () async {
      final raw =
          jsonDecode(
                File(
                  'test/features/whiteboard/smart_layout/recognition/fixtures/tablet_note_20260918.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      var tablet = Scene();
      final elements = raw['elements'] as List;
      for (var i = 0; i < elements.length; i++) {
        final json = Map<String, Object?>.from(elements[i] as Map);
        final element = ExcalidrawJsonCodec.parseElement(
          json,
          json['type'] as String,
          i,
          [],
        );
        if (element != null) tablet = tablet.addElement(element);
      }
      Scene grid(int count) {
        var scene = Scene();
        for (var i = 0; i < count; i++) {
          scene = scene.addElement(
            RectangleElement(
              id: ElementId('shape-$i'),
              x: (i % 30) * 38.0,
              y: (i ~/ 30) * 26.0,
              width: 32,
              height: 20,
              index: (count - i).toString().padLeft(5, '0'),
              seed: i + 1,
              versionNonce: 11,
              updated: 1000,
            ),
          );
        }
        return scene;
      }

      for (final entry in {
        'tablet-47': tablet,
        'grid-300': grid(300),
        'grid-900': grid(900),
      }.entries) {
        final times = <int>[];
        final hashes = <String>{};
        // 一轮预热不计入。每次新 renderer，无跨轮图片缓存；场景内容固定。
        for (var run = 0; run < 6; run++) {
          final renderer = DraftSceneRenderer();
          final clock = Stopwatch()..start();
          final snapshot = await renderer.render(
            scene: entry.value,
            viewport: const ViewportState(),
            pixelSize: const ui.Size(1200, 800),
          );
          clock.stop();
          try {
            expect(snapshot.layers.length, entry.value.activeElements.length);
            final ordered = entry.value.orderedElements;
            for (final layer in snapshot.layers) {
              expect(
                layer.zIndex,
                ordered.indexWhere((e) => e.id.value == layer.elementId),
              );
            }
            final bytes = await snapshot.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            hashes.add(sha256.convert(bytes!.buffer.asUint8List()).toString());
            if (run > 0) times.add(clock.elapsedMicroseconds);
            expect(renderer.liveResourceCount, 0);
          } finally {
            snapshot.dispose();
            renderer.dispose();
          }
        }
        expect(hashes.length, 1, reason: '五轮与预热的真实像素必须一致');
        final sorted = [...times]..sort();
        // ignore: avoid_print
        print(
          'RENDER_BENCH ${jsonEncode({'scene': entry.key, 'cache': 'new-renderer-each-run', 'runs_us': times, 'median_us': sorted[2], 'max_us': sorted.last, 'pixel_sha256': hashes.single})}',
        );
      }
    },
    skip: !const bool.fromEnvironment('SMART_LAYOUT_RENDER_BENCH'),
  );
}
