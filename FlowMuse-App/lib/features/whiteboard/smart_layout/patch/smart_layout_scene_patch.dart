import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../snapshot/scene_revision.dart';
import '../snapshot/source_coverage_ledger.dart';

/// 元素操作三型。应用序冻结为 remove → update → add（计划 §4.8 固定操作序）：
/// 先让位、再改写、最后新增置顶；改动顺序等同修订 patch 协议。
enum ScenePatchElementOpKind { remove, update, add }

/// remove 操作：不携带元素负载，version delta 显式（软删/硬删语义由
/// reducer 决定，版本推进本身是 patch 契约）。
class ScenePatchElementRemove {
  const ScenePatchElementRemove({
    required this.elementId,
    required this.baseVersion,
    required this.newVersion,
    required this.versionNonce,
  });

  final String elementId;

  /// 操作针对的 base 元素 version（commit 期复核用）。
  final int baseVersion;

  /// 恒等于 baseVersion + 1（[PatchInvariant] 强制）。
  final int newVersion;

  /// 显式携带的 nonce；构建期不随机（双跑确定性由调用方显式赋值保证）。
  final int versionNonce;

  @override
  String toString() =>
      'remove($elementId v$baseVersion→$newVersion nonce:$versionNonce)';
}

/// update 操作：完整新元素负载——位置/尺寸/角度/样式/文本/points 与
/// groupIds/frameId/boundElements/index/version/versionNonce 全部显式，
/// 不存在隐式字段；期望的 [baseVersion] 一并记录供 CAS 复核。
class ScenePatchElementUpdate {
  const ScenePatchElementUpdate({
    required this.element,
    required this.baseVersion,
  });

  final Element element;

  /// 操作针对的 base 元素 version；element.version 恒等于 baseVersion + 1
  /// （[PatchInvariant] 强制）。
  final int baseVersion;

  String get elementId => element.id.value;

  @override
  String toString() =>
      'update(${element.id.value} v$baseVersion→${element.version})';
}

/// add 操作：完整新元素负载；version 恒为 1（[PatchInvariant] 强制）。
class ScenePatchElementAdd {
  const ScenePatchElementAdd({required this.element});

  final Element element;

  String get elementId => element.id.value;

  @override
  String toString() => 'add(${element.id.value})';
}

/// file add 操作：排版派生资产（公式渲染图等）落入 Scene 文件仓；
/// fileId 与 base 既有文件冲突即拒绝。
class ScenePatchFileAdd {
  const ScenePatchFileAdd({required this.fileId, required this.file});

  final String fileId;
  final ImageFile file;

  @override
  String toString() => 'file($fileId, ${file.mimeType}, ${file.bytes.length}B)';
}

/// SmartLayoutDocument 操作：replace 或 clear，是 Scene.smartLayout 的
/// 唯一 patch 副作用通道。
class ScenePatchDocumentOp {
  const ScenePatchDocumentOp._(this.document);

  const ScenePatchDocumentOp.replace(SmartLayoutDocument document)
    : this._(document);

  const ScenePatchDocumentOp.clear() : this._(null);

  /// 新文档；null 表示清除（[clears] 为真）。
  final SmartLayoutDocument? document;

  bool get clears => document == null;

  @override
  String toString() => clears ? 'document(clear)' : 'document(replace)';
}

/// 写集：patch 全部副作用的精确枚举（计划 §4.8"精确读写集"）。提交期
/// 冲突判定（V3-502）只看这里，不看实现细节。
class ScenePatchWriteSet {
  const ScenePatchWriteSet({
    required this.elementIds,
    required this.fileIds,
    required this.touchesDocument,
    required this.touchesSelection,
  });

  /// add/update/remove 涉及的全部元素 id（排序、不可变）。
  final List<String> elementIds;

  /// 新增文件 id（排序、不可变）。
  final List<String> fileIds;

  /// 是否替换/清除 SmartLayoutDocument。
  final bool touchesDocument;

  /// 是否设置选择意图（selectionIntent 非 null）。
  final bool touchesSelection;

  bool get isEmpty =>
      elementIds.isEmpty &&
      fileIds.isEmpty &&
      !touchesDocument &&
      !touchesSelection;

  /// 写集相交判定（V3-502 冲突/重派）：元素或文件 id 重叠，或两者都
  /// 触碰 document/selection 同一副作用通道。
  bool intersects(ScenePatchWriteSet other) {
    if (touchesDocument && other.touchesDocument) return true;
    if (touchesSelection && other.touchesSelection) return true;
    final mine = elementIds.toSet();
    if (mine.any(other.elementIds.contains)) return true;
    final myFiles = fileIds.toSet();
    if (myFiles.any(other.fileIds.contains)) return true;
    return false;
  }

