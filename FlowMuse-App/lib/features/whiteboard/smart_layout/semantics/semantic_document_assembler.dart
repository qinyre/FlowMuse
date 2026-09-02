import '../protocol/smart_layout_v3_response.dart';
import '../snapshot/layout_page_snapshot.dart';
import '../snapshot/source_coverage_ledger.dart';
import 'semantic_document.dart';

/// 装配结果：文档 + 推进后的唯一 ledger。
class SemanticAssembly {
  const SemanticAssembly({required this.document, required this.ledger});

  final SemanticDocument document;
  final SourceCoverageLedger ledger;
}

/// 语义文档装配器（V3-204A）：只投影并校验快照的唯一 source ledger。
///
/// - 每个 region → SemanticBlock（role/sourceIds/orderIndex/confidence）；
/// - typed text 只回填自快照对象 exactText（不来自模型）；
/// - 手写转写文本经 [transcribedTextByRegion]（本地 map，不经网络协议）
///   进入块 extras：仅在 region 无 typed exactText 时回填，绝不覆盖
///   打字文本；悬空 regionId（缓存串会话/旧响应）fail closed；
/// - unknown 块的 source 一律 preserved（默认不参与自动重排）；
/// - 未被任何 region 认领的 source → preserved；
/// - 装配失败（悬空 source/ledger 不守恒）抛 StateError，不产出半文档。
class SemanticDocumentAssembler {
  const SemanticDocumentAssembler();

