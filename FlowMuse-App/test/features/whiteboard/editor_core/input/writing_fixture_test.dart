import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/input_policy.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_recorder.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_normalizer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/writing_performance_manifest.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../../../../../integration_test/fixtures/scene_fixtures.dart';
import '../../../../../integration_test/fixtures/writing_recordings.dart';

void main() {
  group('writing recordings', () {
    test('schema、样本数、坐标与时间固定', () {
      expect(writingRecordingFixtures.map((item) => item.name).toSet(), {
        'short_horizontal_no_pressure',
        'long_curve_pressure',
        'quick_zigzag',
        'pressure_ramp',
        'pointer_cancel',
      });
      for (final fixture in writingRecordingFixtures) {
        expect(fixture.schemaVersion, writingFixtureSchemaVersion);
        expect(
          fixture.recording.samples,
          hasLength(fixture.expectedRawSampleCount),
        );
        expect(fixture.recording.samples.first.phase, StrokePhase.down);
        expect(
          fixture.recording.samples.last.phase,
          anyOf(StrokePhase.up, StrokePhase.cancel),
        );
        var previousMicros = -1;
        for (final sample in fixture.recording.samples) {
          expect(sample.x, inInclusiveRange(0, 2000));
          expect(sample.y, inInclusiveRange(0, 2000));
          expect(sample.time.inMicroseconds, greaterThan(previousMicros));
          previousMicros = sample.time.inMicroseconds;
        }
      }
    });

    test('固定 modeler 策略的 accepted 数与声明一致', () {
      for (final fixture in writingRecordingFixtures) {
        final modeler = StrokeInputModeler(InputPolicy.stylus);
        final accepted = fixture.recording.samples
            .map(modeler.process)
            .where((result) => result.point != null)
            .length;
        expect(
          accepted,
          fixture.expectedAcceptedSampleCount,
          reason: fixture.name,
        );
      }
    });

    test('recording JSON round-trip 稳定', () {
      for (final fixture in writingRecordingFixtures) {
        final encoded = jsonEncode(fixture.recording.toJson());
        final decoded = StrokeRecording.fromJson(
          Map<String, dynamic>.from(jsonDecode(encoded) as Map),
        );
        expect(jsonEncode(decoded.toJson()), encoded, reason: fixture.name);
      }
    });

    test('无压力 fixture 通过真实 PointerEvent 边界仍保持无压力', () {
      final fixture = writingRecordingFixtures.singleWhere(
        (item) => item.name == 'short_horizontal_no_pressure',
      );
      final sample = fixture.recording.samples.first;
      expect(sample.kind, StrokeInputKind.touch);
      expect(sample.pressure, isNull);

      final normalized = StrokeInputNormalizer().normalize(
        PointerDownEvent(
          pointer: sample.pointerId,
          kind: PointerDeviceKind.touch,
          position: Offset(sample.x, sample.y),
          pressure: 0,
          pressureMin: 0,
          pressureMax: 1,
        ),
        phase: StrokePhase.down,
      );
      expect(normalized.pressure, isNull);
    });

    test('fixture 内容 hash 稳定且彼此区分', () {
      final hashes = writingRecordingFixtures
          .map((fixture) => fixture.contentHash)
          .toList();
      expect(hashes.toSet(), hasLength(writingRecordingFixtures.length));
      expect(hashes.every((hash) => hash.length == 64), isTrue);
      for (final entry in writingPerformanceFixtures.entries) {
        final fixture = writingRecordingFixtures.singleWhere(
          (candidate) => candidate.name == entry.key,
        );
        expect(fixture.contentHash, entry.value.hash, reason: entry.key);
      }
    });
  });

  group('scene fixtures', () {
    test('100 元素 fixture 可由真实编辑器 codec 加载', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);

      controller.loadFromContent(
        buildSceneFixture(100).toContent(),
        'writing-performance.excalidraw',
      );

      expect(controller.currentScene.elements, hasLength(100));
      expect(
        controller.currentScene.elements.map((element) => element.type).toSet(),
        containsAll(['freedraw', 'rectangle', 'text', 'image']),
      );
    });

    test('固定规模覆盖必要类型、占位图与 z-order', () {
      for (final count in supportedSceneFixtureCounts) {
        final scene = buildSceneFixture(count);
        expect(
          scene.collaborationHash(),
          writingSceneFixtureHashes[count],
          reason: 'scene-$count',
        );
        expect(scene.elements, hasLength(count));
        final types = scene.elements.map((element) => element['type']).toSet();
        expect(types, containsAll(['freedraw', 'rectangle', 'text', 'image']));
        expect(
          scene.elements
              .where((element) => element['type'] == 'image')
              .every(
                (element) =>
                    element['fileId'] == 'fixture-image-placeholder' &&
                    element['status'] == 'pending',
              ),
          isTrue,
        );
        final indices = scene.elements
            .map((element) => element['index']! as String)
            .toList();
        expect(indices.toSet(), hasLength(count));
        expect([...indices]..sort(), indices);
      }
    });

    test('相同规模的序列化和 hash 确定', () {
      for (final count in supportedSceneFixtureCounts) {
        final first = buildSceneFixture(count);
        final second = buildSceneFixture(count);
        expect(
          second.toContent(),
          first.toContent(),
          reason: '$count elements',
        );
        expect(
          second.collaborationHash(),
          first.collaborationHash(),
          reason: '$count elements',
        );
      }
    });

    test('拒绝静默降级到未冻结规模', () {
      expect(() => buildSceneFixture(4999), throwsArgumentError);
    });
  });
}
