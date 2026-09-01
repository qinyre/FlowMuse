import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../snapshot/scene_revision.dart';
import '../snapshot/source_coverage_ledger.dart';
import 'patch_invariant.dart';
import 'smart_layout_scene_patch.dart';

/// feature-private ScenePatchBuilder（计划 §4.8）：以显式操作累积一份
/// 事务，[build] 一次性运行全部 [PatchInvariant] 并物化不可变
/// [SmartLayoutScenePatch]。任何不变量违反都让 build 整体失败——不产生
/// 部分结果，也不提供绕过校验的路径。
///
/// 契约：
/// - base Scene / baseRevision / ledger 仅为构建期只读输入，patch 不持有
///   Scene；baseRevision.fingerprint 必须与 base Scene 当前指纹一致；
/// - 调用方构造元素时必须显式提供 versionNonce 与 updated（Element
///   构造器缺省会随机/取当前时间，破坏双跑确定性）；
/// - builder 本身是可变工作区，可多次 build（每次全量重校验）。
class SmartLayoutScenePatchBuilder {
  SmartLayoutScenePatchBuilder({
    required Scene baseScene,
    required SceneRevision baseRevision,
    required SourceCoverageLedger sourceCoverage,
  }) : _baseScene = baseScene,
       _baseRevision = baseRevision,
       _sourceCoverage = sourceCoverage;

  final Scene _baseScene;
  final SceneRevision _baseRevision;
  final SourceCoverageLedger _sourceCoverage;

  final List<ScenePatchElementRemove> _removes = [];
  final List<ScenePatchElementUpdate> _updates = [];
  final List<ScenePatchElementAdd> _adds = [];
  final List<ScenePatchFileAdd> _fileAdds = [];
  ScenePatchDocumentOp? _documentOp;
  List<String>? _selectionIntent;

  /// 新增元素：完整负载、version 必须为 1、id 不得与 base 或其他操作冲突。
  void addElement(Element element) {
    _adds.add(ScenePatchElementAdd(element: element));
  }

  /// 改写元素：完整新负载 + 期望的 baseVersion（CAS 语义，构建期即与
  /// base 复核，commit 期由 V3-502 再次复核）。
  void updateElement(Element element, {required int baseVersion}) {
    _updates.add(
      ScenePatchElementUpdate(element: element, baseVersion: baseVersion),
    );
  }

  /// 移除元素：不携带负载，version delta 由 [baseVersion] 推导为 +1；
  /// [versionNonce] 显式传入（reducer 应用时不自行随机）。
  void removeElement(
    String elementId, {
    required int baseVersion,
    required int versionNonce,
  }) {
    _removes.add(
      ScenePatchElementRemove(
        elementId: elementId,
        baseVersion: baseVersion,
        newVersion: baseVersion + 1,
        versionNonce: versionNonce,
      ),
    );
  }

  /// 新增文件：fileId 不得与 base 文件仓或其他 fileAdd 冲突。
  void addFile(String fileId, ImageFile file) {
    _fileAdds.add(ScenePatchFileAdd(fileId: fileId, file: file));
  }

  /// 替换 SmartLayoutDocument（覆盖此前的 document 操作意图）。
  void replaceSmartLayoutDocument(SmartLayoutDocument document) {
    _documentOp = ScenePatchDocumentOp.replace(document);
  }

  /// 清除 SmartLayoutDocument（覆盖此前的 document 操作意图）。
  void clearSmartLayoutDocument() {
    _documentOp = const ScenePatchDocumentOp.clear();
  }

  /// 设置选择意图：非 null 即触碰选择通道；空集表示应用后清空选择。
  void setSelectionIntent(Iterable<String> elementIds) {
    _selectionIntent = List.unmodifiable(elementIds);
  }

  /// 构建不可变 patch。存在任何不变量违反时抛 [StateError]（消息含全部
  /// 排序后的违反项），不返回部分结果。
  SmartLayoutScenePatch build() {
    final violations = PatchInvariant.check(
      baseScene: _baseScene,
      baseRevision: _baseRevision,
      sourceCoverage: _sourceCoverage,
      removes: _removes,
      updates: _updates,
      adds: _adds,
      fileAdds: _fileAdds,
      documentOp: _documentOp,
      selectionIntent: _selectionIntent,
    );
    if (violations.isNotEmpty) {
      throw StateError(
        'ScenePatch 不变量违反（${violations.length} 项）：\n'
        '${violations.map((v) => '  - $v').join('\n')}',
      );
    }
    return SmartLayoutScenePatch(
      baseRevision: _baseRevision,
      removes: List.unmodifiable(
        <ScenePatchElementRemove>[..._removes]..sort(_byRemoveId),
      ),
      updates: List.unmodifiable(
        <ScenePatchElementUpdate>[..._updates]..sort(_byUpdateId),
      ),
      adds: List.unmodifiable(
        <ScenePatchElementAdd>[..._adds]..sort(_byAddId),
      ),
      fileAdds: List.unmodifiable(
        <ScenePatchFileAdd>[..._fileAdds]..sort(_byFileId),
      ),
      documentOp: _documentOp,
      selectionIntent: _selectionIntent == null
          ? null
          : List.unmodifiable(<String>[..._selectionIntent!]..sort()),
      sourceCoverage: _sourceCoverage,
    );
  }

  static int _byRemoveId(
    ScenePatchElementRemove a,
    ScenePatchElementRemove b,
  ) => a.elementId.compareTo(b.elementId);

  static int _byUpdateId(
    ScenePatchElementUpdate a,
    ScenePatchElementUpdate b,
  ) => a.elementId.compareTo(b.elementId);

  static int _byAddId(ScenePatchElementAdd a, ScenePatchElementAdd b) =>
      a.elementId.compareTo(b.elementId);

  static int _byFileId(ScenePatchFileAdd a, ScenePatchFileAdd b) =>
      a.fileId.compareTo(b.fileId);
}
