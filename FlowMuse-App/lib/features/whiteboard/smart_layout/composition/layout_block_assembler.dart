import 'dart:ui' as ui;

import '../design/smart_layout_design_tokens.dart';

import '../design/text_measure_adapter.dart';
import '../semantics/semantic_document.dart';
import '../snapshot/layout_page_snapshot.dart';
import 'layout_block.dart';

/// 组装结果（V3-400A）：blocks（阅读序）+ 关系 + 原子组 + ledger 复核。
class LayoutBlockAssembly {
  const LayoutBlockAssembly({
    required this.blocks,
    required this.relationships,
    required this.atomicGroups,
    required this.documentConsumedSourceIds,
    required this.documentPreservedSourceIds,
  });

  final List<LayoutBlock> blocks;
  final List<BlockRelationship> relationships;

  /// 关系连通分量（captionOf/keepWith 并查集）：同组块在流式排版中
  /// 不可拆开（V3-402A keep 契约的输入）。
  final List<List<String>> atomicGroups;

  final List<String> documentConsumedSourceIds;
  final List<String> documentPreservedSourceIds;

  /// ledger 守恒复核：块 sourceRefs 总并集恰等于文档 ledger，
  /// 无重叠、无遗漏（每源恰好出现在一个块）。
  bool get ledgerConserved {
    final seen = <String>{};
    var consumedSeen = 0;
    var preservedSeen = 0;
    for (final block in blocks) {
      for (final ref in block.sourceRefs) {
        if (!seen.add(ref)) return false;
      }
      if (block.isPreservedLike) {
        preservedSeen += block.sourceRefs.length;
      } else {
        consumedSeen += block.sourceRefs.length;
      }
    }
    final consumedSet = documentConsumedSourceIds.toSet();
    final preservedSet = documentPreservedSourceIds.toSet();
    return seen.length ==
            consumedSet.length + preservedSet.length &&
        consumedSeen == consumedSet.length &&
        preservedSeen == preservedSet.length &&
        seen.containsAll(consumedSet) &&
        seen.containsAll(preservedSet);
  }

  LayoutBlock? blockById(String id) {
    for (final block in blocks) {
      if (block.id == id) return block;
    }
    return null;
  }
}

/// 排版输出字体族（冻结决策）：bundled 手写风字体 `Excalifont`——
/// FontResolver 资产路径，测量（TextMeasureAdapter）与渲染
/// （TextRenderer）在任何环境同步同路径；GoogleFonts 族（Nunito 等）
/// 运行时抓取在离线环境不可用，不得进入排版测量链路。
const String kLayoutFontFamily = 'Excalifont';

/// SemanticDocument + 快照 → 排版块（V3-400A）。
///
/// - role→kind 投影：title/body/list/caption/figure/formula/table 直映，
///   unknown → preserved（不参与自动重排）。
/// - 文本三态：text 字段（快照 exactText）→ typed；
///   extras['transcribedText'] → transcribed；两者都缺的语义文本块
///   保持可追溯但不生成测量（缺文本不造数据）。
/// - figure：sourceIds 在快照中的 image 对象提供 fileId/crop/内在尺寸，
///   显示比例 = intrinsic.w·crop.w / intrinsic.h·crop.h；资产缺失记事实。
/// - protected：快照 mobility=protectedObstacle 的对象投影为绕置障碍块；
///   其 ledger 态必须已是 preserved（锁定物不可被消费），违例抛错。
/// - caption 绑定阅读序最近前驱 figure；标题 keepWith 后继首块
///   （section 语义）。
/// - 真实测量：文本块 intrinsic（不限宽）由注入的 [TextMeasureAdapter]
///   计算——禁止估算，测量失败抛错（fail closed）而非返回猜值。
class LayoutBlockAssembler {
  const LayoutBlockAssembler();

