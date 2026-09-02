import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import 'smart_layout_scene_patch.dart';

/// patch 深度等价（preview=commit 语义基石，V3-501A/V3-506 复用）：
/// 逐字段比较两个 patch——操作数、id、version、nonce、完整元素负载
///（[ExcalidrawJsonCodec.elementToJson] 全字段投影，含关系与样式）、
/// 文件字节、文档、选择意图与账本状态。Element 自身按 id 相等
///（身份语义），元素负载等价必须经此处显式投影。
///
/// baseRevision 参与（不同 base 上的相同操作序列不是同一事务）。
abstract final class SmartLayoutScenePatchEquality {
  static bool deepEquals(SmartLayoutScenePatch a, SmartLayoutScenePatch b) {
    if (identical(a, b)) return true;
    if (a.baseRevision != b.baseRevision) return false;
    if (a.removes.length != b.removes.length ||
        a.updates.length != b.updates.length ||
        a.adds.length != b.adds.length ||
        a.fileAdds.length != b.fileAdds.length) {
      return false;
    }
    for (var i = 0; i < a.removes.length; i++) {
      final x = a.removes[i];
      final y = b.removes[i];
      if (x.elementId != y.elementId ||
          x.baseVersion != y.baseVersion ||
          x.newVersion != y.newVersion ||
          x.versionNonce != y.versionNonce) {
        return false;
      }
    }
    for (var i = 0; i < a.updates.length; i++) {
      final x = a.updates[i];
      final y = b.updates[i];
      if (x.baseVersion != y.baseVersion ||
          !_elementsEqual(x.element, y.element)) {
        return false;
      }
    }
    for (var i = 0; i < a.adds.length; i++) {
      if (!_elementsEqual(a.adds[i].element, b.adds[i].element)) return false;
    }
    for (var i = 0; i < a.fileAdds.length; i++) {
      final x = a.fileAdds[i];
      final y = b.fileAdds[i];
      if (x.fileId != y.fileId ||
          x.file.mimeType != y.file.mimeType ||
          x.file.bytes.length != y.file.bytes.length) {
        return false;
      }
      if (!_bytesEqual(x.file.bytes, y.file.bytes)) return false;
    }
    if (!_documentOpsEqual(a.documentOp, b.documentOp)) return false;
    if (!_selectionsEqual(a.selectionIntent, b.selectionIntent)) return false;
    return a.sourceCoverage == b.sourceCoverage;
  }

  static bool _elementsEqual(Element x, Element y) {
    if (identical(x, y)) return true;
    if (x.id != y.id) return false;
    return _valuesEqual(
      ExcalidrawJsonCodec.elementToJson(x),
      ExcalidrawJsonCodec.elementToJson(y),
    );
  }

  static bool _documentOpsEqual(
    ScenePatchDocumentOp? a,
    ScenePatchDocumentOp? b,
  ) {
    if (a == null || b == null) return identical(a, b);
    final left = a.document;
    final right = b.document;
    if (left == null || right == null) {
      return (left == null) == (right == null);
    }
    return _valuesEqual(left.toJson(), right.toJson());
  }

  static bool _selectionsEqual(List<String>? a, List<String>? b) {
    if (a == null || b == null) return identical(a, b);
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// JSON 形值深度等价（Map 键序无关；num 按 ==，1 与 1.0 等价）。
  static bool _valuesEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a is num && b is num) return a == b;
    if (a is String && b is String) return a == b;
    if (a is bool && b is bool) return a == b;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_valuesEqual(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is Iterable && b is Iterable) {
      final la = a.toList();
      final lb = b.toList();
      if (la.length != lb.length) return false;
      for (var i = 0; i < la.length; i++) {
        if (!_valuesEqual(la[i], lb[i])) return false;
      }
      return true;
    }
    return false;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
