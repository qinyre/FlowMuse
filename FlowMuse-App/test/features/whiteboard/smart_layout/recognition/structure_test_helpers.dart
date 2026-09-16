import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/structure_recovery.dart';

/// R5 测试输入构造：手写区域记录 + 识别结果 + 原生场景。
/// regionId 约定 targetSourceIds = ['s-<regionId 去 r: 前缀>']。

RecognitionStructureInput structureInputOf(
  List<RegionRecord> records,
  Map<String, RegionReadOutcome> outcomes, {
  Scene? scene,
  Future<RecognitionStructureResponse?> Function(RecognitionStructureRequest)?
  send,
}) {
  return RecognitionStructureInput(
    capture: RecognitionCapture(
      scene: scene ?? Scene(),
      sceneRevision: const RecognitionSceneRevision(
        epoch: 0,
        revision: 5,
        fingerprint: '0123456789abcdef',
      ),
      contentFingerprint: 'fedcba9876543210',
      operationId: 'op-struct',
      generation: 0,
      pageId: 'page-1',
    ),
    regionRecords: records,
    regionOutcomes: outcomes,
    remainingBudgetOf: () => const Duration(seconds: 60),
    sendStructureRequest: send ?? _failIfCalled,
  );
}

/// 简写：识别成功的区域记录。
RegionRecord regionRecordOf(
  String regionId, {
  required double top,
  required double left,
  double width = 200,
  double lineHeight = 20,
}) {
  final minSource = regionId.replaceFirst('r:', '');
  return RegionRecord(
    regionId: regionId,
    bounds: RecognitionBounds(
      left: left,
      top: top,
      width: width,
      height: lineHeight,
    ),
    targetSourceIds: ['s-$minSource'],
    localLineHeight: lineHeight,
  );
}

RegionReadOutcome recognizedOutcomeOf(
  String regionId,
  String text, {
  List<String> targetSourceIds = const [],
}) {
  final minSource = regionId.replaceFirst('r:', '');
  return RegionReadOutcome(
    regionId: regionId,
    status: RecognitionRegionStatus.recognized,
    targetSourceIds: targetSourceIds.isEmpty
        ? ['s-$minSource']
        : targetSourceIds,
    text: text,
    confidence: 0.9,
  );
}

/// recover() 的直接驱动：区域（text 非空=recognized；null=保留障碍）。
Future<StructureResult> recoverWithRegions(
  List<RegionSpec> specs, {
  Scene? scene,
  Future<RecognitionStructureResponse?> Function(RecognitionStructureRequest)?
  send,
}) {
  final records = <RegionRecord>[];
  final outcomes = <String, RegionReadOutcome>{};
  for (final spec in specs) {
    final minSource = spec.regionId.replaceFirst('r:', '');
    records.add(
      RegionRecord(
        regionId: spec.regionId,
        bounds: RecognitionBounds(
          left: spec.left,
          top: spec.top,
          width: spec.width,
          height: spec.lineHeight,
        ),
        targetSourceIds: ['s-$minSource'],
        localLineHeight: spec.lineHeight,
      ),
    );
    if (spec.text != null) {
      outcomes[spec.regionId] = RegionReadOutcome(
        regionId: spec.regionId,
        status: RecognitionRegionStatus.recognized,
        targetSourceIds: ['s-$minSource'],
        text: spec.text,
        confidence: 0.9,
      );
    }
  }
  final recovery = const StructureRecovery();
  return recovery
      .recover(
        RecognitionStructureInput(
          capture: RecognitionCapture(
            scene: scene ?? Scene(),
            sceneRevision: const RecognitionSceneRevision(
              epoch: 0,
              revision: 5,
              fingerprint: '0123456789abcdef',
            ),
            contentFingerprint: 'fedcba9876543210',
            operationId: 'op-struct',
            generation: 0,
            pageId: 'page-1',
          ),
          regionRecords: records,
          regionOutcomes: outcomes,
          remainingBudgetOf: () => const Duration(seconds: 60),
          sendStructureRequest: send ?? _failIfCalled,
        ),
      )
      .then((value) => value as StructureResult);
}

Future<RecognitionStructureResponse?> _failIfCalled(
  RecognitionStructureRequest request,
) async {
  throw StateError('未触发结构请求时不应派发');
}

class RegionSpec {
  const RegionSpec({
    required this.regionId,
    required this.top,
    required this.left,
    this.text,
    this.width = 200,
    this.lineHeight = 20,
  });

  final String regionId;
  final double top;
  final double left;
  final String? text;
  final double width;
  final double lineHeight;
}