  SemanticAssembly assemble({
    required LayoutPageSnapshot snapshot,
    required SmartLayoutV3Response response,
    List<RawConflict> conflicts = const [],
    Map<String, String> transcribedTextByRegion = const {},
  }) {
    if (transcribedTextByRegion.isNotEmpty) {
      final regionIds = {for (final region in response.regions) region.id};
      final dangling = <String>[
        for (final id in transcribedTextByRegion.keys)
          if (!regionIds.contains(id)) id,
      ]..sort();
      if (dangling.isNotEmpty) {
        throw StateError('转写缓存引用了响应不存在的 region: ${dangling.join(',')}');
      }
    }
    final exactTextBySource = <String, String>{};
    for (final object in snapshot.objects) {
      if (object.exactText != null) {
        exactTextBySource[object.sourceId] = object.exactText!;
      }
    }
    final blocks = <SemanticBlock>[];
    final consumedIds = <String>[];
    final preservedIds = <String>[];

    // region → block；先校验悬空，再推进 ledger。
    for (final region in response.regions) {
      for (final sourceId in region.sourceIds) {
        if (!_snapshotHas(snapshot, sourceId)) {
          throw StateError('分析区域引用了快照不存在的 source: $sourceId');
        }
      }
      final role = SemanticRole.fromWireName(region.role.wireName);
      final textParts = [
        for (final sourceId in region.sourceIds)
          if (exactTextBySource[sourceId] != null) exactTextBySource[sourceId]!,
      ];
      // 手写转写（本地 map）：仅在无 typed exactText 时回填到 extras，
      // 由 LayoutBlockAssembler 投影为 LayoutTextOrigin.transcribed；
      // 空白转写不生成文本（不伪造）。
      final extras = <String, Object?>{};
      if (textParts.isEmpty) {
        final transcribed = transcribedTextByRegion[region.id]?.trim();
        if (transcribed != null && transcribed.isNotEmpty) {
          extras['transcribedText'] = transcribed;
        }
      }
      blocks.add(
        SemanticBlock(
          id: region.id,
          role: role,
          sourceIds: List.unmodifiable(region.sourceIds),
          orderIndex: region.readingOrder,
          confidence: region.confidence,
          text: textParts.isEmpty ? null : textParts.join('\n'),
          extras: Map.unmodifiable(extras),
        ),
      );
      if (role.defaultsToPreserved) {
        // unknown 默认 preserved：source 保持原位语义。
        preservedIds.addAll(region.sourceIds);
      } else {
        consumedIds.addAll(region.sourceIds);
      }
    }

    // 未认领 source → preserved；终态集合先算全并去重，再单次推进。
    final consumedSet = <String>{...consumedIds};
    final preservedSet = <String>{...preservedIds};
    for (final object in snapshot.objects) {
      if (!consumedSet.contains(object.sourceId) &&
          !preservedSet.contains(object.sourceId)) {
        preservedSet.add(object.sourceId);
      }
    }
    for (final stroke in snapshot.inkStrokes) {
      if (!consumedSet.contains(stroke.sourceId) &&
          !preservedSet.contains(stroke.sourceId)) {
        preservedSet.add(stroke.sourceId);
      }
    }
    final overlap = consumedSet.intersection(preservedSet);
    if (overlap.isNotEmpty) {
      throw StateError('source 双终态冲突: ${overlap.toList()..sort()}');
    }
    var ledger = snapshot.sourceCoverage;
    final consumedSorted = consumedSet.toList()..sort();
    final preservedSorted = preservedSet.toList()..sort();
    ledger = ledger.markConsumed(consumedSorted);
    ledger = ledger.markPreserved(preservedSorted);
    if (!ledger.isFinalized) {
      throw StateError('ledger 未闭合：剩余 ${ledger.pendingCount} 个 pending');
    }
    // 守恒校验：文档侧集合与 ledger 推进结果重算一致。
    final documentConsumed =
        ledger.statuses.entries
            .where((e) => e.value == SourceCoverageStatus.consumed)
            .map((e) => e.key)
            .toList()
          ..sort();
    final documentPreserved =
        ledger.statuses.entries
            .where((e) => e.value == SourceCoverageStatus.preserved)
            .map((e) => e.key)
            .toList()
          ..sort();
    if (!_listEqStr(documentConsumed, consumedSorted) ||
        !_listEqStr(documentPreserved, preservedSorted)) {
      throw StateError('文档 ledger 集合与推进结果不一致');
    }

    // 阅读序：按 orderIndex 稳定排序（orderIndex 已是排列——协议保证）。
    final orderedBlocks = [...blocks]
      ..sort(
        (a, b) =>
            a.orderIndex.compareTo(b.orderIndex) * 1000 + a.id.compareTo(b.id),
      );
    final document = SemanticDocument(
      formatVersion: SemanticDocumentFormat.currentVersion,
      pageId: snapshot.pageId,
      epoch: snapshot.sceneRevision.epoch,
      revision: snapshot.sceneRevision.revision,
      fingerprint: snapshot.sceneRevision.fingerprint.value,
      blocks: List.unmodifiable(blocks..sort((a, b) => a.id.compareTo(b.id))),
      readingOrder: SemanticReadingOrder(
        orderedBlockIds: List.unmodifiable([
          for (final block in orderedBlocks) block.id,
        ]),
      ),
      conflicts: List.unmodifiable([
        for (final conflict in conflicts)
          SemanticConflict(
            regionId: conflict.regionId,
            kind: conflict.kind,
            overview: conflict.overview,
            crop: conflict.crop,
          ),
      ]),
      consumedSourceIds: List.unmodifiable(documentConsumed),
      preservedSourceIds: List.unmodifiable(documentPreserved),
    );
    if (!document.ledgerConserved) {
      throw StateError('文档 ledger 不守恒');
    }
    return SemanticAssembly(document: document, ledger: ledger);
  }

  static bool _snapshotHas(LayoutPageSnapshot snapshot, String sourceId) {
    for (final object in snapshot.objects) {
      if (object.sourceId == sourceId) return true;
    }
    for (final stroke in snapshot.inkStrokes) {
      if (stroke.sourceId == sourceId) return true;
    }
    return false;
  }

}

/// 装配输入的冲突留档（总览/crop 分歧原样进入文档）。
class RawConflict {
  const RawConflict({
    required this.regionId,
    required this.kind,
    required this.overview,
    required this.crop,
  });

  final String regionId;
  final String kind;
  final String overview;
  final String crop;
}

bool _listEqStr(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
