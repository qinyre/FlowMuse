import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_composition.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';

// 显式开关才发送真实模型请求。原笔记仅从本地 ignored build 读，不入库。
// flutter test --dart-define=COMPOSITION_TEST_SERVER=http://...
//   --dart-define=COMPOSITION_TEST_NOTE=build/...excalidraw <本文件>
const _server = String.fromEnvironment('COMPOSITION_TEST_SERVER');
const _note = String.fromEnvironment('COMPOSITION_TEST_NOTE');

class _RealNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_server.isEmpty || _note.isEmpty) {
    test('真实模型效果验收需要显式服务地址和本地笔记', () {}, skip: '未配置在线验收输入');
    return;
  }
  setUpAll(() async {
    await (FontLoader('Excalifont')..addFont(
          rootBundle.load('assets/fonts/markdraw/Excalifont-Regular.ttf'),
        ))
        .load();
    const cjkPath = String.fromEnvironment('LAYOUT_EVIDENCE_CJK_FONT');
    if (cjkPath.isNotEmpty) {
      await (FontLoader('OnlineCJK')..addFont(
            File(cjkPath).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
  });
  for (final variant in ['core-1', 'core-2', 'core-3', 'crossed', 'shared']) {
    test('真实模型 $variant', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final doc = ExcalidrawJsonCodec.parse(
          await File(_note).readAsString(),
        ).value;
        var original = Scene();
        for (final e in doc.allElements) {
          original = original.addElement(e);
        }
        for (final e in doc.files.entries) {
          original = original.addFile(e.key, e.value);
        }
        final pictures =
            original.activeElements.whereType<ImageElement>().toList()
              ..sort((a, b) => a.y.compareTo(b.y));
        expect(pictures, hasLength(2), reason: '输入须是已核对的原猫狗页：上狗下猫');
        final dog = pictures[0].id.value, cat = pictures[1].id.value;
        var scene = original;
        if (!variant.startsWith('core')) {
          scene = Scene();
          for (final e in original.activeElements.where(
            (e) => e is ImageElement || e.isCanvasPage,
          )) {
            scene = scene.addElement(e);
          }
          for (final e in original.files.entries) {
            scene = scene.addFile(e.key, e.value);
          }
          final texts = variant == 'shared'
              ? {'shared': '两张图片分别是躺着的小猫和小狗，共同展示动物休息的状态。'}
              : {'cat-note': '这是躺着的小猫。', 'dog-note': '这是躺着的小狗。'};
          var y = 250.0;
          for (final e in texts.entries) {
            scene = scene.addElement(
              TextElement(
                id: ElementId(e.key),
                x: 110,
                y: y,
                width: 410,
                height: 60,
                fontSize: 28,
                fontFamily:
                    const String.fromEnvironment('LAYOUT_EVIDENCE_CJK_FONT') ==
                        ''
                    ? 'Excalifont'
                    : 'OnlineCJK',
                text: e.value,
              ),
            );
            y += 500; // 猫文字放到狗旁、狗文字放到猫旁，关系真值不随位置变。
          }
        }
        final controller = MarkdrawController()..loadScene(scene);
        final before = SceneFingerprint.of(controller.currentScene);
        var calls = 0;
        final scope = SmartLayoutRealSessionScope.build(
          controller: controller,
          serverUri: Uri.parse(_server),
          pageId: 'page-1',
          post:
              ({
                required url,
                required body,
                headers = const {},
                connectTimeoutMs = 8000,
                readTimeoutMs = 130000,
                cancelToken,
              }) async {
                calls++;
                final response = await NativeHttpClient.post(
                  url: url,
                  body: body,
                  headers: headers,
                  connectTimeoutMs: connectTimeoutMs,
                  readTimeoutMs: readTimeoutMs,
                  cancelToken: cancelToken,
                );
                final request = jsonDecode(body) as Map<String, dynamic>;
                final stage = request['stage'];
                final overview = request.remove('overviewPngBase64');
                if (overview is String) {
                  await File(
                    'build/composition-online-$variant-overview.png',
                  ).writeAsBytes(base64Decode(overview));
                  await File(
                    'build/composition-online-$variant-units.json',
                  ).writeAsString(jsonEncode(request['units']));
                }
                await File(
                  'build/composition-online-$variant-$stage.json',
                ).writeAsString(response.body);
                return response;
              },
        );
        final watch = Stopwatch()..start();
        try {
          final ticket = scope.session.beginOperation();
          final analysis = await scope.dependencies.analysisRunner!(ticket);
          expect(
            analysis,
            isA<SmartLayoutRecognitionSucceeded>(),
            reason: '$analysis',
          );
          final success = analysis as SmartLayoutRecognitionSucceeded;
          expect(success.recognition.failure, isNull);
          final semantic = success.semantic.document;
          final composition = SemanticComposition.of(semantic)!;
          expect(composition.analyzed, isTrue, reason: '不能把本地回退冒充真实模型通过');
          final actual = <String>{};
          for (final b in semantic.blocks) {
            final target = b.extras['captionOf'];
            if (target is String) actual.add('${b.id}->$target');
          }
          for (final group in composition.hints.mediaGroups) {
            for (final t in group.textUnitIds) {
              for (final f in group.figureUnitIds) {
                actual.add('$t->$f');
              }
            }
          }
          final expected = <String>{};
          if (variant == 'shared') {
            expected.addAll([
              'native:shared->native:$cat',
              'native:shared->native:$dog',
            ]);
          } else {
            for (final b in semantic.blocks) {
              final text =
                  (b.text ?? b.extras['transcribedText'] as String? ?? '')
                      .replaceAll(RegExp(r'\s'), '');
              if (text.contains('小猫')) expected.add('${b.id}->native:$cat');
              if (text.contains('小狗')) expected.add('${b.id}->native:$dog');
            }
          }
          expect(expected, hasLength(2), reason: 'OCR 必须保留两条可识别说明');
          final correct = actual.intersection(expected).length;
          debugPrint(
            'ONLINE $variant relations_correct=$correct actual=${actual.length} expected=${expected.length} '
            'soft=${composition.hints.softLineBreaks.length} calls=$calls ms=${watch.elapsedMilliseconds}',
          );
          expect(actual, expected, reason: '按事先核对的图像身份验证，不能信任模型自报准确率');
          final candidates = await scope
              .dependencies
              .candidateChainFromDocument!(success, ticket);
          expect(candidates, isNotEmpty);
          debugPrint(
            'ONLINE $variant scores=${candidates.map((c) => '${c.diversityKey}:${c.score.score.toStringAsFixed(4)} '
                '${c.score.entries.map((e) => '${e.id.name}=${e.value.toStringAsFixed(3)}').join(',')}').join('; ')}',
          );
          if (variant.startsWith('core')) {
            expect(
              candidates.first.diversityKey,
              'peerGrid',
              reason: '原短图注核心页默认应清楚并列，不能只在备选里存在',
            );
          }
          debugPrint(
            'ONLINE $variant default=${candidates.first.diversityKey} '
            'recommend=${scope.dependencies.reviewContextBuilder!()!.recommendation?.recommended} total_ms=${watch.elapsedMilliseconds}',
          );
          for (final c in candidates) {
            c.dispose();
          }
          expect(SceneFingerprint.of(controller.currentScene), before);
          expect(calls, variant.startsWith('core') ? 2 : 1);
        } finally {
          scope.dispose();
          controller.dispose();
        }
      }, _RealNetwork());
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}