  LayoutBlockAssembly assemble({
    required SemanticDocument document,
    required LayoutPageSnapshot snapshot,
    required TextMeasureAdapter measure,
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
  }) {
    final objectById = {
      for (final o in snapshot.objects) o.sourceId: o,
    };
    final preservedSet = document.preservedSourceIds.toSet();
    final consumedSet = document.consumedSourceIds.toSet();
    final blocks = <LayoutBlock>[];
    final relationships = <BlockRelationship>[];

    // 阅读序处理（readingOrder 为权威全序；缺席时按 orderIndex 排序）。
    final orderedBlocks = _orderedSemanticBlocks(document);

    for (final sb in orderedBlocks) {
      switch (sb.role) {
        case SemanticRole.figure:
          blocks.add(_figureBlock(sb, objectById, snapshot));
        case SemanticRole.caption:
          blocks.add(_textualBlock(sb, tokens, measure, forceKind: LayoutBlockKind.caption));
        case SemanticRole.title:
          blocks.add(_textualBlock(sb, tokens, measure, forceKind: LayoutBlockKind.title));
        case SemanticRole.body:
          blocks.add(_textualBlock(sb, tokens, measure, forceKind: LayoutBlockKind.paragraph));
        case SemanticRole.list:
          blocks.add(_textualBlock(sb, tokens, measure, forceKind: LayoutBlockKind.list));
        case SemanticRole.formula:
          blocks.add(_textualBlock(sb, tokens, measure, forceKind: LayoutBlockKind.formula));
        case SemanticRole.table:
          blocks.add(_textualBlock(sb, tokens, measure, forceKind: LayoutBlockKind.table));
        case SemanticRole.unknown:
          blocks.add(LayoutBlock(
            id: sb.id,
            kind: LayoutBlockKind.preserved,
            sourceRefs: List.unmodifiable(sb.sourceIds),
            orderIndex: sb.orderIndex.toDouble(),
            keepTogether: true,
            textOrigin: null,
            text: sb.text == null
                ? null
                : TextBlockSpec(
                    text: sb.text!,
                    fontFamily: kLayoutFontFamily,
                    fontSize: tokens.bodySize,
                    lineHeight: tokens.lineHeight,
                  ),
            measuredIntrinsic: null,
            extras: Map.unmodifiable(sb.extras),
          ));
      }
    }

    // protected：快照锁定障碍（绕置输入；ledger 必须已 preserved）。
    for (final object in snapshot.objects) {
      if (object.mobility != SnapshotMobility.protectedObstacle) continue;
      final ledgerPreserved = preservedSet.contains(object.sourceId);
      if (!ledgerPreserved) {
        throw StateError(
          'protected obstacle ${object.sourceId} 不在 ledger preserved——'
          '锁定物不可被消费，语义文档与快照不一致',
        );
      }
      blocks.add(LayoutBlock(
        id: 'protected-${object.sourceId}',
        kind: LayoutBlockKind.protected,
        sourceRefs: [object.sourceId],
        orderIndex: double.maxFinite,
        keepTogether: true,
        figure: object.fileId == null
            ? null
            : FigureBlockSpec(
                fileId: object.fileId!,
                displayAspectRatio: object.visualBounds.width /
                    object.visualBounds.height,
                missingAsset: object.fileId != null &&
                    !_assetResolved(snapshot, object.fileId!),
              ),
        extras: {
          'kind': object.kind,
          'bounds': {
            'left': object.bounds.left,
            'top': object.bounds.top,
            'width': object.bounds.width,
            'height': object.bounds.height,
          },
        },
      ));
    }

    // 关系：caption → 最近前驱 figure；title → 后继首块（section keep）。
    String? lastFigureId;
    final blockIds = [for (final b in blocks) b.id];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.kind == LayoutBlockKind.figure) {
        lastFigureId = block.id;
      } else if (block.kind == LayoutBlockKind.caption &&
          lastFigureId != null) {
        relationships.add(BlockRelationship(
          kind: BlockRelationKind.captionOf,
          fromBlockId: block.id,
          toBlockId: lastFigureId,
        ));
      } else if (block.kind == LayoutBlockKind.title) {
        final next = _nextNonCaptionBlock(blocks, i);
        if (next != null) {
          relationships.add(BlockRelationship(
            kind: BlockRelationKind.keepWith,
            fromBlockId: block.id,
            toBlockId: next.id,
          ));
        }
      }
    }

    final assembly = LayoutBlockAssembly(
      blocks: List.unmodifiable(blocks),
      relationships: List.unmodifiable(relationships),
      atomicGroups: List.unmodifiable(_atomicGroups(blocks, relationships)),
      documentConsumedSourceIds: document.consumedSourceIds,
      documentPreservedSourceIds: document.preservedSourceIds,
    );
    _validateConservation(assembly, consumedSet, preservedSet);
    _validateRelationships(assembly, blockIds.toSet());
    return assembly;
  }

  List<SemanticBlock> _orderedSemanticBlocks(SemanticDocument document) {
    if (document.readingOrder.orderedBlockIds.isNotEmpty) {
      final byId = {for (final b in document.blocks) b.id: b};
      final ordered = <SemanticBlock>[];
      for (final id in document.readingOrder.orderedBlockIds) {
        final block = byId[id];
        if (block != null) ordered.add(block);
      }
      // 未进阅读序的块（异常输入）按 orderIndex 追加，不静默丢弃。
      if (ordered.length != document.blocks.length) {
        final orderedIds = ordered.map((b) => b.id).toSet();
        final rest = document.blocks
            .where((b) => !orderedIds.contains(b.id))
            .toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        ordered.addAll(rest);
      }
      return ordered;
    }
    final sorted = [...document.blocks]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return sorted;
  }

  LayoutBlock _figureBlock(
    SemanticBlock sb,
    Map<String, SnapshotObject> objectById,
    LayoutPageSnapshot snapshot,
  ) {
    ImageCandidate? image;
    for (final sourceId in sb.sourceIds) {
      final object = objectById[sourceId];
      if (object == null) continue;
      if (object.kind == 'image') {
        image = ImageCandidate.fromObject(
          object,
          assetResolved: object.fileId != null &&
              _assetResolved(snapshot, object.fileId!),
        );
        break;
      }
    }
    return LayoutBlock(
      id: sb.id,
      kind: LayoutBlockKind.figure,
      sourceRefs: List.unmodifiable(sb.sourceIds),
      orderIndex: sb.orderIndex.toDouble(),
      keepTogether: true,
      figure: image?.spec,
      extras: Map.unmodifiable(sb.extras),
    );
  }

  LayoutBlock _textualBlock(
    SemanticBlock sb,
    SmartLayoutDesignTokens tokens,
    TextMeasureAdapter measure, {
    required LayoutBlockKind forceKind,
  }) {
    final transcribed = sb.extras['transcribedText'];
    final String? text;
    final LayoutTextOrigin? origin;
    if (sb.text != null) {
      text = sb.text;
      origin = LayoutTextOrigin.typed;
    } else if (transcribed is String) {
      text = transcribed;
      origin = LayoutTextOrigin.transcribed;
    } else {
      text = null;
      origin = null;
    }
    if (text == null) {
      // 无文本的语义块：保留原样（不造文本、不删块）。
      return LayoutBlock(
        id: sb.id,
        kind: forceKind,
        sourceRefs: List.unmodifiable(sb.sourceIds),
        orderIndex: sb.orderIndex.toDouble(),
        keepTogether: forceKind == LayoutBlockKind.formula ||
            forceKind == LayoutBlockKind.table,
        extras: Map.unmodifiable(sb.extras),
      );
    }
    final rtl = sb.extras['direction'] == 'rtl';
    final spec = TextBlockSpec(
      text: text,
      fontFamily: kLayoutFontFamily,
      fontSize: forceKind == LayoutBlockKind.title
          ? tokens.titleFloorSize
          : tokens.bodySize,
      lineHeight: tokens.lineHeight,
      direction: rtl ? TextDirectionSpec.rtl : TextDirectionSpec.ltr,
    );
    return LayoutBlock(
      id: sb.id,
      kind: forceKind,
      sourceRefs: List.unmodifiable(sb.sourceIds),
      orderIndex: sb.orderIndex.toDouble(),
      keepTogether: forceKind == LayoutBlockKind.formula ||
          forceKind == LayoutBlockKind.table,
      textOrigin: origin,
      text: spec,
      measuredIntrinsic: measure.measure(
        text: spec.text,
        fontFamily: spec.fontFamily,
        fontSize: spec.fontSize,
        lineHeight: spec.lineHeight,
        direction: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      ),
      extras: Map.unmodifiable(sb.extras),
    );
  }

  LayoutBlock? _nextNonCaptionBlock(List<LayoutBlock> blocks, int from) {
    for (var i = from + 1; i < blocks.length; i++) {
      final candidate = blocks[i];
      if (candidate.kind == LayoutBlockKind.caption) continue;
      if (candidate.isPreservedLike) continue;
      return candidate;
    }
    return null;
  }

  bool _assetResolved(LayoutPageSnapshot snapshot, String fileId) {
    for (final asset in snapshot.renderAssets) {
      if (asset.fileId == fileId) {
        return asset.status == SnapshotRenderAssetStatus.resolved;
      }
    }
    // 未知资产按缺失事实处理（不猜测存在）。
    return false;
  }

  List<List<String>> _atomicGroups(
    List<LayoutBlock> blocks,
    List<BlockRelationship> relationships,
  ) {
    final idIndex = {
      for (var i = 0; i < blocks.length; i++) blocks[i].id: i,
    };
    final parent = List<int>.generate(blocks.length, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    final relatedIds = <String>{
      for (final rel in relationships) ...[rel.fromBlockId, rel.toBlockId],
    };
    for (final rel in relationships) {
      final a = idIndex[rel.fromBlockId];
      final b = idIndex[rel.toBlockId];
      if (a == null || b == null) continue;
      union(a, b);
    }
    // 组成员 = 关系连通分量的全部端点 + 块级 keepTogether 块；
    // 孤立且非原子的块不成组。
    final groupsByRoot = <int, List<String>>{};
    for (var i = 0; i < blocks.length; i++) {
      if (!blocks[i].keepTogether && !relatedIds.contains(blocks[i].id)) {
        continue;
      }
      groupsByRoot.putIfAbsent(find(i), () => []).add(blocks[i].id);
    }
    final groups = groupsByRoot.values
        .map((ids) => List<String>.of(ids))
        .toList()
      ..sort((a, b) => a.first.compareTo(b.first));
    return groups;
  }

  void _validateConservation(
    LayoutBlockAssembly assembly,
    Set<String> consumedSet,
    Set<String> preservedSet,
  ) {
    if (!assembly.ledgerConserved) {
      final blockRefs = <String>{};
      var dup = 0;
      for (final block in assembly.blocks) {
        for (final ref in block.sourceRefs) {
          if (!blockRefs.add(ref)) dup++;
        }
      }
      throw StateError(
        'ledger 守恒失败：重复 sourceRefs=$dup，'
        '并集 ${blockRefs.length} vs ledger ${consumedSet.length + preservedSet.length}',
      );
    }
  }

  void _validateRelationships(
    LayoutBlockAssembly assembly,
    Set<String> blockIds,
  ) {
    for (final rel in assembly.relationships) {
      if (!blockIds.contains(rel.fromBlockId) ||
          !blockIds.contains(rel.toBlockId)) {
        throw StateError('关系端点缺失：$rel');
      }
    }
  }
}

/// 快照 image 对象 → 图片排版规格。
class ImageCandidate {
  const ImageCandidate({required this.spec});

  factory ImageCandidate.fromObject(
    SnapshotObject object, {
    required bool assetResolved,
  }) {
    final intrinsic = object.imageIntrinsicSize;
    final crop = object.imageCrop;
    double ratio;
    if (intrinsic != null && intrinsic.height > 0) {
      final cropW = crop?.width ?? 1.0;
      final cropH = crop?.height ?? 1.0;
      final w = intrinsic.width * cropW;
      final h = intrinsic.height * cropH;
      ratio = h > 0 ? w / h : 1.0;
    } else {
      // 内在尺寸缺失：用当前显示 bounds 比例（事实兜底，不猜内在值）。
      ratio = object.bounds.height > 0
          ? object.bounds.width / object.bounds.height
          : 1.0;
    }
    return ImageCandidate(
      spec: FigureBlockSpec(
        fileId: object.fileId ?? '',
        displayAspectRatio: ratio,
        missingAsset: !assetResolved,
      ),
    );
  }

  final FigureBlockSpec spec;
}
