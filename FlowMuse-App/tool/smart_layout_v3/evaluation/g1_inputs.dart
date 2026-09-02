import 'dart:convert';
import 'dart:io';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/ink_region_segmenter.dart';

/// G1 评测输入装载（V3-206A）：样本/标注/id 映射/split。
///
/// 数据链（全部只读）：
/// - datasets/synthetic-pool-v2/samples/*.scene.json（85 样本）
/// - datasets/annotations/adjudicated-labels.json（85 样本 roles/order/relations）
/// - datasets/annotations/projections/id-mapping.json（e01→真实元素 id）
/// - datasets/splits/{development,validation}/manifest.json
class G1Inputs {
  G1Inputs._({
    required this.samplesById,
    required this.labelsBySample,
    required this.idMappingBySample,
    required this.devSampleIds,
    required this.validationSampleIds,
  });

  final Map<String, G1SceneSample> samplesById;
  final Map<String, G1Annotation> labelsBySample;
  final Map<String, Map<String, String>> idMappingBySample;
  final List<String> devSampleIds;
  final List<String> validationSampleIds;

  /// 证据根目录（相对 FlowMuse-App 执行目录）。
  static const evidenceRoot = '../docs/研发记录/evidence/smart-layout-v3';

  static G1Inputs load({String root = evidenceRoot}) {
    final samplesDir = Directory('$root/datasets/synthetic-pool-v2/samples');
    final samplesById = <String, G1SceneSample>{};
    for (final file in samplesDir.listSync().whereType<File>()) {
      final stem = file.path.split(Platform.pathSeparator).last;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      json['_file_stem'] = stem.replaceAll('.scene.json', '');
      final sample = G1SceneSample.fromJson(json);
      samplesById[sample.sampleId] = sample;
    }
    final labels =
        jsonDecode(
              File(
                '$root/datasets/annotations/adjudicated-labels.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final labelsBySample = <String, G1Annotation>{};
    for (final raw in labels['annotations'] as List) {
      final annotation = G1Annotation.fromJson(raw as Map<String, Object?>);
      labelsBySample[annotation.sampleId] = annotation;
    }
    final mapping =
        jsonDecode(
              File(
                '$root/datasets/annotations/projections/id-mapping.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final idMappingBySample = <String, Map<String, String>>{};
    for (final raw in mapping['samples'] as List) {
      final record = raw as Map<String, Object?>;
      final sampleId = record['sample_id'] as String;
      idMappingBySample[sampleId] = {
        for (final entry
            in (record['element_ids'] as Map<String, Object?>).entries)
          entry.key: entry.value as String,
      };
    }

    List<String> splitIds(String name) {
      final manifest =
          jsonDecode(
                File(
                  '$root/datasets/splits/$name/manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      return [
        for (final raw in manifest['samples'] as List)
          (raw as Map<String, Object?>)['sample_id'] as String,
      ];
    }

    return G1Inputs._(
      samplesById: samplesById,
      labelsBySample: labelsBySample,
      idMappingBySample: idMappingBySample,
      devSampleIds: splitIds('development'),
      validationSampleIds: splitIds('validation'),
    );
  }
}

class G1SceneSample {
  G1SceneSample({
    required this.sampleId,
    required this.strokes,
    required this.elementTypeById,
  });

  factory G1SceneSample.fromJson(Map<String, Object?> json) {
    final fileStem = json['_file_stem'] as String? ?? '';
    return G1SceneSample(
      sampleId: fileStem,
      strokes: [
        for (final raw in json['elements'] as List)
          if ((raw as Map<String, Object?>)['type'] == 'stroke') raw,
      ],
      elementTypeById: {
        for (final raw in json['elements'] as List)
          ((raw as Map<String, Object?>)['id'] as String):
              raw['type'] as String,
      },
    );
  }

  /// 原始 stroke 元素（保持 JSON 形态，评测侧转 FreedrawElement）。
  final List<Map<String, Object?>> strokes;
  final Map<String, String> elementTypeById;
  final String sampleId;

  List<FreedrawElement> toFreedrawElements() => [
    for (final stroke in strokes)
      FreedrawElement(
        id: ElementId(stroke['id'] as String),
        x: ((stroke['bbox'] as List)[0] as num).toDouble(),
        y: ((stroke['bbox'] as List)[1] as num).toDouble(),
        width: ((stroke['bbox'] as List)[2] as num).toDouble(),
        height: ((stroke['bbox'] as List)[3] as num).toDouble(),
        points: [
          for (final point in stroke['points'] as List)
            Point(
              ((point as List)[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ),
        ],
        pressures: [
          if (stroke['pressure'] is List)
            for (final value in stroke['pressure'] as List)
              (value as num).toDouble(),
        ],
      ),
  ];
}

class G1Annotation {
  G1Annotation({
    required this.sampleId,
    required this.readingOrder,
    required this.roles,
    required this.relations,
  });

  factory G1Annotation.fromJson(Map<String, Object?> json) => G1Annotation(
    sampleId: json['sample_id'] as String,
    readingOrder: [
      for (final id in json['reading_order'] as List) id as String,
    ],
    roles: {
      for (final entry in (json['roles'] as Map<String, Object?>).entries)
        entry.key: entry.value as String,
    },
    relations: [
      if (json['relations'] is List)
        for (final raw in json['relations'] as List)
          raw as Map<String, Object?>,
    ],
  );

  final String sampleId;

  /// 标注元素 id（e01…）的阅读序。
  final List<String> readingOrder;

  /// e-id → role（handwriting/paragraph/title…）。
  final Map<String, String> roles;
  final List<Map<String, Object?>> relations;

  /// 期望分组（区域 ground truth，e-id 形态）：
  /// - reading_order 非空 → 同 role 连续段；
  /// - reading_order 为空（15/85 样本）→ 按 role 全集聚类兜底；
  /// - [strokeOnly] 提供元素类型映射时过滤为纯笔画（预测侧只见笔画，
  ///   image/figure 期望对会虚增 FN）。
  List<List<String>> expectedGroups({Map<String, String>? strokeOnly}) {
    List<List<String>> raw;
    if (readingOrder.isNotEmpty) {
      raw = <List<String>>[];
      String? previousRole;
      for (final elementId in readingOrder) {
        final role = roles[elementId] ?? 'unknown';
        if (role != previousRole || raw.isEmpty) {
          raw.add([elementId]);
          previousRole = role;
        } else {
          raw.last.add(elementId);
        }
      }
    } else {
      final byRole = <String, List<String>>{};
      for (final elementId in roles.keys) {
        byRole
            .putIfAbsent(roles[elementId] ?? 'unknown', () => [])
            .add(elementId);
      }
      raw = [for (final role in byRole.keys.toList()..sort()) byRole[role]!];
    }
    if (strokeOnly == null) {
      return raw;
    }
    return [
      for (final group in raw)
        if (group.any((id) => strokeOnly[id] == 'stroke'))
          [
            for (final id in group)
              if (strokeOnly[id] == 'stroke') id,
          ],
    ].where((group) => group.isNotEmpty).toList();
  }
}

/// 在样本上运行确定性分割，返回预测分组（真实元素 id）。
List<List<String>> segmentSample(G1SceneSample sample) {
  final elements = sample.toFreedrawElements();
  if (elements.isEmpty) return const [];
  final segments = InkRegionSegmenter().segment(elements);
  return [for (final segment in segments) segment.strokeIds];
}
