part of 'recognition_models.dart';

/// 同轮结构扩展。只引用 unitId（进入语义文档后就是 blockId），不拥有正文。
class RecognitionCompositionHints {
  const RecognitionCompositionHints({
    this.pageIntent = 'unknown',
    this.sections = const [],
    this.mediaGroups = const [],
    this.softLineBreaks = const [],
  });

  static const version = 'composition-hints/1';
  final String pageIntent;
  final List<RecognitionSectionHint> sections;
  final List<RecognitionMediaGroup> mediaGroups;
  final List<RecognitionSoftBreak> softLineBreaks;

  factory RecognitionCompositionHints.fromJson(Object? value) {
    const r = RecognitionJsonReader(RecognitionParseSide.response);
    final m = r.object(value, 'compositionHints', const {
      'version',
      'pageIntent',
      'sections',
      'mediaGroups',
      'softLineBreaks',
    });
    if (m['version'] != version ||
        !const {
          'reading',
          'comparison',
          'mixed',
          'unknown',
        }.contains(m['pageIntent'])) {
      r.invalid('compositionHints', '版本或页面意图非法');
    }
    String id(Map<String, Object?> m, String key) {
      final v = r.string(m, key, 'compositionHints');
      if (v.trim().isEmpty || v.runes.length > 64) r.invalid(key, 'ID非法');
      return v;
    }

    List<String> ids(Map<String, Object?> m, String key) {
      final raw = r.list(m, key, 'compositionHints');
      if (raw.isEmpty ||
          raw.length > 128 ||
          raw.any(
            (v) => v is! String || v.trim().isEmpty || v.runes.length > 64,
          )) {
        r.invalid(key, '成员必须为非空ID数组且不超过128');
      }
      final out = raw.cast<String>();
      r.unique(out, key, '成员');
      return List.unmodifiable(out);
    }

    List<Object?> entries(String key) {
      final list = r.list(m, key, 'compositionHints');
      if (list.length > 128) r.invalid(key, '超过128');
      return list;
    }

    final sections = <RecognitionSectionHint>[];
    for (final raw in entries('sections')) {
      final s = r.object(raw, 'sections', const {
        'sectionId',
        'headingUnitId',
        'memberUnitIds',
      });
      sections.add(
        RecognitionSectionHint(
          sectionId: id(s, 'sectionId'),
          headingUnitId: id(s, 'headingUnitId'),
          memberUnitIds: ids(s, 'memberUnitIds'),
        ),
      );
    }
    final media = <RecognitionMediaGroup>[];
    for (final raw in entries('mediaGroups')) {
      final g = r.object(raw, 'mediaGroups', const {
        'groupId',
        'figureUnitIds',
        'textUnitIds',
        'confidence',
      });
      media.add(
        RecognitionMediaGroup(
          groupId: id(g, 'groupId'),
          figureUnitIds: ids(g, 'figureUnitIds'),
          textUnitIds: ids(g, 'textUnitIds'),
          confidence: r.unitInterval(g, 'confidence', 'mediaGroups'),
        ),
      );
    }
    final breaks = <RecognitionSoftBreak>[];
    for (final raw in entries('softLineBreaks')) {
      final b = r.object(raw, 'softLineBreaks', const {
        'unitId',
        'newlineIndexes',
        'confidence',
      });
      final indexes = r.list(b, 'newlineIndexes', 'softLineBreaks');
      var last = -1;
      if (indexes.isEmpty || indexes.length > 2000) {
        r.invalid('newlineIndexes', '换行编号为空或过多');
      }
      for (final index in indexes) {
        if (index is! int || index <= last) {
          r.invalid('newlineIndexes', '编号必须递增且非负');
        }
        last = index;
      }
      breaks.add(
        RecognitionSoftBreak(
          unitId: id(b, 'unitId'),
          newlineIndexes: List.unmodifiable(indexes.cast<int>()),
          confidence: r.unitInterval(b, 'confidence', 'softLineBreaks'),
        ),
      );
    }
    r.unique(sections.map((s) => s.sectionId), 'sections', 'sectionId');
    r.unique(media.map((g) => g.groupId), 'mediaGroups', 'groupId');
    r.unique(breaks.map((b) => b.unitId), 'softLineBreaks', 'unitId');
    return RecognitionCompositionHints(
      pageIntent: m['pageIntent']! as String,
      sections: List.unmodifiable(sections),
      mediaGroups: List.unmodifiable(media),
      softLineBreaks: List.unmodifiable(breaks),
    );
  }