  @override
  String toString() =>
      'ScenePatchWriteSet(elements: ${elementIds.length}, files: '
      '${fileIds.length}, doc: $touchesDocument, selection: '
      '$touchesSelection)';
}

/// 读集：patch 有效性在 base 上依赖的元素（update/remove 目标的版本与
/// 内容、关系引用指向的 base 元素）。远端改写读集元素时即使写集不相交，
/// 重派（V3-502）也必须先复核引用仍然成立。
class ScenePatchReadSet {
  const ScenePatchReadSet({required this.elementIds});

  final List<String> elementIds;

  @override
  String toString() => 'ScenePatchReadSet(elements: ${elementIds.length})';
}

/// 智能排版 feature-private 不可变事务对象（计划 §4.8）：覆盖 element
/// add/update/remove、file refs、SmartLayoutDocument 与 selection intent，
/// 携带 baseRevision 与唯一 [SourceCoverageLedger]（只透传校验，不建
/// 第二套 source 状态）。不持有 Scene——预览与提交由 reducer（V3-501A）
/// 在外部 base 上消费本 patch。
class SmartLayoutScenePatch {
  const SmartLayoutScenePatch({
    required this.baseRevision,
    required this.removes,
    required this.updates,
    required this.adds,
    required this.fileAdds,
    required this.documentOp,
    required this.selectionIntent,
    required this.sourceCoverage,
  });

  /// 构建时所依据的 SceneRevision；commit 临界区复核（V3-502）。
  final SceneRevision baseRevision;

  /// 按 elementId 排序（规范序与枚举声明一致）。
  final List<ScenePatchElementRemove> removes;
  final List<ScenePatchElementUpdate> updates;
  final List<ScenePatchElementAdd> adds;
  final List<ScenePatchFileAdd> fileAdds;

  /// null 表示不触碰 SmartLayoutDocument。
  final ScenePatchDocumentOp? documentOp;

  /// null 表示不触碰选择；非 null（可为空集 = 清空选择）表示应用后
  /// 设置选择为这些元素 id。
  final List<String>? selectionIntent;

  /// 唯一账本透传：构建期要求已终结（全部 consumed/preserved）。
  final SourceCoverageLedger sourceCoverage;

  /// 元素操作按固定应用序（remove → update → add）展开。
  Iterable<Object> get elementOps sync* {
    yield* removes;
    yield* updates;
    yield* adds;
  }

  ScenePatchWriteSet get writeSet => ScenePatchWriteSet(
    elementIds: List.unmodifiable(
      [
        ...[for (final op in removes) op.elementId],
        ...[for (final op in updates) op.elementId],
        ...[for (final op in adds) op.elementId],
      ]..sort(),
    ),
    fileIds: List.unmodifiable([for (final op in fileAdds) op.fileId]..sort()),
    touchesDocument: documentOp != null,
    touchesSelection: selectionIntent != null,
  );

  ScenePatchReadSet get readSet {
    final written = {
      for (final op in removes) op.elementId,
      for (final op in updates) op.elementId,
      for (final op in adds) op.elementId,
    };
    // 指向 patch 自身新增元素的关系是 patch 内部依赖，不构成 base 读；
    // 指向其余（构建期已由不变量保证存在于 base）的引用是读依赖。
    final reads = <String>{
      ...[for (final op in removes) op.elementId],
      ...[for (final op in updates) op.elementId],
      ...[
        for (final ref in _relationRefs)
          if (!written.contains(ref)) ref,
      ],
    };
    final ids = reads.toList()..sort();
    return ScenePatchReadSet(elementIds: List.unmodifiable(ids));
  }

  /// patch 内新增/改写元素声明的关系引用（frameId/containerId/
  /// boundElements）；指向 patch 外（base）的引用构成读依赖。
  Iterable<String> get _relationRefs sync* {
    for (final op in adds) {
      yield* relationRefsOf(op.element);
    }
    for (final op in updates) {
      yield* relationRefsOf(op.element);
    }
  }

  /// 元素负载显式声明的关系引用（frameId/containerId/boundElements id）。
  static Iterable<String> relationRefsOf(Element element) sync* {
    final frameId = element.frameId;
    if (frameId != null) yield frameId;
    if (element is TextElement) {
      final containerId = element.containerId;
      if (containerId != null) yield containerId;
    }
    for (final bound in element.boundElements) {
      yield bound.id;
    }
  }

  @override
  String toString() =>
      'SmartLayoutScenePatch(base: ${baseRevision.epoch}:'
      '${baseRevision.revision}, removes: ${removes.length}, updates: '
      '${updates.length}, adds: ${adds.length}, files: ${fileAdds.length}, '
      'doc: ${documentOp != null}, selection: ${selectionIntent != null})';
}
