import 'dart:convert';

import '../recognition/recognition_models.dart';
import '../snapshot/deterministic_hash.dart';
import 'semantic_document.dart';

/// composition extras 的唯一读写口。复用 wire 值对象，ID 在本代次直接引用块。
/// 原文只保留指纹；角色/正文/图注仍来自同一 SemanticDocument。
class SemanticComposition {
  const SemanticComposition({
    required this.hints,
    required this.textFingerprints,
    this.analyzed = false,
  });

  static const version = 'semantic-composition/1';
  final RecognitionCompositionHints hints;
  final Map<String, String> textFingerprints;
  final bool analyzed;

  static SemanticComposition? of(SemanticDocument document) {
    final value = document.extras['composition'];
    if (value == null) return null;
    if (value is! Map ||
        value['version'] != version ||
        value['analyzed'] is! bool ||
        value['textFingerprints'] is! Map ||
        value.keys.any(
          (k) => !const {
            'version',
            'hints',
            'textFingerprints',
            'analyzed',
          }.contains(k),
        )) {
      throw const FormatException('invalid-semantic-composition');
    }
    final fingerprints = Map<String, String>.from(
      value['textFingerprints'] as Map,
    );
    final hints = RecognitionCompositionHints.fromJson(value['hints']);
    if (fingerprints.length != hints.softLineBreaks.length ||
        hints.softLineBreaks.any((b) => !fingerprints.containsKey(b.unitId))) {
      throw const FormatException('missing-soft-break-fingerprint');
    }
    return SemanticComposition(
      hints: hints,
      textFingerprints: Map.unmodifiable(fingerprints),
      analyzed: value['analyzed'] as bool,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'hints': hints.toJson(),
    'textFingerprints': {...textFingerprints},
    'analyzed': analyzed,
  };

  /// 消费前集中验证，过期软换行失效，不允许重新绑定到修改后的正文。
  void validate(SemanticDocument document) {
    final units = <RecognitionUnitInput>[];
    final roles = <String, String>{};
    for (final b in document.blocks) {
      final text = b.text ?? b.extras['transcribedText'] as String?;
      final kind = b.role == SemanticRole.figure
          ? RecognitionUnitKind.figure
          : b.role == SemanticRole.unknown || text == null
          ? RecognitionUnitKind.preserved
          : b.text != null
          ? RecognitionUnitKind.typed
          : RecognitionUnitKind.ink;
      if (kind == RecognitionUnitKind.ink ||
          kind == RecognitionUnitKind.typed) {
        roles[b.id] = b.role == SemanticRole.list
            ? 'listItem'
            : b.role.wireName;
      }
      units.add(
        RecognitionUnitInput(
          unitId: b.id,
          kind: kind,
          text:
              kind == RecognitionUnitKind.typed ||
                  kind == RecognitionUnitKind.ink
              ? text
              : null,
          bounds: const RecognitionBounds(left: 0, top: 0, width: 0, height: 0),
        ),
      );
    }
    for (final b in hints.softLineBreaks) {
      final block = document.blocks.where((e) => e.id == b.unitId).firstOrNull;
      if (block == null ||
          textFingerprints[b.unitId] !=
              fingerprint64(block.extras['transcribedText'] as String? ?? '')) {
        throw const FormatException('stale-soft-line-break');
      }
    }
    final groups = <String, List<SemanticBlock>>{};
    for (final b in document.blocks.where((b) => b.role == SemanticRole.list)) {
      final id = b.extras['listGroupId'];
      if (id is String) groups.putIfAbsent(id, () => []).add(b);
    }
    hints.validate(
      units: units,
      readingOrder: document.readingOrder.orderedBlockIds,
      roles: roles,
      hasOverview: true, // 已协商准入或用户显式纠错；此处不触发网络。
      listGroups: [
        for (final g in groups.entries)
          RecognitionListGroup(
            groupId: g.key,
            members: g.value.map((b) => b.id).toList(),
            level: g.value.first.extras['level'] as int? ?? 1,
            parentUnitId: g.value.first.extras['parentUnitId'] as String?,
            listType: RecognitionListType.unordered,
          ),
      ],
      captions: [
        for (final b in document.blocks)
          if (b.role == SemanticRole.caption && b.extras['captionOf'] is String)
            RecognitionCaption(
              captionUnitId: b.id,
              targetUnitId: b.extras['captionOf'] as String,
            ),
      ],
    );
  }

  /// 角色/保留/文字改变只撤销受影响的建议，绝不把旧索引套到新文字上。
  SemanticComposition reconcile(
    List<SemanticBlock> blocks, {
    Set<String> invalidatedTextIds = const {},
  }) {
    final byId = {for (final b in blocks) b.id: b};
    final soft = hints.softLineBreaks.where((b) {
      final block = byId[b.unitId];
      return !invalidatedTextIds.contains(b.unitId) &&
          block != null &&
          block.text == null &&
          const {
            SemanticRole.title,
            SemanticRole.body,
            SemanticRole.caption,
          }.contains(block.role) &&
          textFingerprints[b.unitId] ==
              fingerprint64(block.extras['transcribedText'] as String? ?? '');
    }).toList();
    return SemanticComposition(
      analyzed: analyzed,
      hints: RecognitionCompositionHints(
        pageIntent: hints.pageIntent,
        sections: hints.sections
            .where(
              (s) =>
                  byId[s.headingUnitId]?.role == SemanticRole.title &&
                  s.memberUnitIds.every(
                    (id) =>
                        byId.containsKey(id) &&
                        byId[id]!.role != SemanticRole.title,
                  ),
            )
            .toList(),
        mediaGroups: hints.mediaGroups
            .where(
              (g) =>
                  g.figureUnitIds.every(
                    (id) => byId[id]?.role == SemanticRole.figure,
                  ) &&
                  g.textUnitIds.every(
                    (id) => const {
                      SemanticRole.body,
                      SemanticRole.list,
                    }.contains(byId[id]?.role),
                  ),
            )
            .toList(),
        softLineBreaks: soft,
      ),
      textFingerprints: {
        for (final b in soft) b.unitId: textFingerprints[b.unitId]!,
      },
    );
  }

  static String groupId(Iterable<String> ids) =>
      'media-${fingerprint64(jsonEncode(ids.toList()..sort()))}';

  /// 关系编辑以整组为单位，适用于一文多图，不再写 relatedFigure 副本。
  List<({String type, String targetBlockId})> relationsOf(String blockId) {
    final g = hints.mediaGroups
        .where((g) => [...g.figureUnitIds, ...g.textUnitIds].contains(blockId))
        .firstOrNull;
    if (g == null) return const [];
    return [
      for (final id in [...g.figureUnitIds, ...g.textUnitIds])
        if (id != blockId) (type: 'mediaGroup', targetBlockId: id),
    ];
  }

  SemanticComposition setMediaRelations(
    String blockId,
    List<({String type, String targetBlockId})> relations,
    List<SemanticBlock> blocks,
  ) {
    if (relations.any((r) => r.type != 'mediaGroup') ||
        relations.any((r) => r.targetBlockId == blockId) ||
        relations.map((r) => r.targetBlockId).toSet().length !=
            relations.length) {
      throw const FormatException('invalid-media-relations');
    }
    final ids = {blockId, ...relations.map((r) => r.targetBlockId)};
    final byId = {for (final b in blocks) b.id: b};
    final figures = ids
        .where((id) => byId[id]?.role == SemanticRole.figure)
        .toList();
    final texts = ids
        .where(
          (id) => const {
            SemanticRole.body,
            SemanticRole.list,
          }.contains(byId[id]?.role),
        )
        .toList();
    if (relations.isNotEmpty &&
        (figures.isEmpty ||
            texts.isEmpty ||
            figures.length + texts.length != ids.length)) {
      throw const FormatException('invalid-media-members');
    }
    final groups = [
      for (final g in hints.mediaGroups)
        if (![...g.figureUnitIds, ...g.textUnitIds].any(ids.contains)) g,
    ];
    if (relations.isNotEmpty) {
      groups.add(
        RecognitionMediaGroup(
          groupId: groupId(ids),
          figureUnitIds: figures,
          textUnitIds: texts,
          confidence: 1,
        ),
      );
    }
    return SemanticComposition(
      analyzed: analyzed,
      textFingerprints: textFingerprints,
      hints: RecognitionCompositionHints(
        pageIntent: hints.pageIntent,
        sections: hints.sections,
        mediaGroups: groups,
        softLineBreaks: hints.softLineBreaks,
      ),
    );
  }
}