  /// 网络与纠错共用关系校验；无请求上下文时仍检查角色/成员/顺序。
  void validate({
    List<RecognitionUnitInput>? units,
    required List<String> readingOrder,
    required Map<String, String> roles,
    required List<RecognitionListGroup> listGroups,
    required List<RecognitionCaption> captions,
    required bool hasOverview,
  }) {
    const r = RecognitionJsonReader(RecognitionParseSide.response);
    Never fail() => r.invalid('compositionHints', '角色、成员或连续性无效');
    final byId = {
      for (final u in units ?? <RecognitionUnitInput>[]) u.unitId: u,
    };
    final positions = {
      for (var i = 0; i < readingOrder.length; i++) readingOrder[i]: i,
    };
    final subtrees = <Set<String>>[];
    for (final root in listGroups) {
      final set = root.members.toSet();
      for (var i = 0; i < listGroups.length; i++) {
        for (final child in listGroups) {
          if (set.contains(child.parentUnitId)) set.addAll(child.members);
        }
      }
      if (set.any((id) => roles[id] != 'listItem')) fail();
      subtrees.add(set);
    }
    void continuous(List<String> ids) {
      final set = ids.toSet();
      if (ids.isEmpty ||
          ids.length != set.length ||
          ids.any((id) => !positions.containsKey(id))) {
        fail();
      }
      final indices = ids.map((id) => positions[id]!).toList()..sort();
      if (indices.last - indices.first + 1 != ids.length) fail();
      for (final subtree in subtrees) {
        final hits = set.intersection(subtree).length;
        if (hits != 0 && hits != subtree.length) fail();
      }
    }

    final sectionOf = <String, String>{};
    for (final s in sections) {
      if (roles[s.headingUnitId] != 'title' || s.memberUnitIds.isEmpty) fail();
      final ids = [s.headingUnitId, ...s.memberUnitIds];
      continuous(ids);
      var last = positions[s.headingUnitId]!;
      for (final id in s.memberUnitIds) {
        if (positions[id]! <= last || roles[id] == 'title') fail();
        last = positions[id]!;
      }
      for (final id in ids) {
        if (sectionOf.containsKey(id)) fail();
        sectionOf[id] = s.sectionId;
      }
    }
    final captionOf = <String, String>{};
    for (final c in captions) {
      if (roles[c.captionUnitId] != 'caption' ||
          !positions.containsKey(c.targetUnitId) ||
          captionOf.containsKey(c.captionUnitId) ||
          sectionOf[c.captionUnitId] != sectionOf[c.targetUnitId] ||
          (units != null &&
              !const {
                RecognitionUnitKind.figure,
                RecognitionUnitKind.preserved,
              }.contains(byId[c.targetUnitId]?.kind))) {
        fail();
      }
      captionOf[c.captionUnitId] = c.targetUnitId;
    }
    if (roles.entries.any(
      (e) => e.value == 'caption' && !captionOf.containsKey(e.key),
    )) {
      fail();
    }
    final owners = <String>{};
    for (final g in mediaGroups) {
      if (!hasOverview ||
          g.figureUnitIds.isEmpty ||
          g.textUnitIds.isEmpty ||
          !g.confidence.isFinite ||
          g.confidence < 0 ||
          g.confidence > 1 ||
          g.figureUnitIds.any(
            (id) => units != null
                ? byId[id]?.kind != RecognitionUnitKind.figure
                : roles.containsKey(id),
          ) ||
          g.textUnitIds.any(
            (id) => roles[id] != 'body' && roles[id] != 'listItem',
          )) {
        fail();
      }
      final ids = [
        ...g.figureUnitIds,
        ...g.textUnitIds,
        for (final c in captions)
          if (g.figureUnitIds.contains(c.targetUnitId)) c.captionUnitId,
      ];
      continuous(ids);
      for (final id in ids) {
        if (!owners.add(id) || sectionOf[id] != sectionOf[ids.first]) fail();
      }
    }
    for (final target in captionOf.values.toSet()) {
      if (owners.contains(target)) continue;
      continuous([
        target,
        for (final c in captions)
          if (c.targetUnitId == target) c.captionUnitId,
      ]);
    }
    for (final b in softLineBreaks) {
      if (!const {'title', 'body', 'caption'}.contains(roles[b.unitId])) fail();
      if (units == null) continue;
      final u = byId[b.unitId];
      if (u?.kind != RecognitionUnitKind.ink || u?.text == null) fail();
      final lines = u!.text!.split('\n');
      for (final index in b.newlineIndexes) {
        if (index < 0 ||
            index + 1 >= lines.length ||
            lines[index].trim().isEmpty ||
            lines[index + 1].trim().isEmpty) {
          fail();
        }
      }
    }
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'pageIntent': pageIntent,
    'sections': [for (final s in sections) s.toJson()],
    'mediaGroups': [for (final g in mediaGroups) g.toJson()],
    'softLineBreaks': [for (final b in softLineBreaks) b.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionCompositionHints &&
      pageIntent == other.pageIntent &&
      _listEq(sections, other.sections) &&
      _listEq(mediaGroups, other.mediaGroups) &&
      _listEq(softLineBreaks, other.softLineBreaks);
  @override
  int get hashCode => Object.hash(
    pageIntent,
    sections.length,
    mediaGroups.length,
    softLineBreaks.length,
  );
}

class RecognitionSectionHint {
  const RecognitionSectionHint({
    required this.sectionId,
    required this.headingUnitId,
    required this.memberUnitIds,
  });
  final String sectionId;
  final String headingUnitId;
  final List<String> memberUnitIds;
  Map<String, Object?> toJson() => {
    'sectionId': sectionId,
    'headingUnitId': headingUnitId,
    'memberUnitIds': [...memberUnitIds],
  };
  @override
  bool operator ==(Object other) =>
      other is RecognitionSectionHint &&
      sectionId == other.sectionId &&
      headingUnitId == other.headingUnitId &&
      _listEq(memberUnitIds, other.memberUnitIds);
  @override
  int get hashCode =>
      Object.hash(sectionId, headingUnitId, memberUnitIds.length);
}

class RecognitionMediaGroup {
  const RecognitionMediaGroup({
    required this.groupId,
    required this.figureUnitIds,
    required this.textUnitIds,
    required this.confidence,
  });
  final String groupId;
  final List<String> figureUnitIds;
  final List<String> textUnitIds;
  final double confidence;
  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'figureUnitIds': [...figureUnitIds],
    'textUnitIds': [...textUnitIds],
    'confidence': confidence,
  };
  @override
  bool operator ==(Object other) =>
      other is RecognitionMediaGroup &&
      groupId == other.groupId &&
      confidence == other.confidence &&
      _listEq(figureUnitIds, other.figureUnitIds) &&
      _listEq(textUnitIds, other.textUnitIds);
  @override
  int get hashCode => Object.hash(groupId, confidence);
}

class RecognitionSoftBreak {
  const RecognitionSoftBreak({
    required this.unitId,
    required this.newlineIndexes,
    required this.confidence,
  });
  final String unitId;
  final List<int> newlineIndexes;
  final double confidence;
  Map<String, Object?> toJson() => {
    'unitId': unitId,
    'newlineIndexes': [...newlineIndexes],
    'confidence': confidence,
  };
  @override
  bool operator ==(Object other) =>
      other is RecognitionSoftBreak &&
      unitId == other.unitId &&
      confidence == other.confidence &&
      _listEq(newlineIndexes, other.newlineIndexes);
  @override
  int get hashCode => Object.hash(unitId, confidence);
}
