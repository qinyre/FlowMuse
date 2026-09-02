import 'dart:convert';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../snapshot/deterministic_hash.dart';
import 'smart_layout_scene_patch.dart';

/// ScenePatch 调试编解码（V3-500B，**仅测试诊断**）。
///
/// 单向 encode：把 patch 投影为确定性 JSON 形 Map，供测试 fixture、
/// golden 对比与失败诊断。输出不进入持久化协议、不进入协作通道，
/// 生产代码不得依赖本 codec 的格式（格式随诊断需要演进，无兼容承诺）。
/// codec 自带 `diagnosticOnly: true` 标记与版本头，误用可被静态审计。
abstract final class ScenePatchDebugCodec {
  static const String codecVersion = 'scene-patch-debug-v1';

  /// 确定性编码：操作按 patch 内规范序，元素负载经
  /// [ExcalidrawJsonCodec.elementToJson] 全字段投影，文件以内容哈希
  /// 指纹代表字节；同一 patch 双跑编码逐字节一致。
  static Map<String, Object?> encode(SmartLayoutScenePatch patch) => {
    'codec': codecVersion,
    'diagnosticOnly': true,
    'baseRevision': {
      'epoch': patch.baseRevision.epoch,
      'revision': patch.baseRevision.revision,
      'fingerprint': patch.baseRevision.fingerprint.value,
    },
    'removes': [
      for (final op in patch.removes)
        {
          'elementId': op.elementId,
          'baseVersion': op.baseVersion,
          'newVersion': op.newVersion,
          'versionNonce': op.versionNonce,
        },
    ],
    'updates': [
      for (final op in patch.updates)
        {
          'elementId': op.elementId,
          'baseVersion': op.baseVersion,
          'newVersion': op.element.version,
          'element': ExcalidrawJsonCodec.elementToJson(op.element),
        },
    ],
    'adds': [
      for (final op in patch.adds)
        {
          'elementId': op.elementId,
          'element': ExcalidrawJsonCodec.elementToJson(op.element),
        },
    ],
    'fileAdds': [
      for (final op in patch.fileAdds)
        {
          'fileId': op.fileId,
          'mimeType': op.file.mimeType,
          'bytes': op.file.bytes.length,
          'contentHash': fingerprint64(
            'file|${op.fileId}|${op.file.mimeType}|'
            '${jsonEncode(op.file.bytes)}',
          ),
        },
    ],
    'documentOp': patch.documentOp == null
        ? null
        : {
            'op': patch.documentOp!.clears ? 'clear' : 'replace',
            if (!patch.documentOp!.clears)
              'document': patch.documentOp!.document!.toJson(),
          },
    'selectionIntent': patch.selectionIntent,
    'ledger': {
      'hash': patch.sourceCoverage.hashValue,
      'sources': {
        for (final entry in patch.sourceCoverage.statuses.entries)
          entry.key: entry.value.name,
      },
      'counts': {
        'consumed': patch.sourceCoverage.consumedCount,
        'preserved': patch.sourceCoverage.preservedCount,
        'pending': patch.sourceCoverage.pendingCount,
      },
    },
    'writeSet': {
      'elementIds': patch.writeSet.elementIds,
      'fileIds': patch.writeSet.fileIds,
      'touchesDocument': patch.writeSet.touchesDocument,
      'touchesSelection': patch.writeSet.touchesSelection,
    },
    'readSet': {'elementIds': patch.readSet.elementIds},
  };

  /// 规范文本形态（诊断输出/测试 diff；键序固定，双跑一致）。
  static String encodeToString(SmartLayoutScenePatch patch) =>
      const JsonEncoder.withIndent('  ').convert(encode(patch));
}
